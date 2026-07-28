# Hướng dẫn nâng cấp M11 audit foundation cho Mandate 12

> Chỉ thực hiện khi có approval tham gia production. Tài liệu này không cho phép chạy apply trước change window.

## 1. Phạm vi

Nâng cấp in-place trail/bucket/router M11 đang thuộc `infra/live/production`. Không tạo trail/bucket/router trùng lặp, không đổi ARN/name và không import/chuyển Terraform state. Tạo đúng một SNS heartbeat-fallback cùng `ap-southeast-1` cho CloudWatch alarms; heartbeat Lambda tiếp tục dùng hai M11 topics làm hai đường publish độc lập.

## 2. Dependency

### Baseline đã đọc live ngày 21/07/2026

| Item | Giá trị live |
|---|---|
| Account/caller | `197826770971` / `arn:aws:iam::197826770971:user/cdo-2-admin-team` |
| Trail | `techx-corp-tf3-audit-detection-ap-southeast-1-trail` |
| Trail ARN | `arn:aws:cloudtrail:ap-southeast-1:197826770971:trail/techx-corp-tf3-audit-detection-ap-southeast-1-trail` |
| Bucket | `techx-corp-tf3-audit-trail-ap-southeast-1-197826770971` |
| Hiện trạng | logging/validation bật; management All; chưa có S3 data events; Governance 14/lifecycle 30 |
| EKS | `techx-corp-tf3`: `api/audit/authenticator` enabled, retention 90 ngày |
| SNS blocker | Primary 3 pending; global 1 pending |

Không copy các timestamp live trên làm bằng chứng cho ngày deploy. Người deploy chạy lại toàn bộ discovery và lưu output mới vào evidence pack.

| Input | Cách lấy | GO |
|---|---|---|
| Caller | `aws sts get-caller-identity` | Account `197826770971`, không root |
| M11 live | CloudTrail/EventBridge/Lambda/SNS/S3 read-only commands | Khớp repo hoặc drift đã xử lý |
| Owner/state | IaC/CD01 xác nhận `infra/live/production` sở hữu M11 | Có reviewer/change window |
| S3 scope | `m12-coverage-v2.1.md` + metadata-only inventory | Exact ARN kết thúc `/`, owner ký |
| Retention | Security owner duyệt cutover Compliance 365/lifecycle 400 | Chấp nhận không hồi tố object cũ; 365 ngày bao phủ 12 tháng điều tra, lifecycle 400 ngày thêm 35 ngày đệm vận hành |
| Alert | Hai M11 SNS topics và heartbeat-fallback | Mỗi topic có ít nhất một email subscription `Confirmed` và người trực xác nhận nhận test; các subscription khác được phép còn pending |
| Change ID | Ticket/PR chứa Git SHA, identity, UTC window, expected action; plan hash bổ sung sau plan | Có người trực đối chiếu, không mute/suppress critical alert |
| Cost/age | Data-event estimate + inventory size/age của current và noncurrent versions | Trong budget; không có version ≥400 ngày bị expire ngay, hoặc owner đã chọn lifecycle dài hơn/export được duyệt; tiering chưa chọn |
| Baseline | Saved pre-change status/selectors/lock/lifecycle/rules | Đủ hash/timestamp |

## 3. Discovery chỉ đọc

```powershell
$region = "ap-southeast-1"
$globalRegion = "us-east-1"
aws sts get-caller-identity
aws cloudtrail describe-trails --include-shadow-trails --region $region
```

Lấy exact trail/bucket từ output rồi:

