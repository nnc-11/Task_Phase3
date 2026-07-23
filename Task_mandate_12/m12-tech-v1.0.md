# Mandate 12 — Công nghệ và bốn lớp chống đánh bại audit

## 1. Cách hiểu ngắn gọn

Mandate 12 không chỉ yêu cầu "có log". Hệ thống phải xử lý bốn kiểu tấn công khác nhau:

| Bối cảnh | Kẻ tấn công làm gì? | Điều cần chứng minh |
|---|---|---|
| **Không xóa được** | Xóa hoặc sửa log đã được ghi | Bản ghi đã giao tới archive được giữ nguyên, không thể xóa/sửa trong thời hạn bảo vệ |
| **Làm mù** | Tắt trail, phá delivery hoặc phá đường cảnh báo trước khi hành động | Thao tác bị chặn hoặc tạo cảnh báo; nếu hệ thống im lặng bất thường thì heartbeat phát hiện |
| **Làm hụt** | Hành động tại nơi CloudTrail chưa thu thập, ví dụ đọc S3 object khi data events chưa bật | Mọi hành động nhạy cảm trong phạm vi đã duyệt đều để lại event đủ truy vết |
| **Làm mỏng** | Vẫn có event nhưng chỉ biết "ai gọi API lúc nào", không biết cấu hình nào đã đổi | Nối được trạng thái trước, kế hoạch thay đổi, trường cấu hình trong event và trạng thái sau |

Một control không giải quyết được cả bốn vấn đề. Ví dụ, S3 Object Lock bảo vệ file log **sau khi file đã được giao**, nhưng không ngăn việc tắt CloudTrail trước khi tấn công. Vì vậy Mandate 12 dùng nhiều lớp phòng thủ.

## 2. Kiến trúc được chọn

Mandate 12 **không tạo trail thứ hai**. Giải pháp nâng cấp in-place nền Mandate 11 đang có:

```text
AWS management events ─┐
Approved S3 data events ├─> M11 CloudTrail nâng cấp ─> S3 audit archive + signed digest
                        │              │
                        │              └─> EventBridge g1/g7/g8 ─> Lambda router ─> SNS
                        │
Heartbeat mỗi 5 phút ───┴─> kiểm tra trail, delivery, digest, selector, archive,
                             rule, router, alarm, topic/subscription và EKS audit

IAM hardening triển khai sau Foundation:
Daily/CI identities ─> least privilege + permissions boundary ─| audit kill switches
```

Ảnh kiến trúc: [m12-architecture-v1.0.png](m12-architecture-v1.0.png).

## 3. Tech dùng cho “không xóa được”

### 3.1 Amazon S3 Versioning

- Mỗi lần ghi tạo một object version; ghi đè không âm thầm thay thế version cũ.
- Hỗ trợ giữ lịch sử và điều tra khi có thao tác bất thường.
- Versioning một mình chưa đủ vì principal có quyền vẫn có thể xóa version; do đó phải kết hợp Object Lock.

### 3.2 S3 Object Lock — COMPLIANCE mode

- Default retention mục tiêu: `COMPLIANCE 365 ngày` cho **object mới sau cutover**.
- Trong thời gian retention, protected object version không thể bị xóa, ghi đè hoặc rút ngắn thời hạn, kể cả bởi root.
- Object cũ không tự động được bảo vệ hồi tố ở mức 365 ngày; bằng chứng phải ghi rõ UTC cutover.

### 3.3 S3 lifecycle — 400 ngày

- Log được giữ 400 ngày trước khi đủ điều kiện expiration.
- 365 ngày Object Lock tạo cửa sổ điều tra 12 tháng; 35 ngày còn lại là khoảng đệm cho export, review và xử lý sự cố.
- Lifecycle 400 ngày cũng có thể ảnh hưởng object cũ chưa bị xóa, vì vậy cần inventory tuổi/dung lượng và phê duyệt chi phí trước apply.

### 3.4 Bucket policy, IAM boundary và Terraform `prevent_destroy`

- Bucket policy và permissions boundary deny các hành vi phá archive như `DeleteObject`, `DeleteObjectVersion`, `BypassGovernanceRetention` và xóa bucket/policy liên quan.
- `prevent_destroy` chặn Terraform plan vô tình destroy/replace trail hoặc bucket.
- `prevent_destroy` chỉ là guardrail trong Terraform, không thay thế IAM và Object Lock.

### 3.5 CloudTrail log file integrity validation

- CloudTrail tạo digest có chữ ký và liên kết digest theo chuỗi.
- `aws cloudtrail validate-logs` dùng chuỗi digest để phát hiện log file được chuỗi tham chiếu bị sửa hoặc xóa; file giả thêm ngoài chuỗi không thể vượt qua xác minh chữ ký/digest như log hợp lệ.
- Object Lock là lớp **ngăn phá**, còn digest validation là lớp **chứng minh mật mã** rằng archive không bị can thiệp.

## 4. Tech dùng cho “làm mù”

### 4.1 CloudTrail multi-region giữ `IsLogging=true`

