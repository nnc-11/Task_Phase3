output "audit_bucket_name" { value = aws_s3_bucket.audit.id }
output "audit_bucket_arn" { value = aws_s3_bucket.audit.arn }
output "audit_kms_key_arn" { value = aws_kms_key.audit.arn }
output "expected_trail_arn" { value = local.trail_arn }
output "retention_days" { value = var.retention_days }

