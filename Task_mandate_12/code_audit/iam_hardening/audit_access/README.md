# Audit access root

Tạo hai role sau foundation:

- `tf3-m12-audit-admin`: chỉ đọc trail/archive/rules/topics để lấy evidence;
- `tf3-m12-audit-breakglass`: chỉ `StartLogging`, `EnableRule`, read/test SNS.

Input lấy từ upgraded M11 production outputs/live discovery. `audit_rule_arns` phải gồm 5 primary rules (`g1/g4/g5/g6/g7`), 3 global rules (`g2/g3/g8`) và heartbeat schedule: tối thiểu 9 ARN. Thêm đúng 3 Lambda, 3 log groups, 2 heartbeat alarms và 3 topics (primary/global/heartbeat-fallback) để audit-admin đọc được toàn bộ evidence path. Trusted principal phải là named IAM user có MFA trong account `197826770971`, không phải role/root; policy AssumeRole output phải được gắn tại root sở hữu user bằng change riêng được review.

Root này dùng backend/state riêng và chỉ deploy sau khi foundation healthy, mọi recipient bắt buộc trên primary/global/heartbeat-fallback SNS đã Confirmed.

---

**Phiên bản:** v2.1
**Cập nhật:** 21/07/2026
**Trạng thái:** STAGING ONLY
