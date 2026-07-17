# Đề xuất solution Mandate 12 và trade-off

## 1. Quyết định đề xuất

Chọn mô hình **organization trail do security/log-archive account ngoài TF3 sở hữu**, ghi all-region management events và data events có scope vào S3 Object Lock Compliance, bật CloudTrail log file integrity validation, đồng thời phát hiện anti-audit API qua EventBridge sang kênh cảnh báo do security account kiểm soát.

Đây là lựa chọn duy nhất trong các phương án thực tế đáp ứng đúng yêu cầu “admin của chính TF không thể làm mù”. TF3 production root chỉ cung cấp inventory/tag/classification và các control phụ trợ; không sở hữu khóa tắt chính.

## 2. Kiến trúc mục tiêu

```text
AWS Organizations management/delegated security admin
        |
        +-- Organization trail: all regions, global events, read + write
        |       |
        |       +-- Management events
        |       +-- S3 object data events: bucket/prefix nhạy cảm
        |       +-- Log file integrity validation (digest chain)
        |
        +----> Log-archive account
        |         +-- S3 versioning + Object Lock COMPLIANCE 365d
        |         +-- SSE-KMS key, policy chỉ CloudTrail write / auditor read
        |         +-- lifecycle sang storage class rẻ hơn, không giảm lock
        |
        +----> Security detection account
                  +-- EventBridge anti-audit rules
                  +-- SNS/on-call destination
                  +-- delivery/integrity health check

TF3 account 197826770971
        +-- member admin: thấy trail/status, không sửa/xóa/dừng
        +-- resource classification + test fixtures
        +-- không quyền quản trị archive/detection plane
```

## 3. Coverage đề xuất

### Management events

- Multi-region, include global service events, `ReadWriteType=All`.
- Tối thiểu cover CloudTrail, IAM/STS, Organizations, KMS, S3 bucket configuration, EKS, Secrets Manager, EC2/network/CloudFront/WAF và managed datastore control plane.
- `GetSecretValue`/`BatchGetSecretValue` phải truy ra được actor, time, secret ARN/name, source IP/user agent và outcome. Không thu hay hiển thị secret value.

### Data events

- S3 object read/write cho bucket/prefix được phân loại `Sensitive` hoặc thuộc đường audit/data production.
- Bắt buộc có một bucket/prefix test để mentor gọi `GetObject` mà không lộ dữ liệu thật.
- Không bật wildcard cho mọi S3 object trước khi đo volume; mở rộng theo inventory và tag-based governance.

### Anti-audit detections

Mức Critical cho:

- CloudTrail: `StopLogging`, `DeleteTrail`, `UpdateTrail`, `PutEventSelectors`, thay validation, xóa event data store/channel nếu dùng.
- S3 archive: thay bucket policy, lifecycle, Object Lock, encryption, public-access block hoặc delete attempts.
- KMS: disable key, schedule deletion, đổi key policy/grant.
- Organizations: disable trusted access, deregister delegated admin, leave/remove account, thay SCP liên quan.
- Detection plane: disable/delete EventBridge rule/target, SNS topic/subscription/policy.

EventBridge matching CloudTrail API events là near-real-time nhưng AWS mô tả delivery theo best effort; vì vậy bổ sung scheduled health check cho `IsLogging`, latest delivery time, digest arrival và alarm delivery heartbeat.

## 4. Retention

- **365 ngày Object Lock Compliance** cho log và digest.
- Lý do: mandate yêu cầu điều tra tấn công kéo dài nhiều ngày; 365 ngày bao phủ dwell time, phát hiện muộn, điều tra hồi tố và toàn bộ chu kỳ Phase 3 với dư địa lớn.
- Lifecycle chuyển object cũ sang tier rẻ hơn sau thời gian phù hợp; lifecycle không được xóa trước retain-until.
- CloudWatch Logs nếu dùng cho query/alarm nhanh chỉ giữ 30–90 ngày; S3 WORM là source of truth.
- Legal hold dùng cho incident cần giữ vượt 365 ngày.

## 5. Integrity

- Bật `enable_log_file_validation` ngay khi tạo trail. AWS sử dụng SHA-256 cho hash và SHA-256 with RSA cho chữ ký digest; digest theo giờ liên kết digest trước.
- Chạy `validate-logs` theo region/account/time range trước mặt mentor.
- Gate thành công: không có `INVALID`, không có missing digest trong khoảng cần chứng minh; lưu stdout đã redaction cùng UTC window và trail ARN.
- Digest chỉ bảo vệ file đã được delivery/referenced; coverage matrix vẫn phải test riêng.

