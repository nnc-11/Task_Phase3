# Mandate 12 IAM hardening v2.0.
# Heartbeat must fail if either GitHub Terraform role loses this exact boundary.
# GitLab, human users and AIOps identities are intentionally outside this rollout.
audit_detection_bounded_principals = {
  "arn:aws:iam::197826770971:role/techx-corp-tf3-gha-terraform-plan"  = "arn:aws:iam::197826770971:policy/techx-corp-tf3-ci-audit-boundary"
  "arn:aws:iam::197826770971:role/techx-corp-tf3-gha-terraform-apply" = "arn:aws:iam::197826770971:policy/techx-corp-tf3-ci-audit-boundary"
}
