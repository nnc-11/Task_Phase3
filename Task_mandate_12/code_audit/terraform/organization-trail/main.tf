resource "aws_cloudwatch_log_group" "cloudtrail" {
  name              = "/aws/cloudtrail/${var.trail_name}"
  retention_in_days = var.cloudwatch_log_retention_days
}

data "aws_iam_policy_document" "cloudtrail_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "cloudtrail_logs" {
  name               = "techx-tf3-mandate12-cloudtrail-logs"
  assume_role_policy = data.aws_iam_policy_document.cloudtrail_assume.json
}

data "aws_iam_policy_document" "cloudtrail_logs" {
  statement {
    effect    = "Allow"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.cloudtrail.arn}:*"]
  }
}

resource "aws_iam_role_policy" "cloudtrail_logs" {
  role   = aws_iam_role.cloudtrail_logs.id
  policy = data.aws_iam_policy_document.cloudtrail_logs.json
}

resource "aws_cloudtrail" "organization" {
  name                          = var.trail_name
  s3_bucket_name                = var.audit_bucket_name
  kms_key_id                    = var.audit_kms_key_arn
  include_global_service_events = true
  is_multi_region_trail         = true
  is_organization_trail         = true
  enable_logging                = true
  enable_log_file_validation    = true
  cloud_watch_logs_group_arn    = "${aws_cloudwatch_log_group.cloudtrail.arn}:*"
  cloud_watch_logs_role_arn     = aws_iam_role.cloudtrail_logs.arn

  lifecycle {
    prevent_destroy = true
  }

  advanced_event_selector {
    name = "All management events"
    field_selector {
      field  = "eventCategory"
      equals = ["Management"]
    }
  }

  dynamic "advanced_event_selector" {
    for_each = length(var.sensitive_s3_object_arns) == 0 ? [] : [1]
    content {
      name = "Sensitive S3 object reads and writes"
      field_selector {
        field  = "eventCategory"
        equals = ["Data"]
      }
      field_selector {
        field  = "resources.type"
        equals = ["AWS::S3::Object"]
      }
      field_selector {
        field       = "resources.ARN"
        starts_with = var.sensitive_s3_object_arns
      }
    }
  }
}

resource "aws_sns_topic" "anti_audit" {
  name              = "techx-tf3-mandate12-anti-audit"
  kms_master_key_id = "alias/aws/sns"
}

resource "aws_sns_topic_subscription" "email" {
  for_each  = var.alert_email_endpoints
  topic_arn = aws_sns_topic.anti_audit.arn
  protocol  = "email"
  endpoint  = each.value
}

resource "aws_cloudwatch_log_metric_filter" "anti_audit" {
  name           = "mandate12-anti-audit-api-calls"
  log_group_name = aws_cloudwatch_log_group.cloudtrail.name
  pattern        = "{ ($.eventSource = \"cloudtrail.amazonaws.com\") && (($.eventName = \"StopLogging\") || ($.eventName = \"DeleteTrail\") || ($.eventName = \"UpdateTrail\") || ($.eventName = \"PutEventSelectors\")) }"

  metric_transformation {
    name      = "AntiAuditApiCallCount"
    namespace = "TechX/TF3/Mandate12"
    value     = "1"
  }
}

resource "aws_cloudwatch_log_metric_filter" "audit_kms_tamper" {
  name           = "mandate12-audit-kms-tamper"
  log_group_name = aws_cloudwatch_log_group.cloudtrail.name
  pattern        = "{ ($.eventSource = \"kms.amazonaws.com\") && (($.eventName = \"DisableKey\") || ($.eventName = \"ScheduleKeyDeletion\") || ($.eventName = \"PutKeyPolicy\") || ($.eventName = \"CreateGrant\") || ($.eventName = \"RevokeGrant\")) }"

  metric_transformation {
    name      = "AntiAuditApiCallCount"
    namespace = "TechX/TF3/Mandate12"
    value     = "1"
  }
}

resource "aws_cloudwatch_log_metric_filter" "audit_s3_tamper" {
  name           = "mandate12-audit-s3-tamper"
  log_group_name = aws_cloudwatch_log_group.cloudtrail.name
  pattern        = "{ ($.eventSource = \"s3.amazonaws.com\") && (($.eventName = \"PutBucketPolicy\") || ($.eventName = \"DeleteBucketPolicy\") || ($.eventName = \"PutBucketLifecycle\") || ($.eventName = \"DeleteBucketLifecycle\") || ($.eventName = \"PutBucketEncryption\") || ($.eventName = \"DeleteBucketEncryption\") || ($.eventName = \"PutObjectLockConfiguration\")) }"

  metric_transformation {
    name      = "AntiAuditApiCallCount"
    namespace = "TechX/TF3/Mandate12"
    value     = "1"
  }
}

resource "aws_cloudwatch_log_metric_filter" "organization_tamper" {
  name           = "mandate12-organization-tamper"
  log_group_name = aws_cloudwatch_log_group.cloudtrail.name
  pattern        = "{ ($.eventSource = \"organizations.amazonaws.com\") && (($.eventName = \"LeaveOrganization\") || ($.eventName = \"RemoveAccountFromOrganization\") || ($.eventName = \"DisableAWSServiceAccess\") || ($.eventName = \"DeregisterDelegatedAdministrator\") || ($.eventName = \"UpdatePolicy\") || ($.eventName = \"DeletePolicy\")) }"

  metric_transformation {
    name      = "AntiAuditApiCallCount"
    namespace = "TechX/TF3/Mandate12"
    value     = "1"
  }
}

resource "aws_cloudwatch_metric_alarm" "anti_audit" {
  alarm_name          = "techx-tf3-mandate12-anti-audit-api-call"
  alarm_description   = "CloudTrail destructive or coverage-changing API call observed"
  namespace           = "TechX/TF3/Mandate12"
  metric_name         = "AntiAuditApiCallCount"
  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.anti_audit.arn]
}
