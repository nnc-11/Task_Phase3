# Kịch bản tấn công và bằng chứng Mandate 12

## 1. Mục đích

Tài liệu này biến yêu cầu “mentor tự thử đánh bại” thành các test case có thể lặp lại, an toàn và có tiêu chí pass/fail rõ ràng cho TF3.

Mỗi kịch bản ánh xạ theo chuỗi:

```text
Threat → Tiền điều kiện → Hành động → Control → Event/alert kỳ vọng
       → Evidence → Pass/Fail → Cleanup/ứng phó
```

Tài liệu không xác nhận control đã tồn tại trên AWS. Chỉ đánh dấu `VERIFIED` sau khi test live và lưu đủ evidence.

## 2. Quy tắc an toàn và phê duyệt

- Chỉ chạy sau khi change owner, security owner và mentor phê duyệt test window, principal và resource scope.
- Dùng canary bucket/object/secret không chứa dữ liệu thật.
- Không thử xóa hoặc sửa object đang được khóa bằng Object Lock Compliance.
- Không tắt organization trail thật nếu thiết kế đã bảo đảm thao tác phải bị deny; dừng ngay nếu dry-run/authorization check cho thấy có thể thành công.
- Các thử nghiệm có khả năng thành công như đổi EventBridge/SNS/KMS/S3 policy chỉ thực hiện trong sandbox, không chạy trên production audit plane.
- Không bật CLI debug; không chụp `SecretString`, access key, session token hoặc nội dung object.
- Dùng UTC cho toàn bộ test window. Ghi request ID, principal ARN, account, region và expected event trước khi chạy.
- Không cleanup bằng cách xóa log/evidence. Canary data có thể cleanup sau khi retention cho phép; evidence phải giữ theo policy.

## 3. Trạng thái evidence

| Trạng thái | Ý nghĩa |
|---|---|
| `DESIGNED` | Test case và control đã được thiết kế |
| `DEPLOYED` | Control đã apply nhưng chưa được mentor chứng minh |
| `VERIFIED` | Mentor đã thực hiện, team thu đủ evidence và pass criteria |
| `FAILED` | Thiếu event, alert, integrity hoặc control bị vượt qua |
| `BLOCKED` | Không thể test vì thiếu owner/quyền/test fixture; không được coi là pass |

## 4. Chuẩn evidence chung

Mỗi test tạo một thư mục evidence logic theo mẫu:

```text
M12-ATK-<ID>/
├── 00-test-metadata.md
├── 01-request-redacted.txt
├── 02-api-result-redacted.txt
├── 03-cloudtrail-event-redacted.json
├── 04-alert-redacted.txt
├── 05-trail-health-redacted.json
├── 06-integrity-result.txt
└── 07-verdict.md
```

`00-test-metadata.md` tối thiểu ghi:

- test ID, UTC start/end và AWS region;
- tester principal ARN/session issuer và account;
- target resource ARN nhưng không ghi secret value;
- expected event source/name/type;
- approver, observer và người đưa verdict;
- hash SHA-256 của từng evidence file sau redaction.

## 5. Ma trận kịch bản

