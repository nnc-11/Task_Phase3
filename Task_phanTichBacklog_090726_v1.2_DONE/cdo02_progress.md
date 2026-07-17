# CDO02 progress report

Cap nhat: 2026-07-14
Owner/pham vi: CDO02 - Reliability, Cost Optimization, va phan phoi hop CDO lien quan mandate BTC.

## 1. Executive summary

CDO02 hien dang o trang thai co ke hoach va backlog ro, nhung chua du evidence runtime moi nhat de ket luan cac mandate da dat. Viec verify truc tiep qua AWS/EKS dang bi chan vi AWS CLI credential loi `SignatureDoesNotMatch`.

Trong cac evidence da co, rui ro lon nhat nam o observability: Grafana va Jaeger da bi OOMKilled, Metrics API unavailable. Dieu nay anh huong truc tiep den Mandate #2, vi khong co observability on dinh thi kho chung minh SLO/load test/cost mot cach thuyet phuc.

## 2. Scope va gioi han

Report nay chi tong hop tu:

- `CDO02_mandate_01_network_exposure.md`
- `CDO02_mandate_02_flash_sale_under_budget.md`
- `CDO02_backlog_handling.md`
- `incident_Report_TVD.md`
- `PITCH-CDO02.local _update.md`
- mandate BTC trong `mandates_BTC`

Gioi han hien tai:

- Chua verify runtime moi nhat duoc vi AWS CLI credential khong hop le.
- Khong tac dong vao du an chinh.
- Khong chay lenh tac dong ha tang/cluster/repo.

## 3. Trang thai CDO02 theo nhom viec

| Nhom viec | Trang thai | Danh gia |
| --- | --- | --- |
| Mandate #1 - Network exposure | BLOCKED | CDO02 co plan de smoke test va bao ve SLO, nhung thieu endpoint matrix/private access/smoke test evidence. |
| Mandate #2 - Flash sale | BLOCKED | Co quy trinh test va acceptance criteria, nhung thieu baseline, load test result, cost/scale-down evidence. |
| Reliability backlog | IN_PROGRESS | Da xep uu tien dung trong tam checkout/order/observability, nhung nhieu muc can verify runtime. |
| Observability | ISSUE | Grafana/Jaeger OOMKilled la blocker thuc te cho evidence. |
| Cost optimization | IN_PROGRESS | Co claim da toi uu NAT Gateway, nhung can bang chung cost neu nop mentor. |
| Runtime verification | BLOCKED | AWS CLI co key local nhung AWS tu choi request signature. |

## 4. Mandate #1 - Network exposure

Trang thai: BLOCKED

CDO02 khong so huu chinh security boundary, nhung phai dam bao thay doi public/private khong lam hong storefront, checkout, cart, browse va observability.

Da co:

- Pham vi trach nhiem CDO02 da ro.
- Endpoint matrix mau.
- Acceptance criteria.
- Danh sach evidence can nop.

Chua co:

- Endpoint matrix thuc te da chot.
- Ket qua positive test storefront.
- Ket qua negative test Grafana/Jaeger/ArgoCD public access.
- Private access guide cho mentor.
- Smoke test sau thay doi network/ingress.

Can CDO01 cung cap:

- Entry point public chinh thuc: CloudFront-only hay ALB public tam thoi.
- Danh sach operational UI da private hoa.
- Cach truy cap private: VPN/tunnel/bastion/port-forward.
- Rollback path neu thay doi lam rot SLO.

Ket luan: phan CDO02 cua Mandate #1 chua the danh dau done. Dang cho input va evidence tu CDO01/runtime.

## 5. Mandate #2 - Flash sale

Trang thai: BLOCKED

CDO02 tap trung vao checkout/order safety, datastore pressure, observability va cost evidence trong bai test 200 concurrent users/15 phut.

Da co:

- Muc tieu SLO/load/cost da ghi ro.
- Quy trinh test tang dan 25-50 -> 100 -> 200 users.
- Acceptance criteria cho checkout, browse/cart, storefront p95, pod health, observability, cost, scale-down.
- Evidence list cho BTC/mentor.

Chua co:

- Baseline SLO/cost.
- Load test config va result.
- SLO table trong cua so test.
- Runtime health trong cua so test.
- Cost/request hoac cost/order.
- Scale-up/scale-down evidence.

