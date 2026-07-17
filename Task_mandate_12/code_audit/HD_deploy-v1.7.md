# HD_deploy — Mandate 12 audit foundation

Hướng dẫn này chỉ dùng khi được phép thay đổi production. Nó tạo **audit foundation độc lập**; không thay đổi EKS, network, CloudFront, Cloudflare, ứng dụng, flagd hoặc Terraform state hiện có.

Foundation là `PARTIAL`: có CloudTrail, S3 WORM, coverage S3 đã duyệt và alert. Chỉ được tuyên bố Mandate 12 `VERIFIED` sau change IAM hardening riêng, mentor test pass và residual risk root/break-glass được chấp nhận bằng văn bản. Single-account không cho phép tuyên bố root hoặc alert plane cùng account bị chặn tuyệt đối.

## 1. Vị trí file trong repository product

Copy nội dung `Task_Phase3/Task_mandate_12/code_audit/foundation/` vào root mới:

```text
Phase3-TF3-Infra-Sentinel/
└── infra/
    └── live/
        └── audit/                 # tạo mới, state độc lập
            ├── .gitignore
            ├── .terraform.lock.hcl
            ├── versions.tf
            ├── providers.tf
            ├── main.tf
            ├── variables.tf
            ├── outputs.tf
            ├── backend.hcl         # tạo local từ example
            └── terraform.tfvars    # tạo local từ example
```

Không copy vào `infra/live/production/`; không đổi file nào đang có trong root này.

## 2. Phụ thuộc bắt buộc trước deploy

Hoàn tất và ghi evidence cho từng mục dưới đây **trước** khi tạo plan/apply. Nếu một mục chưa rõ owner hoặc chưa có evidence, trạng thái là `NO-GO`.

| Phụ thuộc | Ở đâu | Cần thực hiện/xác nhận | Owner | Evidence cần lưu |
|---|---|---|---|---|
| Identity deploy | AWS account `197826770971` | Dùng IAM user/assumed role cá nhân; không dùng root; xác nhận account/region bằng `aws sts get-caller-identity` | Deployer | Output STS đã redaction nếu cần |
| Terraform backend | Backend đã được duyệt của product | Lấy đúng S3 state bucket + DynamoDB lock table; tạo **key mới** `mandate-12/audit/terraform.tfstate`, không dùng key production | IaC owner | `backend.hcl` local đã review; không commit secret |
| Audit bucket | Account TF3 | Chọn tên bucket **mới**, duy nhất toàn cầu; không dùng lại 7 bucket hiện hữu vì không bucket nào có Object Lock | Security/IaC owner | Tên đã duyệt trong change record |
| S3 data-event scope | Data owner của bucket/prefix nhạy cảm | Duyệt exact ARN prefix cần log `GetObject`; không dùng all-S3/audit archive/fixture canary làm scope thay thế. Terraform state phải được classify và cover nếu sensitive; chỉ không dùng state làm **canary** | Data owner | Approval + ARN prefix trong `terraform.tfvars` local |
| Coverage matrix | Data/Security/IaC owners | Hoàn tất [`m12-coverage-v1.0.md`](../m12-coverage-v1.0.md): toàn bộ bucket/secret/data path nhạy cảm có owner, classification và exact scope | Data + security owners | Matrix đã ký + đối chiếu từng ARN với `terraform.tfvars` |
| Alert recipient | Security/on-call owner | Xác định recipient cho **cả hai** SNS topics và người xác nhận cả hai subscription ngay sau apply | Security owner | Hai email/subscription owner trong change record |
| CloudTrail ownership | AWS account TF3 | Revalidate `describe-trails`; nếu đã có trail mới từ team khác thì dừng, xác định owner và không tạo trail trùng | Security/IaC owner | Output discovery gần thời điểm deploy |
| Cost gate | TF3 budget owner | Forecast Data Events + S3 storage cho prefix đã duyệt; xác nhận không vượt `$300/tuần/TF` | Budget owner | Forecast và ngưỡng no-go |
| IAM hardening | IAM/CI owner | **Không** gộp vào PR foundation. Hoàn tất [`m12-iam-scope-v1.0.md`](../m12-iam-scope-v1.0.md), audit-access root, iam-change executor, boundary PR và root residual acceptance trước verdict | IAM owner | Inventory, attachment map, simulation/baseline, rollback và acceptance |
| Regional alert route | Security/IaC owner | Xác nhận region thực tế của từng denied API event; IAM/global-service event phải test cả `ap-southeast-1` và `us-east-1` | Security owner | Event/target/SNS timestamp theo region |
| Evidence/test window | Mentor + security owner | Đặt UTC window, observer và nơi lưu evidence; chờ digest delivery trước `validate-logs` | Mentor/test owner | Change window + evidence path |

### Checklist dependency

- [ ] Không dùng root; caller là đúng account/region.
- [ ] Backend state key mới, lock table và quyền backend đã được IaC owner duyệt.
- [ ] Có audit bucket name mới, coverage matrix hoàn chỉnh và S3 prefix nhạy cảm được data owner duyệt.
- [ ] Có security owner xác nhận cả hai SNS subscription sau apply.
- [ ] Discovery live không phát hiện trail/bucket audit trùng hoặc drift.
- [ ] Có cost forecast trong ngân sách.
- [ ] IAM hardening được tách thành change riêng, với inventory daily-admin/CI đầy đủ, root acceptance và rollback plan.
- [ ] Có plan kiểm thử runtime cho mọi anti-audit rule, bao gồm regional IAM alert verification.
- [ ] Có change window, mentor/observer và evidence location.

