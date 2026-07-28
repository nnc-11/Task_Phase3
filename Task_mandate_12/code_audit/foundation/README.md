# M11 → M12 audit foundation staging

Thư mục này không phải Terraform root độc lập. Nó chứa file/snippet để owner nâng cấp M11 trong production state:

| File | Đích/tác dụng |
|---|---|
| `module-variables-additions.tf.example` | Thêm input Object Lock và S3 data events vào module M11 |
| `production-variables-additions.tf.example` | Input coverage bắt buộc tại production root |
| `production-auto-tfvars.additions.example` | Lifecycle 400 + approved selectors |
| `module-main-edits.md` | Edit Object Lock, advanced selectors, module call, regional g7 và global g8 |
| `lambda-router-edits.md` | Không suppress critical audit/IAM events; map groups 7/8 |
| `production-heartbeat.tf.example` | Heartbeat/schedule/alarms dùng trail M11; tạo SNS fallback và policy CloudWatch publish cho primary/fallback |
| `lambda/heartbeat.py` | Exact-check trail/digest/selectors, archive controls, source semantics, rules/targets/routers, ba alert topics, alarms và EKS audit; lỗi được đưa vào CloudWatch Errors alarm để chống gửi mail lặp |

Không tạo trail/bucket/router trùng M11. Có đúng một topic mới, chỉ làm fallback cùng region cho heartbeat alarm; đây không phải alert plane thay thế M11. Mỗi topic chỉ cần tối thiểu một email subscription `Confirmed`; pending subscription khác không làm heartbeat FAIL. Xem [HD_audit_foundation-v2.3.md](../HD_audit_foundation-v2.3.md).

---

**Phiên bản:** v2.3
**Cập nhật:** 23/07/2026
**Trạng thái:** STAGING ONLY — cần production owner review
