# M9-07d + M9-15a: Những gì đã làm

## M9-07d: Schema Design/ADR (3 files, branch M9-03)

### 1. `docs/adr/M9-07d-schema-analysis.md`
- Phân tích 2 bảng: `products` (10 rows, READ customer path) + `orderitem` (395k rows, WRITE path)
- Lý do chọn 2 bảng: không có bảng vừa lớn vừa customer-facing trong cùng 1 bảng
- Queries đo kích thước, FK, index, traffic
- Kết luận: 2 bảng bổ trợ nhau để chứng minh compliance #1

### 2. `docs/adr/M9-07d-schema-migration-adr.md` (ADR packet)
- **2 bảng mapping:** `products.categories` TEXT→text[], `orderitem` ADD `created_at`
- **Chuỗi migrate:** expand → dual-write → backfill → validate → contract (W1+W2)
- **SQL skeleton:** idempotent DDL với `lock_timeout='1s'` + `statement_timeout='30s'` + retry
- **Watermark semantics:** sentinel = migration timestamp, semantic rõ ràng
- **SET NOT NULL trick:** validated CHECK → skip full-table scan (bounded lock ms)
- **Risk register:** 7 risks (R1-R7) với mitigation
- **Evidence protocol:** pre/during/post W1+W2 queries
- **Sequence diagram** + Rollback plan

### 3. `docs/adr/M9-15a-mentor-sign-off-request.md` (mentor packet)

---

## M9-15a: Mentor Sign-Off Request

### `docs/adr/M9-15a-mentor-sign-off-request.md`
- Tóm tắt 2 lựa chọn cho mentor (Option A: 2 bảng vs Option B: 1 bảng)
- 5 quyết định cần mentor chốt: bảng mapping, watermark semantics, W2 observation, timeout, batch params
- Xin gia hạn từ 19/07 → 13/08 (giải thích lý do)
- Checklist 6 items cho mentor ký
- Next steps timeline phụ thuộc approval

---

## Files tạo/sửa trong project (branch M9-03)

| File | Action | Lines |
|------|--------|-------|
| `docs/adr/M9-07d-schema-analysis.md` | CREATE | 239 |
| `docs/adr/M9-07d-schema-migration-adr.md` | CREATE | 595 |
| `docs/adr/M9-15a-mentor-sign-off-request.md` | CREATE | 238 |

**Total:** 3 files, 1,072 lines

## Status

- ✅ M9-07d hoàn thành — ADR packet sẵn sàng cho mentor
- ⏳ M9-15a chờ mentor ký — cần phản hồi trước 31/07 AM
