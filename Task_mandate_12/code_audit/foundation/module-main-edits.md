# Các edit bắt buộc trong module M11

File đích: `infra/modules/audit-detection/main.tf`.

## 1. Object Lock

Trong `aws_s3_bucket_object_lock_configuration.trail_logs`, thay:

```hcl
mode = "GOVERNANCE"
days = 14
```

bằng:

```hcl
mode = var.trail_object_lock_mode
days = var.trail_object_lock_days
```

Điều này chỉ đặt default cho object mới. Object đã giao trước cutover giữ retention cũ; Mandate 12 chỉ claim từ timestamp cutover đã ghi evidence.

Trong `aws_s3_bucket_lifecycle_configuration.trail_logs`, thêm lifecycle precondition:

```hcl
lifecycle {
  precondition {
    condition     = var.trail_s3_retention_days > var.trail_object_lock_days
    error_message = "S3 lifecycle retention must be longer than Object Lock retention."
  }
}
```

## 2. CloudTrail selectors

Trong `aws_cloudtrail.audit`, xóa block `event_selector` cũ và thay bằng:

```hcl
advanced_event_selector {
  name = "ManagementReadWrite"

  field_selector {
    field  = "eventCategory"
    equals = ["Management"]
  }
}

dynamic "advanced_event_selector" {
  for_each = length(var.s3_data_event_arns) > 0 ? [true] : []

  content {
    name = "ApprovedSensitiveS3Objects"

    field_selector {
      field  = "eventCategory"
      equals = ["Data"]
    }

    field_selector {
      field  = "resources.type"
      equals = ["AWS::S3::Object"]
    }

    field_selector {
      field       = "resources.ARN"
      starts_with = var.s3_data_event_arns
    }
  }
}
```

Không đưa chính bucket audit vào `s3_data_event_arns`.

## 3. Chặn mutation trực tiếp lên log object

Trong `data.aws_iam_policy_document.trail_logs`, thêm statement sau. CloudTrail vẫn được ghi; user/role kể cả admin không được put/delete/đổi retention trên object archive qua policy hiện hành:

```hcl
statement {
  sid    = "DenyNonCloudTrailObjectMutation"
  effect = "Deny"
  actions = [
    "s3:AbortMultipartUpload",
    "s3:BypassGovernanceRetention",
    "s3:DeleteObject",
    "s3:DeleteObjectTagging",
    "s3:DeleteObjectVersion",
    "s3:PutObject",
    "s3:PutObjectAcl",
    "s3:PutObjectLegalHold",
    "s3:PutObjectRetention",
    "s3:PutObjectTagging",
    "s3:RestoreObject"
  ]
  resources = ["${aws_s3_bucket.trail_logs[0].arn}/*"]

  principals {
    type        = "*"
    identifiers = ["*"]
  }

  condition {
    test     = "StringNotEqualsIfExists"
    variable = "aws:PrincipalServiceName"
    values   = ["cloudtrail.amazonaws.com"]
  }
}
```

## 4. Module call tại production

Trong module `audit_detection_ap_southeast_1`, thêm:

```hcl
trail_object_lock_mode = "COMPLIANCE"
trail_object_lock_days = 365
s3_data_event_arns     = var.audit_detection_s3_data_event_arns
```

Không thêm các input này cho module `us-east-1` vì instance đó không tạo trail.

## 5. Alert rules

Trong `local.audit_detection_regional_event_rules`, thêm group:

```hcl
g7-audit-controls = {
  description = "Group 7: detect mutation of the M11/M12 alert and heartbeat controls."
  sources = [
    "aws.events", "aws.sns", "aws.lambda", "aws.cloudwatch", "aws.s3"
  ]
  event_sources = [
    "events.amazonaws.com", "sns.amazonaws.com", "lambda.amazonaws.com",
    "monitoring.amazonaws.com", "s3.amazonaws.com"
  ]
  event_names = [
    "DisableRule", "DeleteRule", "PutRule", "RemoveTargets", "PutTargets",
    "DeleteTopic", "SetTopicAttributes", "Unsubscribe",
    "DeleteFunction", "UpdateFunctionCode", "UpdateFunctionConfiguration",
    "DeleteAlarms", "DisableAlarmActions", "PutMetricAlarm",
    "PutBucketPolicy", "DeleteBucketPolicy", "PutBucketVersioning",
    "PutObjectLockConfiguration", "PutBucketLifecycleConfiguration",
    "DeleteBucketLifecycle", "DeleteBucketEncryption", "DeletePublicAccessBlock"
  ]
}
```

`lambda-router-edits.md` phải được áp dụng trong cùng PR, nếu không router sẽ nhận rồi bỏ qua group mới.

Trong `local.audit_detection_global_event_rules`, thêm group IAM/OIDC anti-tamper sau. Group này chạy ở `us-east-1` vì IAM là global service:

```hcl
g8-iam-controls = {
  description = "Group 8: detect permissions-boundary, policy and OIDC trust-path tampering."
  sources     = ["aws.iam"]
  event_sources = ["iam.amazonaws.com"]
  event_names = [
    "PutUserPermissionsBoundary", "DeleteUserPermissionsBoundary",
    "PutRolePermissionsBoundary", "DeleteRolePermissionsBoundary",
    "DeletePolicy", "DeletePolicyVersion", "DeleteUserPolicy", "DeleteRolePolicy",
    "DetachUserPolicy", "DetachRolePolicy",
    "CreateOpenIDConnectProvider", "DeleteOpenIDConnectProvider",
    "UpdateOpenIDConnectProviderThumbprint",
    "AddClientIDToOpenIDConnectProvider", "RemoveClientIDFromOpenIDConnectProvider"
  ]
}
```

Sau thay đổi phải có tối thiểu 9 rule được bảo vệ: primary `g1/g4/g5/g6/g7`, global `g2/g3/g8` và heartbeat schedule.

## 6. Terraform destroy guard

Thêm `lifecycle { prevent_destroy = true }` vào `aws_s3_bucket.trail_logs` và `aws_cloudtrail.audit`. Guard này không thay IAM hardening/Object Lock nhưng chặn plan vô tình replace/delete hai resource nguồn bằng chứng.
