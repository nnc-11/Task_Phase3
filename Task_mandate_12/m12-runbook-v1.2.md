# Mandate 12 — Kế hoạch và runbook triển khai

> **Trạng thái:** READY FOR PREPARATION · chỉ thực hiện sau khi solution và gate được phê duyệt.

## 1. Nguyên tắc

- Không sửa repository production trong giai đoạn discovery.
- Không dùng root user để deploy.
- Mọi plan/apply qua identity cá nhân assume-role và saved plan.
- Audit foundation và IAM hardening là hai change riêng.
- Không dùng secret thật hoặc object thật cho mentor demo.
- Không đánh dấu `VERIFIED` chỉ vì apply thành công.

## 2. Phase 0 — Discovery chỉ đọc

Thu evidence:

1. Caller/account/region.
2. Trail hiện có, status, selectors, validation và destination.
3. Bucket/Object Lock/KMS/lifecycle hiện có trong account.
4. EKS control-plane logs và retention.
5. IAM admin users/roles, CI apply role, assume-role path và root hygiene.
6. Sensitive S3 bucket/prefix.
7. Secret inventory metadata; không đọc secret value.
8. Event volume và cost baseline.

### Kết quả đã xác nhận

- Không có CloudTrail trail hoặc Object Lock bucket để tái sử dụng.
- EKS `api`/`audit`/`authenticator` logging đang bật, retention 90 ngày.
- IAM user vận hành hiện tại có `AdministratorAccess` qua group.
- Có hai secret live: `sosflow/db-password` và `techx-corp-tf3/flagd-sync-token`.
- Có 7 S3 bucket; chưa bucket nào có Object Lock. Chỉ `techx-products-catalog-2026` và `techx-tf3-197826770971-tfstate` có Versioning `Enabled`.

Do đó Phase 1 phải tạo audit foundation mới; Phase 3 IAM hardening là điều kiện trước khi chạy deny test trên operator role.

### Go/No-Go

**GO** khi owner, scope, retention, alert recipient, backend/state và rollback path rõ ràng.

**NO-GO** khi:

- không biết trail/bucket hiện có thuộc ai;
- có nguy cơ tạo duplicate trail/bucket không cần thiết;
- chưa biết workflow nào phụ thuộc `AdministratorAccess`;
- plan có change/delete production resource;
- không có người giữ break-glass hoặc security alert.

## 3. Phase 1 — Audit foundation

### Dự kiến tạo/cập nhật

- Account CloudTrail multi-region.
- Management read/write events.
- S3 data selector được duyệt.
- S3 audit archive Versioning + Object Lock Compliance 365 ngày.
- Log file integrity validation.
- EventBridge/SNS anti-audit alert.

### Không thay đổi

- EKS workload, network, edge, datastore, flagd và application.

### Gate plan

- Chỉ add/update audit resources.
- Không destroy.
- Không mở public access.
- Không ghi secret vào state/config.
- Không bật S3 data events ngoài scope.
- Forecast cost trong ngân sách.

### Gate sau apply

- `IsLogging=true`.
- Multi-region/global events đúng.
- Event selectors đúng management/data coverage.
- Log và digest được delivery.
- Object Lock/retention đúng.
- Alert subscription healthy.

Nếu chưa có digest, trạng thái là `DEPLOYED`, chưa `VERIFIED`.

## 4. Phase 2 — Coverage tests

Chuẩn bị:

- canary S3 object không nhạy cảm trong prefix được log;
- canary secret vô giá trị, không app nào sử dụng;
- mentor/tester role có đúng quyền tối thiểu.

Kiểm tra:

1. `GetObject` tạo S3 data event.
2. `GetSecretValue` tạo management read event.
3. Config change canary tạo management write event.
4. Event có actor, session, time, resource, outcome và request ID.

## 5. Phase 3 — IAM hardening riêng

### Thiết kế access migration

1. Inventory toàn bộ use case của apply/admin role hiện tại.
2. Tạo audit-admin role riêng.
3. Tạo operator role với permissions boundary.
4. Test CI plan, EKS operations, incident response và rollback bằng role mới.
5. Chuyển từng workflow/user.
6. Chỉ loại quyền admin trực tiếp khi mọi test pass.

Boundary phải loại quyền:

- mutate CloudTrail;
- sửa/xóa audit bucket/Object Lock;
- tắt EventBridge/SNS alert;
- sửa/gỡ chính boundary và audit protection policy.

