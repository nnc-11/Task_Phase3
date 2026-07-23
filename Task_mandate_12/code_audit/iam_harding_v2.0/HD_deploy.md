# Hướng dẫn deploy IAM hardening v2.0

## 1. Mục tiêu

Rollout permissions boundary cho GitHub Terraform CI mà không đổi application traffic và không tác động user/pipeline ngoài scope.

Thực hiện theo năm phase độc lập:

1. hoàn tất/verify Audit Foundation;
2. bootstrap seed: tạo boundary v2 chưa attach + mở exact state-read;
3. thêm CI guard sau khi plan role đã đọc được bootstrap state;
4. chạy simulation;
5. pre-stage heartbeat rồi attach boundary vào GHA roles.

Không gộp write của bootstrap state và production state vào một apply.

## 2. Gate bắt buộc trước deploy

### NO-GO nếu còn một điều sau

- Heartbeat Lambda chưa tồn tại.
- Heartbeat schedule chưa có target.
- Hai heartbeat alarm chưa tồn tại/healthy.
- Audit bucket còn `COMPLIANCE 14 ngày`/lifecycle `30 ngày`; phải đạt
  `COMPLIANCE 365 ngày`/lifecycle `400 ngày` hoặc retention khác đã được
  Security Owner phê duyệt bằng threat/investigation rationale.
- Chưa chốt xử lý object version đã tạo dưới default lock 14 ngày: extend
  retention có kiểm soát hoặc ghi rõ evidence window chỉ bắt đầu từ object mới
  sau cutover.
- Trail không logging, delivery/digest lỗi hoặc selector không đúng.
- Chưa có named IAM deployment identity bật MFA.
- Chưa chứng minh phiên credential dùng để apply đã xác thực MFA; việc user có
  MFA device không đồng nghĩa access-key session hiện tại dùng MFA.
- Người chạy đang dùng root hoặc long-lived admin session không được duyệt.
- Chưa xác nhận owner root `infra/bootstrap/github-oidc`.
- Chưa có plan riêng của bootstrap state từ đúng commit.
- Candidate boundary đã tồn tại/attach khác baseline nhưng chưa reconcile đúng
  Terraform state owner; không tiếp tục bằng create/import thủ công.
- Production plan còn IAM, Audit Foundation hoặc SNS subscription diff chưa
  được tách khỏi normal workflow.
- Chưa chốt maintenance path để sửa Audit Foundation sau khi boundary được attach.
- Chưa có CODEOWNERS/ruleset hoặc compensating review control bảo vệ workflow,
  gate script, bootstrap IAM và Audit Foundation code.
- Đang có IAM rollout khác (ví dụ scope `pm127-kyverno-ecr`) còn phụ thuộc workflow
  production thông thường.

Live ngày 23/07/2026 đang vướng heartbeat, retention và named MFA, nên hiện là `NO-GO`.

## 3. Đặt file vào repo product

Tạo branch mới từ remote `main` mới nhất. Không dùng local branch cũ.

Trên máy deploy, đặt hai biến và chạy Terraform từ product root:

```powershell
$ProductRoot = "<PATH_TO_PHASE3_TF3_INFRA_SENTINEL>"
$HandoffRoot = "<PATH_TO_TASK_MANDATE_12>/code_audit/iam_harding_v2.0"
$BootstrapRoot = "infra/bootstrap/github-oidc"
$ProductionRoot = "infra/live/production"
Set-Location $ProductRoot
```

Không đặt credential, state hoặc saved plan trong `$HandoffRoot`.

### File thay thế

```text
code_audit/iam_harding_v2.0/repo_overlay/infra/bootstrap/github-oidc/ci-audit-boundary.tf
  -> infra/bootstrap/github-oidc/ci-audit-boundary.tf
```

### File mới

