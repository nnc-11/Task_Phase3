# Mandate 12 — CI permissions boundary v2.
#
# Mục tiêu:
# - production CI không sửa Audit Foundation;
# - production CI không tạo/sửa IAM để tự mở đường vượt boundary;
# - read/refresh và non-IAM workload deployment vẫn được phép theo identity policy;
# - GitLab/human identities không được attach tự động trong rollout này.

locals {
  m12_account_id = data.aws_caller_identity.current.account_id

  m12_trail_arns = [
    "arn:aws:cloudtrail:*:${local.m12_account_id}:trail/${var.cluster_name}-audit-detection-*",
  ]

  m12_archive_bucket_arns = [
    "arn:aws:s3:::${var.cluster_name}-audit-trail-*",
  ]

  m12_archive_object_arns = [
    "arn:aws:s3:::${var.cluster_name}-audit-trail-*/*",
  ]

  m12_rule_arns = [
    "arn:aws:events:*:${local.m12_account_id}:rule/${var.cluster_name}-audit-detection-*",
    "arn:aws:events:*:${local.m12_account_id}:rule/${var.cluster_name}-m12-audit-heartbeat-*",
  ]

  m12_topic_arns = [
    "arn:aws:sns:*:${local.m12_account_id}:${var.cluster_name}-audit-detection-*",
    "arn:aws:sns:*:${local.m12_account_id}:${var.cluster_name}-m12-audit-heartbeat-*",
  ]

  m12_queue_arns = [
    "arn:aws:sqs:*:${local.m12_account_id}:${var.cluster_name}-audit-detection-*",
  ]

  m12_function_arns = [
    "arn:aws:lambda:*:${local.m12_account_id}:function:${var.cluster_name}-audit-detection-*",
    "arn:aws:lambda:*:${local.m12_account_id}:function:${var.cluster_name}-m12-audit-heartbeat*",
  ]

  m12_log_group_arns = [
    "arn:aws:logs:*:${local.m12_account_id}:log-group:/aws/lambda/${var.cluster_name}-audit-detection-*",
    "arn:aws:logs:*:${local.m12_account_id}:log-group:/aws/lambda/${var.cluster_name}-m12-audit-heartbeat*",
  ]

  m12_alarm_arns = [
    "arn:aws:cloudwatch:*:${local.m12_account_id}:alarm:${var.cluster_name}-m12-audit-heartbeat-*",
  ]

  m12_kms_key_arns = [
    "arn:aws:kms:*:${local.m12_account_id}:key/*",
  ]

  m12_kms_alias_names = [
    "alias/${var.cluster_name}-audit-detection-*",
    "alias/${var.cluster_name}-m12-audit-heartbeat-*",
  ]

  m12_kms_alias_arns = [
    "arn:aws:kms:*:${local.m12_account_id}:alias/${var.cluster_name}-audit-detection-*",
    "arn:aws:kms:*:${local.m12_account_id}:alias/${var.cluster_name}-m12-audit-heartbeat-*",
  ]

  m12_ci_boundary_policy_arn = "arn:aws:iam::${local.m12_account_id}:policy/${var.ci_audit_boundary_name}"

  m12_ci_role_arns = [
    "arn:aws:iam::${local.m12_account_id}:role/${var.cluster_name}-gha-terraform-plan",
    "arn:aws:iam::${local.m12_account_id}:role/${var.cluster_name}-gha-terraform-apply",
  ]

  m12_bounded_principal_arns = concat(
    local.m12_ci_role_arns,
    var.additional_bounded_principal_arns,
  )

  # PassRole không bị chặn cho service role TF3 hiện hữu để non-IAM workload
  # deployment không hỏng. CI không thể tạo/sửa role vì IAM write bị deny.
  m12_approved_pass_role_arns = [
    "arn:aws:iam::${local.m12_account_id}:role/${var.cluster_name}-*",
    "arn:aws:iam::${local.m12_account_id}:role/KarpenterNodeRole-${var.cluster_name}",
  ]
}

