# Hướng dẫn IAM hardening Mandate 12

> Change riêng sau khi audit foundation upgrade/digest/heartbeat healthy.

## 1. Dependency

- `m12-iam-scope-v2.0.md` không còn effective-admin `Unknown`;
- exact trail/bucket, 3 topics (primary/global/heartbeat-fallback), toàn bộ confirmed subscription ARNs, 9+ EventBridge rule ARNs, 3 Lambda ARNs, 3 log-group ARNs và 2 heartbeat alarm ARNs;
- named IAM security-owner user đã bật MFA và root residual-risk acceptance;
- mapping principal → Terraform state/root → owner → baseline → rollback;
- audit foundation đã ghi được mọi IAM change trong archive sau cutover.

### Baseline live ngày 21/07/2026

- `techx-corp-tf3-gha-terraform-apply`: attach `AdministratorAccess`, không permissions boundary.
- `tf3-production-operator`: không permissions boundary.
- `cdo-2-admin-team`: admin qua group `AIO2-Admin`, không có MFA device.
- Account summary báo account/root MFA enabled, nhưng root vẫn nằm ngoài permissions boundary và không được dùng để deploy.
- Direct-admin users: `gitlab-ci-deployer`, `cdo02testaudit`, `hieu-AdminAccess`; đều chưa MFA. Hai user có tổng cộng 4 active access keys (`gitlab-ci-deployer`: 2, `hieu-AdminAccess`: 2). Không ghi AccessKeyId vào tài liệu/evidence.
- `AIO2-Admin` có 6 users; account chỉ có 1 MFA device in use. Phải inventory MFA theo từng owner trước migration.

Đây là input để thiết kế, không phải quyền cho phép sửa IAM. IAM phase vẫn blocked cho tới khi foundation healthy, owner mapping hoàn tất và deployment identity có MFA/approved short-lived role.

### Backend/state bắt buộc

Hai root `audit_access` và `iam_change` cần remote state key riêng. Lấy bucket/lock table/region từ CD01 hoặc state owner và điền `backend.hcl` theo file example; không tự tạo backend bằng root này. Kiểm tra chỉ đọc:

```powershell
aws sts get-caller-identity
aws s3api head-bucket --bucket "<approved-tfstate-bucket>"
aws s3api get-bucket-versioning --bucket "<approved-tfstate-bucket>"
aws s3api get-bucket-encryption --bucket "<approved-tfstate-bucket>"
aws dynamodb describe-table --table-name "<approved-lock-table>" --region ap-southeast-1 --query "Table.TableStatus"
```

Nếu bucket/table chưa có, dừng và yêu cầu owner tạo bằng bootstrap/state process hiện hành. GO khi state bucket có versioning/encryption, lock table `ACTIVE`, hai state keys không trùng và caller là approved short-lived/MFA identity, không phải root/current long-lived admin session.

## 2. Inventory chỉ đọc

```powershell
aws iam get-account-authorization-details --filter User Role Group LocalManagedPolicy AWSManagedPolicy
aws iam list-open-id-connect-providers
aws iam get-role --role-name techx-corp-tf3-gha-terraform-apply
aws iam list-attached-role-policies --role-name techx-corp-tf3-gha-terraform-apply
aws iam get-role --role-name tf3-production-operator
aws iam list-groups-for-user --user-name cdo-2-admin-team
aws iam list-attached-user-policies --user-name cdo-2-admin-team
aws iam list-mfa-devices --user-name cdo-2-admin-team
aws iam get-account-summary
aws iam list-entities-for-policy --policy-arn arn:aws:iam::aws:policy/AdministratorAccess
```

Không lưu credential/secret/session token.

## 3. Deploy audit access

Sau approval, đặt `code_audit/iam_hardening/audit_access` thành root riêng, ví dụ:

```text
infra/live/iam/mandate-12/audit_access/
```