```powershell
$trail = "<m11-trail-name-or-arn>"
$bucket = "<m11-trail-bucket>"
aws cloudtrail get-trail-status --name $trail --region $region
aws cloudtrail get-event-selectors --trail-name $trail --region $region
aws s3api get-bucket-versioning --bucket $bucket
aws s3api get-object-lock-configuration --bucket $bucket
aws s3api get-bucket-lifecycle-configuration --bucket $bucket
aws events list-rules --name-prefix "techx-corp-tf3-audit-detection" --region $region
aws events list-rules --name-prefix "techx-corp-tf3-audit-detection" --region $globalRegion
aws lambda list-functions --region $region --query "Functions[?contains(FunctionName, 'audit-detection')]"
aws sns list-topics --region $region --query "Topics[?contains(TopicArn, 'audit-detection')]"
aws eks describe-cluster --name techx-corp-tf3 --region $region --query "cluster.logging.clusterLogging"
```

Với baseline hiện tại có thể gán:

```powershell
$trail = "techx-corp-tf3-audit-detection-ap-southeast-1-trail"
$bucket = "techx-corp-tf3-audit-trail-ap-southeast-1-197826770971"
```

Lấy subscription status, không tạo hoặc confirm thay người nhận:

```powershell
aws sns list-subscriptions-by-topic --topic-arn "<primary-topic-arn>" --region $region
aws sns list-subscriptions-by-topic --topic-arn "<global-topic-arn>" --region $globalRegion
aws sns get-topic-attributes --topic-arn "<primary-topic-arn>" --region $region
```

Trước khi sửa source, tạo change ID và ghi tối thiểu:

```text
Change-ID: <ticket-or-approved-PR>
Git-SHA: <commit-before-plan>
Caller-ARN: <deployment-role-or-user>
UTC-window: <start/end>
Expected critical actions: PutRule, PutTargets, PutMetricAlarm,
UpdateFunctionCode, UpdateFunctionConfiguration, SetTopicAttributes, ...
On-call reviewer: <name/contact>
Saved-plan SHA256: <điền sau bước plan>
```

Không tiếp tục nếu chưa có người trực nhận và đối chiếu alert. Không thêm actor vào suppression, không disable alarm và không mute SNS trong change window.

Không tiếp tục nếu trail/bucket không tồn tại live hoặc thuộc state/owner khác.

## 4. Tạo branch và đặt staging files

Trong approved branch của product repo:

| Nguồn trong Task | Đích trong product repo |
|---|---|
| `foundation/module-variables-additions.tf.example` | `infra/modules/audit-detection/m12-variables.tf` |
| `foundation/production-variables-additions.tf.example` | `infra/live/production/m12-variables.tf` |
| `foundation/production-heartbeat.tf.example` | `infra/live/production/audit-heartbeat.tf` |
| `foundation/lambda/heartbeat.py` | `infra/modules/audit-detection/lambda/heartbeat.py` |
| `foundation/production-auto-tfvars.additions.example` | Merge các giá trị đã duyệt vào `production.auto.tfvars` |

Sau đó thực hiện chính xác [module-main-edits.md](foundation/module-main-edits.md) và [lambda-router-edits.md](foundation/lambda-router-edits.md).

Các sửa đổi trên phải đi cùng nhau: `g7` regional dùng `aws.monitoring`, `g8` global, router map, critical groups `1/2/3/4/7/8`, heartbeat, fallback SNS và topic policy cho CloudWatch publish trên primary/fallback. M11 primary hiện không có CloudWatch service-principal policy; bỏ phần policy thì alarm có thể không giao notification. Nếu thiếu một phần thì NO-GO.

Lưu ý: advanced event selectors sẽ thay thế basic selectors hiện có. Vì vậy block mới bắt buộc giữ selector `Management` rồi mới thêm S3 `Data`; không được chỉ thêm data selector.

Trong `infra/live/production/versions.tf`, thêm provider:

```hcl
archive = {
  source  = "hashicorp/archive"
  version = "~> 2.4"
}
```

Thêm dòng `/infra/live/production/m12-audit-heartbeat.zip` vào `.gitignore` ở root product repo. Không commit state, plan, credential hoặc tfvars chứa dữ liệu nhạy cảm.

## 5. Build artifact và static checks

