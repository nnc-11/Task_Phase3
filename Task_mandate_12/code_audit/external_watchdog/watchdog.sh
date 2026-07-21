#!/usr/bin/env bash
set -euo pipefail

required=(TRAIL_NAME AUDIT_BUCKET_NAME EKS_CLUSTER_NAME PRIMARY_RULE_NAMES GLOBAL_RULE_NAMES PRIMARY_RULE_PATTERNS_JSON GLOBAL_RULE_PATTERNS_JSON PRIMARY_ROUTER_ARN GLOBAL_ROUTER_ARN HEARTBEAT_RULE_NAME HEARTBEAT_FUNCTION_ARN HEARTBEAT_ALARM_NAMES PRIMARY_TOPIC_ARN GLOBAL_TOPIC_ARN EXPECTED_SUBSCRIPTION_ENDPOINTS)
for name in "${required[@]}"; do
  [[ -n "${!name:-}" ]] || { echo "Missing repository variable: ${name}" >&2; exit 2; }
done

status="$(aws cloudtrail get-trail-status --name "$TRAIL_NAME" --region ap-southeast-1 --output json)"
jq -e '.IsLogging == true and (.LatestDeliveryError // "") == "" and (.LatestDigestDeliveryError // "") == ""' <<<"$status" >/dev/null
now_epoch="$(date -u +%s)"
delivery_epoch="$(date -u -d "$(jq -r '.LatestDeliveryTime' <<<"$status")" +%s)"
digest_epoch="$(date -u -d "$(jq -r '.LatestDigestDeliveryTime' <<<"$status")" +%s)"
(( now_epoch - delivery_epoch <= 1200 ))
(( now_epoch - digest_epoch <= 5400 ))
aws cloudtrail describe-trails --trail-name-list "$TRAIL_NAME" --no-include-shadow-trails --region ap-southeast-1 \
  --query 'trailList[?IsMultiRegionTrail==`true` && IncludeGlobalServiceEvents==`true` && LogFileValidationEnabled==`true`]' --output json | jq -e 'length == 1' >/dev/null
aws cloudtrail get-event-selectors --trail-name "$TRAIL_NAME" --region ap-southeast-1 --output json | jq -e '.AdvancedEventSelectors | length >= 2' >/dev/null

[[ "$(aws s3api get-bucket-versioning --bucket "$AUDIT_BUCKET_NAME" --query Status --output text)" == "Enabled" ]]
aws s3api get-object-lock-configuration --bucket "$AUDIT_BUCKET_NAME" --output json | jq -e '.ObjectLockConfiguration.ObjectLockEnabled == "Enabled" and .ObjectLockConfiguration.Rule.DefaultRetention.Mode == "COMPLIANCE" and .ObjectLockConfiguration.Rule.DefaultRetention.Days >= 365' >/dev/null
aws s3api get-bucket-lifecycle-configuration --bucket "$AUDIT_BUCKET_NAME" --output json | jq -e '[.Rules[] | select(.Status == "Enabled") | .Expiration.Days] | min >= 400' >/dev/null
aws s3api get-bucket-encryption --bucket "$AUDIT_BUCKET_NAME" >/dev/null
aws s3api get-public-access-block --bucket "$AUDIT_BUCKET_NAME" --output json | jq -e '.PublicAccessBlockConfiguration | .BlockPublicAcls and .IgnorePublicAcls and .BlockPublicPolicy and .RestrictPublicBuckets' >/dev/null
aws s3api get-bucket-policy-status --bucket "$AUDIT_BUCKET_NAME" --output json | jq -e '.PolicyStatus.IsPublic == false' >/dev/null
aws s3api get-bucket-policy --bucket "$AUDIT_BUCKET_NAME" --query Policy --output text | jq -e --arg resource "arn:aws:s3:::${AUDIT_BUCKET_NAME}/*" '
  [.Statement[] | select(.Effect == "Deny") |
    (.Action | if type == "array" then . else [.] end) as $a |
    (.Resource | if type == "array" then . else [.] end) as $r |
    select(($a | index("s3:DeleteObject")) and ($a | index("s3:PutObject")) and ($r | index($resource)))] | length > 0
