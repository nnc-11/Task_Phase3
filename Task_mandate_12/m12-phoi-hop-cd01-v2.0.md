# Mandate 12 — Phối hợp CD01

## Audit foundation

Vì M12 tái sử dụng M11, cần owner `infra/live/production` review ngay từ foundation, không chỉ ở IAM phase.

CD01/IaC owner cung cấp:

- xác nhận M11 trail/bucket/module thuộc production state;
- change window và baseline plan hiện tại;
- approval exact S3 selectors, Compliance cutover và lifecycle 400 ngày;
- quy trình build lại Lambda router zip;
- reviewer chứng minh plan không replace/delete trail hoặc bucket.

Live 21/07 đã xác nhận trail/bucket nằm trong account và đang healthy; CD01 vẫn phải xác nhận **Terraform state ownership** vì AWS không cho biết resource đang thuộc state/root nào.

TF3/M12 cung cấp code snippets trong `code_audit/foundation`, heartbeat, coverage matrix, test/evidence và cutover gate.

## IAM hardening

CD01 cung cấp owner/workflow/OIDC subjects của `techx-corp-tf3-gha-terraform-plan/apply`, exact roles cần assume/pass-role, baseline và rollback. GitHub roles phải sửa tại `infra/bootstrap/github-oidc`; không attach out-of-band.

Input live đã có: apply role đang attach `AdministratorAccess` và chưa có boundary; `tf3-production-operator` chưa có boundary; current user có admin qua group và chưa MFA. Ngoài ra có 3 direct-admin users; `gitlab-ci-deployer` có active keys và nằm trong M11 router allowlist. CD01 xác nhận identity nào do Mandate 5 sở hữu để tránh hai mandate cùng sửa một principal.

## Thứ tự

1. Revalidate M11 live/read-only.
2. PR nâng cấp M11 → M12; plan/apply theo owner production.
3. Verify cutover/digest/heartbeat/coverage.
4. PR IAM riêng theo owning root.
5. Mentor deny tests và sign-off.

Không bàn giao access key, secret hoặc session token.

---

**Phiên bản:** v2.0
**Cập nhật:** 21/07/2026
**Trạng thái:** READY FOR COORDINATION — live facts có đủ, ownership/approval còn chờ CD01
