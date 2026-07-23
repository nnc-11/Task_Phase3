# Patch `infra/bootstrap/github-oidc/main.tf`

## Mục tiêu

Cho plan role đọc thêm đúng bootstrap state key để workflow `terraform-bootstrap-plan.yml` hoạt động.

Trong inline policy `terraform_plan_state_access`, đổi:

```hcl
Resource = "arn:aws:s3:::${var.state_bucket_name}/${var.state_key}"
```

thành:

```hcl
Resource = [
  "arn:aws:s3:::${var.state_bucket_name}/${var.state_key}",
  "arn:aws:s3:::${var.state_bucket_name}/${var.bootstrap_state_key}",
]
```

Không đổi trust policy, `AdministratorAccess`, tên role hoặc backend.

## Cập nhật comment bị cũ

Trong `aws_iam_role.terraform_apply`, thay comment cũ nói boundary “cho phép IAM
CRUD chung để Terraform vẫn quản audit foundation” bằng:

```hcl
# Mandate 12: apply role vẫn giữ AdministratorAccess cho workload nhưng
# permissions boundary chặn IAM write và Audit Foundation mutation.
# IAM change đi qua bootstrap root; Audit Foundation change đi qua maintenance
# path có MFA và Security Owner review.
permissions_boundary = var.enable_ci_audit_boundary ? aws_iam_policy.ci_audit_boundary.arn : null
```

Comment của plan role có thể giữ nguyên vì role đó vốn chỉ có `ReadOnlyAccess`.
