# Kịch bản trình bày CDO02 — Mentor Review (15-20 phút)

**Trụ phụ trách:** Reliability + Cost Optimization
**Ngày:** 10/07/2026
**Đã đối chiếu với:** Meeting note liên team AI/CDO01/CDO02, 09/06/2026 (backlog chung `P01`-`P25`)

---

## Phần 1 — Hiểu hệ thống (~5-6 phút)

**Kiến trúc (30-45 giây, đừng sa đà):**
> "Hệ thống là fork của OpenTelemetry Demo — 20 microservice, giao tiếp qua gRPC/HTTP, dùng chung 3 datastore: Postgres (đơn hàng/review/kế toán), Valkey (giỏ hàng), Kafka (event đơn hàng). Chạy trên EKS, 3 node t3.large, VPC riêng, API private-only qua SSM bastion. Public qua CloudFront + ALB, HTTPS miễn phí. Observability có sẵn: Prometheus, Grafana, Jaeger."

**SLO đang giữ (30 giây — đọc đúng số, mentor sẽ hỏi ngay):**

| Luồng | SLO |
|---|---|
| Duyệt sản phẩm (non-5xx) | ≥ 99.5% |
| Duyệt sản phẩm (p95 latency) | < 1s |
| Giỏ hàng | ≥ 99.5% |
| **Checkout** | **≥ 99.0%** (ưu tiên cao nhất — ra tiền trực tiếp) |

> "Checkout chỉ có 1% error budget. Toàn bộ backlog của tôi được xếp hạng theo thứ tự bảo vệ đúng luồng này trước."

**3-4 rủi ro lớn nhất (phần quan trọng nhất, ~3-4 phút):**

1. **`replicas: 1` toàn hệ thống — không có bản dự phòng cho bất kỳ service nào.** Đã có bằng chứng thật: lúc rolling-replace node hôm nay (đổi K8s version 1.31→1.32), pod trên đường checkout có gián đoạn ngắn — chứng minh đây không phải rủi ro lý thuyết.
2. **Health check giả** — `checkout`, `payment`, `product-catalog`... đều trả `SERVING` cố định, không kiểm tra dependency thật. Nghĩa là dù thêm probe (readiness/liveness), K8s vẫn không biết pod nào thực sự "chết" bên trong.
3. **Kafka fire-and-forget + accounting auto-commit trước khi xử lý xong** (phát hiện đọc code sâu) — khách có thể **bị charge tiền nhưng đơn hàng biến mất hoàn toàn khỏi hệ thống kế toán**, không log, không dấu vết. Rủi ro tài chính nặng nhất tìm được.
4. **0 PVC trong toàn cluster** — không chỉ giỏ hàng (Valkey), mà cả Postgres và Kafka cũng không có persistent storage. Restart pod bất kỳ = mất dữ liệu vĩnh viễn.
5. **(Mới, từ họp 09/06) ALB đang public trực tiếp, chưa enforce CloudFront-only** — vừa dựng CloudFront xong nhưng ai biết DNS name của ALB vẫn vào thẳng được, né hoàn toàn CloudFront. Đây là câu hỏi P16 team đang mở, tôi chủ động nêu trước khi bị hỏi.

> Bonus nếu còn thời gian: hôm nay bắt được bằng chứng sống — Grafana + Jaeger cùng bị OOMKilled cách nhau đúng 1 phút, nghi do traffic công khai mới (vừa dựng CloudFront) vượt limit cũ đặt từ lúc chỉ có traffic nội bộ. Cho thấy: **rủi ro không tĩnh, thay đổi hạ tầng cũng tạo rủi ro mới cần theo dõi liên tục.**

---

## Phần 2 — Backlog ưu tiên (~5-6 phút)

**Công thức xếp hạng:** Rủi ro (khả năng × mức nghiêm trọng) × Tác động business, theo SLO/BUDGET/INCIDENT_HISTORY của BTC. **Đã họp với AI + CDO01 (09/06) và chốt thành backlog chung `P01`-`P25`** — số dưới đây dùng mã chung, có ghi chú owner để rõ phần nào CDO02 trực tiếp làm.

**Phần CDO02 trực tiếp sở hữu — nêu kỹ (đọc lướt, đừng đọc hết cả bảng):**

| Mã | Việc | Owner | Vì sao ưu tiên |
|---|---|---|---|
| **P01** | Sửa health check giả thành kiểm tra dependency thật | CDO02 | Nền tảng — không sửa trước thì P02 (probe) vô nghĩa |
| **P04** | Rollback/refund checkout khi ship lỗi sau charge | CDO02 | Rủi ro tài chính trực tiếp, khách bị trừ tiền không hoàn |
| **P05** | Sửa accounting auto-commit quá sớm | CDO02 | Mất đơn hàng **âm thầm hoàn toàn** — nặng nhất tìm được |
| **P06** | Kafka ack/retry/dead-letter queue | CDO02 | Cùng gốc P05 — 2 lỗ hổng cộng dồn trên 1 luồng dữ liệu tài chính |
| **P13** | Connection pool Postgres (catalog/review/accounting) | CDO02 | Vá đúng nguyên nhân gốc 1 sự cố đã xảy ra thật (INC-1) |
| **P14** | Valkey cart persistence | CDO02 | Restart pod = mất giỏ hàng toàn bộ khách đang thao tác |

**Phần CDO02 phối hợp cùng CDO01 (chia việc rõ, không giẫm chân):**