| ID | Kịch bản | Nhóm mandate | Mức | Nơi được chạy |
|---|---|---|---|---|
| ATK-01 | Dừng organization trail | Làm mù | Critical | Production, chỉ khi chắc chắn bị deny |
| ATK-02 | Xóa/cập nhật trail hoặc selector | Làm mù + làm hụt | Critical | Production deny test; mutation chỉ sandbox |
| ATK-03 | Vô hiệu hóa alert path | Làm mù cảnh báo | Critical | Sandbox; production dùng authorization simulation/deny test |
| ATK-04 | Phá archive bucket/Object Lock/lifecycle | Làm mỏng/sửa | Critical | Sandbox hoặc production deny test |
| ATK-05 | Disable/schedule deletion audit KMS key | Làm mù delivery | Critical | Sandbox hoặc production deny test |
| ATK-06 | Đọc S3 object nhạy cảm | Làm hụt | High | Production canary prefix |
| ATK-07 | Đọc secret | Làm hụt | Critical | Production canary secret |
| ATK-08 | Đọc nhiều object — exfiltration burst | Làm hụt/phát hiện | Critical | Sandbox hoặc giới hạn canary nhỏ |
| ATK-09 | Low-and-slow data access | Làm hụt/phát hiện | High | Canary theo lịch được duyệt |
| ATK-10 | Assumed-role/session attribution | Làm mỏng danh tính | High | Production canary |
| ATK-11 | Sửa/xóa log hoặc digest | Làm mỏng/sửa | Critical | Chỉ sandbox non-Compliance fixture; production deny test |
| ATK-12 | Rời organization/vô hiệu trusted access | Làm mù toàn bộ | Critical | Không mutate production; sandbox/tabletop + deny evidence |
| ATK-13 | Tạo noise/cost exhaustion | Che giấu + cost | High | Mô phỏng/giới hạn sandbox |
| ATK-14 | Tạo resource nhạy cảm mới ngoài selector | Coverage drift | High | Sandbox hoặc canary resource được duyệt |

## 6. ATK-01 — StopLogging organization trail

### Threat

TF3 admin cố dừng đường ghi log trước khi thực hiện hành vi xấu.

### Tiền điều kiện

- Organization trail đang `IsLogging=true`.
- Tester là principal trong member account TF3, không phải organization management/delegated admin.
- EventBridge anti-audit rule và security recipient đang healthy.

### Hành động

```sh
aws cloudtrail stop-logging \
  --name <organization-trail-arn> \
  --region <trail-home-region>
```

### Kỳ vọng

- API trả `AccessDenied` hoặc lỗi tương đương do member account không được quản trị organization trail.
- Có CloudTrail event với `eventSource=cloudtrail.amazonaws.com`, `eventName=StopLogging`, actor, UTC time và error.
- Security owner nhận Critical alert.
- Sau test, `get-trail-status` vẫn trả `IsLogging=true` và delivery tiếp tục.

### Pass/Fail

- **PASS:** đủ cả deny, event, alert và trail health.
- **FAIL:** lệnh thành công; không tìm thấy attempt; alert không tới; hoặc xuất hiện delivery gap.

### Ứng phó nếu lệnh thành công

Khai báo Critical incident ngay, dừng toàn bộ test, ORG_ADMIN khôi phục logging, xác định blind window và không thực hiện kịch bản tiếp theo cho đến khi digest/delivery continuity được đánh giá.

## 7. ATK-02 — DeleteTrail, UpdateTrail và PutEventSelectors

### Threat

Kẻ tấn công không dừng trail mà xóa trail, chuyển bucket đích, tắt validation hoặc bỏ S3 sensitive prefix khỏi selector.

### Hành động an toàn

- Production: thử `delete-trail` trên organization trail và kỳ vọng deny.
- `update-trail`/`put-event-selectors`: ưu tiên IAM policy simulation hoặc sandbox. Không gửi mutation production nếu chưa chứng minh chắc chắn bị deny.

```sh
aws cloudtrail delete-trail \
  --name <organization-trail-arn> \
  --region <trail-home-region>
```

### Event kỳ vọng

- `DeleteTrail`, `UpdateTrail` hoặc `PutEventSelectors`.
- Actor/session issuer, target trail, error code và request ID.
- Critical alert cho mọi attempt, kể cả bị deny.

### Pass/Fail

- **PASS:** member principal không thay đổi được trail/selector; attempt có log và alert; selectors sau test không đổi.
- **FAIL:** bất kỳ thay đổi trái phép nào thành công, selector mất resource, validation bị tắt hoặc thiếu alert.

## 8. ATK-03 — Vô hiệu hóa EventBridge/SNS

### Threat

Trail vẫn ghi nhưng attacker tắt rule, xóa target/subscription hoặc đổi topic policy để không ai được báo.

### Test

- Production: dùng principal TF3 gọi thao tác phải bị deny hoặc dùng IAM simulation.
- Sandbox: disable rule hoặc remove target trong thời gian ngắn đã phê duyệt để chứng minh health-check/heartbeat độc lập phát hiện.

