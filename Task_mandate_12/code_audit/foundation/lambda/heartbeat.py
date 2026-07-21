import json
import os
from datetime import datetime, timezone

import boto3


def _age_minutes(value):
    if value is None:
        return None
    if value.tzinfo is None:
        value = value.replace(tzinfo=timezone.utc)
    return (datetime.now(timezone.utc) - value).total_seconds() / 60


def _field_values(fields, name, operator="Equals"):
    return set(fields.get(name, {}).get(operator, []))


def _check_selectors(client, trail_name, required_s3_arns):
    response = client.get_event_selectors(TrailName=trail_name)
    selectors = response.get("AdvancedEventSelectors", [])
    management_read_write = False
    discovered_s3 = set()

    for selector in selectors:
        fields = {item["Field"]: item for item in selector.get("FieldSelectors", [])}
        categories = _field_values(fields, "eventCategory")
        if "Management" in categories:
            read_only = fields.get("readOnly")
            allowed_fields = {"eventCategory", "readOnly"}
            if set(fields).issubset(allowed_fields) and (
                read_only is None or set(read_only.get("Equals", [])) == {"true", "false"}
            ):
                management_read_write = True
        if (
            "Data" in categories
            and "AWS::S3::Object" in _field_values(fields, "resources.type")
            and set(fields) == {"eventCategory", "resources.type", "resources.ARN"}
        ):
            discovered_s3.update(_field_values(fields, "resources.ARN", "StartsWith"))

    failures = []
    if not management_read_write:
        failures.append("management selector does not cover both read and write events")
    required = set(required_s3_arns)
    if discovered_s3 != required:
        failures.append(
            "S3 data selector differs from approved scope: "
            f"missing={sorted(required - discovered_s3)}, unexpected={sorted(discovered_s3 - required)}"
        )
    return failures


def _check_rule(client, rule_name, expected, target_arn, label):
    failures = []
    rule = client.describe_rule(Name=rule_name)
    if rule.get("State") not in ("ENABLED", "ENABLED_WITH_ALL_CLOUDTRAIL_MANAGEMENT_EVENTS"):
        failures.append(f"EventBridge rule is not enabled: {label}/{rule_name}")

    actual_pattern = json.loads(rule.get("EventPattern", "{}"))
    actual_detail = actual_pattern.get("detail", {})
    checks = (
        ("source", set(actual_pattern.get("source", [])), set(expected["sources"])),
        ("detail-type", set(actual_pattern.get("detail-type", [])), {"AWS API Call via CloudTrail"}),
        ("detail.eventSource", set(actual_detail.get("eventSource", [])), set(expected["event_sources"])),
        ("detail.eventName", set(actual_detail.get("eventName", [])), set(expected["event_names"])),
    )
    if set(actual_pattern) != {"source", "detail-type", "detail"}:
        failures.append(f"EventBridge pattern has unexpected top-level filters: {label}/{rule_name}")
    if set(actual_detail) != {"eventSource", "eventName"}:
        failures.append(f"EventBridge detail pattern has unexpected filters: {label}/{rule_name}")
    for field, actual, wanted in checks:
        if actual != wanted:
            failures.append(f"EventBridge pattern mismatch {label}/{rule_name}/{field}")

    targets = client.list_targets_by_rule(Rule=rule_name).get("Targets", [])
    if target_arn not in {item.get("Arn") for item in targets}:
        failures.append(f"EventBridge router target missing: {label}/{rule_name}")
    return failures


def _check_subscriptions(client, topic_arn, expected_endpoints, label):
    failures = []
    actual = {}
    token = None
    while True:
        kwargs = {"TopicArn": topic_arn}
        if token:
            kwargs["NextToken"] = token
        response = client.list_subscriptions_by_topic(**kwargs)
        for subscription in response.get("Subscriptions", []):
            actual[subscription.get("Endpoint")] = subscription.get("SubscriptionArn")
        token = response.get("NextToken")
        if not token:
            break

    for endpoint in expected_endpoints:
        subscription_arn = actual.get(endpoint)
        if not subscription_arn or subscription_arn in ("PendingConfirmation", "Deleted"):
            failures.append(f"SNS required subscription is not confirmed: {label}/{endpoint}")
    return failures