### 2.1 Cách lấy hoặc tạo từng phụ thuộc

Thực hiện theo đúng thứ tự dưới đây. Các lệnh `aws` ở bước discovery chỉ đọc; lệnh tạo/attach được ghi rõ là chỉ chạy sau approval.

#### A. Xác nhận identity và CloudTrail hiện trạng

```powershell
aws sts get-caller-identity
aws configure get region
aws cloudtrail describe-trails --include-shadow-trails --region ap-southeast-1
```

Kết quả phải là account `197826770971`, region `ap-southeast-1`. Nếu đã có trail, không tạo trail mới ngay: lấy tên/owner/change record của trail hiện hữu, rồi dừng để security owner quyết định import hay tách ownership.

#### B. Lấy backend state độc lập

1. IaC owner cung cấp tên S3 state bucket và DynamoDB lock table đang được product phê duyệt; không tự đoán hoặc copy state key của `infra/live/production`.
2. Xác nhận backend đã tồn tại bằng metadata-only:

```powershell
aws s3api head-bucket --bucket <approved-tfstate-bucket>
aws dynamodb describe-table --table-name <approved-lock-table> --region ap-southeast-1
```

3. Tạo local `backend.hcl` từ example với key mới `mandate-12/audit/terraform.tfstate`. Key mới được Terraform tạo khi apply; không cần và không được tạo thủ công object state.
4. IaC owner review `backend.hcl`; giữ local, không commit nếu chứa thông tin nội bộ.

#### C. Chọn audit bucket mới

1. Chọn tên theo `tf3-m12-audit-197826770971-<unique-suffix>`.
2. Kiểm tra tên chưa bị chiếm. `404` nghĩa là chưa có bucket; `403` hoặc thành công nghĩa là phải chọn tên khác/kiểm tra ownership.

```powershell
aws s3api head-bucket --bucket tf3-m12-audit-197826770971-<unique-suffix>
```

3. Ghi tên đã duyệt vào `terraform.tfvars`. Terraform sẽ tạo bucket mới cùng Object Lock; **không** tạo bucket bằng Console/CLI trước vì Object Lock phải do Terraform quản lý từ lúc tạo.

#### D. Lấy S3 data-event scope

1. Lấy inventory bucket ở mức metadata, sau đó data owner chọn prefix chứa dữ liệu nhạy cảm:

```powershell
aws s3api list-buckets --query "Buckets[].Name" --output table
aws s3api list-objects-v2 --bucket <candidate-bucket> --prefix <candidate-prefix/> --max-keys 5
```

2. Data owner ký/ghi approval cho ARN theo mẫu `arn:aws:s3:::<bucket>/<prefix>/`.
3. Điền ARN đó vào `s3_data_event_arns` và đối chiếu từng giá trị với [coverage matrix](../m12-coverage-v1.0.md). Không dùng `*`, toàn bộ bucket không có approval, audit archive, secret manifest hoặc canary object làm production coverage scope.
4. Terraform state phải được security/IaC owner phân loại: nếu có sensitive output thì thêm exact state prefix vào matrix/selector hoặc có compensating control được chấp nhận bằng văn bản. Không tự động loại trừ state.
5. Nếu chưa có prefix được duyệt hoặc còn asset nhạy cảm `Unknown` thì dừng ở `NO-GO`; không deploy foundation “rỗng” rồi gọi là Mandate 12 complete.

#### E. Tạo alert recipient

1. Security owner chọn email on-call/nhóm nhận alert, có khả năng xác nhận **cả hai** SNS subscription.
2. Điền vào `alert_email` trong `terraform.tfvars`.
3. Sau foundation apply, recipient phải bấm **cả hai** link xác nhận SNS. Chỉ khi cả hai là `Confirmed` mới qua gate; một `PendingConfirmation` là `DEPLOYED`, chưa `VERIFIED`.

#### F. Tạo forecast chi phí

1. Data owner lấy số read/write dự kiến của prefix từ dashboard ứng dụng, S3 metrics hoặc CloudWatch đã có; không bật all-S3 để “đo thử”.
2. Budget owner dùng đơn giá CloudTrail Data Events và S3 storage tại thời điểm deploy (AWS Pricing/Cost Explorer hiện hành) để tính forecast tuần.
3. Lưu số lượng event giả định, đơn giá, tổng forecast và ngưỡng `$300/tuần/TF` vào change record. Không có forecast = `NO-GO`.

#### G. Chuẩn bị IAM hardening sau foundation

Foundation không tự hạn chế current admin. IAM hardening phải đi qua PR/state root riêng theo đúng chuỗi: **foundation pass → audit-access root apply → cả hai SNS subscription Confirmed → render/create boundary → iam_change executor root → MFA owner assume executor → simulation/baseline từng identity → attach batch nhỏ → denied tests**. Không gộp IAM thay đổi vào PR foundation.

1. IAM owner hoàn tất [IAM scope](../m12-iam-scope-v1.0.md) cho **mọi** daily-admin/CI identity, gồm group, inline/managed policy, trust/OIDC và escalation path; root/audit-admin/break-glass là exception có owner/acceptance, không phải item bị bỏ qua:

```powershell
aws iam get-account-authorization-details `
  --filter User Role Group LocalManagedPolicy AWSManagedPolicy `
  --output json > iam-authorization-details.json
aws iam generate-credential-report
aws iam get-credential-report --output text > iam-credential-report.csv
aws iam list-open-id-connect-providers --output json
aws iam get-role --role-name <approved-ci-or-admin-role>
```

2. Sau foundation apply và Phase 7 health pass, lấy output thật và record trạng thái của cả hai subscription:

```powershell
terraform output trail_arn
terraform output audit_bucket_name
terraform output alert_topic_arn
terraform output global_alert_topic_arn
terraform output -json anti_audit_rule_arns
terraform output -json global_anti_audit_rule_arns
terraform output -json alert_regions
aws sns list-subscriptions-by-topic --topic-arn "<alert-topic-arn-from-terraform-output>"
aws sns list-subscriptions-by-topic --topic-arn "<global-alert-topic-arn-from-terraform-output>"
```

Khi điền `audit_access/terraform.tfvars`, giữ nguyên Region từ output: 7 rule/topic primary là `ap-southeast-1`; 5 rule/topic global là `us-east-1`. Root audit-access từ chối plan nếu không nhận **đúng 2 topic và 12 rule**. `s3_data_event_arns` cũng tự từ chối audit archive để tránh recursive CloudTrail logging.

`PendingConfirmation` ở bước này vẫn cho phép deploy **audit_access read-only/break-glass root** ở bước 3, nhưng là `NO-GO` cho render/create/attach boundary. Sau audit-access apply, chờ **cả hai** email subscription là `Confirmed`, chạy refresh state theo change approval, lấy hai subscription ARN thực tế từ Terraform outputs/list command và lưu chúng vào IAM PR/evidence. Thiếu một ARN hoặc không thể xác nhận recipient vẫn là `NO-GO` cho boundary, vì policy phải bảo vệ đúng cả primary và global alert plane.

3. Tạo branch `chore/mandate-12-iam-boundary` độc lập. Sau IaC-owner approval, copy **toàn bộ standalone root** `code_audit/iam_hardening/audit_access/` vào `infra/live/iam/mandate-12/audit_access/`, dùng backend state key riêng `mandate-12/audit_access/terraform.tfstate`. Điền audit bucket/trail ARN, **cả hai** SNS topic ARN, toàn bộ 12 primary/global rule ARN và exact MFA-capable security owner ARNs theo `audit_access/README.md`; plan/apply root này trước attachment. Không đặt nó trong `infra/live/audit/` hoặc `infra/live/production/`.

Sau audit-access apply, lưu hai role ARN và `security_owner_assume_audit_policy_arn`. Policy assume này chỉ được gắn trong IAM change review vào từng named MFA security owner; không gắn group rộng, operator thường, root hoặc wildcard principal. Audit-admin chỉ đọc evidence; break-glass chỉ `StartLogging`/`EnableRule`.

4. Chọn boundary template trong IAM PR:

   - `operator-boundary-policy.template.json` là **strict default**; nó deny toàn bộ `sts:AssumeRole`. Chỉ attach khi inventory chứng minh target không cần assume role.
   - Nếu CI/workflow cần `sts:AssumeRole`, đây là `NO-GO` cho strict default. Chỉ dùng `operator-boundary-policy.allowlisted-assume-role.template.json` sau khi exact **non-audit** target roles, trust policy/OIDC, audit-admin/break-glass outputs và baseline CI đã được review/test.
   - Không attach boundary vào root, audit-admin/break-glass, hoặc bất kỳ identity nào vẫn giữ unbounded `AdministratorAccess` ngoài scope migration.

5. Copy template đã chọn thành file rendered `operator-boundary.json` trong workspace của **PR IAM riêng**; không copy template vào `infra/live/audit`. Thay toàn bộ placeholder bằng outputs foundation/audit-access thật. Kiểm tra JSON và IAM policy validation trước review:

```powershell
Get-Content -Raw operator-boundary.json | ConvertFrom-Json | Out-Null
aws accessanalyzer validate-policy `
  --policy-document file://operator-boundary.json `
  --policy-type IDENTITY_POLICY `
  --region ap-southeast-1
```

6. Simulate policy cho **từng** target identity và cho primary/global audit resource trước; audit/alert/IAM-escalation actions phải `explicitDeny`, baseline operation cần thiết phải `allowed`:

```powershell
aws iam simulate-principal-policy `
  --policy-source-arn <approved-user-or-role-arn> `
  --permissions-boundary-policy-input-list file://operator-boundary.json `
  --action-names cloudtrail:StopLogging s3:DeleteObject events:DisableRule sns:DeleteTopic iam:DeleteUserPermissionsBoundary iam:UpdateAssumeRolePolicy eks:DescribeCluster `
  --resource-arns <trail-arn> <audit-bucket-arn>/m12-simulation-only <primary-event-rule-arn> <global-event-rule-arn> <primary-alert-topic-arn> <global-alert-topic-arn> <bounded-test-principal-arn>
```

7. Kiểm tra policy ARN trước. Nếu lệnh `get-policy` thành công, review default version trong IAM PR và **bỏ qua** lệnh `create-policy`; nếu trả `NoSuchEntity` thì mới tạo. Chỉ tạo/reuse managed policy ở bước này; **chưa attach boundary** từ daily-admin identity. Attachment mapping, rendered policy, simulation output và baseline verdict phải cùng PR:

```powershell
aws iam get-policy `
  --policy-arn arn:aws:iam::197826770971:policy/tf3-m12-operator-boundary

aws iam create-policy `
  --policy-name tf3-m12-operator-boundary `
  --policy-document file://operator-boundary.json `
  --description "Mandate 12 operator audit-control boundary"
```

8. Copy **toàn bộ standalone executor root** `code_audit/iam_hardening/iam_change/` vào `infra/live/iam/mandate-12/iam_change/`. Copy `backend.hcl.example`/`terraform.tfvars.example` thành file local, dùng state key riêng `mandate-12/iam-change/terraform.tfstate`, điền `operator_boundary_policy_arn`, exact target user/role ARN sets, MFA-trusted security owner ARN set và giữ removal/rollback flag là `false`. Review plan phải chỉ tạo controlled executor/assume policy, không attach boundary hàng loạt và không mutate audit controls.

Sau IAM PR approval, apply `iam_change`, lấy output và gắn policy assume **chỉ** vào named MFA owner theo mapping đã review, rồi assume executor. Không dùng root, group rộng hay `AdministratorAccess` daily identity làm executor:

```powershell
$m12ExecutorRoleArn = terraform output -raw iam_change_role_arn
$m12OwnerAssumePolicyArn = terraform output -raw security_owner_assume_iam_change_policy_arn

# Chọn đúng một lệnh phù hợp identity đã có trong trusted_change_owner_arns.
aws iam attach-user-policy `
  --user-name <named-mfa-security-owner-user> `
  --policy-arn $m12OwnerAssumePolicyArn

# Hoặc, nếu owner là role đã được review:
aws iam attach-role-policy `
  --role-name <named-mfa-security-owner-role> `
  --policy-arn $m12OwnerAssumePolicyArn
```

Không chạy cả hai lệnh cho cùng owner trừ khi mapping review yêu cầu; không attach vào group rộng. Lưu ARN policy/owner và change approval, không lưu credential.

Từ MFA security-owner profile đã được approve, assume executor bằng temporary credential trong **process environment**; không ghi JSON credential, secret key hoặc session token vào file/evidence:

```powershell
$m12OwnerProfile = "<approved-mfa-security-owner-profile>"
$m12MfaSerial = "<security-owner-mfa-device-arn>"
$m12ExecutorRoleArn = terraform output -raw iam_change_role_arn
$m12MfaCode = Read-Host "Enter current MFA code"
$m12EnvNames = @("AWS_ACCESS_KEY_ID", "AWS_SECRET_ACCESS_KEY", "AWS_SESSION_TOKEN")
$m12PreviousEnv = @{}
foreach ($m12EnvName in $m12EnvNames) {
  $m12PreviousEnv[$m12EnvName] = [Environment]::GetEnvironmentVariable($m12EnvName, "Process")
}

$m12Session = aws sts assume-role `
  --role-arn $m12ExecutorRoleArn `
  --role-session-name "m12-iam-change-$(Get-Date -Format yyyyMMddHHmmss)" `
  --serial-number $m12MfaSerial `
  --token-code $m12MfaCode `
  --duration-seconds 3600 `
  --profile $m12OwnerProfile `
  --output json | ConvertFrom-Json

$env:AWS_ACCESS_KEY_ID = $m12Session.Credentials.AccessKeyId
$env:AWS_SECRET_ACCESS_KEY = $m12Session.Credentials.SecretAccessKey
$env:AWS_SESSION_TOKEN = $m12Session.Credentials.SessionToken
aws sts get-caller-identity
```

Lưu ARN/session name/timestamp đã redaction từ `get-caller-identity`, không lưu credentials. Sau batch attachment, khôi phục process environment ngay:

```powershell
foreach ($m12EnvName in $m12EnvNames) {
  if ($null -eq $m12PreviousEnv[$m12EnvName]) {
    Remove-Item -Path "Env:$m12EnvName" -ErrorAction SilentlyContinue
  } else {
    Set-Item -Path "Env:$m12EnvName" -Value $m12PreviousEnv[$m12EnvName]
  }
}
Remove-Variable m12Session, m12MfaCode -ErrorAction SilentlyContinue
```

9. Chỉ từ session executor đã assume, attach từng identity theo attachment map; sau từng attachment chạy baseline + simulation rồi mới chuyển identity tiếp theo:

```powershell
aws iam put-user-permissions-boundary `
  --user-name <approved-operator-user> `
  --permissions-boundary arn:aws:iam::197826770971:policy/tf3-m12-operator-boundary

aws iam put-role-permissions-boundary `
  --role-name <approved-ci-or-operator-role> `
  --permissions-boundary arn:aws:iam::197826770971:policy/tf3-m12-operator-boundary
```

10. Sau mỗi attachment, chạy workflow CI/ops đã được owner chỉ định và repeat simulation. Nếu baseline bị hỏng hoặc CI cần role assumption chưa allowlist, rollback theo IAM PR; **không** tắt/xóa audit foundation. Chỉ khi batch pass mới chuyển sang identity tiếp theo và chạy mandatory denied test.

## 3. Go/No-Go trước PR

**GO** chỉ khi tất cả điều kiện sau đã có approval bằng văn bản:

1. AWS caller là account `197826770971`, region `ap-southeast-1`; không dùng root user.
2. Tên audit bucket mới, duy nhất toàn cầu; không tái dùng bucket cũ vì Object Lock không thể bật sau khi tạo.
3. [Coverage matrix](../m12-coverage-v1.0.md) đã ký: mọi asset nhạy cảm có owner/classification; exact approved S3 ARN khớp `s3_data_event_arns` và Terraform state đã được phân loại.
4. Security owner và email SNS đã xác định, có người xác nhận subscription sau apply.
5. Backend bucket/DynamoDB table được duyệt và state key mới là `mandate-12/audit/terraform.tfstate`.
6. IAM scope inventory không còn daily-admin/CI identity `Unknown`; branch/path cho audit-access và IAM PR, strict/allowlist decision, rollback và root residual acceptance đã được review.
7. Change window, reviewer, regional alert test plan và rollback/break-glass owner đã được chỉ định.

**NO-GO** nếu bất kỳ input nào còn placeholder/rỗng, coverage/identity matrix còn `Unknown`, plan có resource ngoài audit scope, IAM hardening bị gộp vào PR foundation, hoặc strict boundary được dự định attach vào CI cần `sts:AssumeRole`.

## 4. Tạo branch và copy staging

Thực hiện trong bản clone được cấp quyền của repository product, tại repository root:

```powershell
git switch -c chore/mandate-12-audit-foundation

$taskRoot = "G:\XBrain\Phase3\Task_Phase3\Task_mandate_12"
$sourceDir = Join-Path $taskRoot "code_audit\foundation"
$targetDir = Join-Path (Get-Location) "infra\live\audit"
$sourceFiles = @(
  ".gitignore",
  ".terraform.lock.hcl",
  "versions.tf",
  "providers.tf",
  "main.tf",
  "variables.tf",
  "outputs.tf",
  "backend.hcl.example",
  "terraform.tfvars.example"
)

New-Item -ItemType Directory -Force -Path $targetDir
foreach ($sourceFile in $sourceFiles) {
  Copy-Item -LiteralPath (Join-Path $sourceDir $sourceFile) -Destination $targetDir
}

Set-Location $targetDir
Copy-Item -LiteralPath backend.hcl.example -Destination backend.hcl
Copy-Item -LiteralPath terraform.tfvars.example -Destination terraform.tfvars
```

Không copy `.terraform/`. `backend.hcl` và `terraform.tfvars` là local; không commit nếu quy ước repository coi chúng là sensitive. Commit `.terraform.lock.hcl` sau khi `terraform init` thành công và reviewer kiểm tra provider version.

## 5. Điền input và plan an toàn

Thay toàn bộ placeholder trong `backend.hcl` và `terraform.tfvars`. `s3_data_event_arns` và `alert_email` là bắt buộc; Terraform phải fail nếu chúng bị bỏ trống.

```powershell
terraform init -backend-config=backend.hcl -input=false
terraform fmt -check
terraform validate
terraform plan -var-file=terraform.tfvars -out=tfplan
terraform show -no-color tfplan > tfplan.txt
```

Reviewer chỉ được thấy resource audit mới: S3 audit bucket và controls, CloudTrail, SNS, EventBridge và email subscription. **NO-GO** nếu plan thay đổi/destroy bất kỳ resource EKS, VPC, node group, CloudFront, Cloudflare, ALB, datastore, application, flagd hoặc state hiện hữu.

Lưu `tfplan.txt` làm evidence. Không chạy `apply` khi input chưa duyệt hoặc plan không đúng allowlist.

## 6. Apply có kiểm soát

Sau PR approval và trong change window:

```powershell
terraform apply tfplan
terraform output
```

Xác nhận **cả hai** email subscription SNS. Trạng thái sau apply chỉ là `DEPLOYED/PARTIAL`; chưa phải `VERIFIED`.

## 7. Verify foundation và integrity

Chạy chỉ đọc, thay placeholder bằng output thật:

```powershell
$trailName = "tf3-m12-audit"
$trailArn = "<trail-arn-from-terraform-output>"
$auditBucket = "<audit-bucket-from-terraform-output>"
$primaryRuleArnMap = terraform output -json anti_audit_rule_arns | ConvertFrom-Json
$globalRuleArnMap = terraform output -json global_anti_audit_rule_arns | ConvertFrom-Json
$primaryRuleNames = @(
  $primaryRuleArnMap.PSObject.Properties.Value |
    ForEach-Object { ($_ -split "/")[-1] }
)
$globalRuleNames = @(
  $globalRuleArnMap.PSObject.Properties.Value |
    ForEach-Object { ($_ -split "/")[-1] }
)
$primaryAlertTopicArn = terraform output -raw alert_topic_arn
$globalAlertTopicArn = terraform output -raw global_alert_topic_arn

aws cloudtrail describe-trails --trail-name-list $trailName --region ap-southeast-1
aws cloudtrail get-trail-status --name $trailName --region ap-southeast-1
aws cloudtrail get-event-selectors --trail-name $trailName --region ap-southeast-1
aws s3api get-object-lock-configuration --bucket $auditBucket
aws s3api get-bucket-versioning --bucket $auditBucket
aws s3api get-public-access-block --bucket $auditBucket
foreach ($ruleName in $primaryRuleNames) {
  aws events describe-rule --name $ruleName --region ap-southeast-1
  aws events list-targets-by-rule --rule $ruleName --region ap-southeast-1
}
foreach ($ruleName in $globalRuleNames) {
  aws events describe-rule --name $ruleName --region us-east-1
  aws events list-targets-by-rule --rule $ruleName --region us-east-1
}
foreach ($topicArn in @($primaryAlertTopicArn, $globalAlertTopicArn)) {
  aws sns get-topic-attributes --topic-arn $topicArn
  aws sns list-subscriptions-by-topic --topic-arn $topicArn
}
```

