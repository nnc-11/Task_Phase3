# Edit Lambda router M11 cho Mandate 12

File đích: `infra/modules/audit-detection/lambda/index.py`.

## 1. Không suppress anti-audit critical event

Thay:

```python
if is_allowed_automation(actor):
```

bằng:

```python
critical_groups = set(CONFIG.get("critical_group_numbers") or [])
if is_allowed_automation(actor) and group not in critical_groups:
```

Sau đó đổi `critical_group_numbers` trong `detector_config` từ `[1, 2, 4]` thành `[1, 2, 3, 4, 7, 8]`. Group 3 chứa các hành động leo thang quyền như attach/put policy, đổi trust policy và đổi default policy version; vì vậy Terraform/admin automation cũng không được phép làm im lặng nhóm này.

Thay tiếp:

```python
if is_suppressed(actor, target):
```

bằng:

```python
if group not in critical_groups and is_suppressed(actor, target):
```

Critical group 1/2/3/4/7/8 không được im lặng bởi suppression window. Approved change vẫn tạo alert/evidence; người trực đối chiếu change ID thay vì tắt cảnh báo.

## 2. Thêm GROUP_MAP

```python
"events:DisableRule": 7,
"events:DeleteRule": 7,
"events:PutRule": 7,
"events:RemoveTargets": 7,
"events:PutTargets": 7,
"sns:AddPermission": 7,
"sns:RemovePermission": 7,
"sns:DeleteTopic": 7,
"sns:SetTopicAttributes": 7,
"sns:Subscribe": 7,
"sns:ConfirmSubscription": 7,
"sns:SetSubscriptionAttributes": 7,
"sns:Unsubscribe": 7,
"lambda:DeleteFunction": 7,
"lambda:UpdateFunctionCode": 7,
"lambda:UpdateFunctionConfiguration": 7,
"lambda:PutFunctionConcurrency": 7,
"lambda:DeleteFunctionConcurrency": 7,
"monitoring:DeleteAlarms": 7,
"monitoring:DisableAlarmActions": 7,
"monitoring:PutMetricAlarm": 7,
"s3:PutBucketPolicy": 7,
"s3:DeleteBucketPolicy": 7,
"s3:PutBucketVersioning": 7,
"s3:PutObjectLockConfiguration": 7,
"s3:PutBucketLifecycleConfiguration": 7,
"s3:DeleteBucketLifecycle": 7,
"s3:PutBucketEncryption": 7,
"s3:DeleteBucketEncryption": 7,
"s3:PutPublicAccessBlock": 7,
"s3:DeletePublicAccessBlock": 7,

"iam:PutUserPermissionsBoundary": 8,
"iam:DeleteUserPermissionsBoundary": 8,
"iam:PutRolePermissionsBoundary": 8,
"iam:DeleteRolePermissionsBoundary": 8,
"iam:DeletePolicy": 8,
"iam:DeletePolicyVersion": 8,
"iam:DeleteUserPolicy": 8,
"iam:DeleteRolePolicy": 8,
"iam:DetachUserPolicy": 8,
"iam:DetachRolePolicy": 8,
"iam:CreateOpenIDConnectProvider": 8,
"iam:DeleteOpenIDConnectProvider": 8,
"iam:UpdateOpenIDConnectProviderThumbprint": 8,
"iam:AddClientIDToOpenIDConnectProvider": 8,
"iam:RemoveClientIDFromOpenIDConnectProvider": 8,
```

Sau edit phải build lại `audit-alert-router.zip` theo quy trình hiện có và review hash trong plan.
