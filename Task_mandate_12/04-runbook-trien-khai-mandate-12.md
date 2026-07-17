# Runbook triển khai và chứng minh Mandate 12

> **Trạng thái:** runbook đề xuất cho TF3, chưa thực thi. Chữ “TF4” trong file mandate nguồn là lỗi đặt tên. Không chạy production trước khi change owner và delegated security admin phê duyệt ownership, resource scope và cửa sổ triển khai.

## 1. Mục tiêu và nguyên tắc an toàn

Triển khai audit plane chống làm mù, làm hụt và sửa log mà không thay đổi storefront, private ops access hoặc flagd.

- Không apply trực tiếp từ máy cá nhân; dùng PR, saved plan và protected environment.
- Không đưa credential, `SecretString`, token hoặc object nhạy cảm vào terminal capture/evidence.
- Không dùng Terraform state TF3 production để sở hữu organization-level resources.
- Không thử xóa/tamper object thật ở Object Lock Compliance.
- Mọi timestamp dùng UTC; mọi evidence ghi actor/account/region/request ID.

## 2. Vai trò

- `ORG_ADMIN`: AWS Organizations management/delegated CloudTrail admin.
- `LOG_ARCHIVE_ADMIN`: tạo bucket/KMS trước lock, sau đó tách khỏi operator.
- `TF3_OPERATOR`: cung cấp inventory và tạo read event mẫu; không quản trị audit plane.
- `MENTOR_TESTER`: thực hiện ba đòn thử.
- `AUDITOR`: read-only log/digest và chạy validation.
- `SEC_ONCALL`: nhận, acknowledge và điều tra alarm.

Không dùng một principal cho tất cả vai trò.

## 3. Phase 0 — Scope gate

### 3.1 Xác nhận account boundary và ownership

Ghi vào change ticket/ADR:

- Mandate 12 áp dụng cho TF3; ghi nhận chữ “TF4” trong file nguồn là lỗi đặt tên để tránh tranh chấp evidence về sau.
- Organization ID, management account, delegated admin, log-archive account, security account.
- TF3 member account: `197826770971` (phải xác minh live, không chỉ tin tài liệu).
- Ai có quyền break-glass và quy trình dual approval.

**STOP** nếu TF3 không thuộc organization hoặc chưa có external owner. Account-local trail chỉ được dùng bootstrap, không được tuyên bố đạt mandate.

### 3.2 Inventory chỉ đọc

Thu và lưu output đã redaction:

```sh
aws sts get-caller-identity
aws organizations describe-organization
aws cloudtrail describe-trails --include-shadow-trails
aws cloudtrail get-trail-status --name <trail-arn>
aws cloudtrail get-event-selectors --trail-name <trail-arn>
aws s3api list-buckets
aws secretsmanager list-secrets --query 'SecretList[].{ARN:ARN,Name:Name,Tags:Tags}'
```

Không gọi `get-secret-value` ở bước inventory.

### 3.3 Classification và volume

Tạo bảng:

| Resource | Classification | API cần thấy | Event type | Estimated events/week | Owner |
|---|---|---|---|---:|---|
| S3 canary prefix | Sensitive-test | `GetObject` | Data | TBD | TF3 |
| Production sensitive bucket/prefix | Sensitive | `GetObject`, writes/deletes | Data | TBD | Data owner |
| `techx-tf3/flagd-sync-token` | Critical secret | `GetSecretValue` | Management read | TBD | Platform |
| Managed datastore secrets nếu tồn tại | Critical secret | `GetSecretValue` | Management read | TBD | Platform |

Tính forecast bằng giá region hiện hành. **STOP** nếu tổng forecast làm vượt `$300/tuần/TF` hoặc chưa biết volume lớn nhất.

## 4. Phase 1 — Thiết kế và review IaC

Tách tối thiểu ba state/root:

1. `organization-audit`: trusted access, delegated admin, organization trail/SCP.
2. `log-archive`: S3/KMS/Object Lock/lifecycle/bucket policy.
3. `security-detection`: EventBridge/SNS/health checks.

TF3 production root không sở hữu ba root này.

Review bắt buộc:

