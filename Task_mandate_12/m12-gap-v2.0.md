# Mandate 12 — Gap analysis theo hạ tầng mới

> Repository `Phase3-TF3-Infra-Sentinel` tại `bbe2503`, đọc ngày 21/07/2026; không đọc `docs/docx_cdo02`, không tác động production.

## Baseline mới

`LIVE-CONFIRMED` ngày 21/07/2026 bằng AWS CLI read-only trên account `197826770971`: Mandate 11 đã được deploy và đang vận hành. Không có lệnh mutation nào được chạy.

- Trail: `techx-corp-tf3-audit-detection-ap-southeast-1-trail`, home region `ap-southeast-1`, multi-region/global events, validation bật, `IsLogging=true`.
- Delivery gần nhất: log `2026-07-21T16:46:57+07:00`; digest `2026-07-21T15:51:19+07:00`.
- Archive: `techx-corp-tf3-audit-trail-ap-southeast-1-197826770971`, Versioning bật, Object Lock `GOVERNANCE 14 ngày`, lifecycle `30 ngày`, SSE-S3, public access block toàn bộ.
- Event selectors: management Read/Write `All`; `DataResources=[]`, vì vậy chưa có bằng chứng S3 `GetObject`/bulk download.
- Alert plane: 6 EventBridge rules và 2 router Lambda đang tồn tại; rules đều enabled. Primary SNS còn 3 email `PendingConfirmation`, global SNS còn 1.
- EKS `techx-corp-tf3`: `api`, `audit`, `authenticator` enabled; log group retention `90 ngày`.

| Control | M11 hiện codify | Gap M12 |
|---|---|---|
| CloudTrail | Multi-region, management Read/Write, validation | Chưa có S3 Object data events |
| Archive | Versioning, SSE-S3, Object Lock | `GOVERNANCE` 14 ngày; lifecycle mặc định 30 ngày |
| Alert | Trail/IAM/EKS/secret/destructive events | Automation allowlist có thể suppress critical anti-audit; chưa bảo vệ đầy đủ alert plane |
| Blind-window detection | Event-driven | Chưa có heartbeat phát hiện delivery/digest im lặng |
| EKS audit | Live 21/07: `api/audit/authenticator` bật, retention 90 ngày | Repo chưa codify log types; heartbeat phải phát hiện drift |
| IAM | Apply role live có `AdministratorAccess`, không boundary; operator không boundary | Current admin user có admin qua group và chưa MFA; hardening là change riêng |

## Quyết định sau review

Không tạo trail M12 thứ hai. Nâng cấp trail M11 tại chính Terraform root đang sở hữu nó:

1. management events giữ nguyên;
2. thêm exact S3 Object data-event selectors;
3. đổi default Object Lock cho object mới thành `COMPLIANCE` 365 ngày;
4. lifecycle 400 ngày để dài hơn retain-until;
5. giữ integrity validation và chứng minh bằng `validate-logs`;
6. sửa critical alert suppression, thêm regional g7, global g8 và heartbeat 5 phút kiểm tra exact configuration/targets.

## Giới hạn cutover

Object đã giao trước upgrade giữ retention cũ; thay default retention không hồi tố. Claim M12 chỉ bắt đầu từ cutover timestamp khi:

- selector mới active;
- log và digest delivery healthy;
- object mới có Compliance retain-until 365 ngày;
- heartbeat PASS;
- alert subscriptions Confirmed.

## Asset live đã inventory metadata

- 5 Secrets Manager secrets: `sosflow/db-password`, `techx-corp-tf3/flagd-sync-token`, `techx-tf3/elasticache-auth`, `AmazonMSK_techx-tf3/kafka-scram`, `rds!db-78563b84-b60e-454b-a26f-6c25602a02e8`. Không đọc value.
- 8 S3 buckets đã liệt kê trong `m12-coverage-v2.0.md`; vẫn cần owner/classification và exact prefix trước khi bật data events.
- EKS logging/retention đã xác nhận live.
- IAM live: `AdministratorAccess` gắn vào 1 group, 3 users trực tiếp và 1 role. Đáng chú ý `gitlab-ci-deployer` không MFA, có 2 active keys và đang nằm trong router allowlist; phải sửa critical suppression và phối hợp owner để migrate.
- AWS Config live chưa có recorder; solution M12 không dựa vào Config để pass, heartbeat kiểm tra trực tiếp các audit controls.

## Blocker trước deploy

1. Owner duyệt exact S3 bucket/prefix và chi phí data events.
2. Xử lý 3 primary + 1 global SNS subscription còn pending.
3. Bật MFA cho `cdo-2-admin-team` hoặc dùng approved MFA deployment role; không deploy bằng root.
4. CD01/IaC owner xác nhận production state ownership, change window và plan không replace/delete.
5. Xác định owner/migration cho các IAM admin user và active keys; không rotate/delete ngoài approved IAM change.

## Rủi ro triển khai

Phương án reuse tránh duplicate CloudTrail/cost nhưng **không còn độc lập hoàn toàn**: PR audit foundation phải sửa `infra/modules/audit-detection` và `infra/live/production`. Plan chỉ được update M11 audit resources + controls đã liệt kê; nếu có EKS/network/datastore/workload change thì NO-GO.

## Kết luận

M11 live cung cấp đúng nền để nâng cấp, nhưng hiện chưa đủ M12 vì thiếu S3 data events, retention/anti-defeat target, heartbeat và IAM hardening. Trạng thái là `LIVE BASELINE CONFIRMED / READY FOR REVIEW`; chưa được apply và chưa được claim M12.

---

**Phiên bản:** v2.0
**Cập nhật:** 21/07/2026
**Trạng thái:** LIVE BASELINE CONFIRMED — owner approval và blocker deploy còn thiếu
