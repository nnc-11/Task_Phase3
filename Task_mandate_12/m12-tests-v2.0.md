# Mandate 12 — Test và evidence v2

## An toàn

Chỉ test sau approval, dùng canary/bounded identity. Không test root, production secret/object hoặc archive object thật. Policy simulation trước mutation; action đáng lẽ deny mà thành công là Critical incident.

## Pre-test live gate

- Revalidate đúng trail/bucket live đã ghi trong `m12-solution-v2.0.md`.
- Không chạy test khi còn SNS recipient bắt buộc `PendingConfirmation`.
- Deployment/test identity phải có MFA hoặc là approved short-lived role; không dùng root và không dùng access key tĩnh mới.
- Exact S3 canary prefix phải có owner approval và nằm trong selector; không dùng một trong các production object hiện hữu.

## Matrix

| ID | Test | PASS |
|---|---|---|
| T01 | In-place upgrade | Trail ARN/bucket không đổi; không có trail/bucket M12 thứ hai |
| T02 | Stop/delete/change selector | Deny + event + alert; trail vẫn logging, không delivery gap |
| T03 | S3 `GetObject` canary | Parsed data event có actor/session/bucket/key/time/request ID |
| T04 | `GetSecretValue` canary | Parsed management event; evidence không có value |
| T05 | Integrity | `validate-logs` sau cutover không missing/`INVALID` |
| T06 | Retention | Object mới sau cutover có `COMPLIANCE` retain-until >=365 ngày; lifecycle 400 |
| T07 | Heartbeat | 5-minute invocation; exact trail/selectors/bucket/rule-target/router/subscription/alarm checks `PASS`; log age <=20, digest age <=90; EKS audit enabled |
| T08 | Alert controls | EventBridge/SNS/Lambda/CloudWatch mutation denied; group 7 alert nhận được |
| T09 | IAM | Boundary/trust/policy/OIDC mutation denied; global group 8 alert; CI/ops baseline pass |
| T10 | Forensic | Identity → session → action → resource → UTC; EKS supplemental nếu audit enabled |
| T11 | Cleanup/cost | Canary cleanup recorded; one-trail cost/coverage trong approval |
| T12 | External watchdog | OIDC AssumeRole thành công; manual + scheduled run xanh; bỏ/sai role ARN trong test branch làm job đỏ ngoài AWS |

## Cutover evidence

T01 phải có pre/post `describe-trails`, status, selectors, bucket lock/lifecycle và Terraform plan. Object cũ không được dùng chứng minh retention mới; ghi exact cutover UTC.

## Blind-window test

Test cả trail name và ARN bằng bounded identity. PASS cần deny, raw event, EventBridge invocation, Lambda router output, SNS receipt, `IsLogging=true` và no delivery/digest gap. Critical group 1 không được bị automation allowlist suppress.

## Coverage/integrity

Canary object phải nằm trong exact approved selector. Evidence chính là parsed archive log plus `validate-logs`; Event History/`aws s3 ls` chỉ để định vị.

## Heartbeat

Không cố ý tắt trail. Xác minh Lambda log `PASS`, schedule, exact rule pattern/target, routers, alarms, confirmed subscriptions, EKS audit flag, Versioning/Object Lock/lifecycle/encryption/public block và thresholds. Digest dùng ngưỡng riêng 90 phút vì giao chậm hơn log files.

## Evidence pack

Mỗi `M12-Txx/` có metadata, request/result redacted, raw event, pre/post state, alert, integrity output, hashes và verdict. Metadata gồm account, region, UTC, principal/session, approver, observer, Git SHA, plan hash và request ID.

## Verdict

Chỉ `VERIFIED` khi T01–T12 pass, coverage/IAM complete, cutover timestamp rõ và root residual risk ký. Foundation pass nhưng IAM/watchdog chưa xong là `AUDIT READY/PARTIAL`.

---

**Phiên bản:** v2.0
**Cập nhật:** 21/07/2026
**Trạng thái:** DESIGNED AGAINST LIVE BASELINE — chưa chạy production
