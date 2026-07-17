# Task Mandate 12 — Audit không thể bị đánh bại

Thư mục này chứa tài liệu phân tích và mã staging cho Mandate 12 của TF3. Repository production `Phase3-TF3-Infra-Sentinel` chỉ được đọc; chưa có file nào trong `code_audit` được copy hoặc deploy. (sẽ có plan deploy sau review).

## Đọc nhanh

### Bộ draft mới để phê duyệt

1. `01-yeu-cau-va-gap-analysis-mandate-12.md`
2. `02-solution-va-thiet-ke-mandate-12.md`
3. `03-ke-hoach-va-runbook-trien-khai-mandate-12.md`
4. `04-kich-ban-tan-cong-va-bang-chung-mandate-12.md`

Các file đánh số 01–06 cũ được giữ tạm để đối chiếu và chưa xóa. `code_audit/` đang tạm ngưng.

### Tài liệu nguồn/cũ

1. `MANDATE-12-audit-anti-defeat-_BTC.md` — đề chính thức.(không thay đổi)
2. `01-tom-tat-yeu-cau-dau-vao-dau-ra-mandate-12.md` — yêu cầu và acceptance criteria.
3. `02-phan-tich-du-an-hien-tai-voi-mandate-12.md` — hiện trạng/gap của TF3.
4. `03-de-xuat-solution-mandate-12-va-trade-off.md` — giải pháp chọn.
5. `04-runbook-trien-khai-mandate-12.md` — runbook.
6. `05-thiet-ke-flow-mandate-12.md` — flow mục tiêu.
7. `06-kich-ban-tan-cong-va-bang-chung-mandate-12.md` — mentor tests.
8. `code_audit/` — Terraform staging và hướng dẫn triển khai.

## Trạng thái

- Tài liệu/mã: `DESIGNED`.
- AWS live: chưa kiểm tra hoặc triển khai trong task này.
- Không đánh dấu `DEPLOYED`/`VERIFIED` trước khi plan, apply và mentor test có evidence.
