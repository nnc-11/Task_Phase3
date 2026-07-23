# IAM hardening v2.0 — Mandate 12

Gói bàn giao này được dựng từ:

- remote `main` commit `3c8ebd3953c2e017b2176aced2df058c42a92a8b`;
- AWS account `197826770971`, inventory chỉ đọc ngày 23/07/2026;
- Audit Foundation đã deploy một phần.

Đội deploy bắt đầu tại `DEPLOY_MAPPING.md`, sau đó làm lần lượt theo
`HD_deploy.md`; không copy toàn bộ package vào repo product.

## Phạm vi của v2.0

1. Siết `techx-corp-tf3-gha-terraform-apply` bằng permissions boundary.
2. Chặn CI production sửa IAM và các kill switch của Audit Foundation.
3. Thêm PR-time plan riêng cho Terraform root `infra/bootstrap/github-oidc`.
4. Chặn workflow production thông thường apply IAM hoặc Audit Foundation diff
   ngoài quy trình riêng.
5. Theo dõi boundary bằng heartbeat sau khi Foundation hoàn tất.

## Không nằm trong rollout tự động

- Không attach boundary vào `gitlab-ci-deployer`.
- Không thay đổi group `AIO2-Admin`, user AIOps hoặc access key.
- Không sửa `tf3-production-operator/readonly`.
- Không thay đổi RDS, EKS workload, VPC hoặc application traffic.
- Không dùng root account để deploy.

Những identity trên chỉ được migrate sau khi có owner, baseline, MFA và change riêng.

## Nội dung

| File/thư mục | Tác dụng |
|---|---|
| `DEPLOY_MAPPING.md` | Bảng source → destination, phase và diff được phép |
| `LIVE_BASELINE.md` | Hiện trạng repo và AWS live đã kiểm tra |
| `HD_deploy.md` | Runbook bàn giao, gate GO/NO-GO và rollback |
| `repo_overlay/infra/bootstrap/github-oidc/ci-audit-boundary.tf` | File thay thế boundary hiện tại |
| `repo_overlay/.github/workflows/terraform-bootstrap-plan.yml` | Plan riêng cho bootstrap IAM root |
| `repo_overlay/scripts/ci/m12-terraform-scope-gate.py` | Chặn diff xung đột với boundary trong workflow thường |
| `repo_overlay/infra/live/production/m12-iam-hardening.auto.tfvars` | Exact heartbeat map, chỉ copy ở pre-attach |
| `patches/` | Các chỉnh sửa nhỏ phải merge vào file hiện hữu |
| `scripts/preflight-readonly.ps1` | Inventory/gate chỉ đọc |
| `scripts/verify-boundary-readonly.ps1` | Kiểm tra policy và simulation, không attach |
| `scripts/check-repo-compatibility.ps1` | Xác minh package đã map đúng repo, không ghi |
| `tests/` | Test runner/fixture: workload và data-read qua; IAM/audit/SNS subscription bị chặn |

## Trạng thái

`HANDOFF READY / DEPLOY NO-GO`

Chỉ chuyển sang `GO` khi toàn bộ precondition trong `HD_deploy.md` đạt, đặc biệt:

- heartbeat Lambda, target và alarms tồn tại/healthy;
- Object Lock/lifecycle đã được nâng lên retention được phê duyệt (`365/400`
  theo phương án Mandate 12 hiện tại), không còn live `14/30`;
- Audit Foundation đã ghi được IAM events;
- có named deployment identity đã bật MFA;
- bootstrap plan từ đúng commit được review;
- production workflow đã cài gate trước upload/apply;
- workflow/gate/audit paths đã có CODEOWNERS và review control độc lập;
- heartbeat map theo dõi exact boundary trên hai GHA role;
- đã chốt maintenance path riêng cho Audit Foundation;
- IAM rollout hiện hữu như `pm127-kyverno-ecr` đã hoàn tất hoặc được tách khỏi
  workflow production thường;
- owner GitHub/IaC phê duyệt rollout.

`HANDOFF READY` không có nghĩa live đã đạt Mandate 12. Gói này chỉ sẵn để đội
deploy đưa vào change review; live chỉ đạt khi Definition of Done trong
`HD_deploy.md` đã được chứng minh.
