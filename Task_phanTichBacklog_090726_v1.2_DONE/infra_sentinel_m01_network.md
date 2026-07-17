# Report M01 - Network exposure

Cap nhat: 2026-07-14
Pham vi: CDO02 theo doi tac dong Reliability/operational access cua Directive #1.

## 1. Ket luan nhanh

Directive #1 chua co du evidence de ket luan dat. Phan CDO02 hien dang BLOCKED vi can input tu CDO01 ve endpoint public/private, private access guide va ket qua smoke test sau thay doi network.

CDO02 khong so huu chinh security boundary, nhung phai dam bao viec dong operational ports khong lam hong storefront, checkout, cart, browse va kha nang quan sat su co.

## 2. BTC yeu cau gi

- Storefront phai public, khach hang van truy cap duoc.
- Cong van hanh noi bo nhu Grafana, Jaeger, ArgoCD, dashboard/log/metric/trace/admin UI phai private.
- Mentor/BTC phai co cach truy cap private de kiem tra.
- Khong lam gian doan storefront va khong pha SLO.

## 3. CDO02 can chung minh gi

| Muc can chung minh | Trang thai | Ghi chu |
| --- | --- | --- |
| Storefront van public | MISSING | Can positive smoke test browse/cart/checkout. |
| Operational UI khong public | MISSING | Can negative test Grafana/Jaeger/ArgoCD tu public internet. |
| Operational UI van dung duoc qua private path | MISSING | Can private access guide cho mentor. |
| Khong pha datastore flow | MISSING | Can evidence product-catalog/review/accounting/cart/checkout khong bi NetworkPolicy chan. |
| Co rollback path | MISSING | Can input tu CDO01 neu boundary change gay loi. |

## 4. Evidence hien co

Hien chua co evidence runtime moi cho Directive #1 trong cac file Task. File `CDO02_mandate_01_network_exposure.md` moi co plan, checklist va acceptance criteria.

## 5. Blocker

| Blocker | Owner can input | Anh huong |
| --- | --- | --- |
| Chua co endpoint matrix thuc te | CDO01 | Khong biet endpoint nao public/private sau cung. |
| Chua co private access guide | CDO01 | Mentor chua tu kiem tra duoc Grafana/Jaeger/ArgoCD. |
| Chua co smoke test result | CDO02/CDO01 | Khong chung minh duoc storefront va checkout khong bi anh huong. |
| AWS CLI chua verify duoc runtime | Team cap IAM/CDO | Khong the tu doc AWS/EKS hien tai bang CLI. |

## 6. Read-only check can lam khi duoc phep

Chi doc thong tin, khong tac dong:

- Kiem tra endpoint/service/ingress public/private.
- Kiem tra deployment/pod health sau thay doi.
- Kiem tra log/smoke result san co neu da duoc xuat ra file.

Khong duoc lam:

- Khong sua ingress/security group/network policy.
- Khong apply manifest.
- Khong restart/scale/rollout.

## 7. Next report update

Cap nhat file nay khi co:

- Endpoint matrix cua CDO01.
- Storefront smoke test result.
- Public negative test cho operational UI.
- Private access guide cho mentor.
- Rollback note.
