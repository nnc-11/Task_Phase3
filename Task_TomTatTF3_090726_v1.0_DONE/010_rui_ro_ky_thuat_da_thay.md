# 010 - Rui ro ky thuat da thay

Day la danh sach cac rui ro da thay qua tai lieu, Helm chart va source. Khong phai tat ca can lam ngay, nhung day la dau vao tot cho backlog.

## Can nho trong 60 giay

Top rui ro CDO nen nam:

1. Gan nhu moi component `replicas: 1`.
2. Thieu readiness/liveness probe that.
3. Limits thap, thieu requests.
4. Health check nhieu service tra healthy gia.
5. DB connection/pool co nguy co can khi tai tang.
6. Data stores in-cluster single instance.
7. `accounting` da OOMKilled va ECR lifecycle da gay incident.

## 1. Single replica gan nhu toan he thong

`default.replicas: 1` trong chart ap dung cho hau het component. Neu pod chet, rollout, node drain, hoac AZ/node co van de, service do co the mat nang luc phuc vu.

Anh huong:

- Checkout phu thuoc nhieu service single replica.
- Cart phu thuoc Valkey single replica.
- Data stores cung single replica.

## 2. Thieu readiness/liveness probe dong bo

Template ho tro `readinessProbe` va `livenessProbe`, nhung values baseline gan nhu khong cau hinh. Incident history da tung co loi thanh toan luc deploy vi traffic vao pod chua san sang.

Rui ro:

- Pod moi nhan traffic qua som.
- Pod treo nhung van duoc Service route.
- Rollout khong an toan.

## 3. Resource limits thap, thieu requests

Nhieu service chi co memory limit, khong co CPU/memory requests. Mot so limit rat thap:

- `checkout`: 20Mi.
- `product-catalog`: 20Mi.
- `currency`: 20Mi.
- `shipping`: 20Mi.
- `valkey-cart`: 20Mi.
- `postgresql`: 100Mi.
- `accounting` baseline 120Mi va da tung OOMKilled.

Rui ro:

- Scheduler khong co tin hieu requests dung.
- HPA/cluster autoscaler kho hieu nhu cau that.
- OOMKilled khi tai tang.

## 4. Health check gia

Nhieu service tra `SERVING` co dinh ma khong kiem tra dependency that. Vi du `checkout`, `product-catalog`, `product-reviews`, `recommendation`, `payment` co health path/handler kieu luon healthy.

Rui ro:

- Them readiness probe len health check gia se tao cam giac an toan gia.
- Pod bao ready du dependency DB/Kafka/LLM dang chet.

Ngoai le tot hon:

- `cart` co readiness check lien quan feature/connection logic, can doc ky truoc khi dung lam mau.

## 5. PostgreSQL client connection risk

`product-catalog` dung Go `database/sql` qua `otelsql.Open`, nhung chua thay set `MaxOpenConns`/`MaxIdleConns`.

`product-reviews` dung `psycopg2.connect()` moi lan request, khong thay connection pool.

Rui ro:

- Khi tai tang, DB connection co the can.
- Trung voi incident history INC-1: checkout cham/loi gio cao diem do can connection.

## 6. Checkout transaction ordering

Trong `checkout.PlaceOrder`, service charge card truoc roi moi ship order. Neu charge thanh cong nhung ship loi, co nguy co khach bi tru tien trong khi order fail, neu khong co refund/compensation.

Rui ro:

- Anh huong truc tiep khach hang.
- Can xem la bug business logic/reliability cao.

## 7. Kafka accounting risk

`accounting` consumer co `EnableAutoCommit = true`. Postmortem chi ra neu process bi kill giua xu ly, offset co the da commit trong khi DB write chua xong.

Rui ro:

- Mat ban ghi ke toan.
- Loi khong lo tren storefront.

## 8. Data stores in-cluster, single instance

Postgres, Valkey, Kafka baseline deu chay trong cluster va single replica.

Rui ro:

- Node reschedule co the gay downtime/mat state tuy cau hinh volume.
- Managed service co the cai thien reliability nhung ton cost, can ADR.

## 9. Envoy fault filter nhay cam

`frontend-proxy` co fault injection filter. Day co the la co che nhay cam tuong tu flagd, khong nen go neu toi uu Envoy ma chua hieu vai tro.

## 10. ECR lifecycle policy

Da co su co lifecycle policy xoa nham image. Moi cai tien cost o ECR phai lam rat can than:

- Test policy.
- Scope theo service tag prefix/pattern.
- Co alert khi expire image.

## Top 5 nen dua vao pitch CDO

| Uu tien | Viec | Vi sao |
|---|---|---|
| P0 | Rollout safety + readiness that cho checkout path | Truc tiep bao ve checkout SLO |
| P0/P1 | Resource requests/limits + OOM alert | Da co incident accounting OOMKilled |
| P1 | Replica cho service critical | Giam SPOF pod/node |
| P1 | DB connection control | Tranh lap lai INC-1 can connection |
| P2 | Danh gia managed datastore | Reliability cao nhung cost lon, can ADR |
