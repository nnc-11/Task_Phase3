# Tạo/patch `.github/CODEOWNERS`

Remote `main` tại baseline chưa có `.github/CODEOWNERS`. Trước rollout, GitHub
owner phải thay `<SECURITY_OWNER>` và `<PLATFORM_OWNER>` bằng user/team thật rồi
tạo file:

```text
/.github/workflows/terraform-apply.yml                   <SECURITY_OWNER> <PLATFORM_OWNER>
/.github/workflows/terraform-bootstrap-plan.yml          <SECURITY_OWNER> <PLATFORM_OWNER>
/scripts/ci/m12-terraform-scope-gate.py                  <SECURITY_OWNER> <PLATFORM_OWNER>
/infra/bootstrap/github-oidc/                            <SECURITY_OWNER> <PLATFORM_OWNER>
/infra/live/production/audit-detection.tf                <SECURITY_OWNER> <PLATFORM_OWNER>
/infra/live/production/audit-heartbeat.tf                <SECURITY_OWNER> <PLATFORM_OWNER>
/infra/live/production/m12-variables.tf                  <SECURITY_OWNER> <PLATFORM_OWNER>
/infra/live/production/m12-iam-hardening.auto.tfvars     <SECURITY_OWNER> <PLATFORM_OWNER>
/infra/modules/audit-detection/                           <SECURITY_OWNER> <PLATFORM_OWNER>
```

Không commit placeholder.

Branch/ruleset của `main` phải:

- bắt buộc pull request;
- bắt buộc code-owner review từ người không phải tác giả;
- không cho force push/delete;
- yêu cầu các plan/gate status check tương ứng;
- GitHub Environment `production` có reviewer độc lập.

Nếu plan GitHub hiện tại không hỗ trợ một control nào, owner phải ghi compensating
control cụ thể (hai người review + lưu plan/hash/change ID) trước khi `GO`; không
được tự coi như control đã tồn tại.