```text
code_audit/iam_harding_v2.0/repo_overlay/.github/workflows/terraform-bootstrap-plan.yml
  -> .github/workflows/terraform-bootstrap-plan.yml

code_audit/iam_harding_v2.0/repo_overlay/scripts/ci/m12-terraform-scope-gate.py
  -> scripts/ci/m12-terraform-scope-gate.py

# Chỉ copy ở pre-attach phase:
code_audit/iam_harding_v2.0/repo_overlay/infra/live/production/m12-iam-hardening.auto.tfvars
  -> infra/live/production/m12-iam-hardening.auto.tfvars
```

### Chỉnh file hiện hữu

Áp dụng thủ công, review từng hunk:

- `patches/bootstrap-main.md`
- `patches/bootstrap-enable-boundary.md` — chỉ dùng ở phase attach
- `patches/bootstrap-readme.md`
- `patches/bootstrap-variables.md`
- `patches/codeowners.md`
- `patches/heartbeat-boundaries.md`
- `patches/production-workflow.md`

Không overwrite nguyên `main.tf`, `variables.tf` hoặc workflow nếu remote đã đổi sau base SHA.

`patches/codeowners.md` chứa placeholder; GitHub owner phải thay bằng user/team
thật và cấu hình ruleset/environment. Không commit placeholder.

Trước khi copy:

```powershell
& "$HandoffRoot/scripts/check-repo-compatibility.ps1" `
  -RepoRoot $ProductRoot `
  -Stage Baseline
```

Nếu HEAD khác baseline, warning bắt buộc review ba chiều; không copy mù.

## 4. Review tĩnh trước plan

Tại seed branch:

```powershell
terraform fmt -check -recursive infra/bootstrap/github-oidc
terraform -chdir=infra/bootstrap/github-oidc init -backend=false
terraform -chdir=infra/bootstrap/github-oidc validate
python "$HandoffRoot/tests/test_scope_gate.py"
```

Sau khi map CI guard:

```powershell
python -c "import ast,pathlib; ast.parse(pathlib.Path('scripts/ci/m12-terraform-scope-gate.py').read_text(encoding='utf-8'))"
```

Không dùng `terraform apply`, `import`, `state mv/rm/push` trong bước này.

## 5. Change 1 — hoàn tất Foundation

Đội Foundation fix-forward để live có đủ:

- heartbeat Lambda;
- schedule target tới Lambda;
- invocation permission;
- `Errors` và `Missing` alarms;
- heartbeat trả `PASS`;
- Object Lock/lifecycle đã đạt retention được phê duyệt;
- primary/global/fallback có confirmed receiver;
- IAM mutation test để lại CloudTrail event và alert.

Chạy:

```powershell
& "$HandoffRoot/scripts/preflight-readonly.ps1" `
  -DeploymentUserName <NAMED_IAM_USER_CO_MFA> `
  -Stage Foundation
```

Script chỉ gọi API `get/list/describe`. Nó tự kết thúc với exit code `1` khi có
`NO-GO`, thay vì chỉ in inventory để người deploy tự suy đoán.

Preflight kiểm tra named user có MFA device nhưng AWS STS không trả trực tiếp
`mfaAuthenticated` trong `get-caller-identity`. Người deploy phải dùng temporary
session do MFA/credential broker đã duyệt, không dùng access key dài hạn trực
tiếp. Sau apply, lưu CloudTrail event đã redaction có
`sessionContext.attributes.mfaAuthenticated=true` làm evidence. Nếu không chứng
minh được phiên MFA: không apply.

Lưu ý: đổi default Object Lock lên 365 ngày chỉ áp cho object mới. Lifecycle 400
ngày áp theo tuổi object nhưng không tự kéo dài lock của version cũ. Nếu claim
Mandate 12 bao gồm log lịch sử, Foundation owner phải inventory version cũ và
extend retention bằng change riêng; nếu không, tài liệu bằng chứng phải ghi rõ
cutover timestamp.

## 6. Bootstrap seed — tạo boundary v2 chưa attach và mở state-read

Baseline repo đã có file boundary v1 trong bootstrap root nhưng live chưa có
managed policy. Vì vậy **không** apply riêng `bootstrap-main.md`: full plan sẽ
đồng thời tạo boundary đang nằm trong code. Seed PR phải đưa boundary lên v2
trước khi plan.