| Mã | Việc | Ghi chú |
|---|---|---|
| **P02** | Thêm readiness/liveness probe | Phụ thuộc P01 xong trước |
| **P03** | Tăng replicas + PDB nhóm checkout | Tác động business cao nhất trong toàn bộ backlog |
| **P09** | Sửa Grafana/Jaeger OOM | **Đang active ngay lúc pitch** — Grafana restart 9 lần trong ngày, mất khả năng quan sát |
| **P10** | Alert cho OOMKilled/restart/readiness fail | Nền tảng để phát hiện sớm mọi sự cố khác, không riêng gì backlog này |

**Phần đã bàn giao hẳn cho CDO01 qua họp (nêu 1 câu để mentor biết CDO02 không bỏ sót, chỉ không tự ôm việc ngoài trụ):**
> "P07 (metrics-server), P08 (baseline load test), P11 (HPA), P12 (CPU requests/limits), P15 (NetworkPolicy), P16 (ingress boundary), P18 (ResourceQuota), P22 (Cluster Autoscaler) — tôi là người phát hiện ra hầu hết các vấn đề này lúc đọc code/runtime, nhưng qua họp 09/06 đã chốt CDO01 chủ trì vì thuộc đúng trụ Performance Efficiency + Security của họ. Tôi bàn giao evidence đầy đủ, không tự làm để tránh giẫm chân."

**Cost (CDO02 tự giữ, không có mã P chung — nêu ngắn):**
- **COST-01** — viết lại ECR lifecycle policy đúng cách (bài học từ chính sự cố tự gây ra).
- **COST-07 (đã làm)** — 1 NAT Gateway thay vì 3, tiết kiệm ~2/3 chi phí NAT ngay từ lúc dựng baseline.

---

## Phần 3 — Bảo vệ thứ tự (~4-5 phút — mentor sẽ đào sâu phần này nhất)

**Vì sao P01/P02 trước P03 (dù P03 tác động business cao hơn)?**
> "Vì P02 (thêm probe) mà chưa làm P01 (sửa health check thật) thì probe vô nghĩa — K8s vẫn không biết pod nào thực sự chết. Làm P03 (tăng replicas) trước cũng vậy: nhân bản pod mà health check vẫn giả thì traffic vẫn có thể route vào pod hỏng. Thứ tự đúng phải giải quyết root cause trước khi nhân bản."

**Vì sao Spot instance (COST-03) đặt sau P03 dù tiềm năng tiết kiệm 60-70%?**
> "Dùng Spot khi còn `replicas:1` sẽ khuếch đại đúng rủi ro Reliability đang cố sửa — Spot bị AWS thu hồi bất cứ lúc nào, mất node = mất trắng service không có bản dự phòng. Tiết kiệm chi phí không được đánh đổi bằng SLO checkout."

**Vì sao P07/P08/P11/P12/P22 không còn trong backlog CDO02 dù chính CDO02 tìm ra?**
> "Đây là kết quả họp 09/06 — không phải tôi bỏ, mà 3 team thống nhất phân theo đúng trụ phụ trách. Tôi vẫn là người cung cấp evidence (VD số liệu OOM, CPU requests thiếu) để CDO01 làm đúng hướng, nhưng không tự ôm việc ngoài Reliability/Cost để tránh chồng chéo trách nhiệm khi báo cáo tiến độ."

**Cố ý bỏ gì tuần này — mentor chắc chắn hỏi:**
> "**REL-08 — migrate Postgres/Valkey/Kafka sang managed service (RDS/ElastiCache/MSK)**. Dù đây là SPOF nặng nhất về mặt lý thuyết (mất toàn bộ dữ liệu nếu datastore chết), tôi cố ý không tự làm tuần 1 vì 2 lý do: (1) đây là loại việc BTC hay ra mandate — tự làm trước có thể phí công nếu mandate yêu cầu cách khác; (2) chi phí công sức rất lớn so với các item khác đang chờ, trong khi return-on-effort của P01-P06 cao hơn nhiều với cùng lượng thời gian. Đáng chú ý: mục này **không có mã P nào trong backlog chung** — cả 3 team cũng đồng thuận chưa cần làm ngay, không riêng đánh giá của tôi."

> Nếu mentor hỏi "sao không làm PVC cho Postgres/Kafka ngay khi phát hiện 0 PVC hôm nay?" → "Đúng, phát hiện mới hôm nay mở rộng phạm vi P14 từ chỉ Valkey sang cả Postgres/Kafka — nhưng tôi vẫn giữ nguyên quyết định: ghi nhận là accepted risk trong backlog, không vá vội vì đúng lý do REL-08 ở trên."

---

## Ghi chú thực chiến

- Nếu bị hỏi "làm gì rồi, không chỉ nói"? → đã dựng xong hạ tầng (VPC/EKS/CloudFront/SSM bastion — không còn allowlist IP thủ công), đã xử lý xong 2 sự cố thật (accounting OOM, ECR lifecycle), đã dựng CI/CD cho Terraform (PR-plan + approval-gate apply) — backlog reliability/cost thì **cố ý chưa code**, vì tuần này là tuần "find + note", không phải tuần thực thi.
- Nếu bị hỏi "AI Ops sẽ dùng backlog này thế nào?" (câu hỏi mới từ họp 09/06) → "Team AI Ops cần raw data → detect → verify; các mục P0 của tôi (P01 health check thật, P09 Grafana/Jaeger sống lại, P10 alerting) chính là nền tảng dữ liệu để họ detect được — làm xong nhóm này trước thì AI Ops mới có tín hiệu sạch để làm việc."
- Nếu hết giờ, cắt phần "Cost" trong Phần 2 trước — Phần 3 (bảo vệ thứ tự) là phần bị chấm kỹ nhất theo đúng lời mentor nói ("bỏ đúng cũng là một kỹ năng được chấm").
