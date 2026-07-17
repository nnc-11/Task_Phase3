# CDO02 - Cách xử lý backlog liên quan Reliability và Cost

Ngày lập: 13/07/2026  
Owner: CDO02_TranVanDuc  
Phạm vi: các backlog thuộc Reliability, Cost Optimization và phần Operational Excellence ảnh hưởng trực tiếp đến vận hành của CDO02.  
Không bao gồm: phần Security/Performance do CDO01 sở hữu, trừ khi có dependency trực tiếp tới checkout, datastore, observability hoặc cost cap.

## 1. Nguyên tắc ưu tiên

Backlog của CDO02 không xử lý theo số lượng việc làm được, mà theo rủi ro với SLO và chi phí vận hành.

Công thức dùng:

```text
Priority = Risk x Business impact x Evidence
```

Trong đó:

| Yếu tố | Cách hiểu trong phạm vi CDO02 |
|---|---|
| Risk | Khả năng xảy ra lỗi và mức độ nghiêm trọng khi xảy ra |
| Business impact | Ảnh hưởng tới checkout, cart, browse SLO, dữ liệu đơn hàng, cost cap |
| Evidence | Có bằng chứng runtime, postmortem, metric, manifest hay chỉ là giả định |

Những item có bằng chứng đã xảy ra thật sẽ đứng trên rủi ro lý thuyết. Những item bảo vệ checkout và dữ liệu đơn hàng đứng trên tối ưu dài hạn.

## 2. Backlog CDO02 cần xử lý ngay

| Mã | Nội dung | Ưu tiên | Lý do |
|---|---|---|---|
| REL-01 | Replicas >= 2 + PDB cho revenue path | P0 | Đã có bằng chứng checkout fail khi node rolling-replace; hiện đã merge vào repo nhưng cần verify runtime |
| REL-13 | Grafana/Jaeger OOM/restart | P0 | Nếu observability chết thì không chứng minh được SLO, load test, incident |
| REL-15 | Alert cho OOMKilled/restart/readiness fail | P0/P1 | Các lỗi gần đây phát hiện thủ công, MTTR còn cao |
| REL-09/REL-16 | Kafka ack/manual commit/DLQ hoặc mitigation tương đương | P0 | Rủi ro mất đơn hàng âm thầm sau checkout |
| REL-04 | Refund/rollback khi ship lỗi sau charge | P0 | Rủi ro tài chính trực tiếp với khách hàng |
| REL-05 | Postgres connection pool cho product-catalog/product-reviews | P1 | Giảm nguy cơ nghẽn DB khi browse/review tăng |
| REL-10 | Persistence/accepted risk cho datastore | P1 | Postgres/Valkey/Kafka đang là stateful singleton, 0 PVC |
| COST-01 | ECR lifecycle policy đúng | P1 | Tránh lặp lại incident xóa nhầm image |
| COST-02 | Cluster Autoscaler hoặc kế hoạch scale node có kiểm soát | P1/P2 | CDO01 làm chính; CDO02 review cost/SLO và chỉ đồng ý khi metric/resource request đủ tin cậy |

## 3. Việc đã có trong repo nhưng vẫn phải verify

| Item | Trạng thái trong repo | Việc CDO02 cần làm tiếp |
|---|---|---|
| REL-01 replicas | `values-prod.yaml` đã đặt `replicas: 2` cho revenue path/gateway | Verify trên cluster: deployment thật có `AVAILABLE=2` |
| PDB revenue path | `gitops/infrastructure/pdb-checkout.yaml` đã có PDB `minAvailable: 1` | Verify `kubectl get pdb -n techx-tf3`, test drain/kill pod ở giờ an toàn |
| LimitRange/ResourceQuota | Đã có manifest GitOps | Kiểm tra có throttle do default CPU `200m` không |
| Postgres NetworkPolicy | Đã có manifest GitOps | Test không chặn product-catalog/product-reviews/accounting |
| GitOps/ArgoCD | App đang `selfHeal=true`, `prune=true` | Khi incident, phải pause ArgoCD trước khi patch tay |

## 4. Cách xử lý theo từng nhóm

### 4.1 Reliability bảo vệ checkout

Mục tiêu: checkout không fail khi có pod restart, node drain, rollout hoặc load spike.

Thứ tự xử lý:

1. Verify REL-01 đã apply thật trên runtime.
2. Test kill 1 pod checkout/cart/payment/currency ở giờ thấp điểm.
3. Theo dõi checkout success rate, restart count, pending pods.
4. Nếu pass, dùng REL-01 làm điều kiện nền cho EKS upgrade và flash sale test.
5. Nếu fail, rollback hoặc điều chỉnh PDB/replica/topology spread trước khi làm việc khác.

Acceptance criteria:

- Revenue-path deployments có ít nhất 2 pod available.
- PDB tồn tại và không khóa node drain.
- Xóa 1 pod critical không làm checkout vi phạm SLO.

### 4.2 Reliability dữ liệu đơn hàng

Mục tiêu: tránh mất order hoặc sai trạng thái tài chính sau checkout.

Thứ tự xử lý:

1. Rà `checkout`, `accounting`, Kafka producer/consumer.
2. Ưu tiên sửa chỗ mất dữ liệu âm thầm: auto commit quá sớm, thiếu retry, thiếu DLQ.
3. Với payment/ship flow, thêm refund/void hoặc bù trừ khi ship lỗi sau charge.
4. Viết test hoặc kịch bản giả lập lỗi: Kafka consumer restart, shipping fail, payment success nhưng order fail.

Acceptance criteria:

- Không commit Kafka offset trước khi xử lý xong record.
- Có đường đi rõ cho message lỗi: retry hoặc DLQ.
- Khi ship lỗi sau charge, có hành động bù trừ hoặc log/audit đủ rõ để xử lý.

### 4.3 Observability và alert

Mục tiêu: không mất dashboard/trace/alert trong lúc load test hoặc incident.

Thứ tự xử lý:

1. Fix Grafana/Jaeger OOM bằng memory sizing hoặc giảm trace retention/volume.
2. Bổ sung alert cho restart count, OOMKilled, readiness fail.
3. Đảm bảo load test có đủ metric để chứng minh SLO.

Acceptance criteria:

- Không có OOMKilled mới trên Grafana/Jaeger trong bài test.
- Có metric cho checkout/browse/cart success rate và p95 latency.
- Có bằng chứng restart/OOM/readiness trong cửa sổ test.

### 4.4 Cost Optimization

Mục tiêu: giảm chi phí có bằng chứng, không tối ưu bằng cách làm tăng rủi ro SLO.

Thứ tự xử lý:

1. EKS 1.32 extended support: theo ADR 0001, upgrade lên 1.34 sau khi REL-01 và backup tối thiểu sẵn sàng.
2. ECR lifecycle policy: viết lại policy theo service/tag prefix, không dùng rule xóa toàn repo.
3. Autoscaling/Spot/right-size: CDO01 làm chính; CDO02 kiểm tra tác động tới SLO, node run-rate và rollback.
4. Managed datastore: theo ADR 0002, RDS/ElastiCache có ROI tốt hơn MSK, nhưng chỉ làm khi tới lượt hoặc có mandate.

Acceptance criteria:

- Có cost trước/sau hoặc estimate rõ.
- Không tăng node count cố định nếu không có lý do.
- Không dùng Spot cho workload chưa có replica/PDB phù hợp.

## 5. Phạm vi phối hợp với CDO01

| Hạng mục | Owner chính | Phần CDO02 phụ trách |
|---|---|---|
| Public ingress boundary CloudFront/ALB | CDO01 | Verify không làm hỏng checkout/cart/browse |
| NetworkPolicy toàn namespace | CDO01 | Review flow datastore, test Postgres/Valkey/Kafka |
| HPA/performance tuning toàn hệ thống | CDO01 | Cung cấp metric checkout/datastore/cost, review scale-down và budget impact |
| Pod Security hardening diện rộng | CDO01 | Kiểm tra không phá stateful/observability |

## 6. Input/output cần thống nhất với CDO01

Các phần dưới đây cần có input/output rõ giữa CDO01 và CDO02 để báo cáo thể hiện đúng owner và đúng phạm vi từng trụ.

| Hạng mục | Cần CDO01 xử lý / input | Output CDO02 cần nhận | CDO02 dùng để làm gì |
|---|---|---|---|
| CloudFront/ALB boundary | Quyết định entrypoint public chính thức: CloudFront-only hay ALB public tạm thời | ADR/note ngắn + endpoint cuối cùng cần test | Smoke test storefront, checkout, cart sau khi đổi boundary |
| NetworkPolicy ngoài Postgres | Danh sách policy sẽ áp cho Valkey, Kafka, Grafana, Jaeger, ArgoCD | Manifest hoặc bảng allowlist source -> destination -> port | Review không chặn cart/checkout/accounting/observability |
| Metrics-server/Prometheus source | Xác nhận nguồn metric chính cho CPU/memory/SLO | Dashboard/query hoặc lệnh lấy metric | Dùng làm evidence cho REL-13, REL-15, flash sale |
| HPA/autoscaler | Min/max replicas, metric trigger, scale-down behavior | Config HPA/autoscaler + expected node count | Review cost impact và rủi ro scale không co xuống |
| Load test plan | Workload mix, tool, target endpoint, lịch chạy | Test config + cửa sổ test | Chuẩn bị observability, theo dõi checkout/datastore/cost |
| Pod Security hardening | Danh sách service sẽ đổi securityContext | Manifest/PR summary | Kiểm tra không phá workload stateful hoặc service cần write filesystem |

Nếu thiếu output từ CDO01, trạng thái nên ghi theo dạng `Chờ input từ CDO01: <nội dung cần bổ sung>`, kèm ảnh hưởng tới phần evidence của CDO02.

## 7. Kết luận

CDO02 nên xử lý backlog theo đường đi này:

```text
verify REL-01 -> ổn định observability -> bảo vệ order/Kafka/payment -> connection pool/datastore risk -> cost optimization có bằng chứng
```

Các item ngoài Reliability và Cost chỉ tham gia ở mức dependency. Khi trình bày, nhấn mạnh tác động business: giữ checkout không lỗi, không mất đơn hàng, có evidence khi incident, và không vượt cost cap.