M11 module hiện dùng `data.archive_file.audit_alert_router` với `source_dir = "${path.module}/lambda"`; Terraform tự dựng lại `audit-alert-router.zip` từ thư mục này. Không chạy `Compress-Archive` thủ công chỉ với `index.py`, vì artifact đó không phản ánh cơ chế build của repo. Heartbeat có `data.archive_file.m12_audit_heartbeat` riêng tại production root.

Kiểm tra source trước plan mà không tạo `__pycache__` trong repo:

```powershell
$moduleDir = "<product-repo>\infra\modules\audit-detection"
python -c "from pathlib import Path; files=[Path(r'$moduleDir\lambda\index.py'),Path(r'$moduleDir\lambda\heartbeat.py')]; [compile(p.read_text(encoding='utf-8'),str(p),'exec') for p in files]; print('Python syntax PASS')"
```

Sau `terraform plan`, xác nhận hai data source archive đã dựng artifact và plan dùng hash mới. `audit-alert-router.zip` theo convention hiện hữu của M11; `m12-audit-heartbeat.zip` là generated file đã ignore, không commit.

```powershell
$prodRoot = "<product-repo>\infra\live\production"
terraform -chdir=$prodRoot fmt -recursive
terraform -chdir=$prodRoot init
terraform -chdir=$prodRoot validate
terraform -chdir=$prodRoot plan -out=tfplan
terraform -chdir=$prodRoot show -no-color tfplan | Tee-Object -FilePath "$prodRoot\tfplan.txt"
Get-FileHash -Algorithm SHA256 "$prodRoot\tfplan", "$prodRoot\tfplan.txt"
```

Ghi SHA-256 của saved plan vào change ID trước review. Plan/apply có thể phát nhiều g7 CRITICAL alert khi resource thực sự thay đổi; đây là expected evidence, không phải lý do hạ severity. Người trực phải đối chiếu principal, UTC, event name, Git SHA và plan hash rồi ghi `EXPECTED/<change-id>`; alert ngoài danh sách/window phải mở incident.

## 6. Plan gate

Plan được phép:

- update in-place M11 CloudTrail selectors;
- update in-place default Object Lock/lifecycle;
- update Lambda router/rules;
- add `g7-audit-controls`, heartbeat Lambda/schedule/alarms/IAM/log group, một SNS heartbeat-fallback cùng region và topic policy CloudWatch publish trên primary/fallback;
- add global `g8-iam-controls`; tổng tối thiểu 9 protected rules gồm heartbeat schedule;
- update provider lock vì `archive`.

NO-GO nếu:

- replace/delete trail hoặc bucket;
- tạo CloudTrail/bucket/router trùng lặp hoặc SNS khác ngoài heartbeat-fallback đã review;
- có change EKS/network/datastore/edge/workload/flagd;
- selector có audit bucket hoặc ARN chưa duyệt;
- lifecycle 400 có thể expire ngay version hiện hữu đã ≥400 ngày mà chưa có owner-approved preservation/export;
- plan chứa unrelated drift.

Không dùng `-target` để che unrelated plan.

## 7. Apply saved plan

Sau reviewer/security approval, cùng worktree/identity/window:

```powershell
terraform -chdir=$prodRoot apply tfplan
```

Ghi UTC cutover ngay khi apply kết thúc. Apply partial thì preserve state/log và fix-forward; không stop/delete trail.

## 8. Post-apply gate

```powershell
aws cloudtrail get-trail-status --name $trail --region $region
aws cloudtrail get-event-selectors --trail-name $trail --region $region
aws s3api get-object-lock-configuration --bucket $bucket
aws s3api get-bucket-lifecycle-configuration --bucket $bucket
aws events describe-rule --name techx-corp-tf3-m12-audit-heartbeat-schedule --region $region
aws lambda get-function-configuration --function-name techx-corp-tf3-m12-audit-heartbeat --region $region
aws cloudwatch describe-alarms --alarm-name-prefix techx-corp-tf3-m12-audit-heartbeat --region $region
aws sns list-topics --region $region --query "Topics[?contains(TopicArn, 'm12-audit-heartbeat-fallback')]"
aws sns get-topic-attributes --topic-arn "<primary-topic-arn>" --region $region --query "Attributes.Policy"
```