## 6. Trade-off

| Lựa chọn | Chống TF admin | Coverage/integrity | Chi phí/ops | Quyết định |
|---|---|---|---|---|
| Chỉ dựa CloudTrail Event history | Không | 90 ngày management, không WORM/digest archive | Rẻ nhất | Loại |
| Account-local trail + IAM deny | Yếu; admin có thể sửa quyền/control | Có thể có digest/data events | Dễ triển khai | Chỉ bootstrap tạm thời, không dùng làm bằng chứng cuối |
| Account-local trail + SCP | Khá nếu SCP do management account giữ | Tốt | Phụ thuộc Organizations; archive vẫn nên cross-account | Có thể là defense-in-depth |
| Organization trail + cross-account WORM | Mạnh nhất; member không sửa/dừng/xóa | Đáp ứng cả coverage, integrity và retention | Cần BTC/security owner, thiết kế policy kỹ | **Chọn** |
| CloudTrail Lake làm source duy nhất | Ownership có thể tốt | Query/retention tốt nhưng không thay thế demo digest chain mà đề yêu cầu | Ingest/query cao hơn | Không chọn làm source of truth; tùy chọn cho hunting |

### Object Lock Governance hay Compliance

- Governance dễ rollback nhưng principal có `BypassGovernanceRetention` có thể xóa.
- Compliance không thể rút ngắn/xóa trước hạn kể cả root; phù hợp yêu cầu “không thể bị đánh bại”.
- **Chọn Compliance**, nhưng thử policy/lifecycle trên bucket sandbox trước vì không thể rollback retention đã khóa.

### CloudWatch Logs hay S3-only

- CloudWatch thuận tiện metric filter/query nhưng thêm ingest/storage và cùng blast radius nếu đặt trong member account.
- S3-only rẻ hơn nhưng alert/query chậm và phức tạp hơn.
- **Chọn S3 WORM làm bằng chứng + EventBridge cross-account cho alert**; CloudWatch Logs chỉ thêm nếu volume/cost đo được và cần truy vấn vận hành.

## 7. Cost guardrail

Theo bảng giá AWS hiện hành tại thời điểm viết, một bản management events ongoing đưa vào S3 có thể là bản miễn phí đầu tiên; S3 data events tính theo số event và CloudWatch Logs delivery tính theo GB. Giá thay đổi theo region/dịch vụ, nên không ghi một “tổng cố định” khi chưa có volume thật.

Công thức bắt buộc trước apply:

```text
weekly_data_event_cost = weekly_S3_data_events / 100000 * data_event_unit_price
weekly_log_delivery    = delivered_GB * delivery_price_per_GB
weekly_storage         = retained_GB_by_tier * regional_storage_price
weekly_total           = CloudTrail + S3 + KMS requests + alerting + query
```

Guardrails:

- đo 7 ngày hoặc dùng access-log/request metrics để ước lượng;
- scope data events theo sensitive bucket/prefix;
- không giữ duplicate account trail quá một ngày sau khi organization trail được chứng minh ổn định;
- đặt budget cảnh báo cho audit stack và yêu cầu forecast giữ tổng TF dưới `$300/tuần`;
- không bật Insights/Lake mặc định.

Giá tham khảo chính thức: [AWS CloudTrail pricing](https://aws.amazon.com/cloudtrail/pricing/).

## 8. Phân chia ownership

| Owner | Trách nhiệm |
|---|---|
| BTC hoặc delegated security admin | Organization trail, trusted access, SCP, archive/detection accounts, final approval |
| TF3 | Resource inventory, classification, data-event selectors cho resource TF3, test fixture và evidence request; operator không có quyền mutation trên archive |
| Auditor/mentor | Principal thử phá tách biệt và auditor role read-only trên đúng evidence prefix/status cần thiết |
| On-call security | Nhận/ack alert, điều tra actor/time, bảo quản evidence |

Không cho Terraform apply role TF3 quản trị organization trail, archive bucket/KMS hay alert destination.

## 9. Điều kiện triển khai

Chỉ triển khai khi cả sáu điều kiện đúng:

1. Change owner và delegated security admin phê duyệt phạm vi resource, maintenance window và ownership của audit plane.
2. Có management/delegated admin và log-archive account ngoài TF3.
3. Inventory bucket/secret và volume baseline hoàn tất.
4. Cost forecast đạt ngân sách.
5. Policy được security reviewer kiểm tra để CloudTrail vẫn ghi được nhưng operator không phá được.
6. Runbook demo dùng object/secret canary, không ảnh hưởng storefront/ops/flagd.