### Event kỳ vọng

- EventBridge control-plane event tương ứng với disable/delete/update rule/target.
- SNS control-plane event tương ứng với subscription/topic/policy mutation.
- Alert từ đường độc lập hoặc missed-heartbeat alarm.

### Pass/Fail

- **PASS:** production mutation bị deny và có event; sandbox mutation tạo missed-heartbeat/detection alarm trong SLA đã định.
- **FAIL:** alert path có thể bị tắt âm thầm hoặc health check phụ thuộc chính path đang kiểm tra.

## 9. ATK-04 — Phá audit bucket, Object Lock hoặc lifecycle

### Threat

Attacker đổi bucket policy để CloudTrail không ghi được, rút retention, thêm lifecycle xóa sớm hoặc cố xóa log.

### Test an toàn

- Production chỉ thử quyền bằng API read/authorization simulation hoặc delete/policy mutation phải bị deny.
- Không thay Object Lock Compliance thật.
- Sandbox kiểm tra policy mutation và delivery health alarm.

### Kỳ vọng

- TF3 principal không có quyền quản trị archive bucket.
- Delete/overwrite log version bị chặn bởi bucket policy/Object Lock.
- S3 control-plane attempt được ghi và tạo Critical alert.
- Delivery health phát hiện bucket/KMS delivery error trong SLA.

### Pass/Fail

- **PASS:** không thể xóa/overwrite/rút retention; attempt và health status có evidence.
- **FAIL:** log version bị mất, retention bị rút, CloudTrail delivery fail mà không báo hoặc TF3 admin sửa được bucket policy.

## 10. ATK-05 — Phá audit KMS key

### Threat

Attacker disable key, schedule deletion hoặc đổi key policy khiến CloudTrail không thể mã hóa/giao log.

### Test

Production chỉ thực hiện denied API attempt hoặc IAM simulation. Sandbox có thể thử disable rồi khôi phục theo approved recovery plan.

### Event/alert kỳ vọng

- KMS event cho `DisableKey`, `ScheduleKeyDeletion`, `PutKeyPolicy`, grant mutation.
- Critical alert chứa key ARN, actor và region.
- TF3 principal bị deny; audit key vẫn `Enabled`.

### Pass/Fail

- **PASS:** TF3 không thể phá key; attempt có event/alert; delivery không gián đoạn.
- **FAIL:** key bị disable/scheduled deletion, policy bị thay hoặc delivery lỗi không được phát hiện.

## 11. ATK-06 — Đọc S3 object nhạy cảm

### Threat

Attacker kéo object nhưng trail chỉ thu management events nên exfiltration vô hình.

### Fixture

- Canary bucket/prefix nằm trong advanced event selector.
- Object chỉ chứa chuỗi marker không nhạy cảm và test ID.

### Hành động

```sh
aws s3api get-object \
  --bucket <canary-bucket> \
  --key <sensitive-prefix>/<test-id>.txt \
  <approved-local-output-path>
```

### Kỳ vọng

- S3 **data event** `GetObject`.
- Đúng bucket/key, principal/session, source IP, time và request ID.
- Event được giao vào archive và được digest sau đó bao phủ.

### Pass/Fail

- **PASS:** auditor tìm được đúng event trong delivery SLA.
- **FAIL:** không có event, sai selector/resource, không xác định được actor hoặc chỉ có bucket management event.

## 12. ATK-07 — Đọc secret

### Threat

Attacker lấy credential nhưng team không truy ra ai đã đọc secret nào.

### Fixture

- Secret canary có giá trị vô dụng, không được app tham chiếu.
- Tester được cấp quyền read chỉ cho secret canary.

### Hành động

Gọi `GetSecretValue` bằng wrapper/test client không in payload. Nếu dùng CLI, tuyệt đối không bật debug hoặc lưu raw response.

### Kỳ vọng

- CloudTrail management read event `GetSecretValue` từ `secretsmanager.amazonaws.com`.
- Event chỉ ra secret identifier, principal, time và outcome.
- Log/evidence không chứa `SecretString`/`SecretBinary`.

