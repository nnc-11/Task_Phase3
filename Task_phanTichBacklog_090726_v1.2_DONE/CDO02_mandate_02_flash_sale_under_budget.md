# CDO02 - Xử lý Mandate BTC #2: Flash sale trong ngân sách hiện tại

Ngày lập: 13/07/2026  
Owner chính: CDO01 cho Performance/load test/HPA/autoscaling  
CDO02 phối hợp: Reliability, Cost Optimization, datastore/order safety, observability evidence  
Mandate nguồn: `MANDATE-02-scale-under-budget.md`

## 1. Mục tiêu Mandate #2

BTC yêu cầu hệ thống chịu được flash sale:

| Điều kiện | Mục tiêu |
|---|---|
| Load | 200 concurrent users qua load-generator |
| Thời lượng | 15 phút |
| Checkout SLO | >= 99% |
| Browse/cart SLO | >= 99.5% |
| Storefront p95 | < 1s |
| Ngân sách | Không vượt trần hiện tại, không tăng tài nguyên mù |
| Sau tải | Tài nguyên phải co xuống hoặc có bằng chứng không làm phình run-rate |

Phần CDO02 tập trung vào việc giữ checkout/order/data ổn định, có observability đủ tin cậy và chứng minh cost không bị đẩy lên vô kiểm soát.

## 2. Phạm vi CDO02

| Nhóm | CDO02 chịu trách nhiệm |
|---|---|
| Reliability | Revenue path không sập khi load test, pod không OOM/restart bất thường |
| Datastore | Postgres/Valkey/Kafka không thành bottleneck làm mất order hoặc checkout fail |
| Observability | Có metric đủ để chứng minh pass/fail |
| Cost | Theo dõi node count, resource tăng thêm, scale-down, cost/request hoặc cost/order |
| Rollback | Nếu test gây lỗi, có cách giảm tải/quay lại cấu hình trước |

Các phần CDO01 phụ trách chính gồm thiết kế HPA toàn hệ thống, tuning performance chi tiết từng service và security boundary public/private. CDO02 phối hợp bằng cách review tác động tới SLO, datastore, runtime health và cost.

## 3. Điều kiện trước khi chạy test 200 users

Không nên chạy thẳng 200 users nếu các điều kiện dưới đây chưa rõ:

| Điều kiện | Lý do |
|---|---|
| REL-01 đã apply thật | Revenue path cần >=2 replicas + PDB để tránh SPOF |
| Grafana/Jaeger ổn định | Cần evidence trong lúc test |
| Metrics khả dụng | Cần CPU/memory/restart/SLO để phân tích; nếu metrics-server chưa ổn thì phải có nguồn Prometheus/Grafana thay thế |
| Storefront public ổn định | Mandate #2 phụ thuộc Mandate #1 không làm hỏng storefront |
| Cost baseline có sẵn | Không có baseline thì không chứng minh được "không tăng ngân sách" |
| ArgoCD trạng thái rõ | Tránh hotfix tay bị selfHeal revert |

## 4. Quy trình xử lý

### Bước 1 - Baseline trước test

Ghi lại trạng thái trước khi tăng tải:

| Nhóm | Dữ liệu cần ghi |
|---|---|
| Deployment | replicas/available của frontend-proxy, frontend, product-catalog, cart, checkout, payment, currency, shipping |
| Pod health | restart count, OOMKilled history, pending pods |
| SLO | checkout/browse/cart success rate, storefront p95 |
| Node | số node, CPU/memory pressure |
| Cost | run-rate hiện tại hoặc estimate theo node/service chính |

Input cần từ CDO01 trước bước baseline:

| Input | CDO02 dùng để làm gì |
|---|---|
| Target endpoint load test | Xác định storefront path chính thức để đo |
| Workload mix | Biết traffic dồn vào browse/cart/checkout theo tỷ lệ nào |
| Metric source | Dùng Prometheus/Grafana/metrics-server nào để lấy số liệu |
| Lịch chạy test | Chuẩn bị người theo dõi observability và rollback |

