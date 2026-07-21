# M11 → M12 audit foundation staging

Thư mục này không phải Terraform root độc lập. Nó chứa file/snippet để owner nâng cấp M11 trong production state:

| File | Đích/tác dụng |
|---|---|
| `module-variables-additions.tf.example` | Thêm input Object Lock và S3 data events vào module M11 |
| `production-variables-additions.tf.example` | Input coverage bắt buộc tại production root |
| `production-auto-tfvars.additions.example` | Lifecycle 400 + approved selectors |
| `module-main-edits.md` | Edit Object Lock, advanced selectors, module call, regional g7 và global g8 |
| `lambda-router-edits.md` | Không suppress critical audit/IAM events; map groups 7/8 |
| `production-heartbeat.tf.example` | Heartbeat/schedule/alarms dùng trail/topic M11 |
| `lambda/heartbeat.py` | Exact-check trail/digest/selectors, archive controls, rules/targets/routers, subscriptions, alarms và EKS audit |

Không tạo trail/bucket/topic thứ hai. Xem [HD_audit_foundation-v2.0.md](../HD_audit_foundation-v2.0.md).

---

**Phiên bản:** v2.0
**Cập nhật:** 21/07/2026
**Trạng thái:** STAGING ONLY — cần production owner review
