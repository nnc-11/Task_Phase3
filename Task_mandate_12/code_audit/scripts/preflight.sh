#!/usr/bin/env bash
set -euo pipefail

required=(AWS_REGION TF3_ACCOUNT_ID ORGANIZATION_ID MANAGEMENT_ACCOUNT_ID LOG_ARCHIVE_ACCOUNT_ID TRAIL_NAME AUDIT_BUCKET)
for name in "${required[@]}"; do
  if [[ -z "${!name:-}" || "${!name}" == *"<"* ]]; then
    echo "FAIL: $name is missing or still a placeholder" >&2
    exit 1
  fi
done

command -v aws >/dev/null || { echo "FAIL: aws CLI not found" >&2; exit 1; }
command -v terraform >/dev/null || { echo "FAIL: terraform not found" >&2; exit 1; }

caller_account="$(aws sts get-caller-identity --query Account --output text)"
echo "Caller account: $caller_account"
echo "Expected management account for organization root: $MANAGEMENT_ACCOUNT_ID"
echo "Expected log archive account for archive root: $LOG_ARCHIVE_ACCOUNT_ID"

aws organizations describe-organization \
  --query 'Organization.{Id:Id,ManagementAccountId:ManagementAccountId,FeatureSet:FeatureSet}' \
  --output table

terraform version
aws --version

echo "PASS: read-only preflight completed. Manually confirm caller matches the root you are about to plan."