### Bước 2 - Test tăng dần

Không nhảy thẳng lên 200 users nếu chưa có baseline ổn định.

| Mức | Thời lượng | Mục đích |
|---|---|---|
| 25-50 users | 5 phút | Kiểm tra tool, metric, dashboard |
| 100 users | 5-10 phút | Tìm bottleneck sớm |
| 200 users | 15 phút | Bài test BTC |

Sau mỗi mức, kiểm tra:

- Checkout success rate.
- Browse/cart success rate.
- Storefront p95.
- Pod restart/OOM.
- Postgres/Kafka/Valkey lỗi hoặc latency tăng.
- Node count và resource usage.

Output CDO02 trả cho CDO01 sau mỗi mức:

| Output | Nội dung |
|---|---|
| Checkout health | Success rate, lỗi 5xx/timeout nếu có |
| Datastore pressure | Postgres/Kafka/Valkey lỗi, latency, connection/lag nếu có |
| Pod health | Restart/OOM/readiness/pending |
| Cost signal | Node count, replica count, dấu hiệu scale không co xuống |

### Bước 3 - Xử lý bottleneck theo quyền CDO02

| Bottleneck | Cách xử lý ưu tiên |
|---|---|
| Checkout/payment/currency/shipping OOM | Tăng memory có bằng chứng, không tăng bừa toàn hệ thống |
| Product-catalog nghẽn DB | Áp REL-05 connection pool hoặc giới hạn connection |
| Postgres quá nhiều connection | Pool/connection ceiling trước, không scale app mù |
| Kafka/accounting lag hoặc restart | Ưu tiên manual commit/retry/DLQ hoặc tăng resource có kiểm soát |
| Grafana/Jaeger OOM | Giảm trace volume/retention hoặc tăng memory vừa đủ để giữ evidence |
| CPU throttle do LimitRange | Đặt explicit CPU cho service critical thay vì bỏ LimitRange toàn namespace |

Các bottleneck cần CDO01 xử lý hoặc phối hợp:

| Bottleneck | Owner chính | Input CDO02 cần | Output CDO02 cung cấp |
|---|---|---|---|
| HPA scale sai hoặc không scale | CDO01 | HPA config, metric trigger, min/max | SLO/cost impact và service bị ảnh hưởng |
| Storefront p95 >= 1s do frontend/proxy | CDO01 | Performance tuning plan | Runtime evidence và thời điểm spike |
| Node autoscaler không scale hoặc scale quá tay | CDO01 | Autoscaler config, node max/min | Node count/cost observation |
| NetworkPolicy/ingress ảnh hưởng test | CDO01 | Policy/ingress change list | Flow nào fail sau change |
| Metrics-server/Prometheus thiếu số liệu | CDO01 | Metric source thay thế hoặc fix plan | Danh sách metric CDO02 cần để chứng minh mandate |

### Bước 4 - Xác nhận scale down/cost

Sau test, cần chứng minh hệ thống không neo tài nguyên ở đỉnh.

| Dữ liệu | Kỳ vọng |
|---|---|
| Replicas | Nếu HPA có scale up thì scale down về min hợp lý |
| Node count | Không giữ node tăng thêm nếu không cần |
| Cost estimate | Weekly run-rate không vượt cap |
| Error budget | Không đốt SLO để đổi lấy cost thấp |

Output cuối CDO02 cần gửi lại cho CDO01/BTC:

| Output | Nội dung |
|---|---|
| Reliability result | Checkout/browse/cart có giữ SLO không |
| Runtime result | Restart/OOM/readiness/pending trong cửa sổ test |
| Cost result | Node/replica trước-trong-sau, cost/request hoặc cost/order |
| Blocking issue nếu fail | Bottleneck thuộc CDO02 hay cần CDO01 xử lý tiếp |