- Tái sử dụng trail M11 hiện hữu và tiếp tục ghi management read/write events ở nhiều region.
- Không đổi trail ARN/name và không dừng logging trong quá trình nâng cấp.

### 4.2 IAM permissions boundary và least privilege

- Daily operator và CI identity bị deny các kill switch như `StopLogging`, `DeleteTrail`, xóa archive, tắt/xóa EventBridge rule, xóa router/alarm/topic hoặc tự gỡ boundary.
- Boundary là **trần quyền**, không tự cấp quyền; quyền thực tế vẫn phải đến từ policy allow tối thiểu.
- Root trong single account không chịu permissions boundary. Đây là residual risk bắt buộc xử lý bằng root MFA, không có root access key, named custodian, incident-only process và ký chấp nhận rủi ro.

### 4.3 EventBridge tamper rules

- Nhóm g1 bắt các thay đổi CloudTrail như `StopLogging`, `DeleteTrail`, `UpdateTrail` và `PutEventSelectors`.
- Nhóm g7 bắt thay đổi audit controls: S3 policy/retention, EventBridge, Lambda, CloudWatch alarm và SNS.
- Nhóm g8 bắt thay đổi IAM/OIDC có khả năng mở đường phá audit.
- Các nhóm critical `1/2/3/4/7/8` luôn alert, kể cả actor là Terraform automation; allowlist không được che sự kiện critical.

### 4.4 Lambda alert router và Amazon SNS

- Lambda router chuẩn hóa event thành cảnh báo có actor, session, action, resource, thời gian và request ID.
- Router gửi tới SNS primary/global đang kế thừa từ M11.
- Các subscription bắt buộc phải ở trạng thái `Confirmed`; `PendingConfirmation` không được coi là đường cảnh báo hoạt động.

### 4.5 Heartbeat Lambda mỗi 5 phút

Heartbeat không chờ có tamper event mới kiểm tra. Nó đọc live state và xác minh các invariant:

- trail tồn tại, `IsLogging=true`, multi-region và validation bật;
- log delivery không cũ quá 20 phút, digest không cũ quá 90 phút;
- management selector và exact S3 data selectors còn đúng;
- Object Lock, Versioning, lifecycle, encryption, public block và archive deny policy còn đúng;
- EventBridge pattern/target, routers, alarms, topic policies và subscriptions còn đúng;
- EKS `api/audit/authenticator` logging còn bật;
- các principal thuộc scope vẫn mang đúng permissions boundary.

Heartbeat phải so **live state với invariant đã định nghĩa độc lập**, không so Terraform config với chính nó.

### 4.6 CloudWatch alarms và SNS fallback

- Alarm `Errors` phát hiện heartbeat chạy nhưng lỗi.
- Alarm `Missing` phát hiện heartbeat không còn phát metric/invocation như dự kiến.
- Hai alarm gửi tới primary SNS và một fallback SNS cùng region.
- Khi heartbeat tự phát hiện invariant fail, Lambda thử publish primary và global theo hai lần độc lập; một topic lỗi không được ngăn lần thử còn lại.

Kết quả: nếu admin không bị chặn hoàn toàn thì lệnh phá audit vẫn phải tạo event/alert; nếu delivery hoặc chính heartbeat im lặng thì alarm phát hiện blind window.

## 5. Tech dùng cho “làm hụt”

### 5.1 CloudTrail advanced event selectors

Advanced selectors phải giữ đồng thời hai loại coverage:

1. `eventCategory = Management` cho các AWS API quản trị và đọc Secrets Manager.
2. `eventCategory = Data` cho S3 object access trên **exact bucket/prefix ARN đã được owner duyệt**.

Advanced selectors thay thế basic selectors, vì vậy nếu quên management selector khi thêm S3 data selector thì sẽ tạo một coverage gap mới.

### 5.2 S3 object data events

- Ghi các thao tác object-level như `GetObject`, giúp phát hiện tải trộm object hoặc kéo dữ liệu trong phạm vi được duyệt.
- Chỉ bucket/prefix nhạy cảm đã được owner xác nhận mới được đưa vào để kiểm soát noise và chi phí.
- Audit archive bucket không được đưa vào selector để tránh log chính hoạt động ghi log và tạo recursion/noise.

### 5.3 Secrets Manager management events

- `GetSecretValue` để lại CloudTrail management event với identity, thời gian, source IP, user agent, request ID và secret resource metadata.
- CloudTrail **không ghi secret value** (`SecretString`/`SecretBinary`). Mục tiêu là chứng minh ai đã đọc secret nào, không sao chép bí mật vào log.

### 5.4 EKS audit logging

- `api`, `audit` và `authenticator` cung cấp ngữ cảnh Kubernetes bổ sung cho hoạt động trên EKS.
- Đây là evidence bổ sung, không thay thế CloudTrail cho AWS API.
- Mandate 12 không thay đổi EKS; heartbeat chỉ giám sát flag audit logging để phát hiện drift.

### 5.5 Canary coverage test

