# Mandate 12 — Audit anti-defeat

Bộ chuẩn bị cho TF3 trên AWS account `197826770971`. Repository product chỉ được đọc trong lần cập nhật này; chưa có apply/mutation production.

## Bộ v2 hiện hành

1. [m12-gap-v2.0.md](m12-gap-v2.0.md) — baseline hạ tầng mới và gap với M11.
2. [m12-coverage-v2.1.md](m12-coverage-v2.1.md) — inventory/coverage bắt buộc.
3. [m12-iam-scope-v2.0.md](m12-iam-scope-v2.0.md) — IAM ownership và migration.
4. [m12-phoi-hop-cd01-v2.0.md](m12-phoi-hop-cd01-v2.0.md) — input/output phối hợp CD01.
5. [m12-solution-v2.3.md](m12-solution-v2.3.md) — kiến trúc và trade-off đã chọn.
6. [m12-runbook-v2.3.md](m12-runbook-v2.3.md) — phase/gate/rollback.
7. [m12-tests-v2.3.md](m12-tests-v2.3.md) — mentor tests và evidence.
8. [m12-plan-v2.3.md](m12-plan-v2.3.md) — kế hoạch thực thi và gate.
9. [code_audit/HD_audit_foundation-v2.3.md](code_audit/HD_audit_foundation-v2.3.md) — nâng cấp trail M11 và heartbeat step-by-step.
10. [code_audit/HD_iam_hardening-v2.1.md](code_audit/HD_iam_hardening-v2.1.md) — IAM hardening step-by-step.

Bộ `v1.x` và các file `v2.0` đã có bản thay thế `v2.1` đều đã được loại bỏ. Các file còn mang `v2.0` là tài liệu hiện hành chưa có bản thay thế, không phải bản trùng cần xóa.

## Quyết định hiện tại

- Tận dụng trail/archive/alert plane M11; nâng cấp in-place tại production root.
- Không tạo trail/bucket/router M12 trùng M11; chỉ thêm một SNS heartbeat-fallback cùng region cho alarm.
- IAM hardening làm sau foundation, tại đúng Terraform root sở hữu principal.
- Discovery AWS live ngày 21/07/2026 đã xác nhận M11 đang chạy; vẫn phải revalidate ngay trước plan/change window.

## Baseline live đã xác nhận

- Một trail M11 multi-region đang `IsLogging=true`, integrity validation bật, nhưng mới ghi management events và **chưa có S3 object data events**.
- Bucket audit đang Versioning `Enabled`, Object Lock `GOVERNANCE 14 ngày`, lifecycle `30 ngày`.
- EKS `techx-corp-tf3` đang bật `api`, `audit`, `authenticator`; log group giữ `90 ngày`.
- `AdministratorAccess` còn qua 1 group, 3 IAM users trực tiếp và GitHub apply role; current user chưa MFA. Có admin users dùng active long-lived keys, cần owner-led migration.
- SNS còn subscription chưa xác nhận: primary 3, global 1. Cutover chỉ cần tối thiểu một email `Confirmed` trên mỗi topic; pending subscription khác không chặn nghiệm thu.

## Nguồn

- `MANDATE-12-audit-anti-defeat-_BTC.md`: đề chính thức, không sửa.
- `MANDATE-4_BTC.md`: chỉ tham khảo, không phải baseline đã triển khai.

---

**Phiên bản:** v2.3
**Cập nhật:** 23/07/2026
**Trạng thái:** HANDOFF READY / NOT APPROVED FOR APPLY — live dependency và saved-plan gate phải được hoàn tất khi có quyền deploy
