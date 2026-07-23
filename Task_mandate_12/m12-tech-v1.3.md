# Mandate 12 — Công nghệ và bốn lớp chống đánh bại audit

| Thuộc tính | Giá trị |
|---|---|
| Phạm vi | Audit Foundation và IAM Hardening cho TF3 |
| AWS account/region | `197826770971` / `ap-southeast-1` |
| Kiến trúc chọn | Nâng cấp in-place nền Mandate 11, không tạo trail thứ hai |
| Implementation snapshot | Branch `feat/mandate-12-audit-anti-defeat`, commit `8a554a3` |
| Trạng thái | `DESIGN REVIEWED / NOT RUNTIME VERIFIED` |

## Tóm tắt điều hành

Theo discovery AWS read-only ngày 21/07/2026, Mandate 11 đã cung cấp CloudTrail multi-region, S3 archive và alert plane. Baseline này chưa đủ Mandate 12 vì S3 object reads chưa nằm trong event selector, retention mới ở Governance 14 ngày/lifecycle 30 ngày, chưa có heartbeat và một số identity vận hành còn quyền tác động audit.

Giải pháp chọn nâng cấp in-place nền M11. Audit Foundation bổ sung exact S3 data-event scope đã được owner duyệt, Object Lock Compliance 365 ngày cho object mới, lifecycle 400 ngày, tamper rules và heartbeat mỗi 5 phút. Sau khi Foundation ổn định, IAM Hardening giới hạn audit kill switches đối với Daily/CI identities trong scope.

Kết quả không được đánh giá chỉ bằng việc resource tồn tại. Hệ thống phải vượt qua các bài kiểm chứng: thao tác làm mù bị deny hoặc tạo cảnh báo và trail vẫn logging; canary object/secret tạo raw event; `validate-logs` cùng chuỗi pre-state → plan → event → post-state đều PASS.

Kiến trúc single-account không chặn tuyệt đối root. Tài liệu này mô tả thiết kế mục tiêu và mã triển khai đã được review, chưa phải bằng chứng vận hành. Trạng thái chỉ được nâng lên `VERIFIED` sau apply được phê duyệt, kiểm chứng từ UTC cutover và xác nhận bằng văn bản đối với rủi ro root.

### Kết luận điều hành

```text
M11 cung cấp nền ghi log.
M12 làm nền đó khó bị tắt, khó bị né, khó bị sửa và đủ dữ liệu điều tra.
Triển khai theo hai phase: Audit Foundation trước, IAM Hardening sau.
```

## Phạm vi cam kết và giới hạn

| Cam kết kỹ thuật | Điều kiện/bằng chứng bắt buộc | Giới hạn của cam kết |
|---|---|---|
| Object version mới không thể bị xóa/sửa trước retain-until | `GetObjectRetention` cho object sau cutover trả `COMPLIANCE` và thời hạn ≥365 ngày | “Mọi object cũ đã được bảo vệ 365 ngày” hoặc “root không thể thay đổi cấu hình cho object tương lai” |
| Daily/CI identity trong scope không dùng được audit kill switch | Boundary đã attach; simulation và denied test trả `explicitDeny`; post-state không đổi | “Không ai, kể cả root, có thể phá audit” |
| Đọc dữ liệu nhạy cảm trong phạm vi duyệt có vết | Exact S3 Object ARN active; canary `GetObject`/`GetSecretValue` có raw event | “Mọi bucket/object trong account đều được log” |
| Archive trong UTC window kiểm tra không bị sửa/xóa lén | Digest chain hợp lệ; `validate-logs` chạy ở vị trí S3 gốc và không có invalid/missing | “Digest chứng minh sự kiện chưa từng bị hụt trước khi delivery” |
| Selected configuration change đủ nghĩa điều tra | Pre-state + saved-plan hash + `requestParameters` + post-state khớp change ID | “CloudTrail lưu toàn bộ secret, object content hoặc mọi business payload” |
| Blind window được giảm và có bounded detection | Tamper alert path pass; heartbeat thresholds/pass; subscriptions confirmed | “Cảnh báo tức thời tuyệt đối” hoặc “same-account không có residual risk” |

### Ba lớp bằng chứng phải được phân biệt

1. **Cam kết của AWS:** hành vi dịch vụ được AWS mô tả chính thức, ví dụ Object Lock Compliance và signed digest.
2. **Code/design evidence:** Terraform/Lambda/rules có trong implementation snapshot đã review.
3. **Runtime evidence:** chỉ tồn tại sau apply/test, ví dụ retention trên object mới, alert receipt và `validate-logs PASS`.

