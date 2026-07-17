# Mandate 12 — Yêu cầu và gap analysis

> **Trạng thái:** Draft for approval · phân tích tĩnh repository, chưa kiểm tra AWS/EKS live.

## 1. Mục tiêu

Mandate 12 yêu cầu audit trail của TF3 không thể bị vô hiệu hóa bằng ba cách:

- **Làm mù:** dừng hoặc thay đổi đường ghi log trước khi hành động.
- **Làm hụt:** hoạt động ở resource/API chưa được ghi, đặc biệt đọc S3 object hoặc secret.
- **Làm mỏng/sửa:** log không đủ nội dung để điều tra, hoặc bị thêm/xóa/sửa sau khi giao.

Ngoài ra log phải được giữ đủ lâu cho một cuộc tấn công kéo dài nhiều ngày.

## 2. Bốn yêu cầu và bằng chứng bắt buộc

| Yêu cầu | Kết quả cần đạt | Bằng chứng mentor |
|---|---|---|
| Không có cửa sổ mù | Operator không thể tắt/xóa/đổi coverage mà không bị chặn hoặc báo động | Thử `StopLogging`/`DeleteTrail`; có deny hoặc alert, actor/time và trail status |
| Đóng coverage gap | Đọc S3 object, đọc secret và thay đổi cấu hình quan trọng đều có vết | `GetObject`, `GetSecretValue` canary và config-change event |
| Toàn vẹn mật mã | Log/digest không thể bị sửa/xóa âm thầm; chain gap bị phát hiện | CloudTrail log file validation và `validate-logs` |
| Retention | Có thời gian giữ rõ ràng và không thể rút ngắn tùy tiện | Object Lock/retention/lifecycle evidence |

## 3. Baseline kế thừa Mandate 4

Mandate 12 kế thừa các yêu cầu của Mandate 4:

- audit cả AWS cloud và Kubernetes/EKS;
- dựng timeline ai-làm-gì-khi-nào và nội dung thay đổi;
- log không bị người vận hành tự xóa;
- mọi hành động quy về danh tính cá nhân/session, không dùng chung account;
- mentor có thể chọn một sự kiện bất kỳ để team làm forensic tại chỗ.

Object Lock hoặc audit resources từng dùng cho Mandate 4 chỉ được tái sử dụng sau khi kiểm tra live ownership, cấu hình và retention.

## 4. Phạm vi phân tích repository

- Repository: `Phase3-TF3-Infra-Sentinel`.
- Đã loại trừ `docs/docx_cdo02`.
- Chỉ đọc tĩnh; không chạy Terraform, AWS CLI, Kubernetes, test, build hoặc deploy.
- Không suy diễn trạng thái live từ tài liệu thiết kế.

### Quy ước

| Trạng thái | Ý nghĩa |
|---|---|
| `CONFIRMED-REPO` | Có cấu hình hoặc ownership được codify trong repository |
| `VERIFY-LIVE` | Repository không đủ chứng minh, cần truy vấn live chỉ đọc |
| `TARGET` | Control được đề xuất cho Mandate 12, chưa triển khai |

## 5. Hiện trạng dự án liên quan

| Thành phần | Trạng thái | Nhận xét |
|---|---|---|
| AWS account `197826770971`, region chính `ap-southeast-1` | `CONFIRMED-REPO` | Phải đối chiếu caller live trước triển khai |
| Terraform root `infra/live/production` | `CONFIRMED-REPO` | Quản lý network, EKS, access và edge; không nên gộp audit state vào đây |
| EKS API private-only | `CONFIRMED-REPO` | Truy cập qua SSM/Cloudflare; Mandate 12 không thay đổi đường này |
| CloudFront/private origin | `CONFIRMED-REPO` | Storefront/edge nằm ngoài thay đổi audit |
| EKS KMS encryption | `CONFIRMED-REPO` | Không đồng nghĩa CloudTrail archive đã được bảo vệ |
| External Secrets và `techx-tf3/flagd-sync-token` | `CONFIRMED-REPO` | Là resource cần coverage `GetSecretValue`; không dùng secret thật để demo |
| Terraform apply role có `AdministratorAccess` | `CONFIRMED-REPO` | Rủi ro lớn: có thể sửa account-local audit/IAM controls |
| CloudTrail trail đang chạy | `VERIFY-LIVE` | Không thấy `aws_cloudtrail` trong production Terraform |
| S3 data-event selectors | `VERIFY-LIVE` | Chưa thấy được codify |
| Log file integrity validation | `VERIFY-LIVE` | Chưa thấy được codify |
| Object Lock từ Mandate 4 | `VERIFY-LIVE` | Đề nói đã chứng minh nhưng repository không đủ tái xác nhận |
| EKS control-plane audit logging | `VERIFY-LIVE` | Có tài liệu nhắc tới, chưa thấy cấu hình Terraform tương đương |
| AWS Organizations/member account | `VERIFY-LIVE` | Không dùng làm tiền đề cho phương án chọn |
| Datastore/secret Mandate 8 | `VERIFY-LIVE` | Chỉ đưa vào coverage nếu đã tồn tại live |

## 6. Gap analysis

| Mandate control | Gap hiện tại | Mức |
|---|---|---|
| Trail liên tục | Chưa codify trail, status và owner | Critical |
| Chống operator tắt trail | Apply role còn admin; deny policy có thể bị tự gỡ nếu không có boundary/access migration | Critical |
| Cảnh báo anti-audit | Chưa thấy EventBridge/SNS controls | High |
| S3 object reads | Chưa thấy S3 data events | Critical |
| Secret reads | AWS có thể tạo management read event nhưng chưa chứng minh trail durable thu sự kiện | High |
| Config changes | Chưa có durable coverage matrix cho IAM/KMS/S3/EKS/CloudTrail | High |
| Integrity digest | Chưa thấy validation/digest configuration | Critical |
| WORM retention | Mandate 4 evidence cần kiểm tra live | High |
| EKS forensic | EKS audit live/retention chưa xác nhận | High |
| Identity attribution | Có assume-role patterns nhưng còn admin identity; cần kiểm tra shared credential/session | High |

## 7. Live discovery bắt buộc trước phê duyệt triển khai

Chỉ đọc, không mutation:

1. Caller/account/region thực tế.
2. `describe-trails`, `get-trail-status`, event selectors và validation.
3. Bucket/KMS/Object Lock/lifecycle từ Mandate 4.
4. EKS control-plane log types, CloudWatch log group và retention.
5. IAM users/roles có `AdministratorAccess`, cách CI assume apply role và break-glass path.
6. Danh sách bucket/prefix nhạy cảm hiện có.
7. Danh sách secret hiện có; không đọc secret value.
8. Event volume/cost baseline.

## 8. Ràng buộc

- Không thay đổi application source, workload, datastore, network, edge hoặc flagd.
- Giữ storefront public và ops private.
- Không vượt khoảng `$300/tuần/TF`.
- Không dùng root user hoặc shared credential cho vận hành thường ngày.
- Không coi Terraform plan hay tài liệu là bằng chứng `VERIFIED`.

## 9. Kết luận

Repository có nền IaC, private access, KMS và identity flows tốt để triển khai audit độc lập. Tuy nhiên Mandate 12 hiện là **Not Ready/VERIFY-LIVE** vì chưa chứng minh trail, coverage, integrity, retention và operator boundary. Solution phải bắt đầu bằng discovery, sau đó dựng single-account audit foundation và IAM hardening thành hai change riêng.