Lấy ARN fallback từ Terraform output. Trên **mỗi** topic primary, global và fallback chỉ bắt buộc có tối thiểu một email subscription `Confirmed`; không bắt buộc tất cả địa chỉ đã khai báo phải confirm. Cùng một địa chỉ người trực có thể là địa chỉ confirmed trên cả ba topic, nhưng phải bấm xác nhận riêng cho từng topic. Kiểm tra:

```powershell
$fallbackTopic = terraform -chdir=$prodRoot output -raw m12_heartbeat_fallback_topic_arn
aws sns list-subscriptions-by-topic --topic-arn $fallbackTopic --region $region
aws cloudwatch describe-alarms `
  --alarm-name-prefix techx-corp-tf3-m12-audit-heartbeat `
  --region $region `
  --query "MetricAlarms[].{Name:AlarmName,Enabled:ActionsEnabled,Actions:AlarmActions}"
```

Mỗi alarm phải có chính xác hai actions cùng region: primary M11 topic và heartbeat-fallback topic. Không đặt global `us-east-1` topic làm action trực tiếp của alarm. Nếu một trong ba topic không có ít nhất một email `Confirmed` thì trạng thái chỉ là `DEPLOYED/PARTIAL`; các subscription pending còn lại không làm heartbeat FAIL.

Sau khi subscription fallback đã `Confirmed`, test đúng integration CloudWatch → primary/fallback trên alarm mới. Lệnh này chỉ đổi trạng thái test của alarm, không sửa audit configuration; chỉ chạy trong approved window và báo trước người trực:

```powershell
$errorsAlarm = "techx-corp-tf3-m12-audit-heartbeat-errors"
aws cloudwatch set-alarm-state --alarm-name $errorsAlarm --state-value OK --state-reason "M12 approved alarm-path precondition" --region $region
aws cloudwatch set-alarm-state --alarm-name $errorsAlarm --state-value ALARM --state-reason "M12 approved primary-and-fallback notification test" --region $region
```

PASS khi cùng một test alarm đến cả primary và fallback recipients. Metric thật sẽ đánh giá lại state ở chu kỳ kế tiếp; không disable action và không sửa threshold để test.

Invoke heartbeat thủ công một lần chỉ sau apply và đọc kết quả; đây là thao tác runtime được phép trong change window, không làm thay đổi cấu hình:

```powershell
aws lambda invoke --function-name techx-corp-tf3-m12-audit-heartbeat --region $region heartbeat-result.json
Get-Content -Raw heartbeat-result.json
```

Chỉ GO nếu `status=PASS`. Heartbeat kiểm tra trail destination/multi-region/global events/log validation, delivery tối đa 40 phút, digest tối đa 90 phút, exact selectors, S3 lock/versioning/lifecycle/encryption/public block, toàn bộ deny statement bảo vệ archive (principal/condition/actions/resource), EventBridge pattern/target và semantic `source/eventSource`, hai router, schedule, đầy đủ cấu hình hai alarm, CloudWatch publish policy, tối thiểu một email confirmed trên từng topic primary/global/fallback và EKS audit log.

Exact-check selector chỉ chứng minh live configuration đúng cấu trúc và đúng ARN đã khai báo; nó không tự chứng minh ARN ban đầu bắt được event thật. Bằng chứng end-to-end `GetObject` bên dưới là điều kiện GO độc lập để loại trường hợp Terraform và heartbeat cùng dùng một baseline sai.

Khi một invariant FAIL, Lambda raise error để alarm `m12-audit-heartbeat-errors` chuyển trạng thái và gửi qua primary/fallback. CloudWatch chỉ notification khi alarm đổi trạng thái nên lỗi kéo dài không tạo email mới mỗi 5 phút. Chế độ `forceAlertTest` vẫn publish trực tiếp primary/global để kiểm thử có chủ đích. `FAIL` phải fix-forward trước IAM hardening.

Kiểm tra an toàn hai đường publish trực tiếp mà không tắt/xóa control nào:

```powershell
aws lambda invoke `
  --function-name techx-corp-tf3-m12-audit-heartbeat `
  --region $region `
  --cli-binary-format raw-in-base64-out `
  --payload '{"forceAlertTest":true}' `
  heartbeat-alert-test.json
Get-Content -Raw heartbeat-alert-test.json
```