Một file Terraform tồn tại không chứng minh resource đã được apply; một resource tồn tại không chứng minh alert đến người trực; một alert đến người trực không chứng minh log toàn vẹn. Trạng thái hoàn thành phải dựa trên đúng lớp evidence hiện có.

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

Ảnh giải thích bốn cơ chế: [m12-four-mechanisms-v1.0.png](m12-four-mechanisms-v1.0.png).

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
- Nhóm g7 nhận các API thay đổi S3/EventBridge/Lambda/CloudWatch/SNS, sau đó router chỉ phát CRITICAL khi target thuộc audit plane; target không parse được hoặc danh sách keyword rỗng phải fail-safe thành alert.
- Nhóm g8 bắt thay đổi IAM/OIDC có khả năng mở đường phá audit.
- Các nhóm critical `1/2/3/4/7/8` luôn alert, kể cả actor là Terraform automation; allowlist không được che sự kiện critical.
- EventBridge nhận `AWS API Call via CloudTrail` theo cơ chế best-effort, vì vậy nó là lớp phát hiện nhanh chứ không phải bằng chứng duy nhất; heartbeat và archive/digest là các lớp độc lập bổ sung.

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

Schedule 5 phút không đồng nghĩa mọi lỗi được phát hiện trong đúng 5 phút. Thiết kế chấp nhận log age tối đa 20 phút và digest age tối đa 90 phút để phù hợp delivery latency; vượt ngưỡng mới FAIL. Phải nói đây là **bounded detection theo threshold**, không phải “zero-second detection”.

### 4.6 CloudWatch alarms và SNS fallback

- Alarm `Errors` phát hiện heartbeat chạy nhưng lỗi.
- Alarm `Missing` phát hiện heartbeat không còn phát metric/invocation như dự kiến.
- Hai alarm gửi tới primary SNS và một fallback SNS cùng region.
- Khi heartbeat tự phát hiện invariant fail, Lambda thử publish primary và global theo hai lần độc lập; một topic lỗi không được ngăn lần thử còn lại.
- Fallback SNS dùng KMS key riêng; primary topic phải có cả SNS topic policy và KMS key-policy grant phù hợp cho CloudWatch alarm publisher. Chỉ có topic policy mà thiếu KMS grant có thể khiến alarm delivery thất bại.

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

## 7. Các quyết định và giải thích kỹ thuật

### 7.1 Quan hệ giữa Mandate 11 và Mandate 12

M11 cung cấp nền ghi management events, archive và alert. M12 nâng nền đó thành audit anti-defeat: thêm S3 data-event coverage, retention/immutability mạnh hơn, tamper detection, heartbeat và IAM hardening, sau đó chứng minh bằng test/evidence.

### 7.2 Lý do không tạo CloudTrail M12 mới

Trail M11 đã multi-region và đang là source of truth. Tạo trail thứ hai sẽ trùng management events, tăng chi phí, tạo hai state/alert paths và khó xác định nguồn bằng chứng chính. Thiết kế chọn update in-place, với gate không cho plan replace/delete trail hoặc bucket hiện hữu.

### 7.3 Vì sao Object Lock chưa đủ

Object Lock chỉ bảo vệ log sau khi log đã tới S3. Attacker vẫn có thể tắt CloudTrail trước khi hành động, hoạt động ở nơi chưa bật data events hoặc để lại event quá ít thông tin. Mandate 12 bổ sung control cho ba đường né audit này.

### 7.4 Trách nhiệm và đường cảnh báo của heartbeat

Mỗi 5 phút heartbeat kiểm tra trail, delivery, digest, selector, Object Lock/lifecycle, bucket policy, EventBridge targets, routers, alarms, SNS subscriptions, EKS audit và boundary thuộc scope. Khi phát hiện invariant sai, Lambda thử gửi độc lập tới SNS Primary và Global. Nếu heartbeat lỗi hoặc ngừng chạy, CloudWatch `Errors/Missing` alarms gửi tới SNS Primary và Fallback. Người nhận cuối là Security Owner/người trực có subscription `Confirmed`.

### 7.5 Cách chứng minh coverage gap đã được đóng

Thiết kế giữ management read/write events và thêm S3 object data events cho exact bucket/prefix được duyệt. Sau apply, canary `GetObject` và `GetSecretValue` phải tạo raw event có actor/session, resource, UTC và request ID.

