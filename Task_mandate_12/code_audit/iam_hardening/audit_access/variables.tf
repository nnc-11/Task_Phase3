variable "name_prefix" {
  description = "Prefix for the two protected audit-access roles and policies."
  type        = string
  default     = "tf3-m12"

  validation {
    condition     = can(regex("^[a-z0-9-]{3,40}$", var.name_prefix))
    error_message = "name_prefix must contain only lowercase letters, numbers and hyphens."
  }
}

variable "region" {
  description = "AWS region of the existing TF3 production foundation."
  type        = string
  default     = "ap-southeast-1"

  validation {
    condition     = var.region == "ap-southeast-1"
    error_message = "Mandate 12 audit access is approved only for ap-southeast-1."
  }
}

variable "audit_bucket_arn" {
  description = "ARN of the Object-Lock audit archive bucket created by the foundation."
  type        = string

  validation {
    condition     = can(regex("^arn:aws:s3:::[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.audit_bucket_arn))
    error_message = "audit_bucket_arn must be a valid S3 bucket ARN."
  }
}

variable "audit_trail_arn" {
  description = "ARN of the protected CloudTrail trail created by the foundation."
  type        = string

  validation {
    condition     = can(regex("^arn:aws:cloudtrail:[a-z0-9-]+:197826770971:trail/.+$", var.audit_trail_arn))
    error_message = "audit_trail_arn must be a CloudTrail trail ARN in account 197826770971."
  }
}

variable "alert_topic_arns" {
  description = "Exactly the primary, global and same-region heartbeat-fallback SNS topic ARNs."
  type        = set(string)

  validation {
    condition     = length(var.alert_topic_arns) == 3 && alltrue([for arn in var.alert_topic_arns : can(regex("^arn:aws:sns:[a-z0-9-]+:197826770971:.+$", arn))])
    error_message = "alert_topic_arns must contain exactly three valid SNS topic ARNs: primary, global and heartbeat fallback."
  }
}

variable "audit_rule_arns" {
  description = "All EventBridge anti-tamper and heartbeat schedule rule ARNs emitted by the foundation."
  type        = set(string)

  validation {
    condition     = length(var.audit_rule_arns) >= 9 && alltrue([for arn in var.audit_rule_arns : can(regex("^arn:aws:events:[a-z0-9-]+:197826770971:rule/.+$", arn))])
    error_message = "audit_rule_arns must contain all upgraded M11/M12 EventBridge rules plus the heartbeat schedule (at least nine valid ARNs)."
  }
}

variable "audit_lambda_arns" {
  description = "Primary router, global router and heartbeat Lambda ARNs."
  type        = set(string)
  validation {
    condition     = length(var.audit_lambda_arns) == 3 && alltrue([for arn in var.audit_lambda_arns : can(regex("^arn:aws:lambda:[a-z0-9-]+:197826770971:function:.+$", arn))])
    error_message = "audit_lambda_arns must contain exactly three valid Lambda ARNs."
  }
}

variable "audit_log_group_arns" {
  description = "Log-group ARNs of the two routers and heartbeat, without :*."
  type        = set(string)
  validation {
    condition     = length(var.audit_log_group_arns) == 3 && alltrue([for arn in var.audit_log_group_arns : can(regex("^arn:aws:logs:[a-z0-9-]+:197826770971:log-group:.+$", arn)) && !endswith(arn, ":*")])
    error_message = "audit_log_group_arns must contain exactly three valid log-group ARNs."
  }
}

variable "heartbeat_alarm_arns" {
  description = "Heartbeat missing/errors alarm ARNs."
  type        = set(string)
  validation {
    condition     = length(var.heartbeat_alarm_arns) == 2 && alltrue([for arn in var.heartbeat_alarm_arns : can(regex("^arn:aws:cloudwatch:[a-z0-9-]+:197826770971:alarm:.+$", arn))])
    error_message = "heartbeat_alarm_arns must contain exactly two valid alarm ARNs."
  }
}

variable "trusted_principal_arns" {
  description = "Named MFA-capable IAM users in account 197826770971; roles/root are deliberately not accepted because this trust enforces aws:MultiFactorAuthPresent."
  type        = set(string)

  validation {
    condition     = length(var.trusted_principal_arns) > 0 && alltrue([for arn in var.trusted_principal_arns : can(regex("^arn:aws:iam::197826770971:user/.+$", arn))])
    error_message = "trusted_principal_arns must contain at least one named IAM user ARN in account 197826770971."
  }
}

variable "require_mfa" {
  description = "Require AWS MFA context when a trusted principal assumes either protected audit role."
  type        = bool
  default     = true
}
