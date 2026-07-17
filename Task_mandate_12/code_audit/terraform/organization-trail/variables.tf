variable "region" {
  type    = string
  default = "ap-southeast-1"
}

variable "trail_name" {
  type    = string
  default = "techx-tf3-mandate12-organization"
}

variable "audit_bucket_name" {
  description = "Output audit_bucket_name from log-archive root."
  type        = string
}

variable "audit_kms_key_arn" {
  description = "Output audit_kms_key_arn from log-archive root."
  type        = string
}

variable "sensitive_s3_object_arns" {
  description = "Approved S3 object ARN prefixes, each ending with /. Empty only during initial management-event bootstrap."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for arn in var.sensitive_s3_object_arns : can(regex("^arn:[^:]+:s3:::[^/]+/.+/$", arn))])
    error_message = "Each sensitive_s3_object_arns entry must be an S3 object ARN prefix ending with /."
  }
}

variable "alert_email_endpoints" {
  description = "Security-owned email endpoints. Subscription confirmation is manual."
  type        = set(string)
  default     = []
}

variable "cloudwatch_log_retention_days" {
  type    = number
  default = 90
}

