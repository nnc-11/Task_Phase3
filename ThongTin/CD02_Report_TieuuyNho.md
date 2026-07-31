# BÁO CÁO TỔNG HỢP CDO-02
## Quá trình xử lý Mandate của BTC và ứng phó Incident

**Nhóm:** CDO-02;  Reliability + Cost Optimization  
**own**: Tran Van Duc
**Repository:** [Phase3-TF3-Infra-Sentinel](https://github.com/tuu-ngo/Phase3-TF3-Infra-Sentinel)

---

## 1. Tóm tắt điều hành

CDO-02 xử lý mandate theo một nguyên tắc xuyên suốt: **không chỉ sửa cho “chạy được”, mà phải chứng minh hệ thống giữ SLO, có đường lui, không vượt ngân sách và có bằng chứng để người khác tái kiểm tra**. Vì vậy, mỗi mandate thường tạo ra đủ bốn lớp tài sản:

1. **ADR hoặc solution:** ghi quyết định kiến trúc và đánh đổi.
2. **Code/IaC/GitOps:** thay đổi có lịch sử Git, review và rollback được.
3. **Runbook:** quy trình triển khai, kiểm tra, dừng và phục hồi.
4. **Evidence/report/postmortem:** số đo runtime, ảnh/video, kết quả PASS/FAIL và bài học.

### 1.1. Trạng thái các mandate thuộc phạm vi CDO-02

| Mandate | Mô tả ngắn | Vai trò CDO-02 | Trạng thái trung thực tại 30/07 | Bằng chứng nổi bật |
|---|---|---|---|---|
| **#2** | Chịu flash sale 200 user trong ngân sách | Chủ trì Reliability/Cost | ✅ PASS | Checkout 99,9825%; Browse/Cart 100%; p95 46–48 ms; không thêm node |
| **#3** | Bảo trì node không downtime | Chủ trì Reliability | ✅ PASS app-tier | Drain node thật; Checkout 99,94%; Browse 100%; Cart 99,95%; p95 68,6 ms |
| **#8** | Chuyển PostgreSQL/Valkey/Kafka lên managed AWS | Chủ trì toàn bộ | ✅ Hoàn tất 3/3 store | 827/827 cart khớp; 70.478→70.556 order khớp; Kafka lag về 0; incident 0010 có bounded pre-publish event loss được ghi riêng |
| **#9** | Vận hành managed store zero-downtime dưới tải | Chủ trì thiết kế/thực thi | 🛠️ Đang triển khai | Solution v3.2 hoàn chỉnh; M9-01 stale-cache + startup-latch đã code/test, chưa có live chaos evidence |
| **#11** | Phát hiện chủ động hành động audit nguy hiểm | Owner CDO-02 | ✅ Hoàn tất | Email cảnh báo thật; TTD 2–4 giây, dưới ngưỡng 5 phút |
| **#12** | Audit không thể bị đánh bại | Owner CDO-02 | ⚪ SKIP có mentor phê duyệt | Detection đã live; SCP hard-prevention không triển khai do rủi ro $200–460 tiền thật |
| **#13** | Tăng tỷ lệ Spot, dùng Graviton, vẫn chịu interruption | Chủ trì Reliability/Cost | ✅ Đủ evidence nộp | Spot 55,6% toàn fleet; arm64 live; drain Spot; node count 10→9 |
| **#17** | Chịu dependency chết và mất một AZ | Owner req#1/#2 | 🟢 Phần CDO-02 cơ bản đạt, còn caveat | 10/10 service lõi trải ≥2 AZ; fallback đã được pin image; chưa có bằng chứng FIS hoàn chỉnh trong report chốt |
| **#18** | Cắt chi phí ẩn ngoài compute | Chủ trì Cost | ✅ Đạt 5/5 | VPC endpoint −~$114/tháng; metric series −64,5%; log retention 7 ngày; 0 EBS orphan |
| **#20** | Backup/restore DR có RPO/RTO thật | Chủ trì RDS drill | 🟡 PASS phạm vi RDS, chưa claim toàn mandate | PITR khôi phục đúng; RPO 41,25 giây; RTO 23,83 phút; 0 row mất |

### 1.2. Quy ước trạng thái

- **PASS/Hoàn tất:** có triển khai và có bằng chứng runtime/acceptance đủ cho phạm vi tuyên bố.
- **Đang triển khai:** đã có thiết kế hoặc code nhưng chưa đủ live evidence/mentor acceptance.
- **PASS phạm vi:** một phần xác định của mandate đã đạt; không suy rộng thành toàn bộ mandate.
- **SKIP có phê duyệt:** không triển khai phần cốt lõi vì ràng buộc đã được trình bày và mentor chấp nhận; không được gọi là PASS.

### 1.3. Phạm vi và nguồn dùng để dựng lại đề bài

Bản checkout repository hiện tại chỉ còn file hướng dẫn chung trong `phase3 - information/mandates`; các memo mandate gốc được ADR/report trỏ tới nhưng không còn nằm trong cây làm việc này. Vì vậy, phần “đề bài rút gọn” trong báo cáo được đối chiếu từ ADR ký tên, acceptance report, runbook và evidence hiện có, không giả định thêm yêu cầu ngoài hồ sơ.

Báo cáo tập trung vào mandate mà CDO-02 là owner hoặc sở hữu phần Reliability/Cost rõ ràng. Các mandate do CDO-01/AIO chủ trì như #1, #5, #10, #15, #16, #19 không được nhận là thành tích CDO-02; chúng chỉ xuất hiện khi là dependency hoặc nguyên nhân chéo của một incident CDO-02 xử lý.

---

## 2. Cách CDO-02 tiếp cận một mandate

### Bước 1 — Chuyển đề bài thành “hợp đồng nghiệm thu”

Nhóm tách mandate thành:

- kết quả khách hàng phải nhận được;
- SLO/SLI cần đo;
- ràng buộc ngân sách;
- thao tác bị cấm, đặc biệt là không tắt/né `flagd`;
- bằng chứng bắt buộc;
- điều kiện rollback và NO-GO.

**SLI** là chỉ số thực đo, ví dụ tỷ lệ checkout thành công. **SLO** là mục tiêu phải đạt, ví dụ checkout ≥99%. Nhờ tách hai khái niệm này, nhóm không kết luận “hệ thống ổn” chỉ vì pod đang `Running`.

### Bước 2 — Audit hiện trạng bằng cả code và runtime

Nhóm đối chiếu ba nguồn:

1. **Desired state:** Terraform, Helm values, GitOps manifest.
2. **Live state:** AWS CLI, `kubectl`, Prometheus, Jaeger, OpenSearch.
3. **Lịch sử:** Git/PR, audit log, CloudTrail, postmortem cũ.

Điều này ngăn lỗi phổ biến “code đúng nhưng production chưa sync” hoặc “pod Ready nhưng dependency thật đã đứt”.

### Bước 3 — Thiết kế theo failure mode, không theo tên công nghệ

Ví dụ:

- pod bị evict → cần replica, spread, PDB và graceful shutdown;
- DB failover → cần cache/readiness/retry chứ không chỉ Multi-AZ;
- Spot bị thu hồi → cần workload không tạo SPOF và capacity có thể dựng lại;
- audit trail bị tắt → cần phát hiện hoặc lớp policy đứng cao hơn administrator;
- backup có tồn tại → vẫn chưa đủ, phải restore thử và đo RPO/RTO.

### Bước 4 — Triển khai theo GitOps/IaC, có preflight và rollback

Các thay đổi dài hạn được đưa vào Git, tránh để `kubectl` tay trở thành trạng thái chính. Với thao tác nguy hiểm, nhóm dùng:

- preflight;
- backup/snapshot;
- canary hoặc rehearsal;
- abort threshold;
- rollback về known-good;
- hậu kiểm live.

### Bước 5 — Đo đúng cửa sổ và đúng tầng nghiệp vụ

Nhóm ưu tiên metric theo đúng request khách hàng, ví dụ span `PlaceOrder`, thay vì cộng tất cả child span của service. Cách này đặc biệt quan trọng trong Incident `cartFailure`: child span `EmptyCart` lỗi nhưng đơn hàng vẫn hoàn tất; nếu đo sai scope sẽ tạo SLO breach “ảo”.

### Bước 6 — Ghi rõ phần chưa đạt

Các report CDO-02 cố ý phân biệt:

- kiến trúc đã đủ nhưng chưa demo;
- code đã merge nhưng chưa deploy;
- deploy rồi nhưng chưa có live evidence;
- một scope PASS nhưng mandate tổng chưa PASS;
- residual risk được chấp nhận có ý thức.

---

## 3. Thuật ngữ nền dùng trong báo cáo

| Thuật ngữ | Giải thích |
|---|---|
| **Reliability** | Khả năng hệ thống tiếp tục phục vụ đúng khi thành phần lỗi, tải tăng hoặc có bảo trì. |
| **Cost Optimization** | Giảm chi phí trên mỗi đơn/request và loại lãng phí, nhưng không đánh đổi mù quáng SLO hoặc khả năng điều tra. |
| **SPOF** | Single Point of Failure: một điểm chết duy nhất; hỏng điểm đó là mất toàn bộ chức năng. |
| **HA** | High Availability: có nhiều bản/đường dự phòng để lỗi một thành phần không làm dừng dịch vụ. |
| **AZ** | Availability Zone: vùng hạ tầng độc lập trong cùng AWS Region. Trải nhiều AZ giúp chịu lỗi cả một trung tâm dữ liệu. |
| **p95/p99** | 95%/99% request nhanh hơn hoặc bằng giá trị này. Chúng phản ánh “đuôi chậm”, đáng tin hơn trung bình. |
| **HPA** | Horizontal Pod Autoscaler: tự tăng/giảm số pod theo tải. |
| **Karpenter** | Bộ tự động tạo/thu hồi node Kubernetes theo nhu cầu pod. |
| **PDB** | PodDisruptionBudget: giới hạn số pod có thể bị gián đoạn do thao tác tự nguyện như drain. PDB không tự tạo replica. |
| **Topology spread** | Luật buộc/khuyến khích các replica nằm ở node/AZ khác nhau. Hai replica cùng một node vẫn là một SPOF. |
| **Graceful shutdown** | Cho pod ngừng nhận request mới và xử lý nốt request đang chạy trước khi tắt. |
| **GitOps** | Git là nguồn trạng thái chuẩn; ArgoCD đồng bộ manifest từ Git vào cluster. |
| **RPO** | Recovery Point Objective: chấp nhận mất tối đa bao nhiêu dữ liệu theo thời gian. |
| **RTO** | Recovery Time Objective: mất tối đa bao lâu để khôi phục dịch vụ/dữ liệu. |
| **Fail-fast** | Nếu cấu hình nền tảng sai thì dừng sớm, không mở cổng phục vụ trong trạng thái nửa hỏng. |
| **Degrade gracefully** | Khi chức năng phụ lỗi, hệ thống giảm tính năng nhưng luồng chính vẫn chạy, ví dụ thiếu gợi ý nhưng vẫn browse/checkout. |

---

# PHẦN I — QUÁ TRÌNH XỬ LÝ CÁC MANDATE

## 4. Mandate #2 — Flash sale 200 user, giữ SLO trong ngân sách

### 4.1. Đề bài rút gọn

Hệ thống phải chịu **200 user đồng thời trong ít nhất 15 phút**, giữ:

- checkout success ≥99%;
- browse/cart success ≥99,5%;
- storefront p95 <1 giây;
- không tăng ngân sách cố định;
- sau đỉnh tải phải co tài nguyên xuống.

### 4.2. Vấn đề ban đầu

Nhiều service chỉ có một replica; chưa có cơ chế scale pod đầy đủ; observability và một số service có memory limit quá mỏng; Karpenter consolidation từng evict pod đúng lúc test; dashboard Cart còn đo sai tầng.

### 4.3. Kỹ thuật sử dụng

- **HPA:** scale các hot path theo CPU, có `minReplicas` và `maxReplicas` để tránh thiếu capacity hoặc scale vô hạn.
- **Spot burst:** capacity tăng tạm thời dùng Spot, baseline vẫn là on-demand.
- **`do-not-disrupt`:** khóa tạm workload nhạy cảm khỏi Karpenter disruption trong cửa sổ test; sau test phải gỡ để tránh cản tối ưu cost.
- **PgBouncer:** pool kết nối trước PostgreSQL, tránh mỗi pod mở quá nhiều connection khi HPA scale.
- **SLO windowing:** query Prometheus đúng cửa sổ test, không dùng gauge rolling 24h làm bằng chứng duy nhất.

### 4.4. Quá trình thực hiện

1. Viết ADR và runbook, chốt abort threshold.
2. Cài nền metric và HPA.
3. Rà resource limit, quota, topology spread, PDB và Karpenter disruption.
4. Chạy ramp nhỏ trước khi vào 200 user.
5. Chụp baseline, peak và after-state.
6. Dừng tải, xác nhận HPA co xuống và tính cost.

### 4.5. Kết quả

- Checkout: **99,9825%** theo report; Prometheus ghi nhận 0 `PlaceOrder` error trong cửa sổ chính.
- Browse/Cart: **100%**.
- Storefront p95: **46–48 ms**, thấp hơn nhiều so với ngưỡng 1.000 ms.
- HPA frontend: **2 → 7 → 2**.
- Không cần thêm node; cost khoảng **$0,40/giờ**, cost trên mỗi đơn giảm khi throughput tăng.
- Report ghi rõ: bài này chứng minh scale ở tầng **pod**, chưa chứng minh Karpenter phải thêm node vì capacity sẵn có đã đủ.

### 4.6. Bằng chứng

- ADR: [ADR Mandate #2](adr/0004-mandate-02-flash-sale-cdo02.md)
- Runbook: [Flash-sale load test](runbooks/flash-sale-load-test.md)
- Report: [Kết quả load test Mandate #2](mandate-02-load-test-report.md)
- Remediation: [Kế hoạch remediation](mandate-02-load-test-remediation-plan.md)
- Code HPA: [hpa-hotpath.yaml](../gitops/infrastructure/hpa-hotpath.yaml)
- Code connection pool tại thời điểm triển khai: [pgbouncer.yaml trong commit `b3f252f`](https://github.com/tuu-ngo/Phase3-TF3-Infra-Sentinel/blob/b3f252f/gitops/infrastructure/pgbouncer.yaml) (sau Mandate #8, PgBouncer self-hosted không còn nằm trong cây hiện hành)
- Commit nền CDO-02: [`3349fb1`](https://github.com/tuu-ngo/Phase3-TF3-Infra-Sentinel/commit/3349fb1)

### 4.7. Bài học

“Có HPA” không đồng nghĩa “đủ an toàn”: HPA cần metric, quota, headroom node, PDB, spread và policy disruption phù hợp. Đồng thời, tối ưu cost phải tính cả **cleanup sau test**, nếu để `do-not-disrupt` hoặc consolidation quá chậm thì hệ thống sẽ giữ node thừa.

---

## 5. Mandate #3 — Bảo trì node không downtime

### 5.1. Đề bài rút gọn

Drain hoặc rolling restart node giữa giờ có khách nhưng browse → cart → checkout vẫn giữ SLO; pod chưa Ready không nhận traffic; không giải quyết bằng cách nhân đôi mọi thứ.

### 5.2. Kỹ thuật sử dụng

- **Hai replica trên hai AZ:** tránh hai bản sao cùng chết theo một node/AZ.
- **`maxUnavailable: 0`, `maxSurge: 1`:** tạo pod mới trước khi bỏ pod cũ.
- **`preStop` + termination grace:** pod rút khỏi endpoint và xử lý nốt request.
- **PDB:** drain không được evict quá số bản cho phép.
- **ALB deregistration delay:** Load Balancer chờ connection cũ kết thúc trước khi bỏ target.
- **Readiness probe dependency-aware:** pod chỉ vào Service endpoint khi thật sự phục vụ được.

### 5.3. Quá trình thực hiện

1. Audit 10 service revenue path.
2. Bổ sung topology spread, rolling strategy và graceful shutdown.
3. Vá riêng `checkout` vì workload này đi qua Argo Rollouts, không được phủ đầy đủ ở lần đầu.
4. Chọn node app-tier đang chứa nhiều service lõi để bài test có ý nghĩa.
5. `cordon` → `drain` → theo dõi SLO và pod reschedule → `uncordon`.
6. Ghi nhận cả sự cố monitoring-plane, không che giấu.

### 5.4. Kết quả

- Checkout **99,94%**; Browse **100%**; Cart **99,95%**; p95 **68,6 ms**.
- Không pod revenue nào kẹt `Pending`.
- Grafana single-replica bị 502 khoảng một phút vì nằm trên node bị drain, nhưng revenue path không ảnh hưởng; nhóm chuyển sang theo dõi bằng terminal và đọc lại graph sau khi Grafana hồi.
- Datastore single-replica lúc đó được ghi là residual risk, sau này được Mandate #8 loại bỏ.

### 5.5. Bằng chứng

- ADR: [ADR Mandate #3](adr/0007-mandate-03-maintenance-no-downtime-cdo02.md)
- Runbook: [Drain-node demo](runbooks/mandate-03-drain-node-demo.md)
- Report: [Báo cáo drain node](mandate-03-drain-node-report.md)
- Planned stateful maintenance: [stateful-node-planned-maintenance.md](runbooks/stateful-node-planned-maintenance.md)
- Cấu hình production: [values-prod.yaml](<../phase3%20-%20information/deploy/values-prod.yaml>)
- Commit topology spread: [`d3d6863`](https://github.com/tuu-ngo/Phase3-TF3-Infra-Sentinel/commit/d3d6863)
- Commit graceful shutdown: [`ec08085`](https://github.com/tuu-ngo/Phase3-TF3-Infra-Sentinel/commit/ec08085)
- Commit ALB drain: [`7dfe5ec`](https://github.com/tuu-ngo/Phase3-TF3-Infra-Sentinel/commit/7dfe5ec)
- Commit vá checkout: [`1428600`](https://github.com/tuu-ngo/Phase3-TF3-Infra-Sentinel/commit/1428600)

### 5.6. Bài học

Replica count chỉ có ý nghĩa khi replica **thật sự tách failure domain**. Ngoài ra, “không downtime” cần cả phía application, scheduler và load balancer phối hợp; thiếu một trong ba vẫn có thể cắt request đang bay.

---

## 6. Mandate #8 — Chuyển ba datastore lên managed AWS

### 6.1. Đề bài rút gọn

Chuyển:

- PostgreSQL → Amazon RDS;
- Valkey → Amazon ElastiCache;
- Kafka → Amazon MSK;

với yêu cầu không mất dữ liệu, giữ SLO, mã hóa, không public endpoint, credential không nằm trong code và vẫn trong ngân sách.

### 6.2. Vì sao mandate này khó

Ba datastore cũ đều self-hosted, mỗi store chỉ có một bản. Đây là SPOF trên đường ra tiền. Tuy nhiên, chuyển dữ liệu khi hệ thống vẫn có ghi mới giống như “chuyển sổ kế toán khi cửa hàng vẫn đang bán hàng”: nếu thứ tự cutover sai sẽ mất bản ghi hoặc tạo split-brain.

### 6.3. Kỹ thuật theo từng store

#### Valkey → ElastiCache

Dùng **dual-write** trong thời gian ngắn: ghi cả store cũ và mới, sau đó so sánh cho tới khi hội tụ. Dual-write là kỹ thuật ghi cùng dữ liệu vào hai nơi để tạo đường lui; rủi ro là tăng latency và có thể lệch nếu một nhánh lỗi, nên chỉ giữ trong cửa sổ có kiểm soát.

Kết quả đối chiếu: **827/827 giỏ hàng khớp**.

#### PostgreSQL → RDS

Tạm **freeze writer** duy nhất (`accounting`), dump/restore, rồi replay phần phát sinh. Cách này chọn tính đúng dữ liệu hơn việc cho hai DB cùng nhận write không có cơ chế replication chuẩn.

Kết quả: số order **70.478 → 70.556**, phần tăng trong cửa sổ được ghi bù đầy đủ.

#### Kafka → MSK

Thứ tự là producer trước, consumer sau, theo dõi offset/lag và chỉ bỏ store cũ khi consumer mới bắt kịp. MSK dùng TLS + SCRAM, ba broker/ba AZ và replication.

Kết quả cuối: accounting và fraud-detection bắt kịp hoàn toàn, consumer lag về 0.

### 6.4. Hai sự cố lớn trong quá trình

#### Incident 0010 — Checkout outage khi cutover producer

`KAFKA_ADDR` của MSK chứa ba broker phân tách bằng dấu phẩy nhưng code nhét cả chuỗi vào một phần tử của slice. Sarama cố dial một địa chỉ sai và checkout panic.

Nhóm:

1. rollback về Kafka cũ known-good;
2. giữ hệ thống phục vụ lại;
3. tái hiện bằng pod cô lập;
4. thêm stderr log và fail-fast;
5. sửa parse bằng `strings.Split`;
6. verify TLS/SCRAM/idempotent producer trước khi cutover lại.

Chi tiết: [Postmortem 0010](postmortem/0010-mandate-08-kafka-producer-cutover-checkout-outage.md).

#### Incident 0012 — Batch NetworkPolicy chặn managed datastore

Policy của Mandate #5 được viết theo topology store cũ trong cluster, thiếu đường egress tới RDS/ElastiCache/MSK. Vì trùng thời điểm cutover, ban đầu Kafka bị nghi oan. Nhóm dùng một pod cấu hình cũ nhưng vẫn lỗi để loại trừ cutover, sau đó đối chiếu “pod có policy chết/pod không có policy sống”, backup policy và rollback toàn batch.

Chi tiết: [Postmortem 0012](postmortem/0012-mandate5-networkpolicy-batch-outage.md).

### 6.5. Kết quả và bằng chứng

- Hoàn tất 3/3 managed store.
- Parity/reconciliation của ba store ở lần migration cuối không phát hiện mất dữ liệu. Phải đọc cùng [Incident 0010](postmortem/0010-mandate-08-kafka-producer-cutover-checkout-outage.md): cửa sổ checkout panic trước khi publish đã làm mất một lượng event **bounded** không thể recover từ Kafka. Đây là impact của lần cutover lỗi, không được dùng kết quả parity sau đó để xóa khỏi lịch sử.
- Data at rest/in transit được mã hóa; endpoint private; secret qua AWS Secrets Manager/External Secrets.
- Store cũ được giữ làm đường lui tới khi nghiệm thu, sau đó mới gỡ theo GitOps.

Tài liệu:

- ADR: [ADR Mandate #8](adr/0009-mandate-08-managed-migration-cdo02.md)
- Tổng quan/quá trình: [mandate-08-tong-quan-va-qua-trinh.md](mandate-08-tong-quan-va-qua-trinh.md)
- Báo cáo tổng kết: [mandate-08-bao-cao-tong-ket.md](mandate-08-bao-cao-tong-ket.md)
- Biên bản nghiệm thu: [mandate-08-nghiem-thu.md](mandate-08-nghiem-thu.md)
- Runbook: [mandate-08-managed-cutover.md](runbooks/mandate-08-managed-cutover.md)
- Evidence index: [evidence/mandate-08/README.md](evidence/mandate-08/README.md)
- Hạ tầng datastore: [infra/modules/datastores](../infra/modules/datastores)
- Commit producer cutover: [`a8350da`](https://github.com/tuu-ngo/Phase3-TF3-Infra-Sentinel/commit/a8350da)
- Commit consumer cutover: [`42a0339`](https://github.com/tuu-ngo/Phase3-TF3-Infra-Sentinel/commit/42a0339)
- Commit gỡ dependency store cũ: [`b881bf1`](https://github.com/tuu-ngo/Phase3-TF3-Infra-Sentinel/commit/b881bf1)
- Commit tắt store self-hosted: [`87063d4`](https://github.com/tuu-ngo/Phase3-TF3-Infra-Sentinel/commit/87063d4)

### 6.6. Bài học

- Thay topology từ một endpoint sang nhiều endpoint phải có compatibility test riêng.
- Fail-fast biến lỗi cấu hình thành rollout bị chặn thay vì outage.
- Network/security policy phải được viết theo topology hiện hành, không theo sơ đồ cũ.
- Không xóa đường lui trước mentor acceptance chỉ để giảm cost sớm.

---

## 7. Mandate #9 — Vận hành managed store zero-downtime dưới tải

### 7.1. Đề bài rút gọn

Sau khi chuyển lên managed service, hệ thống phải chịu:

- online schema migration;
- nâng major version;
- thay parameter cần reboot;
- xoay credential;
- blip/failover của datastore;

trong giờ có tải và **0 request khách bị rớt**.

### 7.2. Thiết kế tổng

Solution v3.2 chia thành nền tảng và từng change window:

- **stale-cache + startup-latch** cho read path;
- **expand → dual-write → backfill → validate → contract** cho schema;
- accounting idempotent trước MSK rolling upgrade;
- reboot-with-failover có cache đỡ read;
- credential rotation kiểu alternating users, app rebuild connection pool theo generation;
- staging rehearsal trước production;
- production W1/W2 có approval riêng, đặc biệt W2 là bước contract phá hủy đường tương thích cũ.

**Expand/contract migration** nghĩa là thêm schema mới tương thích trước, cho cả code cũ/mới cùng chạy, backfill dữ liệu, rồi chỉ xóa schema cũ sau bake window. Kỹ thuật này tránh deploy code và DDL theo một “big bang”.

### 7.3. Phần M9-01 đã triển khai trong code

`product-catalog` trước đây query DB mỗi request và readiness phụ thuộc DB ping. Khi RDS failover, dù cache có dữ liệu thì pod vẫn bị rút khỏi endpoint.

M9-01 thay bằng:

- snapshot sản phẩm bất biến trong memory;
- `atomic.Pointer` swap snapshot, read không khóa;
- refresh 30 giây;
- lỗi refresh giữ **last-known-good**;
- retry 4 lần với tổng backoff 700 ms ở background, không nằm trên request khách;
- startup-latch: chỉ Ready sau lần prime đầy đủ đầu tiên;
- sau khi đã prime, DB down chỉ là degraded signal, pod vẫn Ready và serve stale;
- metric `cache_primed`, `ever_primed`, `cache_age_seconds`, `served_stale_total`, `db_retry_*`.

Unit test có **19 test** và `go test -race` PASS theo implementation note.

### 7.4. Trạng thái trung thực

- Thiết kế tổng: hoàn chỉnh ở mức solution/work breakdown.
- M9-01: code + unit test + chaos runbook đã có.
- Chưa tự deploy trong task M9-01; chưa có live chaos 60–120 giây chứng minh browse 0 fail.
- Các phần schema, MSK major upgrade, reboot parameter và alternating-user rotation chưa được phép ghi là hoàn tất.

### 7.5. Bằng chứng

- Solution: [mandate-09-zero-downtime-ops-solution.md](docx_cdo02/mandate-09-zero-downtime-ops-solution.md)
- Work breakdown: [mandate-09-work-breakdown.md](docx_cdo02/mandate-09-work-breakdown.md)
- M9-01 notes: [mandate-09-m9-01-catalog-implementation-notes.md](docx_cdo02/mandate-09-m9-01-catalog-implementation-notes.md)
- Chaos runbook: [mandate-09-m9-01-catalog-cache-chaos.md](runbooks/mandate-09-m9-01-catalog-cache-chaos.md)
- Code: [product-catalog/main.go](<../phase3%20-%20information/techx-corp-platform/src/product-catalog/main.go>)
- Test: [product-catalog/main_test.go](<../phase3%20-%20information/techx-corp-platform/src/product-catalog/main_test.go>)
- Commit M9-01: [`c8958ec`](https://github.com/tuu-ngo/Phase3-TF3-Infra-Sentinel/commit/c8958ec)

---

## 8. Mandate #11 — Chủ động phát hiện hành động audit nguy hiểm

### 8.1. Đề bài rút gọn

Audit trail không chỉ để điều tra sau sự cố. Khi có hành động nguy hiểm, hệ thống phải tự cảnh báo đúng người, có đủ ngữ cảnh và đo được time-to-detect.

### 8.2. Kiến trúc

```text
AWS API nguy hiểm
→ CloudTrail
→ EventBridge rule
→ Lambda audit-alert-router
→ SNS email
```

Lambda chuẩn hóa các trường:

- ai thực hiện;
- hành động gì;
- lúc nào;
- từ IP/region nào;
- target nào;
- severity;
- gợi ý điều tra;
- `time_to_detect_seconds`.

Nhóm xây danh mục sáu nhóm hành vi nguy hiểm và thêm allowlist có giới hạn để automation hợp lệ không gây alert fatigue.

### 8.3. Kết quả

| Demo | Event | TTD | Kết quả |
|---|---|---:|---|
| Group 2 | `CreateUser` | 4 giây | PASS |
| Group 3 | `AttachUserPolicy` | 2 giây | PASS |
| Group 5 | `GetSecretValue` | 2 giây | PASS |

Tất cả thấp hơn cam kết **≤5 phút** và email đã tới inbox thật.

### 8.4. Bằng chứng

- Report/evidence: [mandate11-completion-evidence-guide.md](docx_cdo02/mandate11-completion-evidence-guide.md)
- Review: [mandate11-audit-detection-review.md](docx_cdo02/mandate11-audit-detection-review.md)
- Terraform module: [infra/modules/audit-detection](../infra/modules/audit-detection)
- Lambda router: [lambda/index.py](../infra/modules/audit-detection/lambda/index.py)
- Commit guardrail: [`099843a`](https://github.com/tuu-ngo/Phase3-TF3-Infra-Sentinel/commit/099843a)

### 8.5. Bài học

Alert phải “hành động được”: chỉ báo `AccessDenied` là chưa đủ; người nhận cần actor, source, target và câu lệnh/hướng điều tra. Đồng thời, alert path cũng là một hệ thống cần được giám sát; mã hóa SNS bằng KMS nhưng thiếu quyền `GenerateDataKey` từng làm router không gửi được alert, sau đó đã được sửa trong chuỗi Mandate #12.

---

## 9. Mandate #12 — Audit anti-defeat

### 9.1. Đề bài rút gọn

Ngay cả người có quyền administrator cũng không được âm thầm tắt logging/alerting hoặc xóa bằng chứng. Giải pháp lý tưởng cần policy đứng cao hơn quyền trong workload account.

### 9.2. Thiết kế

CDO-02 thiết kế mô hình hai account:

- Account A là AWS Organizations management account.
- Account B là workload account.
- SCP ở A chặn kill-switch CloudTrail/S3/KMS và alert plane.
- Một break-glass maintainer role có quyền bảo trì giới hạn.

**SCP** là Service Control Policy: trần quyền ở cấp Organization. Dù một IAM principal trong member account có `AdministratorAccess`, SCP vẫn có thể từ chối hành động.

### 9.3. Vì sao không triển khai

Join workload account vào Organization giữa tháng làm credit của account B không phủ phần usage từ ngày join đến cuối tháng. Dựa trên run-rate thật, rủi ro phát sinh **$200–460 tiền thật**. Vì bài tập kết thúc 31/07, không thể chờ đầu tháng sau.

Nhóm trình bày ràng buộc và được mentor đồng ý **SKIP** phần SCP hard-prevention.

### 9.4. Phần đã làm

- Detection plane M11/M12 v1 vẫn live.
- CloudTrail data events, alert group, log validation và Object Lock COMPLIANCE đã có.
- Tạo `CDOAuditTeam`, hạ từ administrator xuống `ReadOnlyAccess`, chỉ cho assume maintainer role theo thiết kế.
- Viết đủ SCP, test matrix, rollout/rollback và cost analysis để tái sử dụng.

### 9.5. Trạng thái

**Đóng theo diện SKIP có phê duyệt; không claim PASS Mandate #12.** Detection có, nhưng lớp “administrator cũng không đánh bại được” chưa được chứng minh vì SCP chưa attach.

### 9.6. Bằng chứng

- Báo cáo: [mandate-12-report.md](mandate-12-report.md)
- Kế hoạch Org/SCP: [mandate-12-org-scp-execution-plan.md](mandate-12-org-scp-execution-plan.md)
- ADR: [ADR audit anti-defeat](adr/0011-mandate-12-audit-anti-defeat.md)
- CI boundary: [ci-audit-boundary.tf](../infra/bootstrap/github-oidc/ci-audit-boundary.tf)
- Commit báo cáo/thiết kế: [`bb11e1c`](https://github.com/tuu-ngo/Phase3-TF3-Infra-Sentinel/commit/bb11e1c)

---

## 10. Mandate #13 — Spot + Graviton nhưng không tạo SPOF

### 10.1. Đề bài rút gọn

Tăng tỷ lệ workload chạy trên Spot và Graviton để giảm cost, nhưng phải:

- vượt ngưỡng Spot yêu cầu;
- có arm64 live;
- chịu được một Spot node bị thu hồi;
- tăng khi có tải và co xuống khi hết tải;
- không tạo SPOF mới.

### 10.2. Kỹ thuật

- **Spot:** EC2 capacity giá thấp hơn nhưng AWS có thể thu hồi.
- **Graviton/arm64:** CPU ARM của AWS, thường có tỷ lệ giá/hiệu năng tốt hơn x86.
- **Multi-arch image:** một image reference có manifest cho cả `amd64` và `arm64`.
- **Taint/toleration/node affinity:** chỉ workload đã opt-in mới vào node arm64.
- **Karpenter consolidation:** thu hồi node thừa sau khi tải hạ.

### 10.3. Quyết định an toàn

Không chọn `recommendation` một replica để demo arm64 vì mất một Spot node sẽ làm service biến mất. Nhóm chọn `product-catalog` vì có hai replica, PDB, topology spread và image multi-arch.

### 10.4. Kết quả

- Có Spot `amd64` và Spot `arm64` thật.
- Spot ratio **5/9 = 55,6%** nếu tính cả node chaos exception; **5/8 = 62,5%** nếu tách exception.
- Pool Spot amd64 đạt `3/3`.
- Traffic browse/cart/checkout tăng thật.
- Drain Spot node có pod eviction và hệ thống không gãy.
- Sau khi hạ tải, node count **10 → 9**.
- Một on-demand node dành cho chaos được ghi rõ là exception tạm thời, không được tính như baseline cost dài hạn.

### 10.5. Bằng chứng

- ADR: [ADR Mandate #13](adr/0012-mandate-13-spot-graviton-rollout.md)
- Evidence report: [mandate-13-production-evidence-report.md](evidence/mandate-13/mandate-13-production-evidence-report.md)
- Runbook rollout: [mandate-13-production-rollout-plan.md](runbooks/mandate-13-production-rollout-plan.md)
- Karpenter config: [spot-nodepool.yaml](../gitops/karpenter/spot-nodepool.yaml)
- Runtime override: [values-mandate13.yaml](<../phase3%20-%20information/deploy/values-mandate13.yaml>)
- Commit rollout: [`de8dfef`](https://github.com/tuu-ngo/Phase3-TF3-Infra-Sentinel/commit/de8dfef)
- Commit runtime wiring: [`c98c1d6`](https://github.com/tuu-ngo/Phase3-TF3-Infra-Sentinel/commit/c98c1d6)

### 10.6. Bài học

Cost optimization chỉ tốt khi failure domain vẫn đúng. Đưa một service một replica lên Spot có thể tiết kiệm vài đô nhưng tạo SPOF mới; đó là tối ưu sai. Ngoài ra, tỷ lệ Spot phải công bố rõ cách tính và mọi exception.

---

## 11. Mandate #17 — Chịu dependency chết và mất một AZ

### 11.1. Phân công

- CDO-02: yêu cầu #1 dependency failure và #2 AZ failure.
- CDO-01: yêu cầu #3 NetworkPolicy và #4 RBAC.

### 11.2. Yêu cầu #1 — Dependency chết

Nhóm phân loại dependency:

- `ad`/`recommendation`: có thể timeout rồi trả rỗng, vì thiếu quảng cáo/gợi ý không làm sai đơn.
- `product-catalog`: không được bịa sản phẩm.
- `payment`: không được fake thành công.
- cart/checkout core path: fail-fast có deadline, không degrade thành dữ liệu giả.

CDO-02 thêm deadline/fallback cho các dependency phù hợp và pin image frontend chứa thay đổi ở commit `15175c6`.

**Deadline** là giới hạn thời gian RPC; không có deadline, một dependency treo có thể giữ connection/thread và kéo ngược cả frontend. **Fallback** là kết quả thay thế an toàn; chỉ dùng khi nghiệp vụ cho phép.

### 11.3. Yêu cầu #2 — Mất một AZ

Live evidence ngày 26/07 cho thấy:

- 10/10 service cốt lõi có hai replica ở hai AZ;
- PDB phủ hot path;
- RDS Multi-AZ, MSK ba AZ, ElastiCache multi-AZ;
- Grafana và Prometheus đã tách AZ bằng anti-affinity.

Caveat: phần lớn service amd64 từng tập trung trên hai Spot node ở 1a và 1c. Mất một AZ vẫn còn replica nhưng dồn tải lên một Spot node còn lại; đúng về availability tối thiểu nhưng headroom mỏng.

### 11.4. Trạng thái trung thực

- Req#2 có live placement evidence và được đánh giá ĐẠT về kiến trúc/phân bố.
- Req#1 code đã merge và image digest được re-bump; report ngày 26/07 trước re-bump vẫn ghi “chưa deploy”, nên không dùng report cũ để claim live chaos PASS.
- Runbook FIS mất AZ đã có, nhưng trong bộ evidence được rà cho báo cáo này chưa có result report đầy đủ chứng minh một lần FIS AZ-loss hoàn chỉnh.
- Vì vậy kết luận đúng là **phần CDO-02 cơ bản đạt, còn caveat/evidence cần trình bày trung thực**, không ghi “toàn Mandate #17 PASS tuyệt đối”.

### 11.5. Bằng chứng

- Gap analysis: [mandate-17-reliability-gap-analysis.md](docx_cdo02/mandate-17-reliability-gap-analysis.md)
- Progress update: [mandate-17-progress-update-2026-07-26.md](evidence/mandate-17/mandate-17-progress-update-2026-07-26.md)
- AZ evidence: [rel-17-04-and-req2-az-resilience-2026-07-26.md](evidence/mandate-17/rel-17-04-and-req2-az-resilience-2026-07-26.md)
- FIS runbook: [mandate-17-fis-az-drill.md](runbooks/mandate-17-fis-az-drill.md)
- Commit anti-affinity: [`20128a9`](https://github.com/tuu-ngo/Phase3-TF3-Infra-Sentinel/commit/20128a9)
- Commit image re-bump/evidence: [`15175c6`](https://github.com/tuu-ngo/Phase3-TF3-Infra-Sentinel/commit/15175c6)
- Incident chứng minh failure mode: [Postmortem 0011](postmortem/0011-btc-injected-productcatalogfailure-checkout-degradation.md)

---

## 12. Mandate #18 — Cắt chi phí ẩn ngoài node compute

### 12.1. Đề bài rút gọn

Không chỉ nhìn tiền EC2 node. Phải tìm và cắt:

- data transfer/NAT/VPC endpoint;
- storage sai loại hoặc mồ côi;
- telemetry không có retention/cardinality control;
- top cost-driver có thể tối ưu;

nhưng vẫn giữ SLO và khả năng điều tra.

### 12.2. Kỹ thuật và kết quả

#### VPC endpoint

Trước: 5 interface endpoint × 3 AZ = **15 ENI**, khoảng **$142/tháng**, trong khi NAT data processing thật chỉ khoảng $7/tháng.

Sau:

- bỏ ECR API/DKR endpoint;
- giữ S3 gateway miễn phí;
- thu ba SSM endpoint về AZ có bastion;
- còn **3 ENI**;
- tiết kiệm khoảng **$114/tháng** (~$26/tuần).

#### Log retention

OpenSearch log index tăng khoảng 1 GB/ngày nhưng không có lifecycle. Nhóm thêm CronJob xóa index `otel-logs` cũ hơn bảy ngày. Chọn CronJob thay vì chỉ dựa vào policy trong OpenSearch vì OpenSearch hiện dùng `emptyDir`; CronJob được GitOps dựng lại sau restart.

#### Metric cardinality

Prometheus có **233.042 active series**, riêng histogram bucket apiserver/etcd chiếm phần lớn nhưng không phục vụ SLO sản phẩm. Nhóm drop bucket, giữ `_count`/`_sum`.

Sau: **82.701 series**, giảm **64,5%**.

**Cardinality** là số lượng time series khác nhau. Cardinality quá cao làm Prometheus tốn RAM/CPU/storage ngay cả khi dashboard không dùng.

#### Trace

Nhóm quyết định **không thêm tail sampling**. Jaeger memory backend đã cap 25.000 trace; span rate khoảng 42/s; thêm tail sampling đúng cần routing theo trace ID và có thể làm sai spanmetrics dùng cho canary. Payoff cost gần 0 nhưng rủi ro reliability cao.

#### Orphan storage

Sau khi Mandate #8 được nghiệm thu, nhóm gỡ PVC khỏi GitOps source để ArgoCD prune đúng cách. Kết quả:

- 0 EBS `available`;
- 0 volume gp2;
- không xóa tay để tránh ArgoCD self-heal dựng lại volume.

### 12.3. Xác nhận không “cắt mù”

Sau thay đổi:

- Checkout/Cart/Browse success đều **100%** trong cửa sổ đo;
- p95 checkout 18 ms, frontend 42 ms, cart 3,6 ms;
- bảy Prometheus target vẫn up;
- OpenSearch còn log gần;
- Jaeger còn trace;
- SSM 5/5 instance Online.

### 12.4. Bằng chứng

- Báo cáo nghiệm thu: [mandate-18-nghiem-thu.md](mandate-18-nghiem-thu.md)
- Cost breakdown: [cost-breakdown-2026-07-22.md](cost-breakdown-2026-07-22.md)
- ADR trace: [ADR 0013](adr/0013-mandate-18-trace-sampling-cdo02.md)
- VPC endpoint code: [infra/modules/network/main.tf](../infra/modules/network/main.tf)
- Log retention code: [otel-logs-retention-cronjob.yaml](<../phase3%20-%20information/techx-corp-chart/templates/otel-logs-retention-cronjob.yaml>)
- Metric relabel code: [values.yaml](<../phase3%20-%20information/techx-corp-chart/values.yaml>)
- Commit trim endpoint: [`183cc8a`](https://github.com/tuu-ngo/Phase3-TF3-Infra-Sentinel/commit/183cc8a)
- Commit log retention: [`68f9769`](https://github.com/tuu-ngo/Phase3-TF3-Infra-Sentinel/commit/68f9769)
- Commit metric filtering: [`c42dee1`](https://github.com/tuu-ngo/Phase3-TF3-Infra-Sentinel/commit/c42dee1)

### 12.5. Bài học

“Private endpoint luôn rẻ hơn NAT” là sai nếu traffic nhỏ nhưng endpoint nhân theo nhiều AZ. Tương tự, giảm telemetry tốt chỉ khi giữ signal cần điều tra; bỏ histogram bucket control-plane nhưng giữ count/sum là cắt có chọn lọc.

---

## 13. Mandate #20 — Backup/Restore DR

### 13.1. Đề bài rút gọn

Không được kết luận đạt chỉ vì backup đang bật. Phải:

- làm restore drill thật;
- gây corruption có kiểm soát;
- khôi phục về thời điểm tốt;
- đo RPO/RTO;
- không làm ảnh hưởng production;
- ghi rõ phạm vi store và quyền xóa backup.

### 13.2. Kỹ thuật PITR

**PITR** (Point-in-Time Restore) khôi phục DB về một mốc thời gian trong cửa sổ backup. RDS tạo một DB instance mới từ log/backup, không overwrite production.

Quy trình:

1. tạo marker `GOOD_BEFORE_CORRUPTION`;
2. ghi `T_good_commit`;
3. đổi marker thành `CORRUPTED_AFTER_GOOD_TIME`;
4. chọn `T_restore` nằm giữa hai commit;
5. restore sang RDS drill private tách biệt;
6. query DB drill;
7. xác nhận marker tốt quay lại;
8. đo thời gian restore.

### 13.3. Kết quả

- RDS restore correctness: **PASS**.
- RPO target ≤5 phút; mốc restore cách good commit **41,248 giây**; marker phục hồi đúng; mất 0 row.
- RTO target ≤45 phút; đo được **23,83 phút**.
- Không đổi app secret/connection string, không restart workload, không repoint traffic.
- Production vẫn giữ marker corrupted như dự kiến, chứng minh query không nhầm production với drill DB.

### 13.4. Giới hạn

Evidence này không tự chứng minh backup/restore đầy đủ cho Valkey, MSK, DynamoDB, EBS hoặc separation quyền xóa backup. Vì vậy trạng thái đúng là **PASS RDS drill scope**; Mandate #20 tổng chỉ Done khi mentor/PM chấp nhận scope/limitation và delete-authority posture.

Evidence tại thời điểm ghi còn để trạng thái cleanup RDS drill là pending/chờ xác nhận sau khi upload và review. Đây là tài nguyên tính phí tạm thời, nên phải hậu kiểm việc xóa instance drill; không nên mặc định “drill xong” đồng nghĩa cleanup đã xong.

### 13.5. Bằng chứng

- ADR: [ADR Mandate #20](adr/0016-mandate-20-backup-restore-drill-cdo02.md)
- Solution: [mandate-20-rds-pitr-restore-solution.md](docx_cdo02/mandate-20-rds-pitr-restore-solution.md)
- Runbook: [mandate-20-rds-pitr-drill.md](runbooks/mandate-20-rds-pitr-drill.md)
- Final evidence: [mandate-20-final-rds-pitr-evidence-20260729.md](evidence/mandate-20/mandate-20-final-rds-pitr-evidence-20260729.md)
- Evidence index: [evidence/mandate-20/README.md](evidence/mandate-20/README.md)
- Commit evidence: [`08c8b5e`](https://github.com/tuu-ngo/Phase3-TF3-Infra-Sentinel/commit/08c8b5e)

---

# PHẦN II — CÁCH NHÓM XỬ LÝ KHI BTC BẬT INCIDENT

## 14. Cơ chế BTC fault injection

BTC dùng `flagd` để bật lỗi có kiểm soát trong service. Đây là **fault injection**: cố ý tạo lỗi để kiểm tra khả năng phát hiện, khoanh vùng và chịu lỗi.

Quy tắc quan trọng:

- TF không được gỡ/tắt/né đường đọc flag.
- Nhóm chỉ được đọc trạng thái qua OFREP và xử lý hệ thống như khi gặp lỗi thật.
- Khi flag tự về `off`, hệ thống phải tự hồi phục.
- Không được “làm đẹp SLO” bằng cách đổi lỗi thật thành success giả.

**OFREP** là giao thức đánh giá feature flag. Query OFREP cho biết flag nào đang on/off và giúp phân biệt lỗi BTC bơm với crash/datastore outage.

---

## 15. Quy trình ứng phó chuẩn của CDO-02

### 15.1. Phát hiện và đóng khung thời gian

Nhóm lấy mốc đầu/cuối từ:

- Grafana;
- Prometheus `increase()` theo cửa sổ 2–5 phút;
- timestamp log;
- BTC thông báo.

Không dùng “khoảng lúc đó” nếu metric có thể xác định chính xác.

### 15.2. Đo impact ở tầng khách hàng

Nhóm tách:

- `PlaceOrder` có lỗi thật không;
- browse/cart route nào bị ảnh hưởng;
- error chỉ nằm ở child span hay lan tới parent request;
- request fail trước hay sau Payment/Shipping/Kafka.

Việc xác định fail xảy ra trước payment giúp kết luận có hay không rủi ro tài chính/dữ liệu.

### 15.3. Dựng chuỗi nhân quả

```text
Grafana SLO dip
→ Prometheus xác định service/span gốc
→ Jaeger tìm trace đại diện
→ log xác nhận chữ ký lỗi
→ OFREP xác nhận flag
→ đọc code xác nhận nhánh flag và hành vi lan truyền
```

### 15.4. Loại trừ giả thuyết cạnh tranh

Nhóm kiểm tra:

- pod restart/OOM;
- datastore health;
- NetworkPolicy;
- Kafka lag;
- flag khác;
- thay đổi deploy trùng thời gian.

Chỉ kết luận root cause khi một chuỗi bằng chứng giải thích đầy đủ cả thời gian, service gốc và impact.

### 15.5. Phục hồi

Với BTC injection, nhóm **không tự tắt flag**. Nếu flag đã tự `off`, nhóm:

- xác nhận error rate về 0;
- xác nhận pod/dependency khỏe;
- kiểm tra dữ liệu/side effect;
- không deploy một “fix” vô nghĩa cho lỗi cố ý.

Nếu incident làm lộ resilience gap thật, gap được đưa vào backlog/mandate tiếp theo.

### 15.6. Postmortem

Mỗi postmortem dùng cấu trúc:

- When;
- Where;
- What;
- Why;
- Impact;
- How to fix/prevent;
- lệnh tái lập;
- bằng chứng metric/log/trace/code.

---

## 16. Các incident BTC đã bật

### 16.1. `paymentFailure` — 14/07/2026

| Thuộc tính | Kết quả |
|---|---|
| Cửa sổ | 14:22:16–14:34, khoảng 12 phút |
| Owner điều tra chính | CDO-01; CDO-02 dùng làm mẫu đối chiếu incident về sau |
| Triệu chứng | Checkout fail nhanh 34–59 ms, không treo 15 giây |
| Mẫu Locust | 28/33 checkout fail, khoảng 85% |
| Root cause | BTC bật `paymentFailure` qua flagd |
| Phục hồi | Flag tự `off`; hệ thống tự hồi |
| Dữ liệu | Không có cleanup dữ liệu; đây là payment rejection có kiểm soát |

Điểm kỹ thuật quan trọng: chữ ký “fail nhanh” giúp phân biệt incident này với Kafka producer race trước đó, vốn treo tới timeout 15 giây.

Bằng chứng: [Postmortem 0004](postmortem/0004-btc-injected-payment-failure-flag.md).

### 16.2. `cartFailure` — 15/07/2026

| Thuộc tính | Kết quả |
|---|---|
| Cửa sổ | 18:48:38–19:02:44, khoảng 14 phút |
| Owner | CDO-02 |
| Triệu chứng | Panel Checkout Success Rate tụt dưới 99% |
| Root cause | BTC bật `cartFailure`; RPC `EmptyCart` lỗi |
| Impact thật | **0 đơn fail**; `PlaceOrder` vẫn thành công |
| Side effect | Có thể còn sản phẩm trong giỏ sau khi mua |
| Phục hồi | Flag tự `off`; 0 lỗi trong 5 phút hậu kiểm |

Đây là ví dụ điển hình về **SLO đo sai scope**. Dashboard cộng mọi span của `checkout`, gồm cả child span `EmptyCart` mà code cố ý nuốt lỗi. Nhóm query theo `span_name="oteldemo.CheckoutService/PlaceOrder"` và xem Jaeger để chứng minh parent request vẫn xanh.

Hành động sau incident:

- scope SLO về span quyết định đơn;
- giữ panel phụ cho downstream span errors;
- không gỡ `cartFailure`;
- không retry vô ích vì flag boolean sẽ tiếp tục fail trong suốt thời gian on.

Bằng chứng: [Postmortem 0005](postmortem/0005-btc-injected-cart-failure-flag.md).

### 16.3. `productCatalogFailure` — 20/07/2026

| Thuộc tính | Kết quả |
|---|---|
| Cửa sổ | khoảng 00:17–00:41, 24 phút |
| Owner | CDO-02 |
| Service gốc | `product-catalog` |
| SKU bị bơm lỗi | `OLJCESPC7Z` |
| Checkout impact | 617/4.038 `PlaceOrder` lỗi = **15,3%** |
| Catalog impact | 5.457/71.038 `GetProduct` lỗi = **7,7%** |
| Dữ liệu/tài chính | Không rủi ro; flow abort trước Payment/Shipping/Kafka |
| Detection | Thủ công qua Grafana; alert tự động lúc đó còn hở |

Nhóm chứng minh quan hệ nhân quả 1:1 giữa `GetProduct` lỗi từ checkout và `PlaceOrder` lỗi; loại trừ payment, PostgreSQL, Kafka và cart. Flag tự `off`, hệ thống hồi phục. Tuy nhiên incident chứng minh một dependency lỗi có thể lan ngược làm thủng checkout SLO, trở thành input trực tiếp cho Mandate #17 deadline/fallback.

Bằng chứng: [Postmortem 0011](postmortem/0011-btc-injected-productcatalogfailure-checkout-degradation.md).

---

## 17. So sánh ba incident BTC

| Incident | Customer request có fail? | Dữ liệu/tài chính | Cơ chế chịu lỗi | Gap phát hiện được |
|---|---:|---|---|---|
| `paymentFailure` | Có, fail nhanh | Không có bằng chứng mất dữ liệu | Fail rõ, không timeout dây chuyền | Cần phân biệt lỗi nghiệp vụ với timeout hạ tầng |
| `cartFailure` | Không | Không mất đơn; có thể còn giỏ | Checkout nuốt lỗi bước hậu xử lý | SLO dashboard đo quá rộng, tạo error-budget ảo |
| `productCatalogFailure` | Có, 15,3% checkout | Abort trước charge/ship/publish | Chưa có fallback phù hợp lúc incident | Cần deadline/fallback và alert tự động |

Điểm đáng chú ý: **không phải mọi error span đều là request fail, và không phải mọi dependency đều được fallback giống nhau**. CDO-02 dùng nghiệp vụ để quyết định:

- có thể bỏ quảng cáo/gợi ý;
- có thể bỏ qua lỗi xóa giỏ sau khi đơn đã chốt;
- không được bịa sản phẩm hoặc giả payment thành công.

---

## 18. Incident phát sinh trong lúc thực thi mandate

Ngoài fault injection của BTC, nhóm còn xử lý các incident thực trong quá trình triển khai:

| Incident | Ảnh hưởng | Cách xử lý chính | Report |
|---|---|---|---|
| Accounting OOM + ECR lifecycle xóa image | 44 restart; 17/20 image bị expire | Tăng memory, tắt lifecycle sai, rebuild 20 image, viết preview runbook | [0001](postmortem/0001-accounting-oomkill-and-ecr-lifecycle-incident.md) |
| Kafka→MSK producer cutover | Checkout outage ~14 phút, mất bounded event | Rollback Kafka cũ, pod cô lập, stderr/fail-fast, sửa parse multi-broker | [0010](postmortem/0010-mandate-08-kafka-producer-cutover-checkout-outage.md) |
| NetworkPolicy batch | Checkout + 3 service outage ~30 phút | Loại trừ cutover, backup và rollback cả batch, viết lại theo managed topology | [0012](postmortem/0012-mandate5-networkpolicy-batch-outage.md) |
| Terraform ForceNew thay bastion | Mất đường SSM nội bộ | Xác định diff `ForceNew`, chuyển runbook/script sang tra instance ID động | [0013](postmortem/0013-terraform-forcenew-bastion-replacement-ssm-lockout.md) |
| Bastion egress quá chặt | Không tunnel được RDS/ElastiCache | Mở 5432/6379 giới hạn trong VPC CIDR | [0014](postmortem/0014-pm126-bastion-egress-lockdown-blocks-rds-tunnel.md) |
| EKS API bị mở public bằng tay | Phơi nhiễm 7 giờ 20 phút; không có truy cập thành công trái phép | Đóng public endpoint, đối chiếu code/state/live, audit CloudTrail, đề xuất drift detection | [0015](postmortem/0015-manual-eks-public-endpoint-exposure.md) |

Mẫu chung rút ra:

- phục hồi customer path trước;
- giữ evidence;
- không quy nguyên nhân theo việc “vừa làm gần nhất”;
- tìm discriminator độc lập;
- sửa nguyên nhân hệ thống, không chỉ triệu chứng;
- biến bài học thành code/runbook/alert.

---

# PHẦN III — ĐÁNH GIÁ TỔNG THỂ

## 19. Những kỹ thuật mang lại giá trị lớn nhất

### 19.1. Phân tách failure domain

Hai replica chỉ có giá trị khi nằm khác node/AZ. Topology spread + PDB + graceful shutdown là nền cho Mandate #3, #13 và #17.

### 19.2. Managed service không tự động bảo đảm zero-downtime

RDS Multi-AZ/MSK/ElastiCache loại SPOF hạ tầng, nhưng application vẫn cần:

- retry có giới hạn;
- stale cache;
- idempotency;
- connection pool rebuild;
- readiness đúng;
- migration expand/contract.

Mandate #9 tồn tại chính vì “managed” không đồng nghĩa “mọi failover vô hình với khách”.

### 19.3. Fail-fast và health check đúng nghĩa

Một pod cấu hình sai nhưng vẫn Ready nguy hiểm hơn pod không khởi động. Fail-fast, startup-latch và dependency-aware readiness biến lỗi thành rollout bị chặn, giảm blast radius.

### 19.4. Đo theo nghiệp vụ

`PlaceOrder` success, order reconciliation và cart parity đáng tin hơn trạng thái pod hoặc tổng error span. Incident `cartFailure` chứng minh đo sai scope có thể dẫn đến kết luận sai dù metric hoàn toàn “đúng” về mặt kỹ thuật.

### 19.5. Cost có guardrail

Nhóm không giảm chi phí bằng cách:

- cắt replica lõi xuống một;
- tắt telemetry;
- xóa backup/rollback sớm;
- ép mọi workload lên Spot.

Thay vào đó, nhóm cắt lãng phí không tạo giá trị: endpoint ENI dư, histogram bucket không dùng, log vô hạn, EBS orphan.

---

## 20. Các điểm chưa được phép tô xanh

1. **Mandate #9:** mới hoàn thành code/test M9-01; chưa có live chaos evidence và chưa triển khai các change window còn lại.
2. **Mandate #12:** SKIP có phê duyệt, không phải PASS. SCP chưa attach.
3. **Mandate #17:** req#2 có live placement evidence; req#1 đã re-bump image nhưng bộ report chốt chưa chứng minh live fault test hoàn chỉnh; AZ-loss FIS cần result evidence rõ.
4. **Mandate #20:** RDS PITR PASS; non-RDS coverage và quyền xóa backup vẫn là limitation cần accepted scope.
5. **Mandate #2:** node scale-up bằng Karpenter không xảy ra vì capacity sẵn có đủ; evidence mạnh nằm ở HPA pod scale.
6. **Mandate #3:** demo app-tier PASS; Grafana single-replica từng blip và stateful tier khi đó còn residual, sau này mới được M8 giải quyết.

---

## 21. Ma trận truy vết nhanh

| Chủ đề | Quyết định | Code/IaC | Runbook | Runtime evidence |
|---|---|---|---|---|
| Flash sale | [ADR #2](adr/0004-mandate-02-flash-sale-cdo02.md) | [HPA](../gitops/infrastructure/hpa-hotpath.yaml) | [Load test](runbooks/flash-sale-load-test.md) | [Report #2](mandate-02-load-test-report.md) |
| Maintenance | [ADR #3](adr/0007-mandate-03-maintenance-no-downtime-cdo02.md) | [values-prod](<../phase3%20-%20information/deploy/values-prod.yaml>) | [Drain](runbooks/mandate-03-drain-node-demo.md) | [Report #3](mandate-03-drain-node-report.md) |
| Managed migration | [ADR #8](adr/0009-mandate-08-managed-migration-cdo02.md) | [Datastores module](../infra/modules/datastores) | [Cutover](runbooks/mandate-08-managed-cutover.md) | [Acceptance #8](mandate-08-nghiem-thu.md) |
| Zero-downtime ops | [Solution #9](docx_cdo02/mandate-09-zero-downtime-ops-solution.md) | [Catalog cache](<../phase3%20-%20information/techx-corp-platform/src/product-catalog/main.go>) | [M9-01 chaos](runbooks/mandate-09-m9-01-catalog-cache-chaos.md) | Chưa có live chaos result |
| Audit detection | [M11 review](docx_cdo02/mandate11-audit-detection-review.md) | [Audit module](../infra/modules/audit-detection) | Demo trong evidence guide | [M11 evidence](docx_cdo02/mandate11-completion-evidence-guide.md) |
| Audit anti-defeat | [ADR #12](adr/0011-mandate-12-audit-anti-defeat.md) | [CI boundary](../infra/bootstrap/github-oidc/ci-audit-boundary.tf) | [Org/SCP plan](mandate-12-org-scp-execution-plan.md) | [SKIP report](mandate-12-report.md) |
| Spot/Graviton | [ADR #13](adr/0012-mandate-13-spot-graviton-rollout.md) | [NodePool](../gitops/karpenter/spot-nodepool.yaml) | [Rollout](runbooks/mandate-13-production-rollout-plan.md) | [M13 evidence](evidence/mandate-13/mandate-13-production-evidence-report.md) |
| Dependency/AZ | [Gap analysis #17](docx_cdo02/mandate-17-reliability-gap-analysis.md) | [values-prod](<../phase3%20-%20information/deploy/values-prod.yaml>) | [FIS AZ drill](runbooks/mandate-17-fis-az-drill.md) | [AZ evidence](evidence/mandate-17/rel-17-04-and-req2-az-resilience-2026-07-26.md) |
| Hidden cost | [ADR trace #18](adr/0013-mandate-18-trace-sampling-cdo02.md) | [Network](../infra/modules/network/main.tf) + [retention](<../phase3%20-%20information/techx-corp-chart/templates/otel-logs-retention-cronjob.yaml>) | Các lệnh verify trong report | [M18 acceptance](mandate-18-nghiem-thu.md) |
| Backup/restore | [ADR #20](adr/0016-mandate-20-backup-restore-drill-cdo02.md) | RDS managed bởi [datastores module](../infra/modules/datastores) | [PITR drill](runbooks/mandate-20-rds-pitr-drill.md) | [RDS evidence](evidence/mandate-20/mandate-20-final-rds-pitr-evidence-20260729.md) |

---

## 22. Kết luận

Đóng góp lớn nhất của CDO-02 không nằm ở một manifest riêng lẻ, mà ở việc xây được một chuỗi vận hành có thể kiểm chứng:

```text
Mandate
→ hợp đồng nghiệm thu
→ audit failure mode
→ ADR/solution
→ code/IaC/GitOps
→ preflight + rollout + rollback
→ metric/log/trace/evidence
→ postmortem và backlog tiếp theo
```

Kết quả rõ nhất:

- hệ thống chịu được flash sale 200 user mà không tăng node;
- drain node app-tier không làm mất SLO;
- ba datastore SPOF được chuyển lên managed HA;
- Spot/Graviton được đưa vào production có kiểm soát;
- hidden cost giảm định lượng mà không làm mất observability;
- audit alert có TTD tính bằng giây;
- RDS restore drill có RPO/RTO thật;
- incident BTC được phân tích bằng metric + trace + log + code, không đoán mò và không vô hiệu hóa fault injection.

Điểm cần giữ khi trình bày với BTC/mentor là tính trung thực của trạng thái: **PASS đúng phạm vi, không lấy code thay cho runtime evidence, không gọi SKIP là đạt, và không coi “backup bật” hay “pod Running” là bằng chứng đủ cho Reliability.**
