locals {
  target_identity_arns      = concat(tolist(var.target_user_arns), tolist(var.target_role_arns))
  protected_sns_arns        = concat(tolist(var.alert_topic_arns), tolist(var.alert_subscription_arns))
  protected_audit_role_arns = tolist(var.audit_access_role_arns)
  protected_log_arns        = flatten([for arn in var.audit_log_group_arns : [arn, "${arn}:*"]])
}

data "aws_iam_policy_document" "operator_boundary" {
  statement {
    sid       = "AllowBaselineWithinBoundary"
    effect    = "Allow"
    actions   = ["*"]
    resources = ["*"]
  }

  statement {
    sid       = "DenyProtectedTrailMutation"
    effect    = "Deny"
    actions   = ["cloudtrail:*"]
    resources = [var.audit_trail_arn]
  }

  statement {
    sid       = "DenyAuditArchiveMutation"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [var.audit_bucket_arn, "${var.audit_bucket_arn}/*"]
  }

  statement {
    sid       = "DenyAuditRuleMutation"
    effect    = "Deny"
    actions   = ["events:*"]
    resources = tolist(var.audit_rule_arns)
  }

  statement {
    sid       = "DenyAuditLambdaMutation"
    effect    = "Deny"
    actions   = ["lambda:*"]
    resources = tolist(var.audit_lambda_arns)
  }

  statement {
    sid    = "DenyAuditLogGroupMutation"
    effect = "Deny"
    actions = [
      "logs:DeleteLogGroup",
      "logs:DeleteLogStream",
      "logs:DeleteRetentionPolicy",
      "logs:PutRetentionPolicy"
    ]
    resources = local.protected_log_arns
  }

  statement {
    sid    = "DenyHeartbeatAlarmMutation"
    effect = "Deny"
    actions = [
      "cloudwatch:DeleteAlarms",
      "cloudwatch:DisableAlarmActions",
      "cloudwatch:EnableAlarmActions",
      "cloudwatch:PutMetricAlarm",
      "cloudwatch:SetAlarmState"
    ]
    resources = tolist(var.heartbeat_alarm_arns)
  }

  statement {
    sid       = "DenyAlertPathMutation"
    effect    = "Deny"
    actions   = ["sns:*"]
    resources = local.protected_sns_arns
  }

  statement {
    sid    = "DenyIamPrivilegeAndCredentialMutation"
    effect = "Deny"
    actions = [
      "iam:Add*", "iam:Attach*", "iam:ChangePassword", "iam:Create*",
      "iam:Deactivate*", "iam:Delete*", "iam:Detach*", "iam:Enable*",
      "iam:PassRole", "iam:Put*", "iam:Remove*",
      "iam:ResetServiceSpecificCredential", "iam:ResyncMFADevice",
      "iam:SetDefaultPolicyVersion", "iam:Tag*", "iam:Untag*",
      "iam:Update*", "iam:Upload*"
    ]
    resources = ["*"]
  }

  statement {
    sid       = "DenyInstanceProfileRoleEscalation"
    effect    = "Deny"
    actions   = ["ec2:AssociateIamInstanceProfile", "ec2:ReplaceIamInstanceProfileAssociation"]
    resources = ["*"]
  }

  statement {
    sid       = "DenyProtectedAuditRoleAssumption"
    effect    = "Deny"
    actions   = ["sts:AssumeRole", "sts:AssumeRoleWithSAML", "sts:AssumeRoleWithWebIdentity"]
    resources = local.protected_audit_role_arns
  }

  dynamic "statement" {
    for_each = length(var.approved_assume_role_arns) == 0 ? [true] : []
    content {
      sid       = "DenyAllRoleAssumptionUntilApproved"
      effect    = "Deny"
      actions   = ["sts:AssumeRole", "sts:AssumeRoleWithSAML", "sts:AssumeRoleWithWebIdentity"]
      resources = ["*"]
    }
  }

  dynamic "statement" {
    for_each = length(var.approved_assume_role_arns) > 0 ? [true] : []
    content {
      sid           = "DenyRoleAssumptionExceptReviewedAllowlist"
      effect        = "Deny"
      actions       = ["sts:AssumeRole", "sts:AssumeRoleWithSAML", "sts:AssumeRoleWithWebIdentity"]
      not_resources = tolist(var.approved_assume_role_arns)
    }
  }

  statement {
    sid       = "DenyFederationTokenSessionCreation"
    effect    = "Deny"
    actions   = ["sts:GetFederationToken"]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "operator_boundary" {
  name        = "${var.name_prefix}-operator-boundary"
  description = "Mandate 12 operator permissions boundary protecting audit and privilege paths."
  policy      = data.aws_iam_policy_document.operator_boundary.json

  tags = {
    Project   = "TF3"
    Mandate   = "12"
    Purpose   = "operator-permissions-boundary"
    Protected = "true"
  }

  lifecycle {
    prevent_destroy = true
  }
}

data "aws_iam_policy_document" "iam_change_trust" {
  count = var.enable_iam_change_executor ? 1 : 0
  statement {
    sid     = "AllowMfaProtectedSecurityOwners"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "AWS"
      identifiers = var.trusted_change_owner_arns
    }

    condition {
      test     = "Bool"
      variable = "aws:MultiFactorAuthPresent"
      values   = ["true"]
    }
  }
}

data "aws_iam_policy_document" "iam_change_executor" {
  statement {
    sid = "ReadAndSimulateIamState"
    actions = [
      "iam:GetPolicy", "iam:GetPolicyVersion", "iam:GetRole", "iam:GetUser",
      "iam:ListAttachedRolePolicies", "iam:ListAttachedUserPolicies",
      "iam:ListPolicyVersions", "iam:SimulatePrincipalPolicy"
    ]
    resources = ["*"]
  }

  dynamic "statement" {
    for_each = length(var.target_user_arns) > 0 ? [true] : []
    content {
      sid       = "AttachExactBoundaryToApprovedUsers"
      actions   = ["iam:PutUserPermissionsBoundary"]
      resources = tolist(var.target_user_arns)
      condition {
        test     = "StringEquals"
        variable = "iam:PermissionsBoundary"
        values   = [aws_iam_policy.operator_boundary.arn]
      }
    }
  }

  dynamic "statement" {
    for_each = length(var.target_role_arns) > 0 ? [true] : []
    content {
      sid       = "AttachExactBoundaryToApprovedRoles"
      actions   = ["iam:PutRolePermissionsBoundary"]
      resources = tolist(var.target_role_arns)
      condition {
        test     = "StringEquals"
        variable = "iam:PermissionsBoundary"
        values   = [aws_iam_policy.operator_boundary.arn]
      }
    }
  }

  dynamic "statement" {
    for_each = var.allow_boundary_removal ? [true] : []
    content {
      sid       = "EmergencyRollbackApprovedBoundaries"
      actions   = ["iam:DeleteRolePermissionsBoundary", "iam:DeleteUserPermissionsBoundary"]
      resources = local.target_identity_arns
    }
  }
}

resource "aws_iam_role" "iam_change" {
  count                = var.enable_iam_change_executor ? 1 : 0
  name                 = "${var.name_prefix}-iam-change"
  description          = "Mandate 12 MFA-protected executor for reviewed boundary attachment to exact targets."
  assume_role_policy   = data.aws_iam_policy_document.iam_change_trust[0].json
  max_session_duration = 3600

  tags = {
    Project   = "TF3"
    Mandate   = "12"
    Purpose   = "boundary-change-executor"
    Protected = "true"
  }

  lifecycle {
    precondition {
      condition     = length(local.target_identity_arns) > 0
      error_message = "At least one explicit target user or role ARN is required."
    }
    precondition {
      condition     = length(var.trusted_change_owner_arns) > 0
      error_message = "At least one named MFA-capable change owner is required when the executor is enabled."
    }
    precondition {
      condition     = var.target_ownership_confirmed
      error_message = "IAM target ownership is not confirmed. Update the owning root or complete a reviewed ownership transfer first."
    }
    prevent_destroy = true
  }
}

resource "aws_iam_policy" "iam_change_executor" {
  count       = var.enable_iam_change_executor ? 1 : 0
  name        = "${var.name_prefix}-iam-change-executor"
  description = "Mandate 12 least-privilege policy for attaching the exact rendered boundary."
  policy      = data.aws_iam_policy_document.iam_change_executor.json
  lifecycle { prevent_destroy = true }
}

resource "aws_iam_role_policy_attachment" "iam_change_executor" {
  count      = var.enable_iam_change_executor ? 1 : 0
  role       = aws_iam_role.iam_change[0].name
  policy_arn = aws_iam_policy.iam_change_executor[0].arn
}

data "aws_iam_policy_document" "security_owner_assume_iam_change" {
  count = var.enable_iam_change_executor ? 1 : 0
  statement {
    sid       = "AssumeProtectedIamChangeExecutor"
    actions   = ["sts:AssumeRole"]
    resources = [aws_iam_role.iam_change[0].arn]
  }
}

resource "aws_iam_policy" "security_owner_assume_iam_change" {
  count       = var.enable_iam_change_executor ? 1 : 0
  name        = "${var.name_prefix}-security-owner-assume-iam-change"
  description = "Mandate 12 policy allowing approved security owners to assume the IAM change executor."
  policy      = data.aws_iam_policy_document.security_owner_assume_iam_change[0].json
  lifecycle { prevent_destroy = true }
}