### Pass/Fail

- **PASS:** tìm được đúng event và evidence không lộ secret value.
- **FAIL:** thiếu event/attribution hoặc evidence làm rò rỉ secret.

Lặp lại có kiểm soát với `BatchGetSecretValue` nếu API này nằm trong threat model và quyền production thực tế.

## 13. ATK-08 — Exfiltration burst

### Threat

Attacker đọc hàng loạt object trong thời gian ngắn; từng event được ghi nhưng không có phát hiện hành vi bất thường.

### Test

- Chỉ dùng tập canary nhỏ, giới hạn request và chi phí đã phê duyệt.
- Không quét bucket production.
- Ghi trước số request và thời gian dự kiến.

### Kỳ vọng

- Số `GetObject` data events khớp request count trong sai số/delivery semantics đã định.
- Detection theo rate/count hoặc truy vấn hunting nhận ra burst.
- Không vượt cost guardrail.

### Pass/Fail

- **PASS:** coverage đầy đủ và detection/hunting tạo signal có thể hành động.
- **FAIL:** sampling/gap không giải thích được, detection không có baseline hoặc test gây cost ngoài forecast.

## 14. ATK-09 — Low-and-slow read

### Threat

Attacker đọc ít object trong nhiều ngày để né threshold burst.

### Test

Lập lịch một số `GetObject` canary ở các thời điểm đã phê duyệt, từ cùng một test principal. Không tăng tải production đáng kể.

### Kỳ vọng

- Mọi read đều có data event.
- Truy vấn theo principal/resource/time window dài dựng lại được chuỗi hành vi.
- Nếu không alert theo threshold, runbook phải định nghĩa scheduled hunting/review.

### Pass/Fail

- **PASS:** không mất event và analyst tái dựng được timeline dài ngày.
- **FAIL:** retention/selector/query không đủ để nối chuỗi hoặc team tuyên bố “không có tấn công” chỉ vì không có alert.

## 15. ATK-10 — Assumed role và session attribution

### Threat

Attacker dùng STS assumed role để che danh tính người khởi tạo.

### Test

Tester assume một role canary bằng session name chứa test ID rồi đọc S3 object hoặc secret canary.

### Kỳ vọng

- Event thể hiện assumed-role ARN, session issuer, session name và source.
- Có thể nối `AssumeRole` event với data/read event theo time, principal/session context.
- Quy trình evidence không chỉ ghi role chung mà bỏ mất session attribution.

### Pass/Fail

- **PASS:** dựng được chuỗi caller → assumed role session → hành vi nhạy cảm.
- **FAIL:** chỉ biết role dùng chung mà không truy được session/caller, hoặc session naming không được kiểm soát.

## 16. ATK-11 — Sửa hoặc xóa log/digest

### Threat

Attacker sửa, thay hoặc xóa log sau khi giao để che bằng chứng.

### Test an toàn

- Production: chỉ chứng minh TF3 principal không có delete/overwrite/retention bypass; không tamper object thật.
- Sandbox riêng không dùng Compliance source-of-truth: sao chép fixture log/digest, sửa hoặc xóa một file rồi chạy validation để minh họa `INVALID`/missing.

### Kỳ vọng

- Production WORM từ chối mutation.
- `validate-logs` trên chain thật trả valid.
- Sandbox tamper fixture tạo kết quả invalid/missing có thể phân biệt rõ.

### Pass/Fail

- **PASS:** WORM deny + validation chain thật pass + tamper fixture bị phát hiện.
- **FAIL:** mutation production thành công, validation bỏ qua gap hoặc team chỉ chứng minh file tồn tại mà không xác minh chữ ký/hash.

## 17. ATK-12 — LeaveOrganization hoặc vô hiệu trusted access

### Threat

Attacker loại member account khỏi organization hoặc vô hiệu tích hợp CloudTrail/Organizations để organization trail biến mất.

### Test

- Không mutate production organization.
- Dùng policy review, IAM/SCP simulation và tabletop exercise.
- Nếu có sandbox organization, thực hiện end-to-end tại đó và quan sát trail/detection behavior.