### 7.6 Bảo vệ nội dung secret trong audit log

CloudTrail ghi metadata của `GetSecretValue` để xác định ai đọc secret nào, nhưng không ghi `SecretString` hoặc `SecretBinary`. Auditability được đạt mà không sao chép bí mật vào log.

### 7.7 Cách chứng minh log toàn vẹn

CloudTrail log file integrity validation dùng SHA-256 và chữ ký RSA để tạo signed digest chain. `aws cloudtrail validate-logs` được chạy trên UTC window sau cutover tại vị trí S3 gốc; PASS khi digest và các log file được digest tham chiếu không `INVALID`/missing. Lệnh này không xác minh file đã tải về vị trí khác và không thay heartbeat kiểm tra delivery gap.

### 7.8 Phân biệt làm mỏng và sửa log

Sửa log là thay đổi bằng chứng đã có và được digest phát hiện. Làm mỏng là event vẫn tồn tại nhưng không đủ để dựng lại thay đổi. Control xử lý bằng cách nối pre-state, saved plan, `requestParameters` trong raw event và post-state; reviewer phải xác định được chính xác trường cấu hình đã đổi.

### 7.9 Vai trò của IAM Hardening

Foundation tạo và giám sát đường audit; IAM Hardening giới hạn người có thể sửa đường đó. Daily Operator và CI chỉ giữ quyền cần thiết, mang permissions boundary chặn audit kill switches và không được tự mở rộng/gỡ boundary. Audit-admin/break-glass là đường riêng, có named owner, MFA và quy trình phê duyệt.

### 7.10 Giới hạn của IAM boundary đối với root

AWS root nằm ngoài permissions boundary trong single-account design. Đây là residual risk phải được kiểm soát bằng root MFA, không có root access key, incident-only process, named custodian và signed acceptance.

### 7.11 Ảnh hưởng đối với production

Giải pháp không thay đổi application traffic, workload, VPC, datastore hoặc EKS workload. Thay đổi nằm ở audit/control plane. Tuy nhiên vẫn có rủi ro vận hành với CI/IAM nên Foundation và IAM được tách change, dùng saved plan, change window, simulation và rollback/fix-forward gate.

### 7.12 Điều kiện công nhận hoàn thành

Foundation pass nhưng IAM chưa xong chỉ đạt `AUDIT READY/PARTIAL`. Trạng thái `VERIFIED` yêu cầu coverage, retention, digest, heartbeat, alert paths, forensic evidence, IAM denied tests và root residual acceptance đều hoàn thành.

### 7.13 IAM escalation path còn tồn tại

CI vẫn cần `CreateRole`, `UpdateAssumeRolePolicy` và `AttachRolePolicy` để Terraform quản service roles. Nếu chưa bắt buộc mọi role mới mang đúng boundary, về lý thuyết một PR độc hại có thể tạo role trust account ngoài rồi assume từ bên ngoài. IAM chưa được công nhận hoàn tất cho đến khi `CreateRole/CreateUser` bắt buộc exact boundary và boundary được truyền xuống các module tạo principal, hoặc rủi ro được xử lý bằng change riêng có gate rõ ràng.

### 7.14 Yêu cầu plan riêng cho GitHub OIDC/bootstrap

`infra/bootstrap/github-oidc` dùng Terraform root và state key riêng với production. Production plan không hiển thị IAM diff của root này. Trước khi phê duyệt IAM hardening cần job/read-only plan riêng cho bootstrap state, hoặc tối thiểu một manual plan artifact được tạo từ đúng commit và reviewer xác nhận; apply vẫn do identity MFA thực hiện theo saved plan đã duyệt.

### 7.15 Phạm vi của cam kết chống blind window

Thiết kế single-account không thể đưa ra cam kết tuyệt đối. Cam kết kỹ thuật có thể kiểm chứng là: bounded daily/CI identities bị deny kill switch; tamper API có event-driven alert; heartbeat phát hiện live-state/delivery drift theo ngưỡng; archive/digest cung cấp evidence. Root vẫn ngoài boundary và EventBridge là best-effort, vì vậy residual risk phải được ghi nhận và phạm vi công nhận chỉ giới hạn trong phần đã kiểm thử.

## 8. Bảng tổng hợp control

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

## 9. Điều kiện để được tuyên bố hoàn thành

