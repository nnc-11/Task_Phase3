# Operator boundary và IAM change executor root

Root này luôn tạo managed operator boundary từ exact audit-resource ARNs. Mặc định `enable_iam_change_executor=false`: chỉ tạo boundary để các owner roots tham chiếu. Chỉ bật executor MFA cho exact user/role đã chuyển ownership hoặc không thuộc state khác.

## Gate cứng

Khi `enable_iam_change_executor=true`, `target_ownership_confirmed=false` làm plan/apply fail. Chỉ đặt `true` khi:

- target không do Terraform state khác quản lý; hoặc
- target đã được import/chuyển ownership bằng change đã duyệt.

Không dùng root này cho:

- `techx-corp-tf3-gha-terraform-plan/apply` thuộc `infra/bootstrap/github-oidc`;
- `tf3-production-operator/readonly` thuộc `infra/live/production`.

Các role trên phải harden tại root sở hữu. `allow_boundary_removal=true` chỉ dùng trong rollback riêng, time-boxed và có approval.

---

**Phiên bản:** v2.0
**Cập nhật:** 21/07/2026
**Trạng thái:** BOUNDARY READY FOR REVIEW / EXECUTOR BLOCKED pending ownership confirmation
