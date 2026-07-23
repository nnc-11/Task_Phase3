# Patch `infra/bootstrap/github-oidc/variables.tf`

## 1. Thêm bootstrap state key

```hcl
variable "bootstrap_state_key" {
  description = "Exact state key for the github-oidc bootstrap root."
  type        = string
  default     = "bootstrap/github-oidc/terraform.tfstate"

  validation {
    condition     = var.bootstrap_state_key == "bootstrap/github-oidc/terraform.tfstate"
    error_message = "Mandate 12 bootstrap plan must use the dedicated github-oidc state key."
  }
}
```

## 2. Không tự đưa GitLab/human user vào rollout

Đổi default:

```hcl
variable "additional_bounded_principal_arns" {
  description = "Additional principals approved for a separate owner-led rollout."
  type        = list(string)
  default     = []

  validation {
    condition = alltrue([
      for arn in var.additional_bounded_principal_arns :
      can(regex("^arn:aws:iam::[0-9]{12}:(user|role)/.+$", arn))
    ])
    error_message = "Each value must be an IAM user or role ARN."
  }
}
```

Không thêm `gitlab-ci-deployer` cho tới khi pipeline owner phê duyệt và migration test hoàn tất.

