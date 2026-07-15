# Infra Sentinel - project tracking report

Cap nhat: 2026-07-14
Pham vi theo doi: phan CDO/CDO02 cua du an `Phase3-TF3-Infra-Sentinel`

## 1. Ket luan nhanh

Du an hien chua the xac minh runtime truc tiep qua AWS CLI vi credential AWS dang loi `SignatureDoesNotMatch`. Vi vay trang thai trong report nay duoc tong hop tu cac file san co trong `Task_Phase3`, mandate BTC va incident report da ghi lai truoc do.

Phan CDO02 hien co nhieu plan va backlog tot, nhung evidence de nop mentor con thieu. Hai diem can chu y nhat:

- Mandate #1 va #2 cua BTC dang co checklist/ke hoach, nhung chua co bang chung runtime moi nhat.
- Observability dang la rui ro lon: Grafana va Jaeger tung bi `OOMKilled`, Metrics API unavailable, nen chua du vung de chung minh SLO/load test.

## 2. Nguyen tac an toan khi theo doi

- Chi cap nhat file report trong `Task_Phase3`.
- Khong sua code, manifest, config, secret, pipeline trong du an chinh.
- Khong chay lenh tac dong ha tang/cluster/repo.
- Neu duoc phep kiem tra runtime thi chi dung read-only: `get`, `describe`, `logs --tail`, `sts get-caller-identity`, `list`, `describe-*`.
- Khong dung: `apply`, `create`, `update`, `delete`, `patch`, `edit`, `scale`, `rollout restart`, `drain`, `cordon`, `terraform apply`, `helm upgrade`, load test.

## 3. Trang thai tong quan

| Mang viec | Trang thai | Tom tat |
| --- | --- | --- |
| AWS/runtime verification | BLOCKED | AWS CLI co local credential nhung bi `SignatureDoesNotMatch`; chua verify duoc account/EKS hien tai. |
| CDO02 Mandate #1 - Network exposure | BLOCKED | Co plan, chua co endpoint matrix thuc te, private access guide, smoke test evidence. |
| CDO02 Mandate #2 - Flash sale | BLOCKED | Co quy trinh, chua co baseline SLO/cost, load test result, scale-down evidence. |
| Observability | ISSUE | Evidence cu: Grafana restart 15 lan, Jaeger restart 4 lan do OOMKilled; Metrics API unavailable. |
| Reliability backlog | IN_PROGRESS | Co backlog uu tien, nhieu muc can runtime verify hoac implementation evidence. |
| Cost optimization | IN_PROGRESS | COST-07 duoc report da lam; COST-01 ECR lifecycle policy con can verify/xu ly. |
| Mandate #3/#5/#6 | NOT_ASSESSED | Da tao report khung, nhung chua co evidence CDO02 lien quan hoac runtime check. |

## 4. File report chi tiet

| File | Dung de doc gi | Trang thai |
| --- | --- | --- |
| `cdo02_progress.md` | Report tien do CDO02: mandate, backlog, blocker, AWS CLI, observability | Active |
| `infra_sentinel_m01_network.md` | Report Directive #1: storefront public, ops private, phan CDO02 | Blocked |
| `infra_sentinel_m02_flash_sale.md` | Report Directive #2: flash sale, SLO, cost, phan CDO02 | Blocked |
| `infra_sentinel_m03_maintenance.md` | Report Directive #3: maintenance no downtime | Chua co evidence |
| `infra_sentinel_m05_hardening.md` | Report Directive #5: runtime hardening | Chua co evidence |
| `infra_sentinel_m06_ai_safety.md` | Report Directive #6: AI trust and safety | Chua co evidence |

## 5. Nhung gi da biet ve du an

Tu cac file CDO02 hien co, du an co cac diem nen hieu nhu sau:

- He thong chay tren EKS, namespace `techx-tf3`, region duoc report la `ap-southeast-1`.
- Kien truc duoc mo ta la fork OpenTelemetry Demo, nhieu microservice, dung Postgres, Valkey, Kafka.
- Public path co CloudFront + ALB; operational UI gom Grafana/Jaeger/ArgoCD can private hoa theo mandate #1.
- CDO02 phu trach chinh Reliability va Cost Optimization; CDO01 phu trach chinh Security/Performance boundary.
- Backlog CDO02 tap trung vao checkout/revenue path, datastore/order safety, observability, cost cap.

## 6. Bang chung hien co

| Evidence | Nguon | Y nghia |
| --- | --- | --- |
| Grafana restart 15 lan, OOMKilled | `incident_Report_TVD.md` | Observability chua on dinh, anh huong kha nang chung minh SLO. |
| Jaeger restart 4 lan, OOMKilled | `incident_Report_TVD.md` | Trace co rui ro mat khi load/incident. |
| Metrics API unavailable | `incident_Report_TVD.md` | Khong doc duoc memory realtime bang `kubectl top` tai thoi diem kiem tra. |
| Workload Running tai thoi diem 2026-07-08 | `incident_Report_TVD.md` | App workload duoc report khong CrashLoop/Pending luc do. |
| COST-07 da lam 1 NAT Gateway thay vi 3 | `PITCH-CDO02.local _update.md` | Co claim tiet kiem cost, can evidence neu nop mentor. |
| REL-01 da merge repo nhung can runtime verify | `CDO02_backlog_handling.md` | Chua du de ket luan da ap dung tren cluster. |

## 7. Khoang trong lon nhat

| Khoang trong | Anh huong |
| --- | --- |
| Chua verify runtime moi nhat qua AWS/EKS | Khong biet trang thai hien tai cua cluster, node, deployment, ingress, PDB, HPA. |
| Chua co endpoint matrix thuc te | Mandate #1 chua chung minh duoc storefront public va ops private. |
| Chua co private access guide cho mentor | BTC/mentor chua tu kiem tra duoc operational UI. |
| Chua co baseline SLO/cost | Mandate #2 khong the chung minh "khong vuot ngan sach". |
| Chua co load test result 200 users/15 phut | Mandate #2 chua dat evidence BTC yeu cau. |
| Observability co OOM evidence | Can xu ly/verify truoc khi dung dashboard lam bang chung chinh. |

## 8. Viec tiep theo nen lam

Khong tac dong runtime:

1. Lay tu CDO01 endpoint matrix va private access guide cho mandate #1.
2. Lay bang chung san co: dashboard screenshot/export, load test result, cost estimate, SLO table.
3. Xin Team 1/nguoi cap IAM bo AWS credential dung, neu la temporary credential phai co `aws_session_token`.
4. Khi AWS/kubectl dung duoc, chi chay read-only de verify runtime va cap nhat report.

Can runtime read-only sau khi co credential hop le:

1. Xac nhan account/role bang `aws sts get-caller-identity`.
2. Xac nhan EKS cluster/namespace/deployment/PDB/HPA bang lenh read-only.
3. Xac nhan Grafana/Jaeger con restart/OOM hay da on dinh.
4. Xac nhan REL-01 da apply that: revenue path co >=2 available replicas va PDB.

## 9. Nhat ky report

| Thoi gian | Noi dung |
| --- | --- |
| 2026-07-14 | Tao bo tracker mandate trong `Task_Phase3`. |
| 2026-07-14 | Tach file theo mandate va doi ten ngan gon. |
| 2026-07-14 | Ghi nhan AWS CLI dang bi block boi `SignatureDoesNotMatch`. |
| 2026-07-14 | Chuyen file theo doi sang dang report de doc hieu trang thai du an. |
