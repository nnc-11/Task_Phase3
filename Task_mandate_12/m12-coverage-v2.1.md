# Mandate 12 — Coverage matrix v2

> `NO-GO` nếu còn asset nhạy cảm `Unknown`, thiếu owner hoặc exact S3 scope.

## 1. Dữ liệu

| ID | Asset từ repo mới | Logging cần có | Input/test | Trạng thái |
|---|---|---|---|---|
| COV-01 | `techx-corp-tf3/flagd-sync-token` | Management Read/Write | Canary secret riêng; không đọc secret thật | `LIVE-CONFIRMED` |
| COV-02 | `rds!db-78563b84-b60e-454b-a26f-6c25602a02e8` | Management Read/Write | Metadata-only inventory, owner datastore | `LIVE-CONFIRMED / OWNER PENDING` |
| COV-03 | `techx-tf3/elasticache-auth` | Management Read/Write | Canary test riêng | `LIVE-CONFIRMED / OWNER PENDING` |
| COV-04 | `AmazonMSK_techx-tf3/kafka-scram` | Management Read/Write | Có customer KMS key; không đọc value | `LIVE-CONFIRMED / OWNER PENDING` |
| COV-05 | `sosflow/db-password` | Management Read/Write | Canary test riêng; không đọc value | `LIVE-CONFIRMED / OWNER PENDING` |
| COV-06 | Terraform state bucket/prefix | S3 data events nếu sensitive; nếu loại phải có acceptance | Exact `arn:aws:s3:::bucket/prefix/` | `PENDING OWNER` |
| COV-07 | Product/catalog/static buckets | S3 data events cho prefix sensitive | Một hàng cho từng bucket/prefix | `PENDING INVENTORY` |
| COV-08 | M11 archive được nâng cấp làm M11/M12 archive | Không đưa vào data selector; destination + digest + Compliance | Verify object mới sau cutover | `TARGET-UPGRADE` |
| COV-09 | Không tạo M12 archive thứ hai | N/A | Xác nhận plan không tạo bucket/trail mới | `NOT APPLICABLE` |
| COV-10 | EKS Kubernetes API/audit | EKS control-plane audit logs supplemental | Live: `api/audit/authenticator`, log retention 90 ngày | `LIVE-CONFIRMED-2026-07-21` |

Discovery chỉ đọc đã thấy đúng 5 secret metadata trên; không gọi `GetSecretValue` và không lưu secret value.

## 2. S3 inventory live

| Bucket live | Vai trò dự kiến | Quyết định selector |
|---|---|---|
| `sosflow-alb-logs-197826770971` | ALB access logs | Owner/classification pending |
| `sosflow-frontend-197826770971` | Frontend/static | Owner/classification pending |
| `techx-aiops-playbooks-f6230446` | AIOps playbooks | Ưu tiên review sensitive prefix |
| `techx-corp-tf3-audit-trail-ap-southeast-1-197826770971` | CloudTrail archive | **Exclude** để tránh recursive data events |
| `techx-products-catalog-2026` | Product catalog | Owner/classification pending |
| `techx-tf3-197826770971-tfstate` | Terraform state | Ưu tiên cover exact state prefix sau owner approval |
| `tf3-aiops-models-197826770971` | Model artifacts | Owner/classification pending |
| `thermal-power-plant-frontend-197826770971` | Frontend/static | Owner/classification pending |

Inventory live không đồng nghĩa bật data events cho cả 7 bucket còn lại. Owner phải chọn exact bucket/prefix chứa dữ liệu nhạy cảm để kiểm soát chi phí và nhiễu.

## 3. Cấu hình quan trọng

| ID | Control | Event/health bắt buộc | Evidence |
|---|---|---|---|
| CFG-01 | M11 trail sau nâng cấp M12 | `StopLogging`, `DeleteTrail`, `UpdateTrail`, selector changes | Denied attempt + EventBridge/SNS + trail status |
| CFG-02 | M11/M12 archive | policy, lock, versioning, lifecycle, public access | Deny + post-state + retention của object sau cutover |
| CFG-03 | M12 alert plane | rule/target/topic/subscription changes | Deny + invocation + receipt |
| CFG-04 | Heartbeat | Lambda/schedule mutation; missing invocation | Deny + heartbeat PASS log + missing-invocation alarm test |
| CFG-05 | IAM | boundary/policy/trust/OIDC mutation | Deny + regional event + owner mapping |
| CFG-06 | EKS log config | control-plane logging changes | Verify live and management event |

## 4. Approval table phải điền trước plan

| S3 ARN kết thúc bằng `/` | Classification | Data owner | Lý do coverage/exclusion | Estimated events/month | Approval |
|---|---|---|---|---:|---|
| `TBD` | `TBD` | `TBD` | `TBD` | `TBD` | `PENDING` |

Giá trị trong bảng phải khớp 1:1 với `audit_detection_s3_data_event_arns` được merge vào `infra/live/production/production.auto.tfvars`; không dùng wildcard. Toàn bucket hợp lệ là `arn:aws:s3:::bucket/`.

## 5. Gate

- Inventory live ngày 21/07 đã hoàn tất; chạy lại trong change window để bắt drift.
- Mọi secret/bucket mới từ M8/M11 có owner và classification.
- Canary nằm trong approved selector nhưng không phải dữ liệu production.
- Forecast gồm S3 data events, archive storage 400 ngày và heartbeat; không có duplicate management-event trail.
- Matrix, tfvars và plan có cùng hash/change record.

---

**Phiên bản:** v2.1
**Cập nhật:** 21/07/2026
**Trạng thái:** LIVE INVENTORY COMPLETE / CLASSIFICATION PENDING — chưa đủ điều kiện plan
