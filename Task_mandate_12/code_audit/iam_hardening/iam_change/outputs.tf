output "iam_change_role_arn" {
  description = "MFA-protected role used only for reviewed boundary version/attachment changes."
  value       = try(aws_iam_role.iam_change[0].arn, null)
}

output "operator_boundary_policy_arn" {
  description = "Managed permissions-boundary ARN created and protected by this root."
  value       = aws_iam_policy.operator_boundary.arn
}

output "iam_change_executor_policy_arn" {
  description = "Least-privilege policy attached only to the IAM change role."
  value       = try(aws_iam_policy.iam_change_executor[0].arn, null)
}

output "security_owner_assume_iam_change_policy_arn" {
  description = "Attach manually and only to the named trusted change owners in a separately reviewed IAM change."
  value       = try(aws_iam_policy.security_owner_assume_iam_change[0].arn, null)
}