Gate pass khi trail là multi-region, global events + log file validation bật, `IsLogging=true`, `LatestDeliveryError` và `LatestDigestDeliveryError` rỗng, selector có management + approved S3 prefix, Object Lock là `COMPLIANCE` 365 ngày, **mọi primary/global rule từ Terraform outputs** có target SNS và **cả hai** email subscription đã `Confirmed`. Điều này chỉ chứng minh config/health, chưa chứng minh rule match runtime.

Lưu output ở cả hai region. CloudTrail global-service event có thể được ghi ở `us-east-1`, trong khi EventBridge matching/target là regional. Chưa có runtime denied IAM event + alert route ở region thực tế thì IAM tamper alert là `VERIFY-LIVE`, không phải pass.

Chờ CloudTrail delivery/digest xuất hiện (thường cần ít nhất một chu kỳ digest), rồi xác minh cryptographic integrity và lưu output làm evidence:

```powershell
$endUtc = (Get-Date).ToUniversalTime()
$startUtc = $endUtc.AddHours(-2)
aws cloudtrail validate-logs `
  --trail-arn $trailArn `
  --start-time $startUtc.ToString("yyyy-MM-ddTHH:mm:ssZ") `
  --end-time $endUtc.ToString("yyyy-MM-ddTHH:mm:ssZ") `
  --verbose | Tee-Object -FilePath m12-validate-logs.txt
```

`validate-logs` phải kết thúc không có `INVALID`/missing digest. Nếu chưa có digest hoặc delivery error thì giữ trạng thái `DEPLOYED`, không chạy mentor test.

## 8. Chạy test để hoàn thành Mandate 12

Chỉ bắt đầu sau khi Phase 7 pass: trail delivery/digest healthy, Object Lock đúng, selector có approved prefix, **cả hai** SNS subscription `Confirmed` và security owner/mentor có mặt.

### 8.1 Tạo fixture test an toàn

Tạo fixture **sau** foundation, trong UTC window đã duyệt. Canary secret không có giá trị nghiệp vụ; canary object nằm trong prefix đã được owner duyệt để selector thực sự ghi `GetObject`.

```powershell
$timestamp = (Get-Date).ToUniversalTime().ToString("yyyyMMddTHHmmssZ")
$canarySecret = "tf3-m12-canary-$timestamp"
$canaryBucket = "<approved-sensitive-bucket>"
$canaryPrefix = "<approved-sensitive-prefix>"
$canaryKey = "$canaryPrefix/m12-canary-$timestamp.txt"
$canaryFile = Join-Path $env:TEMP "m12-canary-$timestamp.txt"

Set-Content -LiteralPath $canaryFile -Value "non-sensitive mandate-12 canary" -NoNewline
aws secretsmanager create-secret `
  --name $canarySecret `
  --secret-string "non-sensitive mandate-12 canary" `
  --region ap-southeast-1
aws s3 cp $canaryFile "s3://$canaryBucket/$canaryKey"
```

Ghi tên/ARN fixture và UTC timestamp vào evidence. Không dùng `sosflow/db-password`, `techx-corp-tf3/flagd-sync-token`, Terraform state, audit archive hoặc object production làm fixture.

### 8.2 Chứng minh coverage và integrity

```powershell
# Tạo event đọc; output chỉ là ARN để không hiển thị SecretString.
aws secretsmanager get-secret-value `
  --secret-id $canarySecret `
  --region ap-southeast-1 `
  --query "ARN" `
  --output text

# Tạo GetObject data event; không hiển thị nội dung object.
aws s3 cp "s3://$canaryBucket/$canaryKey" - | Out-Null
```

Chờ CloudTrail delivery. Audit-admin/read-only role lấy **bản sao local** của exact log `.json.gz` theo date-prefix; không sửa object archive. `aws s3 ls` chỉ giúp tìm key, chưa phải evidence event:

```powershell
$auditBucket = "<audit-bucket-from-terraform-output>"
$utcDatePrefix = (Get-Date).ToUniversalTime().ToString("yyyy/MM/dd")
aws s3 ls "s3://$auditBucket/AWSLogs/197826770971/CloudTrail/ap-southeast-1/$utcDatePrefix/" --recursive

$evidenceDir = "<approved-local-evidence-directory>"
$logKey = "<exact-key-ending-in-.json.gz-from-list-output>"
$logCopy = Join-Path $evidenceDir (Split-Path $logKey -Leaf)
New-Item -ItemType Directory -Force -Path $evidenceDir | Out-Null
aws s3 cp "s3://$auditBucket/$logKey" $logCopy

# Local-only: script decompresses/parses the downloaded copy and exports metadata only.
$taskRoot = "G:\XBrain\Phase3\Task_Phase3\Task_mandate_12"
& "$taskRoot\code_audit\tools\Export-M12CloudTrailEvidence.ps1" `
  -LogFile $logCopy `
  -EventName GetObject `
  -ResourceContains "$canaryBucket/$canaryPrefix/" `
  -OutputPath (Join-Path $evidenceDir "M12-T03-getobject-redacted.json")