Blocker:

- Observability co issue OOMKilled.
- Metrics API unavailable trong incident report.
- REL-01 duoc noi la da merge nhung chua verify runtime.
- AWS CLI hien khong verify duoc account/EKS.

Ket luan: Mandate #2 chua co evidence de nop. Can unblock observability va runtime read-only verification truoc khi ket luan.

## 6. Backlog CDO02

| Ma | Noi dung | Trang thai | Ly do |
| --- | --- | --- | --- |
| REL-01 | Replicas >=2 + PDB cho revenue path | NEED_VERIFY | Backlog ghi da merge repo, nhung runtime chua verify. |
| REL-13 | Grafana/Jaeger OOM/restart | ISSUE | Incident report co OOMKilled that. |
| REL-15 | Alert OOMKilled/restart/readiness fail | TODO | Chua thay evidence alert da co. |
| REL-09/REL-16 | Kafka ack/manual commit/DLQ | TODO | Co rui ro mat order am tham, chua thay evidence fix. |
| REL-04 | Refund/rollback khi ship loi sau charge | TODO | Rui ro tai chinh, chua thay evidence fix. |
| REL-05 | Postgres connection pool | TODO | Chua co evidence da xu ly/runtime verify. |
| REL-10 | Persistence/accepted risk datastore | TODO | Pitch ghi 0 PVC la rui ro, chua thay mitigation. |
| COST-01 | ECR lifecycle policy dung | TODO | Can xu ly/verify de tranh xoa nham image. |
| COST-07 | 1 NAT Gateway thay vi 3 | DONE_REPORTED | Da duoc report trong pitch, can bang chung cost neu nop mentor. |

## 7. Observability incident

Nguon: `incident_Report_TVD.md`

| Hang muc | Trang thai | Ghi nhan |
| --- | --- | --- |
| Cluster EKS | OK_REPORTED | `techx-corp-tf3` ACTIVE, K8s 1.31 tai thoi diem 2026-07-08. |
| Namespace workload | OK_REPORTED | Namespace `techx-tf3` truy cap duoc. |
| Pod/deployment | OK_REPORTED | Pod Running, deployment `1/1 READY` tai thoi diem kiem tra. |
| Node | OK_REPORTED | 3 node Ready. |
| Grafana | ISSUE | Restart 15 lan, last reason OOMKilled, memory 300Mi. |
| Jaeger | ISSUE | Restart 4 lan, last reason OOMKilled, memory 600Mi, memory storage. |
| Metrics API | WARN | `kubectl top pods --containers` loi Metrics API not available. |
| Storefront | OK_REPORTED | Chua thay evidence storefront down trong lan kiem tra. |

Nhan dinh: application workload duoc report la chay, nhung tang quan sat khong on dinh. Day la viec can uu tien neu muon chung minh Mandate #2.

## 8. AWS CLI status

Trang thai: BLOCKED

Da kiem tra read-only:

- `aws configure list`: co access key/secret key local, region `ap-southeast-1`.
- `aws configure list-profiles`: co `default`.
- Khong co bien moi truong `AWS_*` override.
- Khong co `aws_session_token`.
- `aws sts get-caller-identity`: loi `SignatureDoesNotMatch`.
- `aws eks list-clusters`: loi `InvalidSignatureException`.

Nhan dinh:

- Local AWS CLI co credential, nhung AWS khong chap nhan.
- Neu credential do Team 1 cap theo gio/STS, kha nang thieu hoac het han `aws_session_token`.

## 9. Next steps

Khong can runtime:

1. Xin CDO01 endpoint matrix/private access guide cho Mandate #1.
2. Thu thap dashboard screenshot/export, load test result, SLO table neu team da co.
3. Xin evidence cost cho COST-07 va baseline cost cho Mandate #2.

Can credential hop le, chi read-only:

1. `aws sts get-caller-identity` de xac nhan account/role.
2. Check EKS cluster/namespace/deployment/PDB/HPA bang lenh read-only.
3. Check Grafana/Jaeger restart hien tai.
4. Verify REL-01 revenue path >=2 replicas + PDB.

Khong duoc lam trong pham vi report:

- Khong apply/sua manifest.
- Khong restart/scale/drain.
- Khong chay load test.
- Khong helm/terraform apply.
