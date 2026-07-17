# Hướng dẫn triển khai code_audit

> Đây là hướng dẫn có gate, không phải lệnh đã chạy. Chỉ thực hiện sau change approval. Luôn dùng account/role riêng cho từng root và kiểm tra `aws sts get-caller-identity` trước mọi plan/apply.

> **KHÔNG THỰC HIỆN HƯỚNG DẪN NÀY Ở TRẠNG THÁI HIỆN TẠI.** Nội dung bên dưới dành cho phương án Organization/cross-account, hiện chỉ là alternative và không phải solution được chọn cho TF3 single-account.

Trình tự thao tác nhanh nằm ở `TOMORROW-CHECKLIST.md`; tài liệu này giải thích chi tiết. Organization trail có thể cần thời gian để xuất hiện/delivery ở mọi member account/region, nên `apply` thành công không đồng nghĩa Mandate đã `VERIFIED` trong cùng phút.

## 1. Điều kiện đầu vào

- TF3 account live đã được xác minh, dự kiến `197826770971`.
- Có AWS Organization, management/delegated CloudTrail admin và log-archive account.
- Có backend S3/DynamoDB riêng cho từng Terraform root.
- Có trail name, Organization ID, management account ID và auditor role ARN.
- Có danh sách S3 object ARN prefix nhạy cảm, ví dụ `arn:aws:s3:::bucket/prefix/`.
- Cost forecast và retention 365 ngày đã được phê duyệt.

**STOP** nếu thiếu external ownership. Không thay bằng account-local trail rồi tuyên bố đạt Mandate 12.

## 2. Copy vào repo sau phê duyệt

Copy:

```text
Task_Phase3/Task_mandate_12/code_audit/terraform/log-archive
→ Phase3-TF3-Infra-Sentinel/infra/audit/log-archive

Task_Phase3/Task_mandate_12/code_audit/terraform/organization-trail
→ Phase3-TF3-Infra-Sentinel/infra/audit/organization-trail
```

Không copy file `*.tfvars` chứa account-specific hoặc sensitive values vào Git. Chỉ commit `.example` đã redaction.

## 3. Deploy log archive trước

```sh
cd infra/audit/log-archive
cp backend.hcl.example backend.hcl
cp terraform.tfvars.example terraform.tfvars
# điền placeholder bằng dữ liệu đã được phê duyệt
terraform init -reconfigure -backend-config=backend.hcl
terraform fmt -check
terraform validate
terraform plan -out=tfplan
terraform show tfplan
terraform apply tfplan
terraform output
```

Gate:

- caller thuộc log-archive account;
- plan chỉ add audit S3/KMS/policies;
- bucket versioning + Object Lock enabled;
- default retention `COMPLIANCE` 365 ngày;
- không có resource ngoài `infra/audit/log-archive` bị change/delete.

## 4. Deploy organization trail

Điền outputs của root trước vào `organization-trail/terraform.tfvars`, sau đó:

```sh
cd ../organization-trail
cp backend.hcl.example backend.hcl
cp terraform.tfvars.example terraform.tfvars
terraform init -reconfigure -backend-config=backend.hcl
terraform fmt -check
terraform validate
terraform plan -out=tfplan
terraform show tfplan
terraform apply tfplan
terraform output
```

Gate:

- caller thuộc management/delegated admin account;
- `is_organization_trail = true`;
- multi-region, global events và log file validation được bật;
- management events read/write được thu;
- S3 data selectors chỉ chứa ARN prefix đã duyệt;
- CloudWatch Logs/SNS detection nằm ngoài quyền TF3 operator;
- không change/delete resource production TF3.
- mọi email subscription đã được security owner xác nhận; alarm không có subscription `PendingConfirmation`.

## 5. Verify sau apply

```sh
aws cloudtrail get-trail-status --name <trail-arn> --region <home-region>
aws cloudtrail get-event-selectors --trail-name <trail-arn> --region <home-region>
aws s3api get-object-lock-configuration --bucket <audit-bucket>
```

Chờ log/digest delivery rồi chạy:

```sh
aws cloudtrail validate-logs \
  --trail-arn <trail-arn> \
  --account-id 197826770971 \
  --start-time <UTC-start> \
  --end-time <UTC-end> \
  --region <home-region> \
  --verbose
```

Sau đó thực hiện ATK-01, ATK-02, ATK-06, ATK-07 và ATK-11 theo `06-kich-ban-tan-cong-va-bang-chung-mandate-12.md`.

## 6. Rollback

- Không thể tắt Object Lock hoặc rút ngắn retention của object Compliance đã tạo.
- Không destroy audit bucket/KMS/trail để rollback thông thường.
- Có thể sửa selector gây noise bằng reviewed plan, nhưng phải giữ management logging và sensitive coverage.
- Nếu cấu hình bucket sai, dừng ghi object mới sau phê duyệt và chuyển sang bucket đúng; giữ object cũ tới hết retention.
- Khi migration trail, không xóa trail cũ trước khi trail mới có delivery + digest hợp lệ.