Seed PR chỉ gồm:

- overlay `ci-audit-boundary.tf` v2;
- `patches/bootstrap-main.md`;
- `patches/bootstrap-variables.md`, vẫn giữ tracked default
  `enable_ci_audit_boundary = false`;
- `patches/bootstrap-readme.md`;
- `.github/CODEOWNERS` đã thay owner thật theo `patches/codeowners.md`.

Chưa thêm bootstrap workflow, production scope gate,
`patches/heartbeat-boundaries.md` hoặc `bootstrap-enable-boundary.md`.
`additional_bounded_principal_arns` phải là `[]`; không đưa GitLab/human vào.

Kiểm tra seed mapping:

```powershell
& "$HandoffRoot/scripts/check-repo-compatibility.ps1" `
  -RepoRoot $ProductRoot `
  -Stage Seed
```

Vì CODEOWNERS mới được tạo trong chính PR này, seed PR phải có ít nhất một
Security/Platform reviewer độc lập làm compensating review. Sau review và merge
đúng commit, dùng named MFA identity:

```powershell
terraform -chdir=$BootstrapRoot init -reconfigure `
  -backend-config="bucket=techx-tf3-197826770971-tfstate" `
  -backend-config="key=bootstrap/github-oidc/terraform.tfstate" `
  -backend-config="region=ap-southeast-1" `
  -backend-config="dynamodb_table=techx-tf3-terraform-lock" `
  -backend-config="encrypt=true"

terraform -chdir=$BootstrapRoot plan -input=false `
  -out=m12-bootstrap-seed.tfplan

terraform -chdir=$BootstrapRoot show -no-color `
  m12-bootstrap-seed.tfplan

terraform -chdir=$BootstrapRoot show -json `
  m12-bootstrap-seed.tfplan `
  > "$BootstrapRoot/m12-bootstrap-seed.json"

Get-FileHash `
  "$BootstrapRoot/m12-bootstrap-seed.tfplan" `
  -Algorithm SHA256
```

Plan chỉ được có hai AWS thay đổi:

1. update inline policy `state-lock-and-read` của GHA plan role để đọc exact
   bootstrap state key;
2. create managed policy `techx-corp-tf3-ci-audit-boundary`.

Hai GHA role vẫn phải có `PermissionsBoundary = null`. Không được thay trust,
replace role, đổi attachment hoặc đụng production state.

Plan JSON có thể chứa dữ liệu nhạy cảm. Không commit/upload công khai. Sau người
thứ hai review plan/hash:

```powershell
terraform -chdir=$BootstrapRoot apply -input=false `
  m12-bootstrap-seed.tfplan
```

Sau apply:

```powershell
aws iam get-policy `
  --policy-arn arn:aws:iam::197826770971:policy/techx-corp-tf3-ci-audit-boundary

aws iam get-role `
  --role-name techx-corp-tf3-gha-terraform-plan `
  --query "Role.PermissionsBoundary"

aws iam get-role `
  --role-name techx-corp-tf3-gha-terraform-apply `
  --query "Role.PermissionsBoundary"
```

Policy phải tồn tại; cả hai boundary phải `null`.

Ngay sau seed merge, bật required PR/code-owner review và chặn force-push/delete.
Chưa đặt bootstrap-plan status thành required cho tới khi workflow được merge ở
mục 7.

## 7. CI guard — thêm bootstrap plan và production scope gate

PR tiếp theo chỉ thêm:

- `repo_overlay/.github/workflows/terraform-bootstrap-plan.yml`;
- `repo_overlay/scripts/ci/m12-terraform-scope-gate.py`;
- `patches/production-workflow.md`.

Chạy:

```powershell
& "$HandoffRoot/scripts/check-repo-compatibility.ps1" `
  -RepoRoot $ProductRoot `
  -Stage Guarded

