# Technical Check Report - Observability sau deploy

Ngày kiểm tra: 08/07/2026  (7:00PM)
Người thực hiện: CDO02-TranVanDuc
Môi trường: EKS `techx-corp-tf3`, namespace `techx-tf3`, region `ap-southeast-1`

| Mã | Hạng mục kiểm tra | Trạng thái | Ghi nhận |
|---|---|---|---|
| C001 | Cluster EKS | OK | Cluster `techx-corp-tf3` đang `ACTIVE`, Kubernetes version `1.31`. |
| C002 | Namespace workload | OK | Namespace `techx-tf3` truy cập được, không ghi nhận lỗi truy cập Kubernetes API sau khi dùng đúng context. |
| C003 | Pod status | OK | Tất cả pod trong namespace đang `Running`; không có pod `Pending`, `CrashLoopBackOff` hoặc `ImagePullBackOff` tại thời điểm kiểm tra. |
| C004 | Deployment status | OK | Các `deployment` đều `1/1 READY`, `AVAILABLE`; `opensearch` `statefulset` cũng `1/1 READY`. |
| C005 | Node status | OK | 3 node EKS đều `Ready`, chạy trong private subnet, không thấy node down. |
| C006 | Grafana restart count | ISSUE | Pod `grafana-6db75489fb-t695t` restart 15 lần. Last reason: `OOMKilled`, exit code `137`. |
| C007 | Grafana memory limit | ISSUE | Container `grafana` đang có `memory limit` và `request` là `300Mi`; mức này có dấu hiệu không đủ cho workload hiện tại. |
| C008 | Jaeger restart count | ISSUE | Pod `jaeger-bbc8c79f5-7j8mf` restart 4 lần. Last reason: `OOMKilled`, exit code `137`. |
| C009 | Jaeger memory limit | ISSUE | Jaeger đang dùng `memory limit` `600Mi`, `storage.type: memory`, `MEMORY_MAX_TRACES=25000`; có rủi ro vượt memory khi trace volume tăng. |
| C010 | Metrics API | WARN | `kubectl top pods -n techx-tf3 --containers` trả về `Metrics API not available`, chưa đọc được memory usage realtime bằng Metrics API. |
| C011 | Kubernetes events | WARN | `kubectl get events -n techx-tf3` không còn event tại thời điểm kiểm tra, nên cần dựa vào pod restart history và `describe pod`. |
| C012 | Storefront impact | OK | Chưa thấy bằng chứng storefront down trong lần kiểm tra này; vấn đề hiện nằm ở tầng observability. |

## Bằng chứng chính

```text
grafana-6db75489fb-t695t   4/4   Running   15
jaeger-bbc8c79f5-7j8mf     1/1   Running   4
```

```text
grafana restarts=15 lastReason=OOMKilled exit=137 finished=2026-07-08T10:18:20Z
jaeger  restarts=4  lastReason=OOMKilled exit=137 finished=2026-07-08T09:49:33Z
```

```text
kubectl top pods -n techx-tf3 --containers
error: Metrics API not available
```

## Nhận định

Hệ thống application hiện vẫn chạy, nhưng observability chưa ổn định. Hai thành phần chính là Grafana và Jaeger đều đã bị `OOMKilled`, trong đó Grafana restart nhiều nhất. Nguyên nhân gần nhất là `memory limit` hiện tại thấp hơn nhu cầu thực tế của workload observability.

## Đề xuất xử lý

| Mã | Việc cần làm | Ưu tiên | Ghi chú |
|---|---|---|---|
| A001 | Tăng `memory limit` cho Grafana | High | Có thể thử `600Mi` trước, sau đó theo dõi restart count. |
| A002 | Tăng `memory limit` cho Jaeger | High | Có thể thử `1Gi` trước, sau đó theo dõi lại dưới tải thực tế. |
| A003 | Giảm `MEMORY_MAX_TRACES` của Jaeger | Medium | Nếu chỉ cần debug ngắn hạn, giảm từ `25000` xuống mức nhỏ hơn để giảm áp lực RAM. |
| A004 | Bổ sung Metrics API hoặc cách đọc metric từ Prometheus | Medium | Cần có số liệu memory usage realtime để đánh giá headroom. |
| A005 | Thêm alert cho `OOMKilled` và restart count | Medium | Nên alert khi pod observability restart nhiều lần trong thời gian ngắn. |

## Kết luận

Kết quả kiểm tra sau deploy: application workload đang ổn định ở mức pod/deployment, nhưng observability có incident về memory. Cần xử lý Grafana và Jaeger trước khi có incident khác, vì dashboard và trace không ổn định sẽ ảnh hưởng trực tiếp đến khả năng điều tra sự cố.

Lưu ý khi thao tác: nếu chạy `Helm upgrade`, cần giữ nguyên `values-flagd-sync.yaml`, không đổi token/URI flagd và không commit secret vào repo.