- Thực hiện `GetObject` trên canary object thuộc approved prefix và `GetSecretValue` trên canary secret trong approved window.
- PASS khi tìm được raw event có principal/session, resource, UTC và request ID, đồng thời không lộ secret value hoặc production object content.
- Nếu không tìm được event thì coverage vẫn `FAIL`, dù trail đang báo `IsLogging=true`.

## 6. Tech dùng cho “làm mỏng”

### 6.1 CloudTrail raw event và `requestParameters`

CloudTrail event cho biết identity/session, event time, event source/name, source IP, user agent, request ID, resource và các request parameters mà dịch vụ cung cấp. Tuy nhiên một event đơn lẻ chưa luôn đủ để kết luận cấu hình cuối cùng đã trở thành gì.

### 6.2 Chuỗi bằng chứng pre-state → plan → event → post-state

Mandate 12 chọn các thay đổi thật đã được duyệt như `PutMetricAlarm` và `PutRule`, rồi nối bốn nguồn:

1. **Pre-state:** cấu hình trước thay đổi từ discovery read-only.
2. **Saved Terraform plan:** thay đổi dự kiến và SHA-256 của plan.
3. **CloudTrail event:** actor/session/request ID và các `requestParameters` được allowlist/redact.
4. **Post-state:** `describe-alarms` hoặc `describe-rule` sau apply.

PASS khi reviewer nối được trường đã dự kiến thay đổi với request thực tế và giá trị cuối cùng. Chỉ có ảnh chụp alert hoặc dòng “user X gọi API Y” là chưa đủ.

### 6.3 Evidence export và redaction

- `Export-M12CloudTrailEvidence.ps1` trích xuất các trường cấu hình allowlist cần cho forensic diff.
- Tool không xuất secret, token, request body nhạy cảm, policy document hoặc object content.
- Raw log copy, bản redacted, integrity output và evidence JSON đều có SHA-256 để chứng minh bộ bằng chứng không bị sửa sau khi thu thập.

### 6.4 Digest validation không thay thế semantic evidence

- Digest validation chứng minh file log không bị sửa/xóa/thêm lén.
- Pre/plan/event/post-state chứng minh event **đủ ý nghĩa** để dựng lại thay đổi.
- Cần cả hai: log toàn vẹn nhưng quá nghèo thông tin vẫn là “làm mỏng”; log nhiều thông tin nhưng không chứng minh toàn vẹn cũng chưa đứng vững như bằng chứng.

## 7. Bảng tổng hợp control

| Công nghệ/control | Ngăn chặn | Phát hiện | Tạo bằng chứng | Bối cảnh chính |
|---|:---:|:---:|:---:|---|
| S3 Versioning + Object Lock Compliance | ✓ |  | ✓ | Không xóa được |
| Lifecycle 400 ngày | ✓ |  | ✓ | Không xóa được/giữ đủ lâu |
| Bucket policy + IAM boundary | ✓ |  | ✓ qua denied event | Không xóa được/làm mù |
| Terraform `prevent_destroy` | ✓ với Terraform |  | plan | Không xóa nhầm |
| CloudTrail integrity validation + digest |  | ✓ | ✓ mật mã | Không xóa/sửa lén |
| EventBridge g1/g7/g8 |  | ✓ | raw tamper event | Làm mù |
| Lambda router + SNS |  | ✓ | alert receipt | Làm mù |
| Heartbeat + CloudWatch alarms + fallback SNS |  | ✓ | heartbeat/alarm logs | Làm mù/im lặng |
| Advanced selectors + S3 data events |  | ✓ | raw access event | Làm hụt |
| Secrets Manager management events |  | ✓ | raw access metadata | Làm hụt |
| EKS audit logs |  | ✓ | Kubernetes audit event | Làm hụt bổ sung |
| Pre-state + saved plan + raw event + post-state |  | ✓ | ✓ ngữ nghĩa | Làm mỏng |
| Evidence exporter + SHA-256 |  | ✓ | ✓ | Làm mỏng/bàn giao |

## 8. Điều kiện để được tuyên bố hoàn thành

- **Audit Foundation đạt:** trail/delivery/digest/selectors/retention/heartbeat/alert paths và canary coverage đều PASS.
- **IAM Hardening đạt:** daily/CI identities thuộc scope có least privilege/boundary, simulation và denied tests PASS.
- **Evidence đạt:** `validate-logs` PASS và forensic diff pre-state → plan → event → post-state được reviewer xác nhận.
- **Retention đạt:** object mới sau cutover có `COMPLIANCE >=365 ngày`, lifecycle 400 ngày và cost/owner approval.
- **Residual risk đạt:** root/single-account limitation được ghi rõ và ký chấp nhận.

Nếu chỉ Foundation pass nhưng IAM chưa hoàn thành, trạng thái là `AUDIT READY/PARTIAL`, chưa được ghi `VERIFIED` cho toàn bộ Mandate 12.

---

**Phiên bản:** v1.0  
**Cập nhật:** 23/07/2026  
**Trạng thái:** EXPLANATION / HANDOFF SUPPORT