python "$HandoffRoot/tests/test_scope_gate.py"
```

Bootstrap workflow lúc này phải đọc được state và plan `No changes`. Nếu còn
`AccessDenied` hoặc AWS diff: dừng, không cấp admin credential cho workflow.

Đây là Git-only change, **không chạy Terraform apply**. Sau merge mới cấu hình
bootstrap plan và production scope gate thành required checks theo ruleset đã
duyệt.

Chạy pre-attach gate:

```powershell
& "$HandoffRoot/scripts/preflight-readonly.ps1" `
  -DeploymentUserName <NAMED_IAM_USER_CO_MFA> `
  -Stage PreAttach
```

## 8. Simulation trước attach

Chạy:

```powershell
& "$HandoffRoot/scripts/verify-boundary-readonly.ps1" -Stage PreAttach
```

Kỳ vọng:

- `StopLogging`, `DeleteTrail`, selector/trail mutation: `explicitDeny`;
- archive bucket/object mutation: `explicitDeny`;
- audit KMS disable/delete/policy mutation: `explicitDeny`;
- EventBridge/Lambda/alarm/SNS/SQS audit-plane mutation: `explicitDeny`;
- `sns:Unsubscribe`/`SetSubscriptionAttributes`: `explicitDeny` với `Resource="*"`,
  nhưng chỉ đối với hai GHA role được attach boundary;
- IAM write, credential issuance và chained `AssumeRole`: `explicitDeny`;
- read/describe và non-IAM workload action mẫu: không bị explicit deny.

Reviewer phải lưu output đã redaction làm evidence. Nếu baseline cần một action đang bị deny, không attach; sửa policy và simulation lại.

`aws accessanalyzer validate-policy` có thể trả warning
`PASS_ROLE_WITH_STAR_IN_ACTION_AND_RESOURCE` vì statement `AllowWithinBoundary`
dùng `Action="*"`/`Resource="*"`. Đây là warning đã biết: permissions boundary
không tự cấp quyền, mà chỉ đặt trần lên identity policy; các explicit deny phía
sau vẫn thắng. Chấp nhận warning này phải được reviewer ghi vào evidence. Mọi
finding mức `ERROR` vẫn là `NO-GO`.
Mọi `SECURITY_WARNING` khác mã đã ghi ở trên cũng là `NO-GO` cho tới khi policy
được sửa hoặc có phê duyệt/rationale riêng.

## 9. Pre-stage heartbeat rồi attach GHA boundary

### 9.1. Pre-stage boundary map

Copy exact `m12-iam-hardening.auto.tfvars`, rồi áp phần comment trong
`patches/heartbeat-boundaries.md` bằng maintenance path mục 11. Saved plan chỉ
được update heartbeat Lambda environment/config để theo dõi hai GHA role.

Heartbeat sẽ tạm `FAIL` vì boundary chưa attach. Người trực phải nhận được alert
trên ít nhất primary và fallback, gắn change ID, không disable alarm. Nếu không
nhận được alert: dừng.

### 9.2. Attach boundary

Áp `patches/bootstrap-enable-boundary.md` để đổi **tracked default**:

```hcl
enable_ci_audit_boundary = true
```

Không chỉ truyền `-var=true` ở CLI. Code phải giữ `true`, nếu không bootstrap
plan kế tiếp sẽ đề nghị detach.

Trước attach plan:

```powershell
& "$HandoffRoot/scripts/check-repo-compatibility.ps1" `
  -RepoRoot $ProductRoot `
  -Stage Attach
```

Plan chỉ được update in-place:

- `techx-corp-tf3-gha-terraform-plan`;
- `techx-corp-tf3-gha-terraform-apply`.

Không được replace role, đổi trust subject hoặc đổi attached policies trong change này.

Chạy bootstrap PR plan. Sau merge, checkout exact main commit và tạo plan mới:

```powershell
terraform -chdir=$BootstrapRoot init -reconfigure `
  -backend-config="bucket=techx-tf3-197826770971-tfstate" `
  -backend-config="key=bootstrap/github-oidc/terraform.tfstate" `
  -backend-config="region=ap-southeast-1" `
  -backend-config="dynamodb_table=techx-tf3-terraform-lock" `
  -backend-config="encrypt=true"

terraform -chdir=$BootstrapRoot plan -input=false `
  -out=m12-boundary-attach.tfplan

