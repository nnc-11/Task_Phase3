# code_audit — staging code cho Mandate 12

Mã trong thư mục này **không nằm trong repository production và chưa được deploy**. Chỉ copy sau khi live discovery xác nhận AWS Organizations, account ownership, backend và resource scope.

> **TẠM DỪNG DEPLOY:** scaffold Terraform hiện có là phương án Organization/cross-account, nhưng solution mới đã chọn single-account hardened audit. Không dùng hai root hiện tại để deploy. Chúng chỉ là phương án tham khảo cho nâng cấp tương lai; mã single-account sẽ được chốt sau khi thảo luận IAM/operator boundary và live discovery.

## Cấu trúc

```text
code_audit/
├── README.md
├── DEPLOY.md
├── TOMORROW-CHECKLIST.md
├── EVIDENCE.md
├── env.example
├── scripts/
│   ├── preflight.sh
│   └── verify.sh
└── terraform/
    ├── log-archive/          # chạy trong security/log-archive account
    └── organization-trail/   # chạy trong management/delegated admin account
```

## Vị trí dự kiến trong repo production

Không đặt vào `infra/live/production` vì root đó sở hữu EKS/network/edge của TF3. Sau khi được phê duyệt, copy nguyên hai root thành:

```text
Phase3-TF3-Infra-Sentinel/
└── infra/
    └── audit/
        ├── log-archive/
        └── organization-trail/
```

Mỗi root phải dùng backend/state riêng và AWS role riêng. Nếu management/log-archive account do BTC hoặc platform team quản lý ngoài repo TF3, giữ code ở repo quản trị trung tâm thay vì copy vào repo production; TF3 chỉ lưu interface outputs và evidence.

## Thứ tự

1. Deploy `log-archive`.
2. Lấy bucket name/ARN và KMS ARN từ outputs.
3. Deploy `organization-trail` với các outputs đó.
4. Chờ log/digest delivery.
5. Chạy mentor tests và `validate-logs` theo runbook.

Ngày triển khai bắt đầu từ `TOMORROW-CHECKLIST.md`, không chạy thẳng `terraform apply`.

## Không thuộc scope của code này

- Không sửa EKS, CloudFront, Cloudflare, SSM, workload, datastore hoặc flagd.
- Không tự tạo/mời account vào Organization.
- Không cấu hình EKS audit logging vì trạng thái live chưa được xác minh.
- Không tự thêm bucket/prefix nhạy cảm chưa được data owner phê duyệt.
- Không chạy mutation test nguy hiểm trên production.
