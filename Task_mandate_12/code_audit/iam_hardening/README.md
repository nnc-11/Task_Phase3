# IAM hardening Mandate 12

Thực hiện sau khi trail M11 đã nâng cấp, digest/heartbeat healthy.

- `audit_access/`: audit-admin read-only và break-glass chỉ recovery.
- `iam_change/`: tạo managed permissions boundary từ exact ARN inputs và executor MFA cho target không thuộc Terraform state khác.

Boundary là HCL động trong `iam_change/main.tf`; không còn JSON template thủ công dễ thiếu ARN. Nó bảo vệ trail, bucket, 9+ rules, 3 Lambda, 3 log groups, 2 alarms, 3 topics (primary/global/heartbeat-fallback), toàn bộ subscription đã confirm, 2 audit roles và đường IAM/STS escalation.

## Ownership gate

- GitHub apply/plan roles thuộc `infra/bootstrap/github-oidc`: sửa tại root đó.
- `tf3-production-operator/readonly` thuộc `infra/live/production`: sửa tại root đó.
- Chỉ đặt `target_ownership_confirmed=true` khi có bằng chứng target không do state khác quản lý hoặc ownership đã chuyển.

Không harden hàng loạt và không dùng root. Xem [m12-iam-scope-v2.0.md](../../m12-iam-scope-v2.0.md).

---

**Phiên bản:** v2.1
**Cập nhật:** 21/07/2026
**Trạng thái:** HANDOFF READY / EXECUTION BLOCKED pending IAM inventory/ownership