Tạo `backend.hcl` với state key riêng rồi chạy `terraform init -backend-config=backend.hcl`. Điền:

- M11/M12 audit bucket/trail ARN;
- ba SNS topic ARNs: primary M11, global M11 và heartbeat-fallback;
- tối thiểu 9 rule ARNs: primary `g1/g4/g5/g6/g7`, global `g2/g3/g8`, heartbeat schedule;
- đúng 3 Lambda, 3 log groups và 2 heartbeat alarm ARNs;
- named MFA security-owner IAM user trong account `197826770971`.

Plan chỉ được tạo audit-admin, break-glass và assume policies. Sau apply, lấy output `security_owner_assume_audit_policy_arn`; root đang sở hữu named user phải gắn policy này vào đúng user bằng một saved plan/change riêng được review. Không attach tay nếu user thuộc Terraform state khác. Chỉ test assume/read sau khi user có MFA và policy đã gắn; break-glass không dùng daily ops.

## 4. Lấy input và render boundary bằng Terraform

Không sửa JSON template tay. `iam_change/main.tf` tạo managed boundary từ các tập ARN có validation. Lấy exact input sau foundation apply bằng Terraform outputs và các lệnh read-only:

```powershell
aws events list-rules --name-prefix techx-corp-tf3-audit-detection --region ap-southeast-1 --query "Rules[].Arn"
aws events list-rules --name-prefix techx-corp-tf3-audit-detection --region us-east-1 --query "Rules[].Arn"
aws events describe-rule --name techx-corp-tf3-m12-audit-heartbeat-schedule --region ap-southeast-1 --query Arn
aws lambda list-functions --region ap-southeast-1 --query "Functions[?contains(FunctionName, 'audit')].[FunctionName,FunctionArn]"
aws lambda list-functions --region us-east-1 --query "Functions[?contains(FunctionName, 'audit')].[FunctionName,FunctionArn]"
aws logs describe-log-groups --log-group-name-prefix /aws/lambda/techx-corp-tf3 --region ap-southeast-1 --query "logGroups[].arn"
aws logs describe-log-groups --log-group-name-prefix /aws/lambda/techx-corp-tf3 --region us-east-1 --query "logGroups[].arn"
aws cloudwatch describe-alarms --alarm-name-prefix techx-corp-tf3-m12-audit-heartbeat --region ap-southeast-1 --query "MetricAlarms[].AlarmArn"
aws sns list-subscriptions-by-topic --topic-arn "<primary-topic>" --region ap-southeast-1
aws sns list-subscriptions-by-topic --topic-arn "<global-topic>" --region us-east-1
aws sns list-subscriptions-by-topic --topic-arn "<heartbeat-fallback-topic>" --region ap-southeast-1
```

Ràng buộc: không dùng `PendingConfirmation`; mỗi topic phải có ít nhất một confirmed subscription ARN; bỏ suffix `:*` khỏi log-group ARN; 3 Lambda phải là primary router, global router, heartbeat; audit roles lấy từ output `audit_access`. `approved_assume_role_arns=[]` là strict default. Chỉ thêm exact non-audit role sau khi review trust/OIDC và chứng minh workload cần assume role đó.

Chạy `terraform fmt/init/validate/plan`; xem JSON policy trong plan. Với target chỉ thuộc owner roots, giữ `enable_iam_change_executor=false`, `target_*=[]`, `trusted_change_owner_arns=[]`: plan chỉ tạo managed boundary. Sau apply, dùng IAM policy validation/Access Analyzer và `simulate-principal-policy`. Audit-control/IAM-escalation actions phải `explicitDeny`; baseline cần thiết phải `allowed`.

## 5. Thay đổi tại đúng owner root

| Principal | Nơi sửa |
|---|---|
| `techx-corp-tf3-gha-terraform-apply/plan` | `infra/bootstrap/github-oidc` |
| `tf3-production-operator/readonly` | `infra/live/production` |
| IAM user/role unmanaged | Import/chuyển ownership hoặc controlled `iam_change` |