- **Audit Foundation đạt:** trail/delivery/digest/selectors/retention/heartbeat/alert paths và canary coverage đều PASS.
- **IAM Hardening đạt:** daily/CI identities thuộc scope có least privilege/boundary, simulation và denied tests PASS.
- **Evidence đạt:** `validate-logs` PASS và forensic diff pre-state → plan → event → post-state được reviewer xác nhận.
- **Retention đạt:** object mới sau cutover có `COMPLIANCE >=365 ngày`, lifecycle 400 ngày và cost/owner approval.
- **Residual risk đạt:** root/single-account limitation được ghi rõ và ký chấp nhận.

Nếu chỉ Foundation pass nhưng IAM chưa hoàn thành, trạng thái là `AUDIT READY/PARTIAL`, chưa được ghi `VERIFIED` cho toàn bộ Mandate 12.

## 10. Nguồn đối chiếu kỹ thuật

### AWS chính thức

- [S3 Object Lock và Compliance mode](https://docs.aws.amazon.com/AmazonS3/latest/userguide/object-lock.html) — protected object version không thể bị overwrite/delete, kể cả root, trong retention.
- [Cấu hình default Object Lock retention](https://docs.aws.amazon.com/AmazonS3/latest/userguide/object-lock-configure.html) — default áp cho object version được đặt vào bucket; individual retention có thể override default.
- [CloudTrail log file integrity validation](https://docs.aws.amazon.com/awscloudtrail/latest/userguide/cloudtrail-log-file-validation-intro.html) — SHA-256, RSA signature và digest files.
- [`validate-logs` bằng AWS CLI](https://docs.aws.amazon.com/awscloudtrail/latest/userguide/cloudtrail-log-file-validation-cli.html) — chỉ kiểm tra log file được digest tham chiếu tại vị trí delivery gốc.
- [CloudTrail advanced data-event selectors](https://docs.aws.amazon.com/awscloudtrail/latest/userguide/filtering-data-events.html) — S3 object data events, exact resource filtering và việc advanced selector thay basic selector.
- [`GetSecretValue` API](https://docs.aws.amazon.com/secretsmanager/latest/apireference/API_GetSecretValue.html) — tạo CloudTrail entry nhưng không đưa `SecretString`/`SecretBinary` vào log.
- [CloudTrail event types](https://docs.aws.amazon.com/awscloudtrail/latest/userguide/cloudtrail-events.html) — management events được log mặc định; S3 object activity là data events phải cấu hình riêng.
- [IAM permissions boundaries](https://docs.aws.amazon.com/IAM/latest/UserGuide/access_policies_boundaries.html) — boundary đặt maximum permissions, không tự cấp quyền.
- [IAM policies và root user](https://docs.aws.amazon.com/IAM/latest/UserGuide/access_policies.html#policies_boundaries) — không thể gắn permissions boundary cho root.
- [AWS API calls qua CloudTrail vào EventBridge](https://docs.aws.amazon.com/eventbridge/latest/userguide/eb-service-event-cloudtrail.html) — cơ chế event và giới hạn best-effort.

### Implementation snapshot đã review

- Branch: `feat/mandate-12-audit-anti-defeat`, commit `8a554a3b965c3d4bc090273dc34979273101fd5b`, kiểm tra ngày 23/07/2026.
- [ADR 0011](https://github.com/tuu-ngo/Phase3-TF3-Infra-Sentinel/blob/8a554a3b965c3d4bc090273dc34979273101fd5b/docs/adr/0011-mandate-12-audit-anti-defeat.md).
- [Heartbeat production](https://github.com/tuu-ngo/Phase3-TF3-Infra-Sentinel/blob/8a554a3b965c3d4bc090273dc34979273101fd5b/infra/live/production/audit-heartbeat.tf).
- [CI audit boundary](https://github.com/tuu-ngo/Phase3-TF3-Infra-Sentinel/blob/8a554a3b965c3d4bc090273dc34979273101fd5b/infra/bootstrap/github-oidc/ci-audit-boundary.tf).
- [Production plan workflow](https://github.com/tuu-ngo/Phase3-TF3-Infra-Sentinel/blob/8a554a3b965c3d4bc090273dc34979273101fd5b/.github/workflows/terraform-plan.yml) — hiện chưa plan root `infra/bootstrap/github-oidc`; đây là gate còn phải đóng trước approve IAM.

---

**Phiên bản:** v1.3  
**Cập nhật:** 23/07/2026  
**Trạng thái:** DESIGN REVIEWED / NOT RUNTIME VERIFIED
