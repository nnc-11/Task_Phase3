# Phân tích dự án hiện tại so với Mandate 12

## 1. Phạm vi và phương pháp

Phân tích tĩnh toàn bộ repository `Phase3-TF3-Infra-Sentinel`, loại trừ tuyệt đối `docs/docx_cdo02`. Không chạy Terraform, AWS CLI, Kubernetes, test, build hoặc kiểm tra live. Vì vậy kết luận dưới đây phản ánh **trạng thái được codify trong repository**, không khẳng định trạng thái AWS thực tế.

Mandate 12 áp dụng cho TF3. Chữ “TF4” trong file mandate nguồn là lỗi đặt tên và không làm thay đổi phạm vi triển khai trên hệ thống TF3.

## 2. Kiến trúc liên quan đã quan sát

- Production root: `infra/live/production`, account tài liệu hóa `197826770971`, region mặc định `ap-southeast-1`.
- EKS API private-only; vận hành qua SSM bastion và Cloudflare Access.
- Storefront đi qua CloudFront/private origin; mandate cấm thay đổi mô hình public/private này.
- EKS secrets được mã hóa bằng customer-managed KMS key có rotation.
- External Secrets role được cấp `secretsmanager:GetSecretValue` cho flagd sync token.
- GitHub Terraform apply role gắn `AdministratorAccess`; `infra/README.md` xác nhận đây là hardening còn mở.
- `production.auto.tfvars` còn một IAM user admin trong `eks_admin_principal_arns`.
- Auditability hiện xuất hiện chủ yếu ở Git/ADR/runbook, Kyverno Audit và các tài liệu mô tả tra cứu CloudTrail/EKS audit; chưa có audit plane chống vô hiệu hóa được codify. Trạng thái CloudTrail/EKS audit live vẫn phải xác minh.
- Tài liệu thiết kế mentor access có tuyên bố EKS control-plane audit logging ghi Kubernetes actions, nhưng tìm kiếm tĩnh không thấy `cluster_enabled_log_types`/cấu hình tương đương trong Terraform. Vì vậy trạng thái EKS audit live là **UNKNOWN**, cần kiểm tra thay vì coi tài liệu thiết kế là bằng chứng triển khai.

## 3. Bằng chứng thiếu trong Terraform hiện tại

Inventory resource type dưới `infra/**/*.tf` không có các resource sau:

- `aws_cloudtrail` hoặc organization trail;
- S3 log-archive bucket dành cho CloudTrail, Object Lock configuration và lifecycle audit;
- CloudTrail log file validation/digest configuration;
- CloudWatch Logs group dành cho CloudTrail;
- EventBridge/SNS detection cho `StopLogging`, `DeleteTrail`, `UpdateTrail`, `PutEventSelectors`;
- AWS Organizations SCP hoặc delegated administrator controls;
- AWS Config/conformance controls giám sát drift của audit plane.

Điều này không chứng minh live account hoàn toàn không có CloudTrail; nó chứng minh repository hiện **không sở hữu/codify** các kiểm soát cần để tái tạo và review.

### Ma trận hiện trạng dùng cho Mandate 12

| Thành phần | Trạng thái | Căn cứ/phạm vi sử dụng |
|---|---|---|
| AWS account `197826770971`, region chính `ap-southeast-1` | `CONFIRMED-REPO` | Có trong `infra/README.md` và production Terraform; account identity vẫn phải đối chiếu live trước test. |
| EKS private-only, SSM/Cloudflare ops access, CloudFront edge | `CONFIRMED-REPO` | Không thay đổi trong Mandate 12. |
| EKS KMS encryption và secret `techx-tf3/flagd-sync-token` | `CONFIRMED-REPO` | Có Terraform/External Secrets config; không đọc secret value trong inventory. |
| Terraform apply role còn `AdministratorAccess` | `CONFIRMED-REPO` | Là rủi ro trực tiếp cho account-local audit plane. |
| Organization membership/management account/delegated admin | `VERIFY-LIVE` | Chưa được chứng minh trong repository. |
| CloudTrail trail/event selectors/log validation đang chạy | `VERIFY-LIVE` | Không có `aws_cloudtrail` trong Terraform production hiện tại. |
| Object Lock/bucket evidence từ Mandate 4 | `VERIFY-LIVE` | Mandate 4 nói đã chứng minh, nhưng repository được đọc không codify đủ bucket/policy/evidence để tái xác nhận. |
| EKS control-plane audit log và retention | `VERIFY-LIVE` | Có tuyên bố trong design, chưa thấy `cluster_enabled_log_types` hoặc cấu hình tương đương. |
| PostgreSQL/ElastiCache/MSK secret của Mandate 8 | `VERIFY-LIVE` | Chỉ thêm coverage nếu resource thực sự tồn tại lúc triển khai Mandate 12. |
| Organization trail, cross-account WORM archive, anti-audit alert | `TARGET` | Là giải pháp Mandate 12, không phải hiện trạng. |

## 4. Gap assessment

