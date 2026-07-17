# Mandate 12 — Tóm tắt yêu cầu đầu vào và đầu ra
NOTE: Tham khảo thôi: file Mandate 12 từ BTC đã rõ rồi(file đó ngắn rõ hơn, khuyến cáo đọc cái đó).

## 1. Phạm vi áp dụng

Mandate 12 **áp dụng cho TF3** và được phân tích trên repository `Phase3-TF3-Infra-Sentinel`, AWS account được tài liệu hóa là `197826770971`. Chữ “TF4” trong tên/nội dung file mandate nguồn là lỗi đặt tên, không phải giới hạn phạm vi. Trước khi thay đổi production vẫn phải xác định rõ chủ sở hữu lớp AWS Organizations/log archive vì lớp này cần nằm ngoài quyền của TF3 operator.

Nguồn mandate: `MANDATE-12-audit-anti-defeat-_BTC.md`. Hạn nộp ghi trong mandate: hết ngày **20/07/2026**.

### Quy ước khớp hiện trạng

- `CONFIRMED-REPO`: có cấu hình hoặc tài liệu ownership trong repository hiện tại.
- `VERIFY-LIVE`: repository không đủ chứng minh, bắt buộc kiểm tra AWS/EKS đang chạy.
- `TARGET`: giải pháp Mandate 12 chưa được triển khai.

Organization trail, cross-account archive, Object Lock của Mandate 4 và EKS audit live không được coi là đang tồn tại chỉ vì xuất hiện trong thiết kế. Chúng phải có evidence live trước khi chuyển từ `VERIFY-LIVE`/`TARGET` sang `DEPLOYED` hoặc `VERIFIED`.

## 2. Mục tiêu nghiệp vụ

Audit trail phải đứng vững trước ba cách vô hiệu hóa mà không cần xóa log:

1. **Làm mù:** dừng/xóa/thay đổi đường ghi log.
2. **Làm hụt:** thực hiện hành vi nhạy cảm ở loại sự kiện chưa được thu thập.
3. **Làm mỏng hoặc sửa:** log thiếu chi tiết hoặc bị thêm/xóa/sửa sau khi ghi.

Kết quả không được chỉ là “có log” hoặc “append-only”; mentor phải tự thực hiện đòn tấn công và team phải đưa ra bằng chứng độc lập.

### Baseline kế thừa từ Mandate 4

Mandate 12 kế thừa, không thay thế các năng lực đã yêu cầu ở Mandate 4:

- audit ở cả tầng cloud và Kubernetes/EKS;
- change trail đủ dựng lại ai thay đổi gì, khi nào và nội dung thay đổi;
- bài forensic tại chỗ trong thời gian giới hạn;
- mọi hành động quy về danh tính cá nhân/session, không dùng tài khoản chung;
- tái sử dụng bằng chứng Object Lock/tamper protection của Mandate 4, sau đó bổ sung anti-blind, coverage và cryptographic validation của Mandate 12.

## 3. Đầu vào bắt buộc

### Đầu vào tổ chức và quyền sở hữu

- Xác nhận AWS account TF3 có thuộc AWS Organizations hay không, organization ID, management account và delegated administrator CloudTrail.
- Một **log-archive/security account nằm ngoài quyền TF3 operator** để sở hữu organization trail, S3 bucket, KMS key và kênh cảnh báo.
- Danh sách principal được phép quản trị audit plane; không dùng chung quyền vận hành workload.
- Xác định BTC, delegated security administrator hoặc đội quản trị trung tâm nào sở hữu organization-level controls.

### Đầu vào phạm vi dữ liệu

- Danh sách bucket chứa dữ liệu nhạy cảm cần S3 object-level data events. Không bật “mọi bucket” một cách mù quáng vì có thể tạo chi phí/nhiễu lớn.
- Danh sách secret và prefix nhạy cảm. Với hệ hiện tại tối thiểu có `techx-tf3/flagd-sync-token`; kế hoạch Mandate 8 còn nêu các secret PostgreSQL, ElastiCache và MSK nếu chúng được triển khai.
- Danh sách cấu hình quan trọng: CloudTrail, S3 audit bucket/Object Lock, KMS, IAM, Organizations/SCP, EKS, network/edge, Secrets Manager và các data store managed.
- Baseline số lượng management events, S3 data events và dung lượng log/ngày để kiểm chứng ngân sách.

### Đầu vào vận hành

- Người nhận cảnh báo và SLA phản hồi.
- Khung retention được phê duyệt.
- Một principal mentor thử nghiệm có quyền đọc secret/bucket mẫu nhưng không có quyền quản trị audit plane.
- Cửa sổ demo và quy tắc không dùng secret thật trong ảnh chụp/output.
- Evidence Mandate 4 hiện có: bucket/Object Lock, K8s audit, CloudTrail/change trail, identity mapping và bài forensic trước đây; mục nào không có evidence live phải đánh dấu `UNKNOWN`, không mặc định đã đạt.

## 4. Yêu cầu chức năng và tiêu chí chấp nhận