terraform -chdir=$BootstrapRoot show -no-color `
  m12-boundary-attach.tfplan

Get-FileHash `
  "$BootstrapRoot/m12-boundary-attach.tfplan" `
  -Algorithm SHA256
```

Sau người thứ hai review plan/hash, apply đúng saved plan:

```powershell
terraform -chdir=$BootstrapRoot apply -input=false `
  m12-boundary-attach.tfplan
```

Sau apply:

```powershell
aws iam get-role `
  --role-name techx-corp-tf3-gha-terraform-plan `
  --query "Role.PermissionsBoundary"

aws iam get-role `
  --role-name techx-corp-tf3-gha-terraform-apply `
  --query "Role.PermissionsBoundary"
```

Sau đó:

1. chạy:

   ```powershell
   & "$HandoffRoot/scripts/verify-boundary-readonly.ps1" -Stage PostAttach
   & "$HandoffRoot/scripts/preflight-readonly.ps1" `
     -DeploymentUserName <NAMED_IAM_USER_CO_MFA> `
     -Stage PostAttach
   ```

2. cả hai script phải exit `0`;
3. xác nhận heartbeat trở lại `PASS`;
4. chạy bootstrap plan workflow;
5. chạy production plan không có IAM/Audit Foundation diff;
6. không chạy production apply chỉ để smoke test;
7. khi có approved non-IAM change thật, theo dõi apply đầu tiên.

Nếu attach bị hủy/thất bại, dùng saved plan riêng rollback
`audit_detection_bounded_principals = {}` để tránh alert kéo dài. Không tắt alarm.

## 10. Production scope gate

`m12-terraform-scope-gate.py` phải chạy sau khi tạo `tfplan` và trước upload/apply.

Gate chặn:

- mọi `aws_iam_*` change;
- mọi `aws_sns_topic_subscription` change vì boundary chặn hai API subscription
  mutation trên `Resource="*"`;
- mọi address chứa `audit_detection_`, `m12_audit_heartbeat` hoặc `m12_heartbeat`.

IAM change phải đi qua PR/root bootstrap riêng. Audit Foundation change phải đi
qua maintenance path ở mục 11.

Điều này tránh plan trộn workload với resource bị boundary deny, apply một phần
rồi mới thất bại.

## 11. Maintenance path cho Audit Foundation

Sau attach phase, GHA production apply role **không còn quyền sửa Audit Foundation**.
Khi thật sự cần fix/upgrade foundation:

1. mở change riêng, Security Owner phê duyệt scope và maintenance window;
2. dùng named IAM identity có MFA, không dùng root và không tạm gỡ boundary;
3. checkout đúng commit đã review; dùng root `infra/live/production` và state
   `eks-baseline/terraform.tfstate`;
4. bảo đảm không có workflow/apply khác đang giữ lock;
5. tạo saved plan, xuất JSON và kiểm tra tất cả change address chỉ thuộc
   `audit_detection_*`, `m12_audit_heartbeat` hoặc `m12_heartbeat`;
6. nếu plan có workload/IAM ngoài audit scope: dừng, không apply;
7. người thứ hai review plan/hash/change ID;
8. apply đúng saved plan; chạy Foundation verification, heartbeat và preflight
   `PostAttach` ngay sau đó.

Lệnh tạo saved plan tại production root:

```powershell
terraform -chdir=$ProductionRoot init -reconfigure `
  -backend-config="bucket=techx-tf3-197826770971-tfstate" `
  -backend-config="key=eks-baseline/terraform.tfstate" `
  -backend-config="region=ap-southeast-1" `
  -backend-config="dynamodb_table=techx-tf3-terraform-lock" `
  -backend-config="encrypt=true"

terraform -chdir=$ProductionRoot plan -input=false `
  -out=m12-foundation-maintenance.tfplan

terraform -chdir=$ProductionRoot show -no-color `
  m12-foundation-maintenance.tfplan

terraform -chdir=$ProductionRoot show -json `
  m12-foundation-maintenance.tfplan `
  > "$ProductionRoot/m12-foundation-maintenance.json"

Get-FileHash `
  "$ProductionRoot/m12-foundation-maintenance.tfplan" `
  -Algorithm SHA256
```