Không chuyển IAM hàng loạt trong cùng change với trail/bucket.

## 6. Phase 4 — Mentor verification

Tối thiểu:

- thử `StopLogging`/`DeleteTrail` bằng bounded operator;
- đọc canary object;
- đọc canary secret;
- chạy `validate-logs`;
- dựng một forensic timeline cloud/Kubernetes/Git nếu action liên quan EKS.

Chi tiết nằm trong file `m12-tests-v1.2.md`.

## 7. Vận hành sau triển khai

### Hằng ngày

- trail logging/delivery health;
- anti-audit alarms;
- delivery/digest errors.

### Hằng tuần

- integrity validation theo time window;
- coverage reconciliation với bucket/secret mới;
- cost thực tế so với forecast;
- review IAM/boundary drift;
- EKS audit retention và forensic query readiness.

### Khi mandate khác tạo resource

```text
Resource mới
→ phân loại dữ liệu
→ thêm coverage selector nếu cần
→ plan/review
→ canary verification
→ cập nhật coverage matrix
```

## 8. Failure handling

| Lỗi | Xử lý |
|---|---|
| Trail ngừng ghi | Critical incident; xác định actor, khôi phục qua audit-admin |
| Delivery error | Kiểm tra bucket policy/encryption; không nới public/admin rộng |
| Missing digest | Khoanh UTC window; không tuyên bố integrity pass |
| `GetObject` không có event | Sửa exact ARN selector sau cost review |
| `GetSecretValue` không có event | Kiểm tra management read coverage và region/time |
| Alert không đến | Kiểm tra rule/target/subscription; dừng mentor destructive test |
| IAM boundary làm hỏng workflow | Quay lại role cũ theo approved rollback; không gỡ audit foundation |
| Cost spike | Thu hẹp noisy non-sensitive selectors; không tắt mandatory logging |

## 9. Rollback

- Không rollback bằng cách tắt audit hoặc xóa archive.
- Object Lock Compliance đã áp dụng không thể rút ngắn.
- Có thể revert selector batch gây noise, nhưng vẫn giữ sensitive coverage.
- IAM migration rollback độc lập về role cũ trong thời gian test, với approval và audit trail.
- Nếu audit bucket cấu hình sai, dừng ghi mới sau approval và chuyển destination; giữ object cũ tới hết retention.

## 10. Definition of Done

- Audit foundation `DEPLOYED` và delivery healthy.
- Operator boundary được test mà không làm hỏng CI/operations.
- Mentor tests pass.
- Integrity validation pass.
- Retention evidence pass.
- Forensic attribution về cá nhân/session pass.
- Cost trong budget.
- Không ảnh hưởng storefront, private ops hoặc flagd.

## 11. Điều kiện bắt đầu chuẩn bị deployment

Static review đủ để bắt đầu chuẩn bị PR/code ở một audit root riêng, nhưng chưa cho phép chạy apply. Trước khi tạo PR phải chốt bốn input: tên/region audit bucket, danh sách S3 bucket-prefix nhạy cảm, KMS/SNS alert owner và backend state key của root audit.

PR audit phải có plan riêng, không có thay đổi trong `infra/live/production`; reviewer đối chiếu plan với allowlist audit resources. Nếu plan có thay đổi EKS, network, Cloudflare, datastore, flagd hoặc resource workload khác thì dừng và tách nguyên nhân trước khi review tiếp.

Sau PR mới thực hiện discovery chỉ đọc để xác nhận thông số live và quyền thực thi. Chỉ khi tất cả gate pass mới chuyển từ `READY FOR PREPARATION` sang `APPROVED FOR APPLY`.

## 12. Input còn thiếu trước PR

AWS CLI đã đủ để loại bỏ giả định sai về trail/Object Lock, nhưng không tự quyết định scope nghiệp vụ. Owner phải phê duyệt bằng văn bản: bucket/prefix S3 cần log `GetObject`, người nhận SNS, tên audit bucket, backend state key và vai trò audit-admin. Không chọn `sosflow/db-password`, `flagd-sync-token`, Terraform state hay production object làm canary.

---

**Phiên bản:** v1.2  
**Cập nhật:** 17/07/2026  
**Trạng thái:** READY FOR PREPARATION — chưa được phép apply