Chỉ PASS khi kết quả có `status=PASS`, `alertDeliveredTo` gồm cả `ap-southeast-1` và `us-east-1`, `alertDeliveryFailures=[]`, đồng thời người trực nhận được hai test messages. Đây là test runtime có chủ đích trong change window, không thay đổi cấu hình AWS.

### Bằng chứng S3 data-event end-to-end

Không dùng `get-event-selectors` làm bằng chứng duy nhất. Chọn một object canary không nhạy cảm đã tồn tại bên trong **đúng bucket/prefix được owner duyệt**. Không dùng audit bucket và không tự tạo object production chỉ để test.

Trong approved window, đọc đúng một byte để tạo sự kiện `GetObject` mà không tải toàn bộ nội dung:

```powershell
$canaryBucket = "<approved-sensitive-bucket>"
$canaryKey = "<approved-prefix/existing-canary-object>"
$canaryFile = Join-Path $env:TEMP "m12-s3-canary-byte.bin"
$canaryStartUtc = (Get-Date).ToUniversalTime()

aws s3api get-object `
  --bucket $canaryBucket `
  --key $canaryKey `
  --range "bytes=0-0" `
  $canaryFile

$canaryEndUtc = (Get-Date).ToUniversalTime()
Remove-Item -LiteralPath $canaryFile -Force
```

Chờ CloudTrail delivery, sau đó lấy raw `.json.gz` từ audit bucket trong UTC window trên và parse trường `Records`. Không dùng `cloudtrail lookup-events` vì Event history không phải bằng chứng cho S3 data events. PASS chỉ khi tìm được record có đồng thời:

- `eventSource = s3.amazonaws.com`;
- `eventName = GetObject`;
- `requestParameters.bucketName = $canaryBucket`;
- `requestParameters.key = $canaryKey`;
- `eventTime` nằm trong test window và identity/request ID được giữ trong evidence.

Lưu key raw log, SHA-256 của file tải về và kết quả `validate-logs` bao phủ cùng window. Không tìm thấy record trong 40 phút thì dừng nghiệm thu: kiểm tra lại exact ARN/prefix, không tự nâng timeout để che coverage sai.

Chờ log object mới sau cutover, lấy key metadata-only và kiểm tra retention:

```powershell
aws s3api get-object-retention --bucket $bucket --key "<new-log-key-after-cutover>"
```

Yêu cầu `Mode=COMPLIANCE`, retain-until >= cutover +365 ngày. Object cũ không được dùng làm evidence.

Chờ digest bao phủ window rồi:

```powershell
$endUtc = (Get-Date).ToUniversalTime()
$startUtc = $endUtc.AddHours(-2)
aws cloudtrail validate-logs `
  --trail-arn "<existing-m11-trail-arn>" `
  --start-time $startUtc.ToString("yyyy-MM-ddTHH:mm:ssZ") `
  --end-time $endUtc.ToString("yyyy-MM-ddTHH:mm:ssZ") `
  --verbose `
  --region ap-southeast-1
