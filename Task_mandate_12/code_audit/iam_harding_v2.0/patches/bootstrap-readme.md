# Patch `infra/bootstrap/github-oidc/README.md`

Thay phần “Mandate 12 — CI audit boundary” cũ bằng nội dung sau để tài liệu khớp
policy v2.0:

```markdown
## Mandate 12 — CI audit boundary v2.0

Apply role vẫn giữ `AdministratorAccess` cho deployment workload, nhưng
permissions boundary là trần quyền với các explicit deny:

- production CI không được tạo/sửa/xóa IAM;
- production CI không được sửa CloudTrail, archive bucket/object, audit KMS,
  EventBridge/SNS/Lambda/log group/alarm thuộc Audit Foundation;
- `iam:PassRole` chỉ còn cho role TF3 đã duyệt;
- role chaining và federation credential issuance bị chặn.

Boundary không cấp thêm quyền. Quyền thực tế là giao của identity policy và
boundary; explicit deny luôn thắng.

IAM change phải đi qua root/state `infra/bootstrap/github-oidc`. Audit Foundation
change phải đi qua maintenance path riêng bằng named MFA identity, saved plan,
Security Owner review và không chạy đồng thời workflow production.

Rollout gồm hai apply riêng: tạo policy với
`enable_ci_audit_boundary=false`, simulation; sau đó mới attach với
`enable_ci_audit_boundary=true`.

Không attach tự động vào GitLab hoặc human/AIOps identities.
```