| ID | Yêu cầu | Tiêu chí chấp nhận có thể kiểm thử |
|---|---|---|
| M12-01 | Không có cửa sổ mù | Organization trail do account ngoài TF3 sở hữu; TF3 admin không thể `StopLogging`, `DeleteTrail`, `UpdateTrail` hoặc đổi event selectors. Mọi attempt được ghi; attempt thành công ở lớp account-local (nếu có) phải phát cảnh báo ngay. |
| M12-02 | Management coverage | Thu cả read và write management events, multi-region, global service events; ghi được thao tác với CloudTrail/IAM/KMS/S3 config/Secrets Manager/EKS. |
| M12-03 | Data coverage | `GetObject` trên đúng bucket/prefix nhạy cảm xuất hiện dưới dạng S3 data event. `GetSecretValue`/`BatchGetSecretValue` có event CloudTrail và truy ra principal, thời gian, resource, source. |
| M12-04 | Toàn vẹn mật mã | Bật log file integrity validation; có digest theo giờ, SHA-256 và chữ ký RSA; `aws cloudtrail validate-logs` trả kết quả hợp lệ cho khoảng demo. Khoảng digest thiếu phải bị coi là thất bại, không bỏ qua. |
| M12-05 | Bất biến | Log/digest vào bucket ở log-archive account, versioning + Object Lock **COMPLIANCE**; TF3 operator không có quyền xóa/ghi đè/đổi retention hoặc cấu hình archive. Chỉ auditor role chuyên biệt có quyền đọc evidence theo least privilege. |
| M12-06 | Giữ đủ lâu | Khuyến nghị 365 ngày WORM online/archive, có lifecycle tối ưu storage nhưng không rút ngắn lock; lý do: bao phủ dwell time nhiều ngày, phát hiện muộn và điều tra hồi tố. |
| M12-07 | Phát hiện anti-audit | Cảnh báo các API CloudTrail destructive/configuration, thay đổi bucket policy/Object Lock/lifecycle, KMS disable/schedule deletion, Organizations/trusted-access và hành vi rời organization. |
| M12-08 | Không phá ràng buộc | Storefront vẫn public, ops private; không sửa/vô hiệu hóa flagd; tổng AWS cost vẫn dưới khoảng `$300/tuần/TF`. |
| M12-09 | Forensic và danh tính kế thừa | Từ một event mentor chọn, dựng timeline cloud + Kubernetes + Git/change trail về đúng principal/session và nội dung thay đổi trong thời gian giới hạn; không chấp nhận tài khoản dùng chung không truy về cá nhân. |

## 5. Gói đầu ra phải nộp

1. Sơ đồ ownership/trust boundary và ADR lựa chọn.
2. Terraform/Policy-as-Code cho organization trail, archive bucket, KMS, selectors, detection và alerting — chỉ sau khi scope được phê duyệt.
3. Ma trận coverage: hành vi → event source/name/type → nơi lưu → truy vấn chứng minh.
4. Evidence “làm mù”: request của mentor, kết quả deny hoặc alarm, event chứa actor/time.
5. Evidence “làm hụt”: mentor đọc object mẫu và secret canary; team tìm được event tương ứng.
6. Evidence “làm mỏng/sửa”: output `validate-logs` cho thời gian demo, kèm chain/digest metadata.
7. Bằng chứng Object Lock, retention/lifecycle, KMS/bucket policy và cost estimate dựa trên volume thật.
8. Runbook triển khai, demo, sự cố, rollback và danh sách residual risks.
9. Bộ kịch bản tấn công có test ID, safety boundary, event kỳ vọng, evidence template và verdict `DESIGNED`/`DEPLOYED`/`VERIFIED`/`FAILED`.

## 6. Quy tắc bằng chứng

- Phân biệt `DESIGNED`, `DEPLOYED`, `VERIFIED`; không dùng file Terraform để thay cho bằng chứng live.
- Timestamp dùng UTC, lưu account ID/region/trail ARN/request ID nhưng redaction credential và `SecretString`.
- Evidence phải do principal mentor tạo và do principal điều tra độc lập truy vấn.
- Không cố tamper/xóa object đang ở Compliance mode; demo integrity bằng xác minh chain, hoặc dùng fixture/bucket thử riêng nếu cần minh họa failure.

## 7. Nguồn kỹ thuật chính

- [AWS — Organization trail và giới hạn của member account](https://docs.aws.amazon.com/en_en/awscloudtrail/latest/userguide/creating-trail-organization.html)
- [AWS — CloudTrail log file integrity validation](https://docs.aws.amazon.com/en_en/awscloudtrail/latest/userguide/cloudtrail-log-file-validation-intro.html)
- [AWS — `validate-logs`](https://docs.aws.amazon.com/awscloudtrail/latest/userguide/cloudtrail-log-file-validation-cli.html)
- [AWS — S3 Object Lock](https://docs.aws.amazon.com/AmazonS3/latest/userguide/object-lock.html)
- [AWS — Secrets Manager `GetSecretValue` tạo CloudTrail entry](https://docs.aws.amazon.com/secretsmanager/latest/apireference/API_GetSecretValue.html)
- [AWS — CloudTrail pricing](https://aws.amazon.com/cloudtrail/pricing/)

## 8. Bản đồ bộ tài liệu

| File | Vai trò |
|---|---|
| `01-tom-tat-yeu-cau-dau-vao-dau-ra-mandate-12.md` | Requirement baseline và acceptance criteria |
| `02-phan-tich-du-an-hien-tai-voi-mandate-12.md` | Gap analysis dựa trên repository TF3 |
| `03-de-xuat-solution-mandate-12-va-trade-off.md` | Quyết định kiến trúc và đánh đổi |
| `04-runbook-trien-khai-mandate-12.md` | Trình tự triển khai/vận hành/rollback |
| `05-thiet-ke-flow-mandate-12.md` | Flow và trust boundary end-to-end |
| `06-kich-ban-tan-cong-va-bang-chung-mandate-12.md` | Threat scenarios và mentor evidence |
