# Code staging Mandate 12

| Thành phần | Tác dụng |
|---|---|
| `foundation/` | Snippets nâng cấp in-place M11: data events, Compliance 365, regional g7, global g8, heartbeat và SNS fallback cùng region |
| `iam_hardening/audit_access/` | Audit-admin read-only và break-glass recovery hẹp |
| `iam_hardening/iam_change/` | Managed boundary động + executor cho identity đã xác nhận ownership; không dùng cho role thuộc state khác |
| `tools/` | Parse bản sao CloudTrail log thành evidence redacted |
| `HD_audit_foundation-v2.2.md` | Discovery → edit M11 → plan/apply → cutover evidence |
| `HD_iam_hardening-v2.1.md` | IAM ownership → audit access → boundary → migration/test |

Không copy `.terraform`, state, plan hoặc credential. Foundation v2 sửa chính M11 trong `infra/live/production`; IAM hardening vẫn là change/root riêng.

Live discovery 21/07/2026 đã xác nhận trail M11 đang chạy và EKS audit đang bật. Chưa deploy vì còn exact S3 scope/owner, SNS pending confirmations, MFA deployment identity và CD01/state approval. Dùng hai file HD riêng cho foundation và IAM.

---

**Phiên bản:** v2.2
**Cập nhật:** 21/07/2026
**Trạng thái:** STAGING ONLY — chưa deploy
