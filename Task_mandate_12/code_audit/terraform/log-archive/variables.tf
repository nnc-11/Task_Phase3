variable "region" {
  description = "CloudTrail home region and audit archive region."
  type        = string
  default     = "ap-southeast-1"
}

variable "bucket_name" {
  description = "Globally unique S3 audit archive bucket name."
  type        = string
}

variable "organization_id" {
  description = "AWS Organizations ID, for example o-xxxxxxxxxx."
  type        = string

  validation {
    condition     = can(regex("^o-[a-z0-9]{10,32}$", var.organization_id))
    error_message = "organization_id must look like o-xxxxxxxxxx."
  }
}

variable "management_account_id" {
  description = "12-digit account that owns the organization trail."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.management_account_id))
    error_message = "management_account_id must be a 12-digit AWS account ID."
  }
}

variable "trail_name" {
  description = "Organization trail name; used to constrain S3/KMS access."
  type        = string
  default     = "techx-tf3-mandate12-organization"
}

variable "retention_days" {
  description = "Default Object Lock COMPLIANCE retention."
  type        = number
  default     = 365

  validation {
    condition     = var.retention_days >= 365
    error_message = "Mandate 12 retention must be at least 365 days."
  }
}

variable "auditor_principal_arns" {
  description = "Read-only auditor/mentor role ARNs. Do not use TF3 operator admin roles."
  type        = list(string)
  default     = []
}

