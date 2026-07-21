# Mandate 12 — IAM scope v2

## 1. Nguyên tắc ownership

Permissions boundary phải được khai báo tại Terraform root đang sở hữu principal. Không attach out-of-band rồi để root cũ gỡ lại do drift.

## 2. Inventory repo và AWS live

| Principal | Repo owner | Hiện trạng repo | Hướng xử lý |
|---|---|---|---|
| `techx-corp-tf3-gha-terraform-apply` | `infra/bootstrap/github-oidc` | Live: `AdministratorAccess`, không permissions boundary | CD01/IaC owner thay policy/boundary tại root này; baseline plan/apply |
| `techx-corp-tf3-gha-terraform-plan` | `infra/bootstrap/github-oidc` | `ReadOnlyAccess` + state lock/read | Giữ read-only; kiểm tra không có escalation path |
| `tf3-production-operator` | `infra/live/production` | Live: role tồn tại, không permissions boundary; repo cho four named users assume | Không coi là AWS admin; boundary nếu cần phải thêm tại production root |
| `tf3-production-readonly` | `infra/live/production` | Read EKS/SSM tunnel | Giữ read-only; verify trust/owner |
| `cdo-2-admin-team` | production tfvars + live IAM | Live: member group `AIO2-Admin`; group có `AdministratorAccess`; user không có MFA device | **Blocker:** bật MFA/chuyển sang approved role; migrate sau khi operator path pass |
| IAM user `gitlab-ci-deployer` | ngoài repo ownership rõ ràng; tên xuất hiện trong M11 allowlist | Live: direct `AdministratorAccess`, không MFA, 2 active access keys; role cùng tên không tồn tại | **Critical:** không cho allowlist suppress anti-audit; owner phải migrate sang OIDC role và thu hồi key theo change riêng |
| IAM users `cdo02testaudit`, `hieu-AdminAccess` | chưa rõ owner/state | Live: direct `AdministratorAccess`; cả hai không MFA; `hieu-AdminAccess` có 2 active keys | Đưa vào effective-admin migration; không tự sửa trước owner approval |
| M12 audit-admin/break-glass/iam-change | M12 state riêng | Chưa deploy | Named MFA owners, không dùng daily ops |
| Root | ngoài boundary | Account summary live có `AccountMFAEnabled=1`; root không thể bị permissions boundary | Xác nhận no access key/custodian + signed residual acceptance; không dùng root deploy |

Live `list-entities-for-policy` cho thấy `AdministratorAccess` gắn vào 1 group, 3 users trực tiếp và 1 role. Group `AIO2-Admin` có 6 users. Account có 15 users, 1 group, 48 roles, chỉ 1 MFA device in use; root/account MFA bật và không có root access key. Vẫn phải map owner/workflow và cả inline/custom-policy escalation trước khi gọi full effective-admin inventory complete.

## 3. Input còn phải hoàn tất

Với từng user/role/group/OIDC: exact ARN, attached/inline policies, permissions boundary, trust policy, owner, workflow, last-used/credential metadata và assume-role chain. Không lưu access key/secret/session token.

## 4. Thứ tự migration

1. Foundation M12 healthy và heartbeat PASS.
2. Tạo audit-admin/break-glass read/recovery roles.
3. CD01/IaC owner sửa GitHub apply role trong `infra/bootstrap/github-oidc` bằng PR riêng.
4. Test plan/apply baseline; không chạy apply production chỉ để test.
5. Owner production sửa role thuộc `infra/live/production` nếu boundary được yêu cầu.
6. Với IAM identity không có Terraform owner: import/chuyển ownership, hoặc dùng `iam_change` sau khi `target_ownership_confirmed=true`.
7. Migrate từng user/admin group; cuối cùng mới bỏ đường admin trực tiếp.

## 5. Boundary bắt buộc deny

- mutation M12 trail/archive/EventBridge/SNS/heartbeat;
- assume audit-admin/break-glass từ daily identity;
- IAM credential, policy, boundary, trust và privilege-escalation mutation;
- `iam:PassRole` ngoài allowlist đã duyệt;
- role assumption ngoài exact non-audit allowlist.

Boundary không thay thế việc bỏ `AdministratorAccess`; target cuối là policy allow tối thiểu + boundary guardrail.

## 6. Gate theo identity

| Identity | Owner/root | Simulation | Baseline | Rollback | Approval | Verdict |
|---|---|---|---|---|---|---|
| `TBD` | `TBD` | `PENDING` | `PENDING` | `TBD` | `PENDING` | `NO-GO` |

Không còn hàng `TBD` cho effective-admin trước verdict.

## 7. Residual risk

Single-account root có thể phá cả audit và alert plane. Trước `VERIFIED` phải có: root MFA, no access key, named custodian, incident-only use, review expiry, security/account-owner acceptance và external GitHub watchdog OIDC read-only. Nếu chưa có watchdog thì chỉ `PARTIAL` hoặc phải có signed exception; tuyệt đối không dùng static AWS key.

---

**Phiên bản:** v2.0
**Cập nhật:** 21/07/2026
**Trạng thái:** LIVE ADMIN PATHS CONFIRMED — blocked bởi MFA/access keys, custom-policy inventory và owner approval