| Mandate | Hiện trạng repo | Đánh giá | Khoảng trống cần đóng |
|---|---|---|---|
| Không có cửa sổ mù | Không có organization trail/SCP/detection; apply role là admin | **FAIL / High** | Đưa trail và bucket sang security/log-archive account; member admin không quản trị được organization trail; cảnh báo attempt. |
| Ghi lệnh tắt và báo động | Không có EventBridge/SNS rule tương ứng | **FAIL / High** | Detection riêng, độc lập với trail bị nhắm; route tới người ngoài operator group. |
| Management coverage | Event history có thể tồn tại mặc định nhưng repo không cấu hình durable trail | **UNKNOWN/FAIL** | All-region, read+write management events, global events, delivery dài hạn. |
| S3 object read | Không thấy advanced event selectors | **FAIL / High** | Bật data event có scope cho bucket/prefix nhạy cảm và audit bucket access nếu phù hợp. |
| Secret read | AWS ghi `GetSecretValue` vào CloudTrail, nhưng repo chưa có durable protected trail | **PARTIAL** | Thu management read events, chứng minh `GetSecretValue`/`BatchGetSecretValue`, alert bất thường; không log secret value. |
| Config changes | Chưa có durable/protected management trail | **FAIL** | Cover CloudTrail, IAM, KMS, S3, EKS, Secrets Manager, Organizations và network/edge changes. |
| Integrity mật mã | Không có `enable_log_file_validation` | **FAIL / Critical** | Digest chain + scheduled/on-demand `validate-logs`; alert khi chain/missing delivery fail. |
| Bất biến | Chỉ Terraform state bucket có versioning/encryption; không phải CloudTrail archive | **FAIL** | Dedicated cross-account bucket, versioning, Object Lock Compliance, deny policies. |
| Retention | Không có audit-log lifecycle/retention | **FAIL** | 365 ngày lock; lifecycle tiering; policy ngăn giảm retention. |
| Ngân sách | Chưa có baseline event volume/cost model | **UNKNOWN** | Đo volume trước; scope S3 data events; budget alarm; tránh duplicate trails lâu dài. |
| Storefront/ops/flagd | Kiến trúc hiện tại phù hợp | **PASS nếu không chạm** | Module audit phải tách biệt, không sửa edge, EKS routing hay flagd. |
| K8s audit + forensic (kế thừa M4) | Có mô tả trong design, chưa thấy cấu hình EKS audit logging được codify | **UNKNOWN / High** | Xác minh control-plane log types live, retention và truy vấn; chạy bài forensic nối AWS identity → EKS username → Kubernetes verb/resource. |
| Danh tính cá nhân | Repo có IAM user/assume-role patterns nhưng còn admin user và cần kiểm tra shared credentials/session naming | **PARTIAL** | Mỗi người dùng identity riêng, assume-role/session có attribution; cấm tài khoản/credential dùng chung trong evidence path. |

## 5. Hai blind spot dễ hiểu sai

### Secrets Manager không phải S3 data event

`GetSecretValue` và `BatchGetSecretValue` được Secrets Manager ghi vào CloudTrail dưới hoạt động API của service. Điều cần bảo đảm là trail thu **read management events** và lưu bền vững. Không cần khai báo Secrets Manager như một S3 data-resource selector. Tuy nhiên event chỉ cho biết ai gọi API trên secret nào; **không và không được chứa `SecretString`**.

### Digest không chứng minh sự kiện chưa bao giờ bị bỏ khỏi coverage

Integrity validation chứng minh log/digest sau khi delivery không bị sửa/xóa và chỉ ra chain gap. Nó không cứu được một resource chưa được selector thu ngay từ đầu. Vì vậy coverage test và cryptographic validation là hai gate độc lập.

## 6. Rủi ro đặc thù của repository

1. **AdministratorAccess:** một account-local trail do cùng account sở hữu có thể bị admin dừng/xóa/thay selectors. IAM deny nội bộ không đủ mạnh nếu principal có thể sửa chính policy.
2. **Terraform ownership split:** bootstrap roots chỉ mô tả ownership và được cảnh báo không apply/import tùy tiện. Audit plane không nên nhét vào production root mà không phân định state/account owner.
3. **Secret scope đang mở rộng:** repository hiện codify flagd token; Mandate 8 đề xuất thêm secret datastore. Coverage inventory phải lấy từ live account tại thời điểm triển khai.
4. **S3 volume chưa biết:** bật toàn bộ S3 object read/write có thể gây nhiễu và chi phí; phải chọn bucket/prefix nhạy cảm có chủ đích.
5. **Single-region thinking:** production chính ở Singapore nhưng IAM/CloudFront và API toàn cục cần multi-region trail + global service events.
6. **Alert path cùng blast radius:** SNS/topic/subscription trong account TF3 có thể bị admin vô hiệu hóa; security account phải sở hữu ít nhất một đường cảnh báo.
7. **Tuyên bố quá mức:** Git history, EKS audit và CloudTrail Event history 90 ngày không thay thế WORM cross-account digest chain.

## 7. Những gì cần kiểm tra live trước implementation

- AWS Organizations membership và ai là management/delegated admin.
- `describe-trails`, `get-trail-status`, event selectors và log validation hiện có.
- CloudTrail event history cho `StopLogging`, `DeleteTrail`, `UpdateTrail` gần đây.
- Danh sách bucket/secret/KMS key/data store thật và tag owner/data-classification.
- S3 Object Lock bucket từ Directive 4 thuộc account nào, mode/retention/bucket policy thực tế.
- EKS control-plane audit logging đang bật loại nào và retention bao lâu.
- Có dựng được timeline mentor chọn từ CloudTrail + EKS audit + Git/change trail trong thời gian giới hạn hay không.
- Mọi admin/on-call action có truy về cá nhân/session issuer hay còn shared account/credential.
- Event volume 7 ngày, S3 bytes/tháng, chi phí CloudTrail/S3/KMS/SNS hiện tại.
- Principal mentor và operator có/không có quyền trên organization trail/log archive.

## 8. Kết luận readiness

Repository TF3 hiện ở trạng thái **Not Ready** cho Mandate 12. Điểm mạnh là IaC/GitOps, KMS, private ops path và discipline tài liệu đã có; nhưng bốn control nền tảng — external ownership, coverage có chủ đích, cryptographic validation và retention bất biến — chưa được codify. Không nên vá bằng một account-local trail rồi tuyên bố hoàn tất; cách đó không vượt qua bài test “admin của chính team”.
