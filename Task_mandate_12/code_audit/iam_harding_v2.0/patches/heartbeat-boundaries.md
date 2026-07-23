# Patch heartbeat theo dõi CI boundary

## 1. Tạo file riêng

Copy:

```text
repo_overlay/infra/live/production/m12-iam-hardening.auto.tfvars
  -> infra/live/production/m12-iam-hardening.auto.tfvars
```

Không chèn map vào `production.auto.tfvars`; file đó đang chứa nhiều cấu hình
application/team khác. File mới chỉ chứa exact map hai GHA role, không thêm
GitLab/human/AIOps.

## 2. `infra/live/production/m12-variables.tf`

Sửa comment cũ nói sẽ thêm `gitlab-ci-deployer`: rollout v2.0 chỉ theo dõi hai
GHA role. GitLab/human/AIOps là owner-led change riêng.

## Thứ tự rollout

Pre-stage map bằng Audit Foundation maintenance path ngay trước attach phase. Trong
khoảng map đã cập nhật nhưng boundary chưa attach, heartbeat phải phát cảnh báo
“boundary missing”; đó là expected alert có change ID, không phải tắt alarm.

Sau đó attach boundary ở bootstrap root và xác nhận heartbeat trở lại `PASS`.
Nếu attach phase bị hủy, rollback riêng map về `{}` bằng đúng saved plan đã review.
