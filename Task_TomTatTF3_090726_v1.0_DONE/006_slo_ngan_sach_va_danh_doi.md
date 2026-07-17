# 006 - SLO, ngan sach va danh doi

SLO va ngan sach la hai thanh ray de xep uu tien. Neu khong quy ve SLO hoac cost, backlog rat de thanh danh sach viec cam tinh.

## Can nho trong 60 giay

- Checkout success >= 99.0% la SLO quan trong nhat vi gan doanh thu.
- Browse/cart la 99.5%.
- AI review best-effort nhung khong duoc hien thi sai lech.
- Cost cap khoang 300 USD/tuan/TF.
- CDO phai noi duoc moi thay doi ha tang bao ve SLO nao va ton bao nhieu.

## SLO chinh

Duyet/tim san pham:

- Non-5xx request rate >= 99.5%.
- p95 latency storefront < 1s.

Gio hang:

- Ti le thao tac thanh cong >= 99.5%.

Checkout:

- Ti le dat hang thanh cong >= 99.0%.
- Day la luong quan trong nhat vi lien quan doanh thu truc tiep.

Tom tat review AI:

- Best-effort, khong co SLA cung.
- Nhung khong duoc hien thi tom tat sai lech cho khach.

## Error budget

Checkout SLO 99.0% nghia la error budget 1%.

Neu con budget:

- Co the deploy, migrate, thu nghiem co kiem soat.

Neu chay budget:

- Dong bang thay doi rui ro.
- Tap trung on dinh, rollback, containment.

Error budget la ngon ngu de noi voi PM/SRE: "luc nay co du an toan de ship khong?"

## Ngan sach

Moi TF co khoang 300 USD/tuan cho AWS:

- EKS node/EC2.
- RDS/ElastiCache/MSK neu migrate managed.
- EBS.
- NAT, load balancer, data transfer.
- Observability storage.
- Backup.

## Cac danh doi thuong gap

Reliability vs Cost:

- Them replica re hon managed Multi-AZ.
- RDS Multi-AZ ben hon nhung ton tien hon.
- Single NAT tiet kiem nhung co rui ro egress theo AZ.

Performance vs Cost:

- Node lon luon san sang de hon nhung dat.
- Autoscaling tiet kiem hon nhung can requests/probes/HPA dung.

Observability vs Cost:

- Luu log dai hon giup debug tot hon.
- Retention dai co the ton storage.

Security vs Toc do:

- Least privilege/IAM/OIDC mat cong ban dau.
- Dung access rong de nhanh se kho audit va nguy hiem.

## Cach xep uu tien bang SLO + cost

Mau cau tot:

"Viec nay bao ve checkout SLO 99% vi hien checkout phu thuoc vao nhieu service single-replica. Chi phi them replica cho cac service critical thap hon nhieu so voi migrate managed toan bo, nen lam truoc."

Mau cau yeu:

"Nen them replica vi best practice."

## Cach bien SLO thanh backlog CDO

| Tin hieu | Backlog CDO tuong ung |
|---|---|
| Checkout loi/cham | Rollout safety, replica, dependency timeout, DB/Kafka health |
| Pod restart/OOM | Requests/limits, memory sizing, alert |
| Deploy gay loi | Readiness/liveness probe that, canary/rollback |
| DB connection can | Pool limit, timeout, connection reuse |
| Cost tang bat thuong | Budget alert, right-size node, retention policy |
