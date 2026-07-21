# Hướng dẫn nâng cấp M11 audit foundation cho Mandate 12

> Chỉ thực hiện khi có approval tham gia production. Tài liệu này không cho phép chạy apply trước change window.

## 1. Phạm vi

Nâng cấp in-place trail/bucket/router M11 đang thuộc `infra/live/production`. Không tạo trail/bucket/SNS thứ hai, không đổi ARN/name và không import/chuyển Terraform state.

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
| S3 scope | `m12-coverage-v2.0.md` + metadata-only inventory | Exact ARN kết thúc `/`, owner ký |
| Retention | Security owner duyệt cutover Compliance 365/lifecycle 400 | Chấp nhận không hồi tố object cũ |
| Alert | Hai M11 SNS topics và toàn bộ recipient bắt buộc | Không còn `PendingConfirmation`, có người trực/test receipt |
| Cost | Data-event estimate + storage 400 ngày | Trong budget |
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
```

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

Các sửa đổi trên phải đi cùng nhau: `g7` regional, `g8` global, router map/critical groups và heartbeat. Nếu thiếu một phần thì NO-GO vì event có thể được EventBridge nhận nhưng router bỏ qua, hoặc heartbeat không phát hiện target/pattern bị đổi.

Lưu ý: advanced event selectors sẽ thay thế basic selectors hiện có. Vì vậy block mới bắt buộc giữ selector `Management` rồi mới thêm S3 `Data`; không được chỉ thêm data selector.

Trong `infra/live/production/versions.tf`, thêm provider:

```hcl
archive = {
  source  = "hashicorp/archive"
  version = "~> 2.4"
}
```

Thêm `m12-audit-heartbeat.zip` vào `.gitignore`. Không commit state, plan, credential hoặc tfvars chứa dữ liệu nhạy cảm.

## 5. Build router và static checks

M11 module hiện deploy router từ `audit-alert-router.zip`; sau khi sửa `index.py`, build lại theo convention repo và kiểm tra zip chứa `index.py` ở root.

```powershell
$moduleDir = "<product-repo>\infra\modules\audit-detection"
Compress-Archive `
  -LiteralPath "$moduleDir\lambda\index.py" `
  -DestinationPath "$moduleDir\audit-alert-router.zip" `
  -Force

python -c "import zipfile; z=zipfile.ZipFile(r'<product-repo>\infra\modules\audit-detection\audit-alert-router.zip'); print(z.namelist())"
python -m py_compile "$moduleDir\lambda\index.py" "$moduleDir\lambda\heartbeat.py"
```

Nếu `py_compile` tạo `__pycache__`, xóa chỉ cache vừa sinh trước commit.

```powershell
$prodRoot = "<product-repo>\infra\live\production"
terraform -chdir=$prodRoot fmt -recursive
terraform -chdir=$prodRoot init
terraform -chdir=$prodRoot validate
terraform -chdir=$prodRoot plan -out=tfplan
terraform -chdir=$prodRoot show -no-color tfplan | Tee-Object -FilePath "$prodRoot\tfplan.txt"
Get-FileHash -Algorithm SHA256 "$prodRoot\tfplan", "$prodRoot\tfplan.txt"
```

## 6. Plan gate

Plan được phép:

- update in-place M11 CloudTrail selectors;
- update in-place default Object Lock/lifecycle;
- update Lambda router/rules;
- add `g7-audit-controls`, heartbeat Lambda/schedule/alarms/IAM/log group;
- add global `g8-iam-controls`; tổng tối thiểu 9 protected rules gồm heartbeat schedule;
- update provider lock vì `archive`.

NO-GO nếu:

- replace/delete trail hoặc bucket;
- tạo CloudTrail/bucket/SNS thứ hai;
- có change EKS/network/datastore/edge/workload/flagd;
- selector có audit bucket hoặc ARN chưa duyệt;
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
```

Invoke heartbeat thủ công một lần chỉ sau apply và đọc kết quả; đây là thao tác runtime được phép trong change window, không làm thay đổi cấu hình:

```powershell
aws lambda invoke --function-name techx-corp-tf3-m12-audit-heartbeat --region $region heartbeat-result.json
Get-Content -Raw heartbeat-result.json
```

Chỉ GO nếu `status=PASS`. Heartbeat hiện kiểm tra trail destination/multi-region/global events/log validation, delivery/digest age, exact selectors, S3 lock/versioning/lifecycle/encryption/public block, exact EventBridge pattern/target, hai router, schedule, alarms, mọi endpoint SNS bắt buộc và EKS audit log. `FAIL` phải fix-forward trước IAM hardening.

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

Heartbeat log phải `PASS`; mọi recipient bắt buộc trên cả hai SNS topics phải `Confirmed`; canary `GetObject` và `GetSecretValue` có parsed archive evidence. Chưa đủ điều kiện nào thì trạng thái `DEPLOYED/PARTIAL`.

## 9. Rollback

Không rollback bằng cách tắt trail/xóa bucket. Selector/router/heartbeat lỗi thì fix-forward. Compliance retention đã đặt cho object mới không thể rút ngắn. Nếu workload plan xuất hiện, dừng trước apply.

## Tài liệu AWS đối chiếu

- [CloudTrail advanced event selectors](https://docs.aws.amazon.com/awscloudtrail/latest/userguide/logging-data-events-with-cloudtrail.html)
- [S3 Object Lock configuration](https://docs.aws.amazon.com/AmazonS3/latest/userguide/object-lock-configure.html)
- [CloudTrail validate-logs](https://docs.aws.amazon.com/awscloudtrail/latest/userguide/cloudtrail-log-file-validation-cli.html)

---

**Phiên bản:** v2.0
**Cập nhật:** 21/07/2026
**Trạng thái:** LIVE BASELINE CONFIRMED / READY FOR REVIEW — chưa được phép deploy
