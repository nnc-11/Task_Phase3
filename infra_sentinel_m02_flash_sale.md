# Report M02 - Flash sale under budget

Cap nhat: 2026-07-14
Pham vi: CDO02 theo doi Reliability, Cost va evidence cho Directive #2.

## 1. Ket luan nhanh

Directive #2 chua co du evidence de ket luan dat. CDO02 da co quy trinh test va acceptance criteria, nhung hien chua co baseline SLO/cost, load test result 200 users/15 phut, cost/request, cost/order hoac scale-down evidence.

Blocker quan trong la observability: incident report ghi Grafana va Jaeger bi OOMKilled, Metrics API unavailable. Neu chua giai quyet/verify lai, dashboard co the khong du tin cay de lam evidence load test.

## 2. BTC yeu cau gi

- Chiu 200 concurrent users qua load-generator trong 15 phut.
- Checkout success rate >= 99%.
- Browse/cart success rate >= 99.5%.
- Storefront p95 < 1s.
- Khong vuot ngan sach hien tai.
- Sau dinh tai, tai nguyen phai co xuong lai muc binh thuong.

## 3. Trang thai evidence

| Evidence can co | Trang thai | Ghi chu |
| --- | --- | --- |
| Baseline SLO truoc test | MISSING | Chua thay trong Task. |
| Baseline cost/run-rate | MISSING | Chua thay trong Task. |
| Load test config 200 users/15 phut | MISSING | Chua co file/result. |
| Load test result | MISSING | Chua co bang ket qua. |
| Checkout/browse/cart SLO table | MISSING | Chua co evidence cua cua so test. |
| Storefront p95 | MISSING | Chua co p95 trong bai test. |
| Runtime health pod/node | PARTIAL | Incident cu co pod/node OK, nhung khong phai cua so flash sale. |
| Observability health | ISSUE | Grafana/Jaeger OOMKilled, Metrics API unavailable. |
| Scale down evidence | MISSING | Chua co replica/node before-during-after. |
| Cost/request hoac cost/order | MISSING | Chua co. |

## 4. Evidence hien co

Tu `incident_Report_TVD.md`:

- Grafana restart 15 lan, last reason `OOMKilled`, memory 300Mi.
- Jaeger restart 4 lan, last reason `OOMKilled`, memory 600Mi.
- Metrics API unavailable khi chay `kubectl top pods --containers`.
- Tai thoi diem 2026-07-08, workload duoc report Running va node Ready.

Tu `CDO02_mandate_02_flash_sale_under_budget.md`:

- Da co quy trinh test tang dan 25-50 -> 100 -> 200 users.
- Da co acceptance criteria va evidence list.

## 5. Rui ro CDO02 can canh

| Rui ro | Anh huong |
| --- | --- |
| Observability chet trong luc test | Khong chung minh duoc SLO/load/cost. |
| REL-01 chua apply runtime | Revenue path co the van SPOF khi load/maintenance. |
| Postgres/Kafka/Valkey nghen | Checkout/order co the fail hoac mat du lieu. |
| HPA/autoscaler scale qua tay | Vuot budget hoac khong co scale-down evidence. |
| AWS CLI bi block | Khong doc duoc node/cluster/cost/runtime state moi. |

## 6. Read-only check can lam khi co credential hop le

Chi doc thong tin:

- Deployment replicas/available cua revenue path.
- PDB/HPA hien co.
- Pod restart/OOM.
- Node count va node condition.
- Dashboard/export SLO neu co.
- Cost/run-rate neu co quyen read-only Cost Explorer.

Khong duoc lam:

- Khong chay load test.
- Khong scale/rollout/restart.
- Khong sua HPA/resource request/limit.
- Khong apply manifest.

## 7. Next report update

Cap nhat khi co:

- Baseline SLO/cost.
- Load test config/result.
- Replica/node before-during-after.
- Evidence Grafana/Jaeger da on dinh.
- Cost/request hoac cost/order.