data "aws_iam_policy_document" "ci_audit_boundary" {
  statement {
    sid       = "AllowWithinBoundary"
    effect    = "Allow"
    actions   = ["*"]
    resources = ["*"]
  }

  statement {
    sid    = "DenyAuditTrailMutation"
    effect = "Deny"
    actions = [
      "cloudtrail:AddTags",
      "cloudtrail:CreateTrail",
      "cloudtrail:DeleteTrail",
      "cloudtrail:PutEventSelectors",
      "cloudtrail:PutInsightSelectors",
      "cloudtrail:RemoveTags",
      "cloudtrail:StartLogging",
      "cloudtrail:StopLogging",
      "cloudtrail:UpdateTrail",
    ]
    resources = local.m12_trail_arns
  }

  statement {
    sid    = "DenyAuditArchiveControlMutation"
    effect = "Deny"
    actions = [
      "s3:DeleteBucket",
      "s3:DeleteBucketPolicy",
      "s3:PutBucketObjectLockConfiguration",
      "s3:PutBucketPolicy",
      "s3:PutBucketPublicAccessBlock",
      "s3:PutBucketVersioning",
      "s3:PutEncryptionConfiguration",
      "s3:PutLifecycleConfiguration",
    ]
    resources = local.m12_archive_bucket_arns
  }

  statement {
    sid    = "DenyAuditArchiveObjectMutation"
    effect = "Deny"
    actions = [
      "s3:AbortMultipartUpload",
      "s3:BypassGovernanceRetention",
      "s3:DeleteObject",
      "s3:DeleteObjectTagging",
      "s3:DeleteObjectVersion",
      "s3:DeleteObjectVersionTagging",
      "s3:PutObject",
      "s3:PutObjectAcl",
      "s3:PutObjectLegalHold",
      "s3:PutObjectRetention",
      "s3:PutObjectTagging",
      "s3:PutObjectVersionAcl",
      "s3:RestoreObject",
    ]
    resources = local.m12_archive_object_arns
  }

  # kms:ResourceAliases là condition theo resource, nên vẫn match khi request dùng
  # key ID/ARN thay vì alias.
  statement {
    sid    = "DenyAuditKmsKeyMutation"
    effect = "Deny"
    actions = [
      "kms:CancelKeyDeletion",
      "kms:CreateGrant",
      "kms:DisableKey",
      "kms:DisableKeyRotation",
      "kms:EnableKey",
      "kms:EnableKeyRotation",
      "kms:PutKeyPolicy",
      "kms:RevokeGrant",
      "kms:ScheduleKeyDeletion",
      "kms:TagResource",
      "kms:UntagResource",
      "kms:UpdateKeyDescription",
    ]
    resources = local.m12_kms_key_arns

    condition {
      test     = "ForAnyValue:StringLike"
      variable = "kms:ResourceAliases"
      values   = local.m12_kms_alias_names
    }
  }

  statement {
    sid    = "DenyAuditKmsAliasMutation"
    effect = "Deny"
    actions = [
      "kms:DeleteAlias",
      "kms:UpdateAlias",
    ]
    resources = local.m12_kms_alias_arns
  }

  statement {
    sid    = "DenyAuditRuleMutation"
    effect = "Deny"
    actions = [
      "events:DeleteRule",
      "events:DisableRule",
      "events:PutRule",
      "events:PutTargets",
      "events:RemoveTargets",
    ]
    resources = local.m12_rule_arns
  }

  statement {
    sid    = "DenyAuditTopicMutation"
    effect = "Deny"
    actions = [
      "sns:AddPermission",
      "sns:DeleteTopic",
      "sns:RemovePermission",
      "sns:SetTopicAttributes",
    ]
    resources = local.m12_topic_arns
  }

  statement {
    sid    = "DenyAuditQueueMutation"
    effect = "Deny"
    actions = [
      "sqs:AddPermission",
      "sqs:DeleteQueue",
      "sqs:PurgeQueue",
      "sqs:RemovePermission",
      "sqs:SetQueueAttributes",
    ]
    resources = local.m12_queue_arns
  }

  # SNS subscription actions không support exact subscription ARN trong IAM
  # simulator của account này; Resource theo topic không tạo explicitDeny.
  # Deny "*" chỉ áp vào hai GHA role mang boundary. Repo hiện chỉ quản subscription
  # audit; GitLab/human/AIOps không attach boundary trong rollout v2.0.
  statement {
    sid    = "DenySubscriptionTeardownForBoundedCi"
    effect = "Deny"
    actions = [
      "sns:SetSubscriptionAttributes",
      "sns:Unsubscribe",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "DenyAuditFunctionMutation"
    effect = "Deny"
    actions = [
      "lambda:DeleteFunction",
      "lambda:DeleteFunctionConcurrency",
      "lambda:PutFunctionConcurrency",
      "lambda:RemovePermission",
      "lambda:UpdateFunctionCode",
      "lambda:UpdateFunctionConfiguration",
    ]
    resources = local.m12_function_arns
  }

  statement {
    sid    = "DenyAuditLogMutation"
    effect = "Deny"
    actions = [
      "logs:DeleteLogGroup",
      "logs:DeleteLogStream",
      "logs:DeleteRetentionPolicy",
      "logs:PutRetentionPolicy",
    ]
    resources = local.m12_log_group_arns
  }

  statement {
    sid    = "DenyHeartbeatAlarmMutation"
    effect = "Deny"
    actions = [
      "cloudwatch:DeleteAlarms",
      "cloudwatch:DisableAlarmActions",
      "cloudwatch:EnableAlarmActions",
      "cloudwatch:PutMetricAlarm",
      "cloudwatch:SetAlarmState",
    ]
    resources = local.m12_alarm_arns
  }

  # Production apply CI không quản IAM. IAM change phải đi qua bootstrap/IAM
  # workflow riêng có security review. Đây cũng đóng đường CreateRole -> external trust.
  statement {
    sid    = "DenyIamWriteFromProductionCi"
    effect = "Deny"
    actions = [
      "iam:Add*",
      "iam:Attach*",
      "iam:ChangePassword",
      "iam:Create*",
      "iam:Deactivate*",
      "iam:Delete*",
      "iam:Detach*",
      "iam:Enable*",
      "iam:Put*",
      "iam:Remove*",
      "iam:ResetServiceSpecificCredential",
      "iam:ResyncMFADevice",
      "iam:SetDefaultPolicyVersion",
      "iam:Tag*",
      "iam:Untag*",
      "iam:Update*",
      "iam:Upload*",
    ]
    resources = ["*"]
  }

  statement {
    sid           = "DenyPassRoleOutsideApprovedTf3Roles"
    effect        = "Deny"
    actions       = ["iam:PassRole"]
    not_resources = local.m12_approved_pass_role_arns
  }

  # Không chặn AssumeRoleWithWebIdentity dùng để tạo chính session GHA.
  statement {
    sid    = "DenyCredentialAndRoleChaining"
    effect = "Deny"
    actions = [
      "sts:AssumeRole",
      "sts:GetFederationToken",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "ci_audit_boundary" {
  name        = var.ci_audit_boundary_name
  description = "Mandate 12 v2: isolate production CI from IAM writes and audit-plane mutation."
  policy      = data.aws_iam_policy_document.ci_audit_boundary.json

  lifecycle {
    prevent_destroy = true
  }
}

output "ci_audit_boundary_policy_arn" {
  value = aws_iam_policy.ci_audit_boundary.arn
}

output "ci_audit_boundary_attached" {
  value = var.enable_ci_audit_boundary
}

output "ci_audit_boundary_expected_map" {
  value = {
    for arn in local.m12_bounded_principal_arns :
    arn => aws_iam_policy.ci_audit_boundary.arn
  }
}
