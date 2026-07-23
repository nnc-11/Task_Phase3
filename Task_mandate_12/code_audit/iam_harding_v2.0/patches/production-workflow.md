# Patch `.github/workflows/terraform-apply.yml`

Ngay sau bước tạo `tfplan`, thêm:

```yaml
      - name: Export Terraform plan JSON
        run: terraform show -json tfplan > tfplan.json

      - name: Enforce normal production scope
        run: python ../../../scripts/ci/m12-terraform-scope-gate.py tfplan.json
```

Giữ step này trước upload artifact và trước apply.

Mục tiêu: production workflow thường không apply một phần rồi fail tại IAM hoặc
Audit Foundation do boundary. Mọi IAM diff phải tách sang bootstrap/IAM change;
mọi Audit Foundation diff phải đi theo maintenance path riêng có Security Owner
phê duyệt.

Gate nhận diện:

- mọi resource type `aws_iam_*`;
- mọi `aws_sns_topic_subscription` change vì boundary chặn subscription
  mutation toàn cục trên hai GHA role;
- module/resource có address chứa `audit_detection_`, `m12_audit_heartbeat` hoặc
  `m12_heartbeat`.

Gate phải chạy trước upload saved plan/artifact và trước apply.