### Kỳ vọng

- TF3 principals không có quyền thực hiện organization-level mutation.
- Organization/trusted-access/delegated-admin changes đều được log và cảnh báo ở management/security account.
- Có offboarding detection và incident procedure cho trường hợp account bị remove.

### Pass/Fail

- **PASS:** quyền bị chặn, detection nằm ngoài TF3 và tabletop xác định rõ owner/response.
- **FAIL:** TF3 có thể rời organization, hoặc organization mutation không có external alert/evidence.

## 18. ATK-13 — Noise và cost exhaustion

### Threat

Attacker tạo số lượng data event lớn để tăng chi phí, làm analyst quá tải hoặc che event thật.

### Test

- Dùng mô phỏng cost từ event count trước.
- Nếu cần test live, giới hạn sandbox bằng request cap, timebox và budget alarm.
- Không load-test S3 production chỉ để chứng minh audit.

### Kỳ vọng

- Cost anomaly/budget signal hoạt động.
- Detection có aggregation/dedup/rate context nhưng vẫn giữ raw evidence.
- Playbook thu hẹp noisy non-sensitive selector mà không tắt mandatory management logging hoặc sensitive coverage.

### Pass/Fail

- **PASS:** phát hiện cost/noise, có response không phá coverage bắt buộc.
- **FAIL:** giải pháp duy nhất là tắt logging hoặc event flood làm mất khả năng điều tra.

## 19. ATK-14 — Resource mới nằm ngoài selector

### Threat

Một bucket/prefix nhạy cảm mới được tạo nhưng không được thêm vào selector; attacker đọc dữ liệu ở đó mà không có data event.

### Test

- Tạo canary bucket/prefix theo quy trình được duyệt.
- Gắn classification/tag như resource nhạy cảm.
- Kiểm tra automation/governance có phát hiện selector drift trước khi cho dữ liệu vào.

### Kỳ vọng

- Resource onboarding gate yêu cầu logging coverage.
- Config/policy control báo noncompliance nếu selector chưa bao phủ.
- Sau remediation, `GetObject` canary tạo data event.

### Pass/Fail

- **PASS:** resource không thể âm thầm đi vào production ngoài coverage hoặc drift được phát hiện trong SLA.
- **FAIL:** coverage phụ thuộc inventory thủ công không có reconciliation và resource mới tạo blind spot.

## 20. Bảng verdict dùng khi demo

| Test ID | UTC window | Principal | Expected event | Deny/control | Event found | Alert | Integrity | Verdict |
|---|---|---|---|---|---|---|---|---|
| ATK-01 | | | `StopLogging` | | | | | `DESIGNED` |
| ATK-02 | | | `DeleteTrail`/config | | | | | `DESIGNED` |
| ATK-06 | | | S3 `GetObject` data event | N/A | | N/A | | `DESIGNED` |
| ATK-07 | | | `GetSecretValue` | N/A | | theo policy | | `DESIGNED` |
| ATK-11 | | | validation result | WORM | | | | `DESIGNED` |

## 21. Điều kiện hoàn tất Mandate 12

Tối thiểu mentor phải trực tiếp chứng minh:

1. **Làm mù:** ATK-01 và ATK-02 bị chặn hoặc tạo cảnh báo ngay; organization trail vẫn ghi.
2. **Làm hụt:** ATK-06 và ATK-07 truy được đúng event, actor, time và resource.
3. **Làm mỏng/sửa:** ATK-11 chứng minh WORM deny và `validate-logs` pass cho demo window.
4. **Retention:** evidence Object Lock Compliance 365 ngày và policy không cho TF3 rút ngắn.
5. **Độc lập:** archive/detection owner nằm ngoài TF3 operator blast radius.

ATK-03, ATK-05, ATK-08, ATK-09, ATK-10, ATK-12, ATK-13 và ATK-14 củng cố defense-in-depth và residual-risk analysis. Nếu chưa chạy, phải ghi `DESIGNED` hoặc `BLOCKED`, không ghi `VERIFIED`.

