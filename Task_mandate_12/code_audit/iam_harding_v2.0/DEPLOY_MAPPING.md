# Mapping bàn giao IAM hardening v2.0

## 1. Nguồn và đích

| Nguồn trong gói v2.0 | Đích trong repo product | Cách dùng | Phase |
|---|---|---|---|
| `repo_overlay/infra/bootstrap/github-oidc/ci-audit-boundary.tf` | `infra/bootstrap/github-oidc/ci-audit-boundary.tf` | Thay toàn bộ file v1 đang có | Bootstrap seed |
| `repo_overlay/.github/workflows/terraform-bootstrap-plan.yml` | `.github/workflows/terraform-bootstrap-plan.yml` | File mới | CI guard |
| `repo_overlay/scripts/ci/m12-terraform-scope-gate.py` | `scripts/ci/m12-terraform-scope-gate.py` | File mới | CI guard |
| `repo_overlay/infra/live/production/m12-iam-hardening.auto.tfvars` | `infra/live/production/m12-iam-hardening.auto.tfvars` | File mới, exact map hai GHA role | Pre-attach |
| `patches/bootstrap-main.md` | `infra/bootstrap/github-oidc/main.tf` | Merge đúng hunk, không overwrite file | Bootstrap seed |
| `patches/bootstrap-variables.md` | `infra/bootstrap/github-oidc/variables.tf` | Merge đúng hunk, default boundary vẫn `false` | Bootstrap seed |
| `patches/bootstrap-readme.md` | `infra/bootstrap/github-oidc/README.md` | Thay phần Mandate 12 cũ | Bootstrap seed |
| `patches/codeowners.md` | `.github/CODEOWNERS` + GitHub ruleset/environment | Thay placeholder bằng owner thật | Bootstrap seed |
| `patches/production-workflow.md` | `.github/workflows/terraform-apply.yml` | Thêm gate sau saved plan, trước upload | CI guard |
| `patches/heartbeat-boundaries.md` | Comment trong `infra/live/production/m12-variables.tf` | Sửa mô tả scope, không đổi runtime | Pre-attach |
| `patches/bootstrap-enable-boundary.md` | `infra/bootstrap/github-oidc/variables.tf` | Đổi tracked default `false` → `true` | Attach |

## 2. File không copy vào repo product

| File | Cách dùng |
|---|---|
| `scripts/preflight-readonly.ps1` | Chạy từ máy deploy; chỉ gọi AWS get/list/describe |
| `scripts/verify-boundary-readonly.ps1` | Chạy từ máy deploy để simulation; không attach |
| `scripts/check-repo-compatibility.ps1` | Kiểm tra anchor/hash mapping trên repo; chỉ đọc |
| `tests/` | Test runner/fixture kiểm thử scope gate, không deploy |
| `LIVE_BASELINE.md` | Baseline tham chiếu; phải discovery lại nếu deploy sau ngày 23/07/2026 |

Không copy state, `.terraform`, plan, credential hoặc output chưa redaction vào Git.

## 3. Thứ tự state bắt buộc

```text
Foundation dependency
  -> bootstrap seed: state-read + boundary v2 create (enable=false)
  -> CI guard: bootstrap plan workflow + production scope gate
  -> PreAttach simulation
  -> production heartbeat boundary map
  -> bootstrap boundary attach (enable=true trong code)
  -> PostAttach verification
```

- Bootstrap root: `infra/bootstrap/github-oidc`
- Bootstrap state: `bootstrap/github-oidc/terraform.tfstate`
- Production/Foundation root: `infra/live/production`
- Production state: `eks-baseline/terraform.tfstate`

Không đưa resource của root này sang state kia. Không chạy hai apply đồng thời.

## 4. Diff được phép theo phase

| Phase | Diff AWS được phép |
|---|---|
| Bootstrap seed | Chỉ update inline policy của GHA plan role và create managed boundary v2; hai GHA role vẫn boundary `null` |
| CI guard | Chỉ Git/workflow/script; bootstrap plan phải không còn AWS diff |
| Pre-attach heartbeat | Chỉ update heartbeat configuration với exact map hai GHA role |
| Attach | Chỉ update in-place permissions boundary của hai GHA role |
| Rollback attach | Bootstrap plan chỉ detach hai GHA role; production plan riêng chỉ đưa heartbeat map về `{}`; không xóa policy/foundation |

Có diff ngoài hàng tương ứng: `NO-GO`.

## 5. Điều kiện bàn giao

Đội deploy đọc theo thứ tự:

1. `DEPLOY_MAPPING.md`;
2. `HD_deploy.md`;
3. chạy `check-repo-compatibility.ps1 -Stage Baseline` trước khi copy;
4. từng file trong `patches/` đúng phase;
5. chạy lại compatibility ở `Seed`, `Guarded` (sau CI guard) và `Attach`;
6. chạy preflight/simulation read-only và lưu evidence đã redaction.

Không suy luận giá trị owner, MFA identity, retention approval hoặc GitHub
reviewer. Đây là input phải được người có thẩm quyền cung cấp.
