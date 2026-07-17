output "organization_trail_arn" { value = aws_cloudtrail.organization.arn }
output "organization_trail_home_region" { value = var.region }
output "cloudwatch_log_group_name" { value = aws_cloudwatch_log_group.cloudtrail.name }
output "anti_audit_topic_arn" { value = aws_sns_topic.anti_audit.arn }
output "configured_sensitive_s3_object_arns" { value = var.sensitive_s3_object_arns }

