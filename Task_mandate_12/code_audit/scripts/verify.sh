#!/usr/bin/env bash
set -euo pipefail

required=(AWS_REGION TF3_ACCOUNT_ID TRAIL_ARN AUDIT_BUCKET)
for name in "${required[@]}"; do
  if [[ -z "${!name:-}" || "${!name}" == *"<"* ]]; then
    echo "FAIL: $name is missing or still a placeholder" >&2
    exit 1
  fi
done

echo "== Caller =="
aws sts get-caller-identity

echo "== Trail status =="
aws cloudtrail get-trail-status --name "$TRAIL_ARN" --region "$AWS_REGION"

echo "== Event selectors =="
aws cloudtrail get-event-selectors --trail-name "$TRAIL_ARN" --region "$AWS_REGION"

echo "== Archive controls =="
aws s3api get-bucket-versioning --bucket "$AUDIT_BUCKET"
aws s3api get-object-lock-configuration --bucket "$AUDIT_BUCKET"
aws s3api get-public-access-block --bucket "$AUDIT_BUCKET"
aws s3api get-bucket-encryption --bucket "$AUDIT_BUCKET"

echo "PASS: configuration queries completed. Review output for IsLogging, delivery errors, selectors and COMPLIANCE retention."
echo "NOTE: validate-logs must wait until the requested UTC window is covered by delivered digest files."