- trail multi-region, include global events, read+write management events;
- advanced selectors chính xác cho S3 object ARN/prefix;
- log file validation enabled;
- bucket versioning và Object Lock enabled từ lúc tạo;
- default retention `COMPLIANCE`, 365 ngày;
- KMS/bucket policy cho CloudTrail delivery đúng account/org paths;
- explicit deny member/operator delete, policy mutation và retention reduction;
- auditor chỉ đọc đúng log prefix/digest/status;
- EventBridge target nằm ngoài TF3 operator blast radius;
- không có diff tới edge, EKS workloads, ingress, Cloudflare hoặc flagd.

## 5. Phase 2 — Pre-production proof

Trong sandbox/security test account:

1. Tạo bucket thử với versioning/Object Lock; xác minh policy cho CloudTrail delivery.
2. Tạo trail thử và selectors cho canary bucket.
3. Chờ delivery/digest đầu tiên; AWS cho biết digest bắt đầu khoảng một giờ sau khi bật validation.
4. Chạy validation cho một UTC range hoàn chỉnh.
5. Thử principal không đặc quyền gọi CloudTrail destructive API và xác minh deny/alarm.
6. Kiểm tra alert có actor/time/account/region/eventName và không có secret.
7. Review lifecycle không xóa trước retain-until.

**Không chuyển production** nếu có missing digest, delivery error, KMS denial, alert không đến hoặc member operator sửa được control.

## 6. Phase 3 — Production rollout không tạo blind window

Thứ tự bắt buộc:

1. Tạo archive bucket/KMS/detection path trước.
2. Tạo organization trail với management events + validation.
3. Xác minh `IsLogging=true`, latest delivery time và digest arrival cho TF3.
4. Bật data selectors theo từng batch nhỏ; kiểm tra volume/cost/error sau mỗi batch.
5. Bật/kiểm tra health check và alert heartbeat.
6. Chỉ sau ít nhất một chu kỳ delivery/digest hợp lệ mới cân nhắc bỏ duplicate account-local trail.
7. Nếu migrate từ account-local trail, giữ overlap tối đa khoảng một ngày để tránh gap; ghi nhận duplicate-event cost.

Không bao giờ xóa trail cũ trước khi trail mới có evidence delivery và validation.

## 7. Phase 4 — Mentor demo ba đòn

Kịch bản chi tiết, safety boundary và evidence template nằm tại `06-kich-ban-tan-cong-va-bang-chung-mandate-12.md`. Phần này chỉ giữ happy-path demo tối thiểu; nếu có khác biệt, quy tắc an toàn nghiêm ngặt hơn trong file 06 được ưu tiên.

### 7.1 Đòn 1: Làm mù

`MENTOR_TESTER` trong TF3 thử lần lượt trên organization trail:

```sh
aws cloudtrail stop-logging --name <organization-trail-arn>
aws cloudtrail delete-trail --name <organization-trail-arn>
```

Nếu được phê duyệt, thử `update-trail`/`put-event-selectors` với thay đổi vô hại về mặt dữ liệu nhưng phải bị deny; không thử thay đổi archive retention thật.

Kỳ vọng:

- member account không thể sửa/dừng/xóa organization trail;
- API attempt xuất hiện trong CloudTrail management event với actor/time/error;
- SEC_ONCALL nhận alert và acknowledge theo SLA;
- `get-trail-status` vẫn `IsLogging=true`.

Evidence: command đã redaction, exit/error, event JSON đã redaction, alert receipt, trail status.

### 7.2 Đòn 2: Làm hụt

Chuẩn bị object canary không chứa dữ liệu nhạy cảm và secret canary có giá trị không dùng ở đâu.

```sh
aws s3api get-object --bucket <canary-bucket> --key <sensitive-prefix>/mentor-proof /tmp/mentor-proof
aws secretsmanager get-secret-value --secret-id <canary-secret> --query ARN --output text
```

Lưu ý: lệnh Secrets Manager vẫn trả payload đầy đủ trước khi `--query` xử lý ở client; chỉ chạy bằng tester được phép và không capture debug/output raw. Tốt hơn dùng ứng dụng test kiểm soát output hoặc secret canary vô giá trị.

Kỳ vọng:

- S3: tìm được data event `GetObject`, đúng bucket/key/principal/time.
- Secrets Manager: tìm được management read event `GetSecretValue`, đúng secret/principal/time; log không chứa secret value.
- Nếu một event không thấy sau delivery SLA: **FAIL coverage**, không giải thích bằng eventual consistency vô hạn.

