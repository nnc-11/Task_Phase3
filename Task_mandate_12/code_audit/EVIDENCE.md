# Evidence checklist

Tạo thư mục evidence ngoài Git hoặc trong vị trí được phê duyệt; không lưu credential, `SecretString`, token hay object content.

## Trước apply

- Change approval và UTC window.
- Caller identity cho từng root.
- Terraform version/provider lock information.
- Redacted plan text và SHA-256 của saved plan.
- Cost forecast và resource coverage list.

## Sau apply

- Terraform outputs đã redaction.
- `get-trail-status` và `get-event-selectors`.
- Object Lock, versioning, encryption và public access block.
- CloudWatch alarm/SNS subscription status.
- Latest log và digest delivery timestamps.

## Mentor tests

- ATK-01/02: request, AccessDenied, CloudTrail attempt event, alert receipt, `IsLogging=true`.
- ATK-06: `GetObject` data event đúng principal/time/bucket/key.
- ATK-07: `GetSecretValue` event; không lưu giá trị secret.
- ATK-11: `validate-logs` summary không missing/`INVALID`.
- Forensic: AWS identity → STS session → EKS/Kubernetes/Git change nếu test liên quan.

## Metadata bắt buộc

- UTC start/end, account, region, trail ARN và request ID.
- Tester, observer, approver và người đưa verdict.
- Trạng thái `DESIGNED`/`DEPLOYED`/`VERIFIED`/`FAILED`.
- SHA-256 cho evidence files sau redaction.

