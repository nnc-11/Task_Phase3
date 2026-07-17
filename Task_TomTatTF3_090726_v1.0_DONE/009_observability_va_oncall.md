# 009 - Observability va on-call

He thong co san stack observability. Viec cua TF la dung no de biet he thong dang khoe hay dang chet am tham.

## Can nho trong 60 giay

- Metrics: Prometheus/Grafana.
- Traces: Jaeger.
- Logs: OpenSearch.
- Telemetry vao qua OpenTelemetry Collector.
- Pod `Running` chua du; phai xem Ready, restarts, OOMKilled, latency, error rate.
- Loi bat dong bo nhu `accounting` co the khong hien ra tren storefront.

## Stack co san

OpenTelemetry Collector:

- Nhan telemetry tu service.
- Chay mode daemonset trong chart.
- Co host metrics, kubelet metrics, cluster metrics, annotation discovery.

Prometheus:

- Luu metrics.
- Nguon cho SLO dashboard va alert.

Jaeger:

- Distributed tracing.
- Dung de xem mot request checkout di qua service nao, cham o dau.

OpenSearch:

- Logs.

Grafana:

- Dashboard tong hop.
- Alerting co the dung de bao restart, error rate, latency, resource.

## Nen theo doi gi dau tien

Service health:

- Pod Running/Ready.
- Restart count.
- OOMKilled.
- ImagePullBackOff/CrashLoopBackOff.

SLO:

- Checkout success rate.
- Checkout p95 latency.
- Product browse non-5xx.
- Cart success rate.

Dependency:

- PostgreSQL connections, latency, errors.
- Kafka consumer lag/errors.
- Valkey availability.
- LLM latency/errors.

Resource:

- CPU/memory usage vs limit/request.
- Node pressure.
- Pod evictions.

Rollout:

- Deployment unavailable replicas.
- Pods ready before receiving traffic.
- Restart spike after deploy.

## Bai hoc tu postmortem accounting

`accounting` bi OOMKilled lap lai nhieu gio nhung checkout van thanh cong, nen khach khong thay ngay. Day la mau loi "chet am tham":

- Service bat dong bo chet khong lam request frontend fail.
- Du lieu ke toan co the mat neu Kafka offset auto-commit truoc khi ghi DB xong.
- Neu chi nhin storefront, se bo sot.

Alert nen co:

- Pod restart count tang bat thuong.
- OOMKilled.
- Kafka consumer lag.
- Accounting write error.
- ImagePullBackOff.

## Cach truc on-call co ky luat

Moi ca truc nen co nhung cau hoi:

- SLO nao dang bi de doa?
- Co deploy nao vua xay ra?
- Flagd co thay doi/incident flag nao khong?
- Dependency nao dang loi?
- Co can rollback/containment khong?
- Anh huong khach hang la gi?
- Can ghi postmortem khong?

## Dieu can tranh

- Chi xem pod Running ma bo qua Ready/restarts.
- Thay loi thi tang limit vo toi va ma khong tim nguyen nhan.
- Tat flagd de het loi.
- Deploy trong luc error budget dang chay ma khong co ly do.
- Sua production ma khong ghi lai.

## Dashboard/alert CDO nen uu tien

| Nhom | Tin hieu |
|---|---|
| SLO | checkout success rate, p95 latency, browse 5xx |
| Pod | restart count, OOMKilled, CrashLoopBackOff, ImagePullBackOff |
| Resource | memory near limit, CPU throttling, node pressure |
| Rollout | unavailable replicas, readiness fail |
| Dependency | PostgreSQL connection/errors, Kafka lag, Valkey errors |
