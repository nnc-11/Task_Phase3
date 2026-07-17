# Checklist triển khai ngày mai

> **BLOCKED / SUPERSEDED:** checklist này thuộc phương án Organization/cross-account. Không dùng để triển khai cho solution single-account đang được chọn và thảo luận.

## A. Trước cửa sổ triển khai — GO/NO-GO

- [ ] Có change ticket, approver, executor, observer và UTC window.
- [ ] Xác nhận TF3 account bằng `aws sts get-caller-identity`; không tin account ID trong tài liệu.
- [ ] Xác nhận Organization ID, management/delegated account và log-archive account.
- [ ] Xác nhận executor có đúng role cho từng account, không dùng TF3 production admin để quản trị audit plane.
- [ ] Backend bucket/lock table riêng cho hai Terraform root đã tồn tại.
- [ ] Điền `env.sh` từ `env.example`, không commit file này.
- [ ] Điền `backend.hcl` và `terraform.tfvars`, không commit giá trị live/sensitive.
- [ ] Danh sách sensitive S3 ARN prefix đã được data owner duyệt.
- [ ] Security email/on-call owner sẵn sàng xác nhận SNS subscription.
- [ ] Cost forecast và Object Lock Compliance 365 ngày được chấp thuận.
- [ ] Chạy `scripts/preflight.sh`; tất cả kiểm tra bắt buộc pass.

**NO-GO** nếu thiếu Organization/external owner, caller sai account, backend chưa sẵn sàng, bucket name đã tồn tại ngoài ownership, hoặc plan có change/delete production resource.

## B. Deploy root 1 — log archive

- [ ] Vào đúng role/account log archive.
- [ ] `terraform init -reconfigure -backend-config=backend.hcl`.
- [ ] `terraform fmt -check && terraform validate`.
- [ ] `terraform plan -out=tfplan`.
- [ ] Hai người review plan: chỉ add S3/KMS/policy/lifecycle, không change/delete.
- [ ] `terraform apply tfplan`.
- [ ] Lưu output bucket ARN/name, KMS ARN, expected trail ARN và retention.
- [ ] Kiểm tra versioning, Object Lock Compliance và public access block.

## C. Deploy root 2 — organization trail

- [ ] Vào đúng management/delegated role/account.
- [ ] Điền output root 1 vào tfvars root 2.
- [ ] `terraform init`, `fmt -check`, `validate`, `plan -out=tfplan`.
- [ ] Hai người review: organization + multi-region + validation; selector đúng scope; không change/delete.
- [ ] `terraform apply tfplan`.
- [ ] Xác nhận SNS email subscription.
- [ ] Chạy `scripts/verify.sh` sau khi export đúng biến môi trường.

## D. Gate sau apply

- [ ] `IsLogging=true`.
- [ ] Event selectors có management events và đúng S3 ARN prefix.
- [ ] Latest delivery/digest không báo lỗi sau thời gian delivery hợp lý.
- [ ] Log group, metric filters, alarm và SNS subscription healthy.
- [ ] Tạo canary object/secret theo approval; không dùng production secret value.
- [ ] Mentor test ATK-01/02/06/07/11 theo file 06.
- [ ] `validate-logs` pass cho UTC window đã có digest.
- [ ] Lưu evidence theo `EVIDENCE.md`.

## E. Điều kiện kết thúc

- `DEPLOYED`: apply + delivery health pass.
- `VERIFIED`: mentor tests + integrity validation + evidence pass.
- Nếu chỉ apply thành công nhưng digest chưa đến: giữ `DEPLOYED`, không báo hoàn tất.
- Nếu bất kỳ lệnh tắt trail nào thành công ngoài dự kiến: dừng test, mở Critical incident và khôi phục qua organization owner.
