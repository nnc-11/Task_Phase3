# Audit access root

Tạo hai role sau foundation:

- `tf3-m12-audit-admin`: chỉ đọc trail/archive/rules/topics để lấy evidence;
- `tf3-m12-audit-breakglass`: chỉ `StartLogging`, `EnableRule`, read/test SNS.

Input lấy từ upgraded M11 production outputs/live discovery. `audit_rule_arns` phải gồm 5 primary rules (`g1/g4/g5/g6/g7`), 3 global rules (`g2/g3/g8`) và heartbeat schedule: tối thiểu 9 ARN. Thêm đúng 3 Lambda, 3 log groups, 2 heartbeat alarms và 2 topics để audit-admin đọc được toàn bộ evidence path. Trusted principal phải là named MFA-capable user/role, không phải root.

Root này dùng backend/state riêng và chỉ deploy sau khi foundation healthy, mọi recipient bắt buộc trên cả hai SNS topics đã Confirmed.

---

**Phiên bản:** v2.0
**Cập nhật:** 21/07/2026
**Trạng thái:** STAGING ONLY