### 7.3 Đòn 3: Làm mỏng/sửa

Sau khi digest cho demo window đã đến:

```sh
aws cloudtrail validate-logs \
  --trail-arn <organization-trail-arn> \
  --account-id 197826770971 \
  --start-time <UTC-start> \
  --end-time <UTC-end> \
  --region ap-southeast-1 \
  --verbose
```

Lặp cho region có global service event nếu cần. Kỳ vọng: summary hợp lệ, không `INVALID`, không digest/log missing. Lưu output, UTC window, CLI version và hash của evidence file.

## 8. Kiểm tra sau rollout

### Hằng ngày

- `IsLogging=true` cho trail.
- LatestDeliveryTime/LatestDigestDeliveryTime không quá ngưỡng.
- Không có delivery/KMS/S3 error.
- Alert heartbeat thành công.

### Hằng tuần

- Chạy validation cho tuần trước theo account/region.
- Review anti-audit events và failed authorization.
- So coverage inventory với bucket/secret mới.
- So actual event count/storage/cost với forecast.
- Kiểm tra retention/Object Lock/KMS/bucket policy drift.

### Khi có incident

- Đặt legal hold cho evidence liên quan nếu cần giữ quá retention.
- Không chỉnh sửa file gốc; phân tích trên bản sao và lưu hash.
- Ghi chain of custody: người lấy, thời gian, nguồn, hash, nơi lưu.

## 9. Failure handling

| Triệu chứng | Hành động ngay | Điều cấm |
|---|---|---|
| `IsLogging=false` | Critical incident; kiểm tra organization/trusted access, actor event, khôi phục qua ORG_ADMIN | Không xóa/recreate vội làm mất continuity |
| Delivery error | Kiểm tra bucket/KMS policy và CloudTrail status; giữ trail chạy | Không nới bucket public hoặc cấp admin rộng |
| Digest trễ/missing | Khoanh UTC range, kiểm tra delivery status, mở incident integrity | Không gọi range đó “valid” |
| S3 `GetObject` không thấy | Review exact advanced selector ARN/readOnly setting | Không bật wildcard toàn account mà chưa cost review |
| Secret read không thấy | Xác minh management read enabled, region/time/event source | Không log secret value để “bù chi tiết” |
| Alert không tới | Dùng independent health channel, kiểm tra rule/target/subscription | Không coi log tồn tại là thay thế alert |
| Cost spike | Thu hẹp noisy non-sensitive selector, lifecycle tiering, pause optional Insights/Lake | Không tắt organization management logging/integrity |

## 10. Rollback

Rollback chỉ cho thành phần có thể đảo ngược:

- revert selector batch gây volume ngoài dự kiến nhưng vẫn giữ management logging;
- disable optional CloudWatch/Lake/Insights;
- sửa detection rule/target qua reviewed change;
- giữ trail cũ trong migration cho tới khi trail mới ổn định.

Không thể/không được rollback:

- Object Lock đã bật trên bucket;
- rút ngắn Compliance retention của object đã khóa;
- xóa archive để giảm chi phí;
- tắt logging/integrity mà không có replacement đã được chứng minh.

Nếu thiết kế Compliance 365 ngày sai, ngừng ghi object mới vào bucket đó sau phê duyệt và chuyển sang bucket mới đúng cấu hình; object cũ vẫn phải giữ đến hết retention.

## 11. Checklist sign-off

- [ ] Change owner xác nhận resource scope của TF3 và owner của audit plane.
- [ ] Trail/bucket/detection nằm ngoài quyền TF3 operator.
- [ ] Management read+write, multi-region, global events đã verify.
- [ ] S3 sensitive data selectors khớp inventory.
- [ ] Mentor Stop/Delete/Update attempt bị deny hoặc alert; trail không mù.
- [ ] Mentor `GetObject` và `GetSecretValue` đều truy được event.
- [ ] `validate-logs` pass cho demo window/account/region.
- [ ] Object Lock Compliance 365 ngày và lifecycle đã review.
- [ ] Cost actual/forecast nằm trong ngân sách.
- [ ] Không có thay đổi storefront, private ops hoặc flagd.
- [ ] Evidence pack đã redaction, hash và ký tên người chịu trách nhiệm.
- [ ] Verdict từng test bắt buộc được ghi đúng trạng thái; chưa test live không được đánh dấu `VERIFIED`.
