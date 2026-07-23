# Live baseline — 23/07/2026

## 1. Nguồn đối chiếu

- AWS account: `197826770971`
- Region chính: `ap-southeast-1`
- Remote `main`: `3c8ebd3953c2e017b2176aced2df058c42a92a8b`
- Local product repo không được dùng làm nguồn cuối vì đang chậm hơn remote.

Không ghi access-key ID, secret hoặc session token vào tài liệu.

## 2. Audit Foundation live

| Thành phần | Trạng thái |
|---|---|
| CloudTrail | `techx-corp-tf3-audit-detection-ap-southeast-1-trail`, đang logging |
| Log integrity validation | Bật |
| Multi-region trail | Bật |
| S3 data events | Exact bucket `techx-tf3-197826770971-tfstate/` |
| Audit bucket | `techx-corp-tf3-audit-trail-ap-southeast-1-197826770971` |
| Object Lock | `COMPLIANCE 14 ngày` |
| Lifecycle | Xóa current/noncurrent version sau `30 ngày` |
| Regional router | Tồn tại |
| Global router | Tồn tại |
| Regional rules | `g1`, `g4`, `g5`, `g6`, `g7` đang enabled |
| Global rules | `g2`, `g3`, `g8` đang enabled |
| Heartbeat schedule | Tồn tại, `rate(5 minutes)` |
| Heartbeat schedule target | **Không có target** |
| Heartbeat Lambda | **Không tồn tại** |
| Heartbeat alarms | **Không tồn tại** |
| SNS | Primary, global và fallback tồn tại |
| Heartbeat boundary map | Rỗng (`audit_detection_bounded_principals = {}`) |

Kết luận: Foundation mới deploy một phần. Không attach IAM boundary trước khi heartbeat được hoàn tất và PASS, vì khi rollout IAM lỗi sẽ thiếu đường giám sát độc lập.

## 3. IAM live

| Identity/control | Trạng thái |
|---|---|
| `techx-corp-tf3-gha-terraform-plan` | `ReadOnlyAccess`, không boundary |
| `techx-corp-tf3-gha-terraform-apply` | `AdministratorAccess`, không boundary |
| CI boundary managed policy | Chưa tồn tại live |
| `gitlab-ci-deployer` | Direct admin, không MFA, 2 active long-lived keys, không boundary |
| `tf3-production-operator` | `ViewOnlyAccess`, không boundary |
| `tf3-production-readonly` | EKS/SSM tunnel read path |
| Direct admin users | 3 user |
| Admin group | `AIO2-Admin`, 6 user |
| Named IAM-user MFA | Không có user được xác nhận có MFA |
| Account/root MFA | Bật |
| Root access key | Không có |

`gitlab-ci-deployer`, `AIO2-Admin` và các human admin không được thay đổi trong rollout này. Đó là change owner-led riêng.

## 4. Terraform ownership

| Resource | Root/state owner |
|---|---|
| GHA plan/apply roles | `infra/bootstrap/github-oidc` |
| Bootstrap state | `bootstrap/github-oidc/terraform.tfstate` |
| Production/Audit Foundation | `infra/live/production` |
| Production state | `eks-baseline/terraform.tfstate` |
| Lock table | `techx-tf3-terraform-lock`, `ACTIVE` |
| Production apply workflow | Còn scope IAM `pm127-kyverno-ecr` |
| `.github/CODEOWNERS` | Chưa tồn tại tại baseline |

Không attach boundary out-of-band vào GHA roles. Boundary phải được khai báo và apply tại root `infra/bootstrap/github-oidc`.