& "$taskRoot\code_audit\tools\Export-M12CloudTrailEvidence.ps1" `
  -LogFile $logCopy `
  -EventName GetSecretValue `
  -ResourceContains $canarySecret `
  -OutputPath (Join-Path $evidenceDir "M12-T04-getsecretvalue-redacted.json")

Get-FileHash -Algorithm SHA256 $logCopy, `
  (Join-Path $evidenceDir "M12-T03-getobject-redacted.json"), `
  (Join-Path $evidenceDir "M12-T04-getsecretvalue-redacted.json") |
  Format-Table -AutoSize
```

`code_audit/tools/Export-M12CloudTrailEvidence.ps1` không gọi AWS, chỉ đọc log copy local, tự decompress `.json.gz`, lọc theo `-EventName` và optional `-ResourceContains`, rồi xuất metadata redacted. Nếu một log file chưa có cả hai records, tải file kế tiếp cùng UTC window; không sửa archive hoặc tự tạo record evidence. T03/T04 chỉ `PASS` khi JSON output chỉ rõ actor, session, time, region, request ID và resource của `GetObject`/`GetSecretValue`, kèm output `validate-logs`.

### 8.3 Deploy IAM hardening và test anti-audit

1. Hoàn tất mục **2.1-G** theo sequence foundation → `audit_access` → SNS confirmed → rendered boundary → per-identity simulation/baseline → attachment batch. Nếu CI cần `sts:AssumeRole` nhưng strict boundary chưa có allowlist đã review/test, đây là `NO-GO`; không attach rồi “thử xem có chạy không”.
2. Tạo test map từ **cả** `terraform output -json anti_audit_rule_arns` và `terraform output -json global_anti_audit_rule_arns`: mỗi primary/global rule output phải có một denied API action, expected service-specific event source, EventBridge target và recipient evidence. Map là evidence bắt buộc, gồm cả rule được bổ sung sau này.
3. Từ **dedicated bounded operator identity**, sau simulation và dưới quan sát security owner, chạy test CloudTrail tối thiểu:

```powershell
$trailName = "tf3-m12-audit"
aws cloudtrail stop-logging --name $trailName --region ap-southeast-1
aws cloudtrail delete-trail --name $trailName --region ap-southeast-1
```

4. Chạy đủ các nhóm còn lại từ cùng bounded identity, chỉ trên exact audit controls/dedicated test principal đã phê duyệt:

| Nhóm rule/control | API deny tối thiểu cần map/test | Điều kiện PASS bổ sung |
|---|---|---|
| Audit S3 | Một mutation bucket audit, ví dụ `s3api delete-public-access-block --bucket <audit-bucket>` | `AccessDenied`, Object Lock/versioning/PAB sau test không đổi |
| EventBridge | `events disable-rule --name <anti-audit-rule>`; lặp map cho mọi rule output cần chứng minh | `AccessDenied`, rule/target vẫn enabled và alert receipt có timestamp |
| SNS | `sns delete-topic --topic-arn <alert-topic-arn>` hoặc subscription/policy mutation đã duyệt | `AccessDenied`, topic/subscription vẫn `Confirmed` |
| IAM boundary/policy | Detach/delete boundary hoặc policy-attachment mutation trên **dedicated bounded test principal** | `AccessDenied`, boundary/attachment không đổi |
| IAM trust path | `iam:UpdateAssumeRolePolicy` trên dedicated bounded test role sau simulation | `AccessDenied`, trust policy hash không đổi |

Với test trust path, không tạo broad trust document. Lấy **bản hiện tại** của dedicated test role làm request input; nếu policy bị cấu hình sai và request được phép, nội dung vẫn semantic-idempotent nhưng phải xử lý Critical incident:

```powershell
$boundedTestRole = "<dedicated-bounded-test-role>"
$trustPolicyInput = Join-Path $evidenceDir "current-trust-policy.json"
aws iam get-role --role-name $boundedTestRole `
  --query "Role.AssumeRolePolicyDocument" --output json |
  Set-Content -LiteralPath $trustPolicyInput -Encoding utf8
Get-FileHash -Algorithm SHA256 $trustPolicyInput
aws iam update-assume-role-policy `
  --role-name $boundedTestRole `
  --policy-document "file://$trustPolicyInput"
```

Kỳ vọng của mọi request là `AccessDenied`. Nếu bất kỳ lệnh nào thành công, dừng test, mở Critical incident và preserve evidence; không tiếp tục test hoặc tự xóa evidence. Break-glass chỉ có quyền recovery hẹp cho `StartLogging`/`EnableRule`; delete trail/topic/bucket hoặc control hỏng khác phải qua approved incident/root-custodian và Terraform recovery change riêng. Không test root, audit-admin/break-glass, workload role, object production hoặc archive object thật.

5. Với **mỗi** test map row, dùng log-copy + `Export-M12CloudTrailEvidence.ps1` để capture actor/session/error/`eventSource`/`awsRegion`, EventBridge target invocation và SNS receipt. T01/T02/T08/T09 chỉ `PASS` khi đủ deny + event + alert + control không đổi.

Ngoài ảnh/email SNS đã nhận, lấy metric EventBridge `Invocations` và `FailedInvocations` trong đúng test window cho **từng** primary/global rule. List target hay rule `ENABLED` không chứng minh target đã chạy:

```powershell
$metricEndUtc = (Get-Date).ToUniversalTime()
$metricStartUtc = $metricEndUtc.AddMinutes(-30)
$primaryRuleNames = @(
  (terraform output -json anti_audit_rule_arns | ConvertFrom-Json).PSObject.Properties.Value |
    ForEach-Object { ($_ -split "/")[-1] }
)
$globalRuleNames = @(
  (terraform output -json global_anti_audit_rule_arns | ConvertFrom-Json).PSObject.Properties.Value |
    ForEach-Object { ($_ -split "/")[-1] }
)
$ruleSets = @(
  @{ Region = "ap-southeast-1"; Names = $primaryRuleNames },
  @{ Region = "us-east-1"; Names = $globalRuleNames }
)
foreach ($ruleSet in $ruleSets) {
  foreach ($ruleName in $ruleSet.Names) {
    aws cloudwatch get-metric-statistics `
      --namespace AWS/Events --metric-name Invocations `
      --dimensions "Name=RuleName,Value=$ruleName" `
      --start-time $metricStartUtc.ToString("yyyy-MM-ddTHH:mm:ssZ") `
      --end-time $metricEndUtc.ToString("yyyy-MM-ddTHH:mm:ssZ") `
      --period 60 --statistics Sum --region $($ruleSet.Region)
    aws cloudwatch get-metric-statistics `
      --namespace AWS/Events --metric-name FailedInvocations `
      --dimensions "Name=RuleName,Value=$ruleName" `
      --start-time $metricStartUtc.ToString("yyyy-MM-ddTHH:mm:ssZ") `
      --end-time $metricEndUtc.ToString("yyyy-MM-ddTHH:mm:ssZ") `
      --period 60 --statistics Sum --region $($ruleSet.Region)
  }
}
```

Lưu output metric theo rule, EventBridge target invocation và email receipt. `Invocations` phải có datapoint phù hợp với action test; `FailedInvocations` không được có lỗi chưa giải thích. Metric không thay alert receipt, và email receipt không thay metric.

6. Với denied IAM action, kiểm tra region thực tế trước khi verdict; EventBridge là regional:

```powershell
$iamEventName = "DeleteUserPermissionsBoundary" # thay bằng action IAM đã chạy
foreach ($lookupRegion in @("ap-southeast-1", "us-east-1")) {
  aws cloudtrail lookup-events `
    --region $lookupRegion `
    --lookup-attributes AttributeKey=EventName,AttributeValue=$iamEventName `
    --max-results 10
}
```

Archive log copy vẫn là evidence chính. `lookup-events` chỉ hỗ trợ định vị nhanh event/region. Nếu event chỉ thấy ở `us-east-1` mà không có EventBridge/SNS route đã test ở region đó, M12-T10 là `VERIFY-LIVE`/không pass; mở change regional riêng trước mentor sign-off.

### 8.4 Evidence và verdict cuối

Theo [m12-tests-v1.5.md](../m12-tests-v1.5.md), tạo một thư mục evidence cho mỗi T01–T11 gồm UTC window, approver, observer, principal/session, command redacted, log/digest result, EventBridge/SNS/region evidence và verdict.

Chỉ đánh dấu Mandate 12 `VERIFIED` khi T01–T11 pass, `validate-logs` không có `INVALID`/missing digest, Object Lock retention 365 ngày có evidence, coverage matrix không còn asset nhạy cảm `Unknown`, IAM scope/attachment mapping hoàn chỉnh, root residual acceptance đã ký, và không có ảnh hưởng storefront/private ops/flagd. Claim phải ghi rõ giới hạn single-account: root/break-glass và continuity của toàn bộ same-account alert plane là residual risk, không phải “đã bị chặn tuyệt đối”.

### 8.5 Cleanup fixture sau evidence

Chỉ cleanup **sau** khi evidence log/alert đã hash, observer xác nhận và request IDs đã ghi vào verdict. Không dùng force delete secret hoặc xóa archive/evidence gốc.

```powershell
# Chỉ delete marker/version-aware cleanup cho canary key đã tạo ở 8.1.
aws s3api delete-object --bucket $canaryBucket --key $canaryKey

# Không dùng --force-delete-without-recovery; giữ recovery window tối thiểu 7 ngày.
aws secretsmanager delete-secret `
  --secret-id $canarySecret `
  --recovery-window-in-days 7 `
  --region ap-southeast-1

Remove-Item -LiteralPath $canaryFile -Force
```

Lưu output delete/scheduled deletion, object version/delete-marker metadata nếu có, UTC time và hash evidence vào `M12-T11`. Nếu cleanup không thành công, ghi incident/owner follow-up; không “dọn” bằng quyền root hoặc bằng cách xóa audit log.

## 9. Rollback và break-glass

Không rollback bằng cách tắt trail hoặc xóa audit bucket. Khi selector gây noise/cost, chỉ thu hẹp selector sau approval và vẫn giữ sensitive coverage.

`prevent_destroy` bảo vệ resource audit. Nếu có yêu cầu xóa vĩnh viễn, phải là change break-glass riêng được security owner phê duyệt: lưu evidence, xác nhận retention/legal hold, review PR gỡ guard, rồi mới thao tác. Không dùng nó để xử lý sự cố thường ngày.

---

**Phiên bản:** v1.7  
**Cập nhật:** 18/07/2026  
**Trạng thái:** READY FOR REVIEW — chưa được phép deploy
