# Change attach — persist `enable_ci_audit_boundary`

File: `infra/bootstrap/github-oidc/variables.tf`

Chỉ thực hiện ở change attach, sau khi policy đã được tạo và simulation
`PreAttach` đã pass.

Đổi:

```hcl
variable "enable_ci_audit_boundary" {
  description = "Attach permissions boundary Mandate 12 vào terraform_plan/terraform_apply. Xem ci-audit-boundary.tf."
  type        = bool
  default     = false
}
```

thành:

```hcl
variable "enable_ci_audit_boundary" {
  description = "Attach permissions boundary Mandate 12 vào terraform_plan/terraform_apply. Xem ci-audit-boundary.tf."
  type        = bool
  default     = true
}
```

Không chỉ truyền `-var=enable_ci_audit_boundary=true` ở command line: nếu code
vẫn default `false`, plan CI kế tiếp sẽ đề nghị gỡ boundary.

Rollback có review đổi default về `false`, tạo saved plan mới và chỉ được detach
boundary khỏi hai GHA role.