Không dùng `iam_change` attach boundary vào role thuộc hai state đầu. Owner root khai báo `permissions_boundary` và policy least-privilege trong code, tạo saved plan và baseline test.

Không attach boundary trực tiếp bằng AWS CLI từ tài khoản hiện tại. Nếu Mandate 5/CD01 đang thay cùng principal, dừng M12 IAM change và nhận input/output chính thức trước để tránh state conflict.

## 6. Dùng executor khi có unmanaged/transferred target

Chỉ cho exact unmanaged/transferred targets:

1. tạo root/backend riêng từ `iam_change/`;
2. điền toàn bộ exact audit resource ARNs, target ARNs và MFA change owners vào `terraform.tfvars` theo file example;
3. đặt `enable_iam_change_executor=true`, giữ `allow_boundary_removal=false`;
4. đặt `target_ownership_confirmed=true` sau signed ownership evidence;
5. plan phải tạo boundary + executor, không được sửa principal ngoài allowlist; review/apply;
6. lấy output `security_owner_assume_iam_change_policy_arn`; root sở hữu named MFA user gắn policy này bằng saved plan/change riêng được review;
7. assume executor short-lived;
8. executor chỉ attach chính `operator_boundary_policy_arn` output vào một identity đã duyệt; baseline, evidence, rồi mới target tiếp.

Người deploy phải assume executor bằng phiên ngắn có MFA và dùng profile/session đó, không dùng credential admin hiện tại. Với từng target đã ký ownership, chạy đúng một lệnh rồi đọc lại trạng thái:

```powershell
$boundaryArn = terraform -chdir=<iam-change-root> output -raw operator_boundary_policy_arn

# Chọn đúng một nhánh:
aws iam put-user-permissions-boundary --user-name "<approved-user>" --permissions-boundary $boundaryArn --profile <mfa-executor-profile>
aws iam get-user --user-name "<approved-user>" --profile <mfa-executor-profile> --query "User.PermissionsBoundary"

aws iam put-role-permissions-boundary --role-name "<approved-role>" --permissions-boundary $boundaryArn --profile <mfa-executor-profile>
aws iam get-role --role-name "<approved-role>" --profile <mfa-executor-profile> --query "Role.PermissionsBoundary"
```

Không chạy cả hai nhánh nếu change chỉ duyệt một target. Với role thuộc `infra/bootstrap/github-oidc` hoặc `infra/live/production`, tuyệt đối không dùng các lệnh trên; owner thêm `permissions_boundary = <operator_boundary_policy_arn>` vào resource code và apply saved plan tại root đó.

## 7. Test bắt buộc

- `StopLogging`, `DeleteTrail`, selector mutation;
- audit bucket policy/lock/lifecycle mutation;
- disable/delete M11/M12 EventBridge rules/targets;
- SNS mutation;
- heartbeat Lambda/schedule/alarm mutation;
- boundary/policy/trust/OIDC escalation.

Mọi request kỳ vọng `AccessDenied`, có CloudTrail event, router/SNS alert và post-state không đổi. Nếu thành công: dừng, Critical incident.

## 8. Chuyển quyền cũ

Chỉ sau baseline/deny tests pass:

1. chuyển daily workflow sang bounded role;
2. theo dõi một window;
3. bỏ `AdministratorAccess`/admin group/direct EKS admin path theo owner plan;
4. giữ named break-glass, không dùng shared account.

## 9. Rollback

Rollback từng identity tại root sở hữu. Với executor, `allow_boundary_removal=true` chỉ trong change riêng/time-boxed, sau đó trả về false. Không dùng root để bypass và không gỡ audit foundation.

---

**Phiên bản:** v2.1
**Cập nhật:** 21/07/2026
**Trạng thái:** HANDOFF READY / EXECUTION BLOCKED — pending foundation health, MFA, full effective-admin inventory và IAM ownership