## 5. Acceptance criteria cho CDO02

| Tiêu chí | Kết quả cần có |
|---|---|
| Checkout | >= 99% trong cửa sổ test |
| Browse/cart | >= 99.5% trong cửa sổ test |
| Storefront p95 | < 1s |
| Pod health | Không có OOMKilled mới ở revenue path |
| Observability | Dashboard/metric đủ để chứng minh kết quả |
| Cost | Có baseline trước/sau, không vượt trần |
| Scale down | Tài nguyên sau test trở về mức thường hoặc có lý do giữ lại |

## 6. Evidence cần nộp BTC/Mentor

| Evidence | Nội dung |
|---|---|
| Load test config | Users, duration, workload mix, thời điểm chạy |
| SLO table | Checkout/browse/cart success rate, storefront p95 |
| Runtime health | Restart count, OOMKilled, pending pods, readiness fail |
| Capacity table | CPU/memory service critical, node count trước/trong/sau |
| Cost table | Cost baseline, cost trong test, cost/request hoặc cost/order |
| Re-run guide | Cách mentor chứng kiến hoặc chạy lại |

## 7. Rủi ro và cách giảm thiểu

| Rủi ro | Ảnh hưởng | Giảm thiểu |
|---|---|---|
| Tăng replica quá nhiều | Tốn cost, nghẽn datastore | Chỉ tăng revenue path, đo Postgres/Kafka trước |
| Load test làm checkout fail | Vi phạm SLO | Test tăng dần, dừng khi error rate vượt ngưỡng |
| Observability chết giữa test | Không có evidence | Fix Grafana/Jaeger trước, giảm trace volume nếu cần |
| HPA/Autoscaler chưa ổn | Scale không co xuống hoặc tăng node ngoài dự kiến | CDO01 đặt min/max rõ; CDO02 kiểm tra node run-rate sau test |
| Cost tăng nhưng không đo được | Không chứng minh mandate | Ghi node count/run-rate trước khi test |
| ArgoCD revert hotfix | Bottleneck quay lại | Nếu patch tay, pause ArgoCD và codify sau |

## 8. Thứ tự thực thi CDO02 đề xuất

```text
verify REL-01 runtime
-> ổn định Grafana/Jaeger
-> lấy cost/SLO baseline
-> chạy load test tăng dần
-> xử bottleneck theo evidence
-> chạy 200 users/15 phút
-> ghi SLO + cost + scale-down evidence
```

## 9. Note owner/input-output với CDO01

| Việc | Owner | CDO02 cần từ CDO01 | CDO02 trả lại |
|---|---|---|---|
| Load test tool/config | CDO01 | Users, duration, workload mix, endpoint | Reliability/cost result theo từng mức tải |
| HPA/autoscaling | CDO01 | Min/max, trigger metric, scale-down policy | Cost impact, node count, SLO impact |
| Performance tuning frontend/proxy | CDO01 | Change list và thời điểm rollout | p95/error evidence trước/sau |
| Metrics platform | CDO01 | Dashboard/query/lệnh lấy metric | Danh sách metric thiếu hoặc bất thường |
| Mandate final evidence pack | CDO01 + CDO02 | Format nộp BTC | Phần CDO02: SLO, runtime health, cost, datastore/order safety |

Nếu thiếu input từ CDO01, trạng thái nên ghi theo dạng: `Chờ input từ CDO01: thiếu <input>, ảnh hưởng <evidence/test nào>`.

## 10. Kết luận

Mandate #2 không nên được xử bằng cách thêm tài nguyên cho nhanh. Với CDO02, cách đúng là giữ revenue path ổn định, bảo vệ datastore/order flow, đo được SLO và chứng minh cost không phình.

Thông điệp khi trình bày:

```text
Hệ thống chịu được flash sale vì checkout path có redundancy, datastore không bị nghẽn mù,
observability đủ chứng minh kết quả, và tài nguyên không bị neo ở mức peak sau test.
```
