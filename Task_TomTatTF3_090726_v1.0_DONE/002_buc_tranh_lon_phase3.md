# 002 - Buc tranh lon Phase 3

Phase 3 la bai tap mo phong viec tiep quan mot san pham dang chay production.TF3 nhan mot he thong co san, dua no len chay tren AWS/EKS cua minh, roi tu danh gia rui ro, tu xep uu tien, tu van hanh va bao ve quyet dinh.

## Can nho

- Day la bai **van hanh san pham**.
- TF3 phai tu build image, deploy EKS, giu SLO, xu ly incident, va bao ve backlog.
- Ban la CDO nen trong tam la platform: Terraform, Helm, observability, reliability, performance, cost, security, auditability.
- Moi viec CDO lam phai tra loi: bao ve SLO nao, ton bao nhieu, rollback ra sao, ghi audit o dau.

## Mục tiêu thật sự

Mục tiêu không phải chỉ là viết code. Mục tiêu là chứng minh có thể own (chịu trách nhiệm) một service:

Hiểu kiến trúc và luồng business.
Biết đâu là luồng tạo ra doanh thu, đâu là luồng phụ.
Đảm bảo SLO ngay cả khi có sự cố.
Cải tiến hệ thống trong giới hạn ngân sách.
Xử lý incident mà không làm ảnh hưởng đến cơ chế thi đấu.
Ghi lại các quyết định để có thể audit: ai làm gì, vì sao làm.

## TF3 la ai

TF3 gom:

- AIO02: tang AI, gom AIOps va AI trong san pham.
- CDO01: platform/ha tang.
- CDO02: platform/ha tang.

## Neu ban thuoc team CDO

Trong Phase 3, CDO khong chi "dung cloud". CDO chiu trach nhiem bien he thong thanh mot service van hanh duoc:

- Security: IAM, secret hygiene, network exposure, least privilege, supply chain.
- Reliability: replica, probe, rollout, dependency failure, backup/restore, incident response.
- Performance Efficiency: requests/limits, autoscaling, latency, bottleneck, load test.
- Cost Optimization: node sizing, NAT, ECR, observability retention, managed service ROI.
- Auditability: ADR, postmortem, CloudTrail/K8s audit, change log, ai lam gi khi nao.

Trong moi viec CDO lam, cau hoi phai la: "viec nay bao ve SLO nao, ton bao nhieu, rui ro rollback la gi, va co ghi lai du de audit khong?"

## Hai luong cong viec chay song song

Operate:

- Theo doi pods, logs, metrics, traces.
- Phat hien incident.
- Giu checkout, cart, browsing dat SLO.
- Lam postmortem sau su co.

Build:

- Cai thien reliability, performance, cost, security, auditability.
- Dung backlog da pitch.
- Viet ADR cho quyet dinh lon.

## Vi sao day la bai kho

He thong co nhieu rang buoc trai chieu:

- Reliability muon them replica, managed service, Multi-AZ.
- Cost muon tiet kiem, khong bat moi thu qua lon.
- Performance muon scale dung luc, tranh nghep tai.
- Security muon least privilege, secret hygiene.
- Auditability muon moi thay doi co nguoi chiu trach nhiem.
- Product muon khach hang thay cai thien, khong chi ha tang dep.

Lam dung la phai giai thich duoc danh doi, khong phai "bat het cho chac".

## Mot cau tom tat de nho

Phase 3 cham kha nang bien mot he thong microservice co san nhieu diem yeu thanh mot service van hanh duoc, trong gioi han SLO, cost va luat choi.