' >/dev/null

check_rules() {
  local region="$1" names="$2" target="$3" patterns="$4" rule actual expected state
  IFS=',' read -ra rules <<<"$names"
  for rule in "${rules[@]}"; do
    state="$(aws events describe-rule --name "$rule" --region "$region" --query State --output text)"
    [[ "$state" == "ENABLED" || "$state" == "ENABLED_WITH_ALL_CLOUDTRAIL_MANAGEMENT_EVENTS" ]]
    actual="$(aws events describe-rule --name "$rule" --region "$region" --query EventPattern --output text | jq -c -S .)"
    expected="$(jq -c -S --arg rule "$rule" '.[$rule]' <<<"$patterns")"
    [[ "$expected" != "null" && "$actual" == "$expected" ]]
    aws events list-targets-by-rule --rule "$rule" --region "$region" --query 'Targets[].Arn' --output json | jq -e --arg arn "$target" 'index($arn) != null' >/dev/null
  done
}
check_rules ap-southeast-1 "$PRIMARY_RULE_NAMES" "$PRIMARY_ROUTER_ARN" "$PRIMARY_RULE_PATTERNS_JSON"
check_rules us-east-1 "$GLOBAL_RULE_NAMES" "$GLOBAL_ROUTER_ARN" "$GLOBAL_RULE_PATTERNS_JSON"

[[ "$(aws events describe-rule --name "$HEARTBEAT_RULE_NAME" --region ap-southeast-1 --query State --output text)" == "ENABLED" ]]
aws events list-targets-by-rule --rule "$HEARTBEAT_RULE_NAME" --region ap-southeast-1 --query 'Targets[].Arn' --output json | jq -e --arg arn "$HEARTBEAT_FUNCTION_ARN" 'index($arn) != null' >/dev/null
aws lambda get-function-configuration --function-name "$PRIMARY_ROUTER_ARN" --region ap-southeast-1 --query 'State' --output text | grep -Fx Active
aws lambda get-function-configuration --function-name "$GLOBAL_ROUTER_ARN" --region us-east-1 --query 'State' --output text | grep -Fx Active
aws lambda get-function-configuration --function-name "$HEARTBEAT_FUNCTION_ARN" --region ap-southeast-1 --query 'State' --output text | grep -Fx Active

IFS=',' read -ra alarms <<<"$HEARTBEAT_ALARM_NAMES"
aws cloudwatch describe-alarms --alarm-names "${alarms[@]}" --region ap-southeast-1 --output json | jq -e --argjson n "${#alarms[@]}" '[.MetricAlarms[] | select(.ActionsEnabled == true)] | length == $n' >/dev/null
aws sns get-topic-attributes --topic-arn "$PRIMARY_TOPIC_ARN" --region ap-southeast-1 >/dev/null
aws sns get-topic-attributes --topic-arn "$GLOBAL_TOPIC_ARN" --region us-east-1 >/dev/null
check_subscriptions() {
  local region="$1" topic="$2" subscriptions endpoint
  subscriptions="$(aws sns list-subscriptions-by-topic --topic-arn "$topic" --region "$region" --output json)"
  IFS=',' read -ra endpoints <<<"$EXPECTED_SUBSCRIPTION_ENDPOINTS"
  for endpoint in "${endpoints[@]}"; do
    jq -e --arg endpoint "$endpoint" '[.Subscriptions[] | select(.Endpoint == $endpoint and .SubscriptionArn != "PendingConfirmation" and .SubscriptionArn != "Deleted")] | length == 1' <<<"$subscriptions" >/dev/null
  done
}
check_subscriptions ap-southeast-1 "$PRIMARY_TOPIC_ARN"
check_subscriptions us-east-1 "$GLOBAL_TOPIC_ARN"
aws eks describe-cluster --name "$EKS_CLUSTER_NAME" --region ap-southeast-1 --output json | jq -e '[.cluster.logging.clusterLogging[] | select(.enabled == true) | .types[]] | index("audit") != null' >/dev/null

echo "M12 external watchdog: PASS"