def handler(_event, _context):
    region = os.environ["PRIMARY_REGION"]
    global_region = os.environ["GLOBAL_REGION"]
    trail_name = os.environ["TRAIL_NAME"]
    bucket_name = os.environ["AUDIT_BUCKET_NAME"]
    topic_arn = os.environ["ALERT_TOPIC_ARN"]
    global_topic_arn = os.environ["GLOBAL_ALERT_TOPIC_ARN"]
    max_log_age = int(os.environ["MAX_LOG_DELIVERY_AGE_MINUTES"])
    max_digest_age = int(os.environ["MAX_DIGEST_DELIVERY_AGE_MINUTES"])
    required_retention = int(os.environ["REQUIRED_RETENTION_DAYS"])
    required_lifecycle = int(os.environ["REQUIRED_LIFECYCLE_DAYS"])
    eks_cluster_name = os.environ["EKS_CLUSTER_NAME"]
    primary_rules = json.loads(os.environ["PRIMARY_RULES_JSON"])
    global_rules = json.loads(os.environ["GLOBAL_RULES_JSON"])
    primary_router_arn = os.environ["PRIMARY_ROUTER_ARN"]
    global_router_arn = os.environ["GLOBAL_ROUTER_ARN"]
    schedule_rule_name = os.environ["HEARTBEAT_SCHEDULE_RULE_NAME"]
    heartbeat_function_arn = os.environ["HEARTBEAT_FUNCTION_ARN"]
    alarm_names = json.loads(os.environ["HEARTBEAT_ALARM_NAMES_JSON"])
    expected_endpoints = json.loads(os.environ["EXPECTED_SUBSCRIPTION_ENDPOINTS_JSON"])
    required_s3_arns = json.loads(os.environ["S3_DATA_EVENT_ARNS_JSON"])

    cloudtrail = boto3.client("cloudtrail", region_name=region)
    s3 = boto3.client("s3", region_name=region)
    sns = boto3.client("sns", region_name=region)
    sns_global = boto3.client("sns", region_name=global_region)
    events_primary = boto3.client("events", region_name=region)
    events_global = boto3.client("events", region_name=global_region)
    lambda_primary = boto3.client("lambda", region_name=region)
    lambda_global = boto3.client("lambda", region_name=global_region)
    cloudwatch = boto3.client("cloudwatch", region_name=region)
    eks = boto3.client("eks", region_name=region)
    failures = []

    try:
        trails = cloudtrail.describe_trails(trailNameList=[trail_name], includeShadowTrails=False)
        if len(trails.get("trailList", [])) != 1:
            failures.append("exactly one protected CloudTrail configuration was not found")
        else:
            trail = trails["trailList"][0]
            if trail.get("S3BucketName") != bucket_name:
                failures.append("CloudTrail destination bucket differs from approved bucket")
            if not trail.get("IsMultiRegionTrail"):
                failures.append("CloudTrail is no longer multi-region")
            if not trail.get("IncludeGlobalServiceEvents"):
                failures.append("CloudTrail no longer includes global service events")
            if not trail.get("LogFileValidationEnabled"):
                failures.append("CloudTrail log-file validation is disabled")

        status = cloudtrail.get_trail_status(Name=trail_name)
        if not status.get("IsLogging"):
            failures.append("CloudTrail IsLogging is false")
        delivery_age = _age_minutes(status.get("LatestDeliveryTime"))
        if delivery_age is None or delivery_age > max_log_age:
            failures.append(f"LatestDeliveryTime is missing or older than {max_log_age} minutes")
        digest_age = _age_minutes(status.get("LatestDigestDeliveryTime"))
        if digest_age is None or digest_age > max_digest_age:
            failures.append(f"LatestDigestDeliveryTime is missing or older than {max_digest_age} minutes")
        for key in ("LatestDeliveryError", "LatestDigestDeliveryError"):
            if status.get(key):
                failures.append(f"{key}: {status[key]}")
        failures.extend(_check_selectors(cloudtrail, trail_name, required_s3_arns))
    except Exception as exc:
        failures.append(f"CloudTrail check failed: {type(exc).__name__}: {exc}")

    try:
        versioning = s3.get_bucket_versioning(Bucket=bucket_name)
        if versioning.get("Status") != "Enabled":
            failures.append("audit bucket versioning is not Enabled")
        lock = s3.get_object_lock_configuration(Bucket=bucket_name).get("ObjectLockConfiguration", {})
        retention = lock.get("Rule", {}).get("DefaultRetention", {})
        if lock.get("ObjectLockEnabled") != "Enabled":
            failures.append("audit bucket Object Lock is not Enabled")
        if retention.get("Mode") != "COMPLIANCE" or retention.get("Days", 0) < required_retention:
            failures.append("audit bucket retention is not COMPLIANCE at the required duration")

        lifecycle = s3.get_bucket_lifecycle_configuration(Bucket=bucket_name)
        expiration_days = [
            rule.get("Expiration", {}).get("Days", 0)
            for rule in lifecycle.get("Rules", [])
            if rule.get("Status") == "Enabled"
        ]
        if not expiration_days or min(expiration_days) < required_lifecycle:
            failures.append("audit bucket lifecycle is shorter than the approved retention")

        encryption = s3.get_bucket_encryption(Bucket=bucket_name)
        algorithms = {
            item.get("ApplyServerSideEncryptionByDefault", {}).get("SSEAlgorithm")
            for item in encryption.get("ServerSideEncryptionConfiguration", {}).get("Rules", [])
        }
        if not algorithms.intersection({"AES256", "aws:kms"}):
            failures.append("audit bucket default encryption is missing")

        public_access = s3.get_public_access_block(Bucket=bucket_name)["PublicAccessBlockConfiguration"]
        if not all(public_access.get(key) for key in (
            "BlockPublicAcls", "IgnorePublicAcls", "BlockPublicPolicy", "RestrictPublicBuckets"
        )):
            failures.append("audit bucket public-access block is incomplete")
        if s3.get_bucket_policy_status(Bucket=bucket_name).get("PolicyStatus", {}).get("IsPublic"):
            failures.append("audit bucket policy is public")
        policy = json.loads(s3.get_bucket_policy(Bucket=bucket_name)["Policy"])
        required_mutations = {
            "s3:BypassGovernanceRetention", "s3:DeleteObject", "s3:DeleteObjectVersion",
            "s3:PutObject", "s3:PutObjectRetention"
        }
        mutation_deny_found = False
        for statement in policy.get("Statement", []):
            actions = statement.get("Action", [])
            if isinstance(actions, str):
                actions = [actions]
            resources = statement.get("Resource", [])
            if isinstance(resources, str):
                resources = [resources]
            if (
                statement.get("Effect") == "Deny"
                and required_mutations.issubset(set(actions))
                and f"arn:aws:s3:::{bucket_name}/*" in resources
            ):
                mutation_deny_found = True
                break
        if not mutation_deny_found:
            failures.append("audit bucket non-CloudTrail object-mutation deny is missing or weakened")
    except Exception as exc:
        failures.append(f"S3 audit bucket check failed: {type(exc).__name__}: {exc}")

    for client, expected_rules, router_arn, label in (
        (events_primary, primary_rules, primary_router_arn, region),
        (events_global, global_rules, global_router_arn, global_region),
    ):
        for rule_name, expected in expected_rules.items():
            try:
                failures.extend(_check_rule(client, rule_name, expected, router_arn, label))
            except Exception as exc:
                failures.append(f"EventBridge rule check failed: {label}/{rule_name}: {type(exc).__name__}: {exc}")

    try:
        schedule = events_primary.describe_rule(Name=schedule_rule_name)
        if schedule.get("State") != "ENABLED" or schedule.get("ScheduleExpression") != "rate(5 minutes)":
            failures.append("heartbeat schedule rule configuration differs from approved state")
        schedule_targets = events_primary.list_targets_by_rule(Rule=schedule_rule_name).get("Targets", [])
        if heartbeat_function_arn not in {item.get("Arn") for item in schedule_targets}:
            failures.append("heartbeat schedule target is missing")
    except Exception as exc:
        failures.append(f"heartbeat schedule check failed: {type(exc).__name__}: {exc}")

    for client, function_arn, label in (
        (lambda_primary, primary_router_arn, "primary router"),
        (lambda_global, global_router_arn, "global router"),
    ):
        try:
            config = client.get_function_configuration(FunctionName=function_arn)
            if config.get("State") != "Active" or config.get("LastUpdateStatus") not in (None, "Successful"):
                failures.append(f"{label} Lambda is not healthy")
        except Exception as exc:
            failures.append(f"{label} Lambda check failed: {type(exc).__name__}: {exc}")

    try:
        alarms = cloudwatch.describe_alarms(AlarmNames=alarm_names).get("MetricAlarms", [])
        alarms_by_name = {alarm["AlarmName"]: alarm for alarm in alarms}
        for alarm_name in alarm_names:
            alarm = alarms_by_name.get(alarm_name)
            if not alarm:
                failures.append(f"heartbeat alarm is missing: {alarm_name}")
            elif not alarm.get("ActionsEnabled") or topic_arn not in alarm.get("AlarmActions", []):
                failures.append(f"heartbeat alarm action is disabled or changed: {alarm_name}")
    except Exception as exc:
        failures.append(f"CloudWatch alarm check failed: {type(exc).__name__}: {exc}")

    for client, current_topic, label in (
        (sns, topic_arn, region),
        (sns_global, global_topic_arn, global_region),
    ):
        try:
            client.get_topic_attributes(TopicArn=current_topic)
            failures.extend(_check_subscriptions(client, current_topic, expected_endpoints, label))
        except Exception as exc:
            failures.append(f"SNS alert path check failed: {label}: {type(exc).__name__}: {exc}")

    try:
        logging_config = eks.describe_cluster(name=eks_cluster_name)["cluster"].get("logging", {})
        enabled_types = set()
        for entry in logging_config.get("clusterLogging", []):
            if entry.get("enabled"):
                enabled_types.update(entry.get("types", []))
        if "audit" not in enabled_types:
            failures.append("EKS control-plane audit logging is not enabled")
    except Exception as exc:
        failures.append(f"EKS audit logging check failed: {type(exc).__name__}: {exc}")

    result = {
        "checkedAt": datetime.now(timezone.utc).isoformat(),
        "trail": trail_name,
        "status": "FAIL" if failures else "PASS",
        "failures": failures,
    }
    print(json.dumps(result, default=str))
    if failures:
        sns.publish(
            TopicArn=topic_arn,
            Subject="CRITICAL: TF3 Mandate 12 audit heartbeat failed",
            Message=json.dumps(result, indent=2, default=str),
        )
    return result
