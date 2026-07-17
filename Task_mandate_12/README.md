# Mandate 12 — Audit không thể bị đánh bại

Thư mục chỉ chứa tài liệu chuẩn bị cho Mandate 12 của TF3. Dự án dùng một AWS account Free Tier; “sub account” là IAM user/role trong cùng account, không phải AWS Organizations. Repository production chỉ được đọc; chưa có thay đổi hay triển khai nào vào production.

## Bộ tài liệu hiện hành

1. [m12-gap-v1.3.md](m12-gap-v1.3.md) — yêu cầu, hiện trạng và gap.
2. [m12-solution-v1.4.md](m12-solution-v1.4.md) — solution được đề xuất và thiết kế.
3. [m12-runbook-v1.3.md](m12-runbook-v1.3.md) — kế hoạch, gate và runbook.
4. [m12-tests-v1.3.md](m12-tests-v1.3.md) — kịch bản kiểm thử và evidence.

## Tài liệu nguồn

- [MANDATE-12-audit-anti-defeat-_BTC.md](MANDATE-12-audit-anti-defeat-_BTC.md) — đề chính thức; giữ nguyên nội dung.
- [MANDATE-4_BTC.md](MANDATE-4_BTC.md) — chỉ tham khảo, không phải hạng mục đã triển khai.

`code_audit/` đang tạm dừng; không dùng để triển khai khi solution chưa được phê duyệt.

## Quy tắc version

- Minor (`v1.1` → `v1.2`): đổi tên file hiện hành và cập nhật nội dung; không giữ bản minor cũ.
- Major (`v1.x` → `v2.0`): tạo bộ file mới, giữ bộ major cũ để đối chiếu.
- Chỉ sửa bản mới nhất. Phiên bản và trạng thái luôn ghi ở cuối mỗi tài liệu làm việc.

---

**Phiên bản:** v1.4  
**Cập nhật:** 17/07/2026  
**Trạng thái:** READY FOR PREPARATION — chưa được phép apply