```

Heartbeat log phải `PASS`; direct alert-path test primary/global phải PASS; mỗi topic primary/global/fallback có ít nhất một email `Confirmed`; hai alarm phải có primary/fallback actions; mọi alert phát sinh khi apply phải được đối chiếu change ID; canary `GetObject` và `GetSecretValue` có parsed archive evidence. Các subscription pending ngoài email confirmed tối thiểu không chặn nghiệm thu. Chưa đủ điều kiện nào thì trạng thái `DEPLOYED/PARTIAL`.

### Bằng chứng T10 chống làm mỏng log

Chọn tối thiểu một `PutMetricAlarm` và một `PutRule` đã được phê duyệt trong chính foundation apply. Không tạo mutation ngoài plan chỉ để lấy bằng chứng. Với mỗi resource, evidence pack bắt buộc có:

1. pre-state từ discovery, saved-plan text và SHA-256;
2. raw CloudTrail log copy chứa event tương ứng, SHA-256 và kết quả `validate-logs` bao phủ cùng UTC window;
3. bản redacted giữ identity/session, UTC, request ID, resource và các trường cấu hình allowlist;
4. post-state từ `describe-alarms`/`describe-rule`;
5. diff nối `pre-state/plan -> requestParameters -> post-state`, được reviewer đối chiếu change ID.

Sau khi tải bản sao log liên quan về evidence workspace ngoài repo, chạy tool local:

```powershell
$tool = "<Task_mandate_12>\code_audit\tools\Export-M12CloudTrailEvidence.ps1"
& $tool `
  -LogFile "<evidence>\cloudtrail-config-change.json.gz" `
  -EventName PutMetricAlarm,PutRule `
  -EvidenceProfile ConfigChange `
  -OutputPath "<evidence>\M12-T10-config-change.json"

Get-FileHash -Algorithm SHA256 `
  "<evidence>\cloudtrail-config-change.json.gz", `
  "<evidence>\M12-T10-config-change.json"
```

Tool chỉ xuất các trường cấu hình trong allowlist và không xuất secret/token/body/policy document. Nếu event không có trường allowlist hoặc không nối được giá trị plan với post-state thì T10 FAIL; không dùng ảnh chụp alert thay cho forensic diff.

Lifecycle 400 ngày áp dụng cả object hiện có chưa bị xóa; version đã ≥400 ngày có thể đủ điều kiện expire ngay sau thay đổi. Compliance 365 ngày giữ mỗi object mới đủ 12 tháng, bao phủ dwell time nhiều ngày/tuần và ít nhất bốn chu kỳ review theo quý; lifecycle 400 ngày thêm 35 ngày đệm cho delivery và điều tra. Đính kèm inventory dung lượng/tuổi của current và noncurrent versions cùng cost approval vào evidence. Nếu có version ≥400 ngày, dừng và chọn lifecycle dài hơn hoặc preservation/export được owner duyệt trước apply. Không thêm `GLACIER_IR` trong cutover này; nếu tối ưu sau, dùng change riêng và giữ expiration ≥400 ngày. Heartbeat đã bỏ qua lifecycle rule chỉ có transition khi đánh giá expiration để không báo FAIL giả.

## 9. Rollback

Không rollback bằng cách tắt trail/xóa bucket. Selector/router/heartbeat lỗi thì fix-forward. Compliance retention đã đặt cho object mới không thể rút ngắn. Nếu workload plan xuất hiện, dừng trước apply.

## Tài liệu AWS đối chiếu

- [CloudTrail advanced event selectors](https://docs.aws.amazon.com/awscloudtrail/latest/userguide/logging-data-events-with-cloudtrail.html)
- [CloudWatch Monitoring events qua EventBridge](https://docs.aws.amazon.com/eventbridge/latest/ref/events-ref-monitoring.html)
- [S3 Object Lock configuration](https://docs.aws.amazon.com/AmazonS3/latest/userguide/object-lock-configure.html)
- [CloudTrail validate-logs](https://docs.aws.amazon.com/awscloudtrail/latest/userguide/cloudtrail-log-file-validation-cli.html)

---

**Phiên bản:** v2.3
**Cập nhật:** 23/07/2026
**Trạng thái:** HANDOFF READY / NOT APPROVED FOR APPLY — phải hoàn tất dependency và plan gate trong change window
