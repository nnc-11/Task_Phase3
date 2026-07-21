variable "region" {
  description = "AWS region of the existing TF3 production foundation."
  type        = string
  default     = "ap-southeast-1"

  validation {
    condition     = var.region == "ap-southeast-1"
    error_message = "Mandate 12 IAM change executor is approved only for ap-southeast-1."
  }
}

variable "name_prefix" {
  description = "Prefix for the protected IAM change role and policies."
  type        = string
  default     = "tf3-m12"

  validation {
    condition     = can(regex("^[a-z0-9-]{3,40}$", var.name_prefix))
    error_message = "name_prefix must contain only lowercase letters, numbers and hyphens."
  }
}

variable "audit_trail_arn" {
  description = "Exact ARN of the reused M11 CloudTrail trail."
  type        = string
  validation {
    condition     = can(regex("^arn:aws:cloudtrail:[a-z0-9-]+:197826770971:trail/.+$", var.audit_trail_arn))
    error_message = "audit_trail_arn must be a trail ARN in account 197826770971."
  }
}

variable "audit_bucket_arn" {
  description = "Exact ARN of the reused M11 audit bucket."
  type        = string
  validation {
    condition     = can(regex("^arn:aws:s3:::[a-z0-9][a-z0-9.-]+$", var.audit_bucket_arn))
    error_message = "audit_bucket_arn must be a valid S3 bucket ARN."
  }
}

variable "audit_rule_arns" {
  description = "All protected rules: primary g1/g4/g5/g6/g7, global g2/g3/g8 and heartbeat schedule."
  type        = set(string)
  validation {
    condition     = length(var.audit_rule_arns) >= 9 && alltrue([for arn in var.audit_rule_arns : can(regex("^arn:aws:events:[a-z0-9-]+:197826770971:rule/.+$", arn))])
    error_message = "audit_rule_arns must contain at least nine valid protected rule ARNs."
  }
}

variable "audit_lambda_arns" {
  description = "Exactly the primary router, global router and heartbeat Lambda ARNs."
  type        = set(string)
  validation {
    condition     = length(var.audit_lambda_arns) == 3 && alltrue([for arn in var.audit_lambda_arns : can(regex("^arn:aws:lambda:[a-z0-9-]+:197826770971:function:.+$", arn))])
    error_message = "audit_lambda_arns must contain exactly three Lambda ARNs."
  }
}

variable "audit_log_group_arns" {
  description = "CloudWatch log-group ARNs of the two routers and heartbeat (use log-group ARN without :*)."
  type        = set(string)
  validation {
    condition     = length(var.audit_log_group_arns) == 3 && alltrue([for arn in var.audit_log_group_arns : can(regex("^arn:aws:logs:[a-z0-9-]+:197826770971:log-group:.+$", arn)) && !endswith(arn, ":*")])
    error_message = "audit_log_group_arns must contain exactly three log-group ARNs."
  }
}

variable "heartbeat_alarm_arns" {
  description = "The heartbeat missing and errors alarm ARNs."
  type        = set(string)
  validation {
    condition     = length(var.heartbeat_alarm_arns) == 2 && alltrue([for arn in var.heartbeat_alarm_arns : can(regex("^arn:aws:cloudwatch:[a-z0-9-]+:197826770971:alarm:.+$", arn))])
    error_message = "heartbeat_alarm_arns must contain exactly two alarm ARNs."
  }
}

variable "alert_topic_arns" {
  description = "Exactly the primary, global and same-region heartbeat-fallback alert topic ARNs."
  type        = set(string)
  validation {
    condition     = length(var.alert_topic_arns) == 3 && alltrue([for arn in var.alert_topic_arns : can(regex("^arn:aws:sns:[a-z0-9-]+:197826770971:.+$", arn))])
    error_message = "alert_topic_arns must contain exactly three topic ARNs: primary, global and heartbeat fallback."
  }
}

variable "alert_subscription_arns" {
  description = "Every confirmed required subscription ARN on primary, global and heartbeat-fallback topics; PendingConfirmation is invalid."
  type        = set(string)
  validation {
    condition     = length(var.alert_subscription_arns) >= 3 && alltrue([for arn in var.alert_subscription_arns : can(regex("^arn:aws:sns:[a-z0-9-]+:197826770971:.+:[0-9a-f-]+$", arn))])
    error_message = "alert_subscription_arns must contain at least one confirmed subscription for each of the three protected topics."
  }
}

variable "audit_access_role_arns" {
  description = "Exactly the M12 audit-admin and break-glass role ARNs."
  type        = set(string)
  validation {
    condition     = length(var.audit_access_role_arns) == 2 && alltrue([for arn in var.audit_access_role_arns : can(regex("^arn:aws:iam::197826770971:role/.+$", arn))])
    error_message = "audit_access_role_arns must contain exactly two role ARNs."
  }
}

variable "approved_assume_role_arns" {
  description = "Reviewed non-audit roles daily operators may assume. Empty means deny all role assumption."
  type        = set(string)
  default     = []
  validation {
    condition     = alltrue([for arn in var.approved_assume_role_arns : can(regex("^arn:aws:iam::197826770971:role/.+$", arn))])
    error_message = "approved_assume_role_arns must contain only role ARNs in account 197826770971."
  }
}

variable "target_user_arns" {
  description = "Explicit daily-operator IAM user ARNs eligible to receive this exact boundary."
  type        = set(string)
  default     = []

  validation {
    condition     = alltrue([for arn in var.target_user_arns : can(regex("^arn:aws:iam::197826770971:user/.+$", arn))])
    error_message = "target_user_arns must contain only IAM user ARNs from account 197826770971."
  }
}

variable "target_role_arns" {
  description = "Explicit daily-operator IAM role ARNs eligible to receive this exact boundary."
  type        = set(string)
  default     = []

  validation {
    condition     = alltrue([for arn in var.target_role_arns : can(regex("^arn:aws:iam::197826770971:role/.+$", arn))])
    error_message = "target_role_arns must contain only IAM role ARNs from account 197826770971."
  }
}

variable "trusted_change_owner_arns" {
  description = "Named MFA-capable IAM users allowed to assume the executor; roles/root are excluded because this trust enforces aws:MultiFactorAuthPresent."
  type        = set(string)
  default     = []

  validation {
    condition     = alltrue([for arn in var.trusted_change_owner_arns : can(regex("^arn:aws:iam::197826770971:user/.+$", arn))])
    error_message = "trusted_change_owner_arns may contain only named IAM user ARNs in account 197826770971."
  }
}

variable "enable_iam_change_executor" {
  description = "Create the MFA executor only for exact unmanaged/transferred targets. Boundary-only deployment keeps this false."
  type        = bool
  default     = false
}

variable "allow_boundary_removal" {
  description = "Emergency rollback only. False by default; set true only in a separately approved, time-boxed change."
  type        = bool
  default     = false
}

variable "target_ownership_confirmed" {
  description = "Must be true only after each target is confirmed unmanaged by another Terraform state, or its owning root is updated in the same approved change."
  type        = bool
  default     = false
}
