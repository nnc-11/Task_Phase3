# 004 - Kien truc he thong

TechX Corp la storefront thuong mai dien tu microservice tren Kubernetes. Khach vao web, xem san pham, xem review co tom tat AI, them gio hang, checkout. He thong co observability day du: metrics, logs, traces, dashboards.

## Can nho trong 60 giay

- Cong vao duy nhat la `frontend-proxy` Envoy port `8080`.
- Luong quan trong nhat la checkout vi gan doanh thu va SLO 99%.
- Data stores baseline deu in-cluster/single instance: PostgreSQL, Valkey, Kafka.
- `flagd` la co che BTC dung de bom incident, khong duoc go/doi huong.
- CDO can hieu service dependency de biet ha tang loi se anh huong SLO nao.

## Cong vao duy nhat

Tat ca request vao qua `frontend-proxy`, la Envoy, port `8080`.

Qua cong nay co the vao:

- Storefront.
- Grafana.
- Jaeger.
- Load generator UI.
- OTLP endpoint cho frontend browser traces.

## Cac service chinh

`frontend-proxy`

- Envoy gateway.
- Route vao frontend va cac UI observability.

`frontend`

- Next.js storefront.
- Goi cac service phia sau.

`product-catalog`

- Go.
- List/get/search san pham.
- Dung PostgreSQL.

`product-reviews`

- Python.
- Doc review tu PostgreSQL.
- Goi `llm` de sinh tom tat AI va hoi dap.

`llm`

- Python.
- Mac dinh co the la mock backend.
- AIO co the cam LLM that qua secret/API key.

`cart`

- .NET/C#.
- Luu gio hang trong `valkey-cart`.

`checkout`

- Go.
- Dieu phoi dat hang: cart, product catalog, currency, shipping, quote, payment, email, Kafka.
- Day la luong ra tien, can uu tien bao ve.

`payment`, `shipping`, `quote`, `currency`, `email`

- Cac service phu cho checkout.

`accounting`, `fraud-detection`

- Consumer Kafka sau checkout.
- Bat dong bo, khong nam truc tiep tren duong response checkout nhung quan trong ve du lieu business.

`recommendation`, `ad`, `image-provider`

- Tang trai nghiem duyệt san pham.

`load-generator`

- Locust tao traffic mo phong.

`flagd`

- Feature flag.
- Trong Phase 3, BTC dung no de bom incident.

## Data stores

`postgresql`

- Dung boi `product-catalog`, `product-reviews`, `accounting`.
- Baseline la pod in-cluster, single replica.

`valkey-cart`

- Redis-compatible store cho gio hang.
- Baseline single replica.

`kafka`

- `checkout` publish order event.
- `accounting` va `fraud-detection` consume.
- Baseline single broker.

## Luong request quan trong

Duyet san pham:

`user -> frontend-proxy -> frontend -> product-catalog/recommendation/ad`

Trang san pham co AI:

`user -> frontend -> product-reviews -> postgresql + llm`

Gio hang:

`user -> frontend -> cart -> valkey-cart`

Checkout:

`user -> frontend -> checkout -> cart/product-catalog/currency/shipping/quote/payment/email -> kafka`

Sau checkout:

`kafka -> accounting + fraud-detection`

## Cach nghi ve kien truc

Neu checkout loi, anh huong doanh thu truc tiep. Neu product review AI loi, SLO khong cung nhu checkout, nhung khong duoc hien thi tom tat sai. Neu accounting loi, khach co the khong thay ngay, nhung du lieu ke toan co rui ro mat/muon.

## Ban do phu thuoc cho CDO

| Luong | Dependency ha tang quan trong | Neu loi thi sao |
|---|---|---|
| Browse product | frontend-proxy, frontend, product-catalog, PostgreSQL | Anh huong browse SLO/latency |
| Cart | cart, valkey-cart | Khach mat/khong sua duoc gio hang |
| Checkout | checkout + nhieu service phu + Kafka | Anh huong doanh thu truc tiep |
| Review AI | product-reviews, PostgreSQL, llm | Co the mat tinh nang AI hoac hien thi sai |
| Accounting | Kafka, accounting, PostgreSQL | Co the mat/tre du lieu ke toan |