Không dùng `-target` để giấu diff ngoài scope. Chỉ sau review plan/hash mới:

```powershell
terraform -chdir=$ProductionRoot apply -input=false `
  m12-foundation-maintenance.tfplan
```

Đây là đường bảo trì tạm thời cho mô hình single account. Không trao credential
cho workflow. Về dài hạn nên tạo `AuditFoundationRole` riêng, chỉ assume qua
protected environment có reviewer.

## 12. Ảnh hưởng dự kiến đến workflow hiện hữu

Workflow production hiện có scope IAM như `pm127-kyverno-ecr`. Sau khi cài gate,
scope đó sẽ bị chặn trước upload/apply. Phải hoàn tất change đó trước rollout
v2.0 hoặc chuyển nó sang IAM/bootstrap change riêng; không được bỏ qua gate.

Boundary cũng deny `iam:CreateServiceLinkedRole`. Dịch vụ AWS cần service-linked
role lần đầu phải được inventory và pre-create qua IAM change đã review trước
deployment workload; không nới boundary tạm thời.

## 13. Không attach trong rollout này

### `gitlab-ci-deployer`

Không attach boundary và không rotate/delete key trong change này. Identity đang quản pipeline ngoài ownership rõ ràng; thay đổi có thể làm hỏng deployment của team khác.

Boundary có deny `sns:Unsubscribe` toàn cục vì API này không match exact topic ARN
trong IAM simulator. Deny chỉ tác động principal mang boundary; do
`gitlab-ci-deployer` không được attach trong rollout này nên pipeline GitLab và
topic ngoài scope của identity đó không bị ảnh hưởng.

Để tránh normal apply thất bại giữa chừng, production scope gate chặn mọi
`aws_sns_topic_subscription` diff. Repo baseline chỉ quản subscription audit;
không có subscription AIOps/application bị thay đổi bởi rollout này.

Muốn migrate phải có:

- pipeline owner;
- inventory action thực dùng;
- migration sang OIDC/short-lived role;
- smoke test GitLab;
- rotate lần lượt từng key;
- rollback đã duyệt.

### `AIO2-Admin` và human users

Không sửa group/user AIOps. Mandate 12 chỉ ghi residual risk và yêu cầu owner-led migration. Không coi CI boundary là đã hoàn tất toàn bộ IAM hardening khi các admin path này còn tồn tại.

## 14. Rollback

Rollback chỉ dùng khi CI baseline hỏng sau attach:

1. named MFA deployment identity đặt `enable_ci_audit_boundary = false`;
2. tạo và review saved plan bootstrap;
3. plan chỉ gỡ boundary khỏi hai GHA role, không xóa managed policy;
4. apply;
5. xác nhận expected heartbeat alert “boundary missing” được nhận;
6. bằng production maintenance path, xóa
   `m12-iam-hardening.auto.tfvars` hoặc đổi map về `{}`, plan chỉ được update
   heartbeat configuration rồi apply;
7. xác nhận role hoạt động và heartbeat trở lại `PASS`;
8. mở incident/root-cause trước lần thử tiếp.

Không rollback bằng cách xóa policy, sửa trust, dùng root hoặc gỡ Audit Foundation.

## 15. Definition of Done

- Foundation heartbeat `PASS`.
- Boundary policy tồn tại và policy document được lưu evidence.
- Hai GHA role mang exact boundary ARN.
- Bootstrap plan workflow xanh.
- Production scope gate chặn IAM, Audit Foundation và mọi SNS subscription diff
  xung đột với boundary.
- Audit Foundation maintenance path đã có owner/reviewer.
- Production plan baseline xanh.
- Denied tests có CloudTrail event + alert, post-state không đổi.
- Không có thay đổi trên AIOps, RDS, EKS workload hoặc application traffic.
- Residual human/root/GitLab paths được ghi rõ, không claim tuyệt đối.
