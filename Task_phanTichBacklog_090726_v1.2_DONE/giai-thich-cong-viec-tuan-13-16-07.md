# Giải thích công việc tuần 13–16/07/2026 — dành cho người chưa biết gì về DevOps

> Tài liệu này viết cho thành viên mới, **không cần biết trước bất kỳ khái niệm nào**.
> Mọi thuật ngữ chuyên ngành đều được giải thích ngay lần đầu xuất hiện, và tổng hợp lại
> ở bảng thuật ngữ cuối file. Đọc tuần tự từ đầu sẽ dễ hiểu nhất, vì phần sau dùng khái
> niệm của phần trước.

---

## Phần 0 — Bối cảnh: chúng ta đang làm gì?

Đội TF3 tiếp quản một **website bán hàng** (giống Shopee/Tiki thu nhỏ) tên TechX Corp,
đang chạy thật, có khách truy cập thật (do ban tổ chức — gọi tắt **BTC** — giả lập).
Nhiệm vụ: vận hành nó **không được sập**, trong ngân sách giới hạn (~$300/tuần), và BTC
sẽ **cố tình bơm lỗi** vào hệ thống để thử phản ứng của đội.

Website này không phải một chương trình duy nhất, mà là **~20 chương trình nhỏ ghép lại**,
mỗi cái làm một việc:

- `frontend` — trang web khách nhìn thấy
- `product-catalog` — quản lý danh sách sản phẩm
- `cart` — giỏ hàng
- `checkout` — đặt hàng (luồng "ra tiền" quan trọng nhất)
- `payment` — thanh toán
- `shipping`, `currency`, `quote`, `email`... — các việc phụ trợ

Kiến trúc kiểu này gọi là **microservice** (dịch vụ nhỏ): thay vì một chương trình khổng lồ,
ta có nhiều chương trình nhỏ nói chuyện với nhau qua mạng. Ưu điểm: một cái hỏng không kéo
sập tất cả (nếu thiết kế đúng). Nhược điểm: có rất nhiều thứ để vận hành và rất nhiều chỗ
để hỏng.

### Dữ liệu nằm ở đâu?

Ba "kho dữ liệu" (gọi chung là **datastore**):

1. **PostgreSQL** (gọi tắt Postgres) — **cơ sở dữ liệu** (database) dạng bảng, giống Excel
   siêu mạnh: lưu danh sách sản phẩm, đánh giá, sổ sách kế toán.
2. **Valkey** — một loại **cache** (bộ nhớ đệm): kho lưu siêu nhanh nhưng đơn giản, dùng
   lưu giỏ hàng. (Valkey là bản mã nguồn mở của Redis — nếu bạn nghe ai nói "Redis" thì
   hiểu là cùng loại.)
3. **Kafka** — **hàng đợi tin nhắn** (message queue): giống hộp thư giữa các service.
   Khi khách đặt hàng xong, `checkout` bỏ một "lá thư" vào Kafka, các service `accounting`
   (kế toán) và `fraud-detection` (chống gian lận) sẽ lấy thư ra xử lý **sau**, không bắt
   khách phải chờ.

### Hệ thống chạy ở đâu?

Trên **AWS** (Amazon Web Services) — dịch vụ cho thuê máy chủ của Amazon. Ta không mua máy
vật lý; ta thuê "máy ảo" theo giờ. Vài khái niệm AWS sẽ gặp nhiều:

- **Region** — khu vực địa lý của trung tâm dữ liệu. Ta dùng `ap-southeast-1` (Singapore).
- **AZ (Availability Zone)** — một region có 2-3 "tòa nhà" trung tâm dữ liệu tách biệt
  nhau (điện, mạng riêng). Nếu một tòa cháy, tòa kia vẫn chạy. Đặt máy ở **nhiều AZ** là
  cách chống thảm họa cơ bản nhất.
- **EC2 instance** — một máy ảo thuê của AWS.
- **EKS** — dịch vụ Kubernetes của AWS (Kubernetes là gì → ngay bên dưới).
- **ECR** — kho lưu trữ "ảnh đóng gói" của chương trình (image — giải thích bên dưới).
- **IAM** — hệ thống phân quyền của AWS: ai được làm gì.

### Kubernetes là gì? (khái niệm quan trọng nhất tài liệu này)

Tưởng tượng bạn quản lý một **khu chung cư**:

- **Node** = một tòa nhà (thực chất là một máy ảo EC2). Cluster của ta có ~4-5 node.
- **Pod** = một căn hộ trong tòa nhà. Mỗi pod chạy một bản sao của một service.
  Ví dụ service `cart` có 2 pod = 2 căn hộ giống hệt nhau, ở (lý tưởng là) 2 tòa khác nhau.
- **Container** = "người ở" trong căn hộ — chính là chương trình đang chạy, được đóng gói
  kèm mọi thứ nó cần (thư viện, cấu hình) thành một **image** (ảnh đóng gói). Image được
  lưu trong kho ECR; muốn chạy ở đâu thì "tải ảnh về và bung ra".
- **Kubernetes** (viết tắt **K8s**) = **ban quản lý chung cư tự động**. Bạn khai báo
  "tôi muốn service cart luôn có 2 căn hộ hoạt động", K8s tự lo: căn nào cháy thì xây lại,
  tòa nào sập thì chuyển hộ dân sang tòa khác. Toàn bộ khu chung cư gọi là **cluster**.
- **Deployment** = bản khai báo mong muốn: "service X chạy image Y, số bản sao
  (**replica**) là 2". K8s đọc bản khai này và duy trì đúng như vậy.
- **Service (theo nghĩa K8s)** = "số điện thoại lễ tân": các pod sinh ra chết đi liên tục,
  địa chỉ đổi liên tục, nên K8s cấp một địa chỉ cố định; ai gọi đến sẽ được nối tới một
  pod đang khỏe. Danh sách pod khỏe đứng sau địa chỉ đó gọi là **endpoint**.

### Ai bấm nút deploy? — GitOps

**Deploy** = đưa phiên bản mới của chương trình/cấu hình lên chạy thật.

Cách cổ điển: kỹ sư gõ lệnh trực tiếp vào cluster. Rủi ro: không ai biết ai đã đổi gì,
lúc nào, tại sao.

Cách của ta: **GitOps** — toàn bộ cấu hình mong muốn của hệ thống nằm trong **Git**
(hệ thống quản lý phiên bản code, lưu trên GitHub). Một phần mềm tên **ArgoCD** chạy trong
cluster, liên tục so sánh "thực tế trong cluster" với "khai báo trong Git" — lệch là nó tự
sửa cho khớp Git. Hệ quả:

- Muốn đổi gì → sửa file trong Git → tạo **PR** (Pull Request — "đơn xin gộp thay đổi",
  cần người khác duyệt) → PR được duyệt và gộp (merge) vào nhánh `main` → ArgoCD tự áp dụng.
- Không ai sửa tay trong cluster nữa. Mọi thay đổi đều có lịch sử, có người duyệt.

Cấu hình khai báo bằng **Helm** — công cụ "khuôn mẫu" cho K8s: thay vì viết cấu hình cho
20 service lặp đi lặp lại, ta viết một khuôn (chart) + một file giá trị
(`values-prod.yaml`) liệt kê điểm khác nhau của từng service.

Còn **hạ tầng nền** (máy ảo, mạng, cluster EKS...) khai báo bằng **Terraform** — cùng triết
lý "hạ tầng là code": viết file mô tả, chạy lệnh, AWS dựng đúng như mô tả.

### SLO — thước đo "không được sập"

- **SLI** (Service Level Indicator) — chỉ số đo chất lượng, ví dụ "% request thành công".
- **SLO** (Service Level Objective) — mục tiêu cam kết trên chỉ số đó. Của ta:
  - Đặt hàng (checkout) thành công ≥ **99%**
  - Xem hàng/giỏ hàng thành công ≥ **99.5%**
  - **p95 độ trễ < 1 giây** — nghĩa là: xếp mọi request theo thời gian phản hồi,
    request ở vị trí 95% (chậm hơn 95% số còn lại) phải dưới 1 giây. Dùng p95 thay vì
    trung bình vì trung bình che mất người dùng bị chậm.
- Vi phạm SLO = bị trừ điểm/đền bù (trong đời thật là mất tiền, mất khách).

### flagd — cách BTC bơm lỗi (LUẬT SỐNG CÒN)

**Feature flag** (cờ tính năng) = công tắc bật/tắt hành vi của chương trình **mà không cần
sửa code**. Hệ thống có một service tên `flagd` phát các công tắc này; giá trị công tắc do
**BTC điều khiển từ xa**. BTC bơm sự cố bằng cách bật cờ như `cartFailure` (làm giỏ hàng
lỗi), `paymentFailure` (làm thanh toán lỗi)...

**LUẬT TUYỆT ĐỐI (vi phạm = loại khỏi cuộc chơi):** không được gỡ/tắt/né cơ chế đọc cờ này.
Phải sống chung với lũ — xử lý sự cố bằng thiết kế chịu lỗi, không phải bằng cách rút dây
công tắc của BTC.

---

## Phần 1 — Thứ Hai 13/07: Dựng lại toàn bộ hệ thống trên tài khoản AWS mới

### Chuyện gì xảy ra?

Tài khoản AWS cũ (của BTC cấp) **bị khóa**. Toàn bộ máy chủ, cluster, kho image — mất quyền
truy cập. Website sập hoàn toàn. Đội quyết định dựng lại từ đầu trên tài khoản mới
`197826770971`.

### Làm thế nào?

May mắn là toàn bộ hạ tầng đã được viết thành **code Terraform** từ trước (thư mục
`infra/live/production/`). Nên "dựng lại từ đầu" không phải bấm chuột tay hàng trăm lần
trên giao diện AWS, mà là:

1. Trỏ Terraform sang tài khoản mới, chạy lệnh → Terraform tự tạo: mạng riêng (**VPC**),
   cluster EKS, các nhóm máy (node group), kho ECR, máy trung gian (bastion — giải thích dưới).
2. **Build lại image**: image cũ nằm trong ECR của tài khoản cũ (mất quyền truy cập), phải
   chạy lại **CI** để build và đẩy image mới. (CI = Continuous Integration — hệ thống tự
   động build/kiểm thử code mỗi khi có thay đổi trên GitHub; của ta là GitHub Actions.)
3. Sửa file cấu hình để trỏ vào image mới (vì tên image chứa địa chỉ kho, mà kho đã đổi).
4. ArgoCD đồng bộ → website sống lại.

### Vấp phải gì? (bài học thật)

- **Bastion không kết nối được.** Bastion = "máy cổng gác": cluster của ta cố tình **không
  mở ra internet** (an toàn hơn), muốn quản trị phải đi vòng qua một máy trung gian bằng
  dịch vụ **SSM** của AWS (Session Manager — kết nối vào máy mà không cần mở cổng mạng nào).
  Lỗi: máy bastion dùng ảnh hệ điều hành bản "minimal" (tối giản) — bản này **không cài sẵn
  SSM agent** (phần mềm con để SSM hoạt động). Sửa: đổi sang bản "standard" (PR #56).
- **Image tag không tồn tại.** Cấu hình cũ trỏ vào image `d2bc367` — image này chỉ có trong
  kho cũ. Phải trỏ sang bản build mới.

### Tại sao việc này quan trọng?

Đây là minh chứng sống cho giá trị của **Infrastructure as Code** (hạ tầng là code): vì mọi
thứ là code, "thảm họa mất cả tài khoản" chỉ tốn một ngày thay vì hàng tuần. Bài học rút ra:
mọi giá trị gắn với tài khoản cụ thể (địa chỉ kho image, mã định danh...) nên là **biến số**,
đừng viết chết (hard-code) trong file.

---

## Phần 2 — Thứ Ba 14/07 (sáng): Probe — dạy K8s cách biết pod sống hay chết

### Vấn đề

K8s tự chữa lành ("căn hộ cháy thì xây lại") — nhưng nó chỉ chữa được nếu **biết** pod đang
hỏng. Mặc định, K8s chỉ biết "tiến trình còn chạy hay không". Một chương trình bị treo
(đứng hình nhưng chưa chết) hay vừa khởi động (chạy rồi nhưng chưa sẵn sàng phục vụ) — K8s
không phân biệt được, và vẫn gửi khách vào → khách gặp lỗi.

Giải pháp của K8s là **probe** (que thăm dò) — K8s định kỳ "gõ cửa" hỏi thăm pod. Có 2 loại,
**nhầm lẫn giữa 2 loại này là nguồn sự cố kinh điển**:

| Loại | Câu hỏi | Nếu trả lời "không" thì sao |
|---|---|---|
| **readiness probe** (sẵn sàng) | "Anh nhận khách được chưa?" | **Ngừng gửi khách** vào pod này (gỡ khỏi endpoint). Pod vẫn sống, được thời gian hồi phục. |
| **liveness probe** (sống) | "Anh còn sống không?" | **Giết pod, tạo lại** từ đầu. |

### Đã làm gì?

1. **Kiểm kê thực tế trước** (PR #69): soi từng service trên cluster thật xem cái nào
   có/thiếu probe — làm việc trên bằng chứng, không phỏng đoán.
2. **Thêm probe cho 11 service** (PR #73), và **chọn loại probe theo bản chất từng service**:
   - Service **có phụ thuộc dữ liệu** (product-catalog, product-reviews, checkout — cần
     Postgres/Kafka mới làm việc được): readiness probe hỏi qua **gRPC health check**
     — một chuẩn "khám sức khỏe" cho service, và code đã được sửa (việc REL-02 trước đó)
     để câu trả lời **phản ánh cả tình trạng database**: DB chết → service tự khai
     "tôi chưa sẵn sàng" → K8s ngừng gửi khách vào. (gRPC là giao thức các service nội bộ
     dùng nói chuyện với nhau — nhanh hơn HTTP thường.)
   - Service **không phụ thuộc gì** (currency, payment, ad...): chỉ cần kiểm tra
     "cổng mạng có mở không" (`tcpSocket`) là đủ. Kiểm tra cầu kỳ hơn không cho thêm
     thông tin gì.

### Tại sao KHÔNG cho liveness probe kiểm tra database?

Câu hỏi phỏng vấn kinh điển. Nếu liveness (loại "trả lời sai là bị giết") mà kiểm tra DB:
khi DB chập chờn, K8s sẽ **giết hàng loạt pod app đang hoàn toàn khỏe mạnh** → sự cố nhỏ
ở DB thành sự cố lớn toàn hệ thống (gọi là **cascade failure** — sụp đổ dây chuyền).
Nguyên tắc: kiểm tra phụ thuộc chỉ đặt ở readiness (bị cách ly chờ hồi phục), không bao giờ
ở liveness (bị hành quyết).

---

## Phần 3 — Thứ Ba 14/07 (chiều): PVC — cho database một "ổ cứng" không mất dữ liệu

### Vấn đề

Pod trong K8s là **sinh vật phù du**: chết đi tạo lại là chuyện thường ngày. Mặc định, ổ đĩa
của pod (`emptyDir` — thư mục tạm) **chết theo pod**. Mà Postgres/Valkey của ta đang chạy
kiểu này — nghĩa là: pod database restart một cái, **toàn bộ dữ liệu sản phẩm, đánh giá,
giỏ hàng... bốc hơi**. Đây là quả bom hẹn giờ.

### Giải pháp: PVC

**PVC (PersistentVolumeClaim)** = "đơn xin cấp ổ cứng bền". K8s cấp cho pod một ổ đĩa
**tách rời khỏi vòng đời pod** — thực chất là một ổ **EBS** của AWS (ổ cứng mạng gắn vào
máy ảo). Pod chết, ổ vẫn còn; pod mới sinh ra gắn lại ổ cũ, dữ liệu nguyên vẹn.

Đã làm (PR #75): gắn PVC cho Postgres và Valkey; với Valkey bật thêm **AOF** (Append-Only
File — chế độ ghi mọi thao tác xuống đĩa, để restart xong dựng lại đúng trạng thái).

### Ba hệ quả kỹ thuật phải xử lý kèm (phần "hiểu sâu")

1. **RWO — một ổ chỉ gắn được một tòa nhà.** Ổ EBS là loại **RWO (ReadWriteOnce)**: tại một
   thời điểm chỉ gắn được vào **một node**. Hệ quả: khi cập nhật phiên bản, không thể dùng
   kiểu "dựng pod mới xong mới hạ pod cũ" (hai pod sẽ giành nhau ổ) — phải dùng chiến lược
   **Recreate**: hạ pod cũ hẳn rồi mới dựng pod mới. Đổi lại, mỗi lần cập nhật database có
   vài chục giây gián đoạn — trade-off (đánh đổi) phải chấp nhận.
2. **Ổ EBS bị khóa theo AZ.** Ổ tạo ở "tòa nhà khu A" không gắn được vào node "khu B".
   Nên database được ghim vào một **node group riêng** tên `stateful_1a`: một node duy nhất,
   cố định ở AZ 1a, có **taint** — "biển cấm" của K8s: node gắn taint thì pod thường không
   được xếp vào, chỉ pod có "giấy phép" (toleration) tương ứng mới vào được. Đảm bảo node
   này chỉ dành cho database.
3. **Stateful vs stateless.** Service **stateless** (không giữ trạng thái — frontend, cart
   app, checkout...) chết tạo lại thoải mái, đặt đâu cũng được. Service **stateful** (giữ
   dữ liệu — Postgres, Valkey, Kafka) là "hàng dễ vỡ", cần đối xử đặc biệt. Toàn bộ mục này
   là câu chuyện đối xử với hàng dễ vỡ.

---

## Phần 4 — Thứ Ba 14/07 (tối): Thất bại đáng giá — Kafka PVC và quyết định rút lui

Đây là phần **nên đọc kỹ nhất** nếu bạn muốn hiểu tư duy vận hành, vì nó kể về một thất bại.

### Diễn biến

1. **Hiệp 1** — Áp PVC cho Kafka giống Postgres/Valkey (PR #77/#80). Kafka **CrashLoop** —
   thuật ngữ chỉ pod chết đi sống lại vòng lặp vô tận (crash → K8s dựng lại → crash tiếp...).
   Nguyên nhân: ổ đĩa mới định dạng chuẩn ext4 luôn có sẵn một thư mục hệ thống tên
   `lost+found`. Kafka nhìn vào thư mục dữ liệu, thấy "có gì đó không phải của mình" →
   từ chối khởi động (thà chết chứ không ghi đè lên dữ liệu lạ — hành vi an toàn của nó).
2. **Hiệp 2** — Sửa bằng `subPath` (PR #82): thay vì cho Kafka dùng cả gốc ổ đĩa, chỉ cho nó
   một thư mục con — nó không nhìn thấy `lost+found` nữa. Kafka lên... rồi **CrashLoop tiếp**,
   lỗi khác: **KRaft metadata hỏng**. Giải thích: Kafka phiên bản mới tự quản lý "sổ hộ khẩu
   nội bộ" (metadata: định danh cụm `cluster.id`, trạng thái bầu chọn leader...) — cơ chế này
   tên KRaft. Sổ hộ khẩu cũ trên ổ đĩa không khớp với lần khởi tạo mới → Kafka từ chối chạy,
   và lần này **không có cách vá sạch nhanh**.
3. **Hiệp 3** — **Quyết định rút toàn bộ** (PR #83): gỡ PVC, trả Kafka về chạy ổ tạm như cũ.

### Tại sao rút lui là quyết định ĐÚNG (không phải bỏ cuộc)?

Phép tính thiệt–hơn tại thời điểm đó:

- **Chi phí của sự cố đang diễn ra**: Kafka chết = checkout không gửi được "thư báo đơn hàng"
  = ảnh hưởng trực tiếp luồng ra tiền, NGAY BÂY GIỜ.
- **Lợi ích đang cố giành lấy**: không mất tin nhắn Kafka khi pod restart. Nhưng phân tích
  kỹ: Kafka ở đây chỉ là "ống dẫn" giữa checkout và kế toán; điều quan trọng nhất — không
  mất đơn hàng **khi hệ đang chạy** — đã được đảm bảo bằng việc khác từ trước (REL-09: bắt
  checkout chờ Kafka xác nhận đã nhận thư, bắt accounting xác nhận đã xử lý xong mới xóa thư).
  Mất tin nhắn khi broker restart là rủi ro nhỏ hơn nhiều so với cảm giác ban đầu.
- **Kết luận**: đang trả giá lớn (sự cố live) cho lợi ích nhỏ (persistence cho ống dẫn),
  và lối vá tiếp thì mù mờ. → Rút, ghi chép lại nguyên nhân, để dành bài toán này cho lời
  giải đúng (dùng dịch vụ Kafka có quản lý của AWS — MSK — trong Mandate #8).

**Nguyên tắc rút ra**: khi đang vá một sự cố do chính thay đổi của mình gây ra, hãy liên tục
tự hỏi "chi phí sự cố đang chạy có còn nhỏ hơn lợi ích của thay đổi không?". Câu trả lời
đổi chiều thì revert, không cố đấm ăn xôi. Revert cũng cần được xem là kỹ năng, không phải
nỗi xấu hổ.

---

## Phần 5 — Thứ Ba 14/07: Bảo vệ database khỏi... chính công cụ tiết kiệm tiền

### Bối cảnh: Karpenter và Spot

- **Karpenter** = công cụ tự động thuê/trả máy ảo theo nhu cầu: thiếu chỗ xếp pod thì thuê
  thêm node, thừa thì trả bớt (gọi là **consolidation** — dồn pod lại, trả node thừa để
  tiết kiệm tiền).
- **Spot instance** = máy ảo AWS bán rẻ 60-90% vì là "hàng tồn kho" — đổi lại AWS có quyền
  **đòi lại máy bất kỳ lúc nào** (báo trước 2 phút). Dùng cho app stateless thì tuyệt
  (chết thì tạo lại chỗ khác), dùng cho database thì là thảm họa.

### Vấn đề & cách xử (PR #88)

Karpenter tối ưu chi phí bằng cách chủ động tắt node — nhưng database của ta là
**single-replica** (chỉ một bản duy nhất): mỗi lần node chứa nó bị tắt là một lần
xem-hàng/giỏ-hàng sập ngoài kế hoạch. Xử lý: đảm bảo Postgres/Valkey nằm trên node
**on-demand** (loại thuê ổn định, không bị đòi lại) thuộc nhóm mà Karpenter **không quản**,
kèm đánh dấu chống mọi hình thức di dời tự nguyện.

### Bài học tư duy

Trụ của đội là **Reliability (độ tin cậy) + Cost Optimization (tối ưu chi phí)** — hai thứ
kéo co nhau. Tối ưu chi phí đúng nghĩa không phải "tiết kiệm mọi nơi" mà là **biết chỗ nào
không được tiết kiệm**: Spot + tự động dồn node cho app stateless; on-demand cố định cho
database. Máy chỉ được phép di dời database khi **con người chủ động làm theo quy trình**.

---

## Phần 6 — PgBouncer: đề xuất rồi tự bác — vì sao vẫn có giá trị

**Bối cảnh**: từng có sự cố (INC-1) do **cạn kết nối database**. Mỗi kết nối vào Postgres
tốn tài nguyên; Postgres giới hạn số kết nối đồng thời; nhiều service cùng mở kết nối vô
tội vạ → hết suất → mọi thứ lỗi.

**Hai lời giải cạnh tranh**:

1. **PgBouncer** (PR #62): đặt một "lễ tân giữ cửa" trước Postgres — mọi service nói chuyện
   với lễ tân, lễ tân giữ một nhóm nhỏ kết nối thật tới Postgres và cho mượn xoay vòng.
   (Kỹ thuật này gọi là **connection pooling** — gộp chung bể kết nối.)
2. **Pool trong code từng service** (REL-05 — hướng được chọn): mỗi service tự giới hạn
   số kết nối nó mở, cấu hình ngay trong code.

**Vì sao chọn hướng 2**: cùng giải quyết được gốc rễ (chặn cạn kết nối), nhưng PgBouncer
thêm **một mắt xích hạ tầng mới** — thêm một thứ có thể hỏng (một **SPOF** mới — Single
Point of Failure, điểm chết đơn lẻ: bộ phận mà nó hỏng là cả hệ hỏng theo), thêm một thứ
phải giám sát, cập nhật, hiểu. Ở quy mô hiện tại (~5 service dùng DB), lợi ích không bù
được độ phức tạp. PgBouncer chỉ đáng khi có hàng chục client.

**Bài học**: đề xuất một phương án, so sánh nghiêm túc, rồi **tự bác nó có lý do** — là quy
trình ra quyết định đúng, không phải công cốc. Giữa hai lời giải tương đương, chọn cái
**ít bộ phận chuyển động hơn**.

---

## Phần 7 — Đêm 14/07: Cloudflare Zero Trust — cửa sau an toàn cho đội ngũ

### Vấn đề

Trước đó (Mandate #1), đội đã **đóng toàn bộ cổng quản trị** khỏi internet: các công cụ nội
bộ như **Grafana** (màn hình theo dõi biểu đồ sức khỏe hệ thống), **Jaeger** (soi đường đi
của từng request xuyên qua các service — gọi là **tracing**), **ArgoCD** (giao diện GitOps)
— khách không được phép thấy. Đúng về bảo mật, nhưng tạo ma sát khủng khiếp cho nội bộ:
muốn xem biểu đồ phải mở **SSM tunnel** (đường hầm mạng tạm qua máy bastion) — tunnel tự
đứt sau 10-20 phút không dùng, và mỗi người phải có tài khoản IAM + biết gõ lệnh kubectl.
Thành viên không chuyên hạ tầng gần như không tự xem được gì.

### Giải pháp: Cloudflare Tunnel + Access (mô hình "Zero Trust")

Dựng các địa chỉ như `grafana.arthur-ngo.org` — ai trong đội cũng mở được **bằng trình
duyệt, đăng nhập SSO** (Single Sign-On — đăng nhập một lần bằng tài khoản định danh sẵn có,
ví dụ Google), không cần IAM, không cần dòng lệnh.

**Kiến trúc — điểm cần hiểu đúng**: cái hay nằm ở chiều của kết nối.

- Ta chạy một phần mềm nhỏ tên `cloudflared` **bên trong cluster**. Nó **chủ động gọi ra
  ngoài** tới mạng lưới Cloudflare và giữ đường hầm đó mở.
- Người dùng truy cập `grafana.arthur-ngo.org` → tới Cloudflare → Cloudflare bắt
  **đăng nhập SSO trước** (lớp gác cổng tên Cloudflare Access) → đạt thì mới chuyển tiếp
  vào đường hầm → tới Grafana trong cluster.
- **Không có bất kỳ cổng nào của cluster mở ra internet.** Kẻ tấn công quét địa chỉ mạng
  của ta sẽ không thấy gì để tấn công. Đây là triết lý **Zero Trust**: không tin ai theo
  vị trí mạng, chỉ tin danh tính đã xác thực.

### Chuỗi 5 lỗi liên tiếp khi triển khai — giáo trình debug thu nhỏ

Triển khai xong về lý thuyết, thực tế hỏng 5 lần, **mỗi lần ở một tầng khác nhau**, và lỗi
tầng trước **che mất** lỗi tầng sau (phải sửa xong mới thấy lỗi kế tiếp):

| # | Triệu chứng | Nguyên nhân | Tầng | Bài học |
|---|---|---|---|---|
| 1 | `ImagePullBackOff` (K8s không tải được image) | Ghi sai tên phiên bản image cloudflared | Image | Lỗi đánh máy cũng là sự cố; đọc kỹ thông báo lỗi của K8s |
| 2 | `CrashLoopBackOff` — pod bị giết lặp vô hạn | Liveness probe trỏ vào trang "metrics" nhưng quên bật cờ `--metrics` cho cloudflared → trang không tồn tại → probe fail → K8s tưởng pod chết → giết | Probe | **Pod hoàn toàn khỏe, bị chính probe cấu hình sai giết.** Probe sai còn tệ hơn không có probe |
| 3 | Grafana trả `502 Bad Gateway` (lỗi "người trung gian không gọi được người đứng sau") | **NetworkPolicy** — "luật tường lửa nội bộ" của K8s quy định pod nào được nói chuyện với pod nào — của Grafana đang ở chế độ chặn-hết-trừ-danh-sách-cho-phép, mà cloudflared không có trong danh sách | Mạng | Thêm lớp bảo mật mới thì phải rà lại danh sách cho phép |
| 4 | Vẫn 502 sau khi thêm cloudflared vào danh sách | Ghi cổng `80` (cổng của Service) trong khi NetworkPolicy soi ở tầng pod — phải ghi `3000` (cổng thật của container Grafana) | Mạng (sâu hơn) | NetworkPolicy áp dụng **sau khi** Service đã chuyển đổi cổng — phải dùng cổng container |
| 5 | Vào được nhưng bị đá về `localhost:3000` | Grafana có cấu hình `root_url` — nó tự dựng đường link chuyển hướng dựa trên cấu hình này, mặc định là địa chỉ nội bộ | Cấu hình app | Đặt app sau một proxy thì phải dạy app biết địa chỉ công khai của nó |

**Phương pháp luận rút ra**: debug theo **thứ tự đường đi của request** — image có tải được
không → pod có sống không → mạng có thông không → app có cấu hình đúng không. Mỗi lần sửa
một tầng, mỗi lần một PR riêng để sau này ai đọc lại cũng hiểu chuyện gì đã xảy ra.

### Một sự cố phụ đáng nhớ: sửa schema làm liệt cả dây chuyền deploy (PR #99)

Thêm một trường cấu hình mới (`digest`) vào file values nhưng quên khai báo trong
`values.schema.json` — file "danh sách trường hợp lệ", có chế độ **từ chối mọi trường lạ**.
Kết quả: Helm từ chối render → ArgoCD báo lỗi so sánh → **toàn bộ pipeline deploy đứng**,
không chỉ phần bị sửa. Từ đó có quy ước: luôn chạy `helm template` (render thử) trước khi
commit bất kỳ thay đổi chart nào. Đây cũng là mặt trái của GitOps cần biết: Git là nguồn
chân lý, nên **một commit hỏng có thể làm liệt cả hệ thống deploy**.

---

## Phần 8 — Thứ Tư 15/07: Mandate #3 — Bảo trì không downtime (phần việc lớn nhất tuần)

### Đề bài của BTC

> Rút một máy chủ ra bảo trì **giữa giờ có khách** — khách không được cảm nhận gì.
> SLO phải giữ. Có 3 yêu cầu: (1) bảo trì không downtime, (2) không còn điểm chết đơn lẻ
> trên luồng ra tiền, (3) pod chưa sẵn sàng không được nhận khách.
> Ràng buộc: trong ngân sách, và nguyên văn: **"đừng chỉ nhân đôi mọi thứ cho chắc"**.

"Rút máy chủ ra bảo trì" trong K8s gọi là **drain** (rút cạn) node: lệnh yêu cầu K8s đuổi
toàn bộ pod trên node đó sang node khác một cách có trật tự, để node trống mà tắt/sửa/thay.

### Bước 1 — Khám bệnh trước khi kê đơn (audit)

Đọc trực tiếp cấu hình và code, phát hiện 3 lỗ hổng:

1. **10 service luồng ra tiền có 2 replica, NHƯNG 2 bản sao có thể nằm chung một node.**
   Nghe có vẻ ổn ("có dự phòng rồi mà") nhưng nếu cả 2 căn hộ cùng một tòa nhà, tòa đó bảo
   trì là service mất sạch. Có **PDB** cũng không cứu được — PDB (PodDisruptionBudget) là
   luật "không được đuổi quá N pod của service này cùng lúc", nó chặn **tốc độ** đuổi chứ
   không quyết định **vị trí** pod. Hai cái bổ trợ nhau, không thay thế nhau.
2. **Không service nào biết "chết một cách lịch sự"** (graceful shutdown — giải thích dưới).
3. **Database chỉ có một bản duy nhất** trên một node — không có phép màu nào giúp nó sống
   qua việc drain chính node đó.

### Bước 2 — Bốn cơ chế đã xây

**Cơ chế 1: topologySpread + maxUnavailable:0 (PR #112) — ép dự phòng tách tòa nhà**

- **topologySpreadConstraints** = luật phân bố pod: "2 bản sao của service này **bắt buộc**
  nằm ở 2 AZ khác nhau" (tức chắc chắn 2 node khác nhau, thậm chí 2 tòa nhà trung tâm dữ
  liệu khác nhau). Chọn mức **cứng** (`DoNotSchedule` — thà không xếp lịch còn hơn xếp sai)
  cho tiêu chí AZ, mức **mềm** cho tiêu chí node để việc tự động nhân bản khi tải cao
  (**HPA** — HorizontalPodAutoscaler, bộ tự thêm/bớt pod theo tải) không bị kẹt.
- **maxUnavailable: 0, maxSurge: 1** = luật cập nhật phiên bản: "khi thay pod cũ bằng pod
  mới, **dựng pod mới cho chạy tốt đã rồi mới hạ pod cũ**" — số pod phục vụ không bao giờ
  tụt xuống dưới mức khai báo, kể cả giữa lúc deploy.
- **Trade-off đã cân nhắc**: luật cứng theo AZ có thể làm việc deploy bị **chờ** nếu một AZ
  hết chỗ — nhưng nhờ maxUnavailable:0, "chờ" nghĩa là phiên bản cũ vẫn phục vụ bình
  thường, khách không ảnh hưởng. Lỗi nghiêng về phía an toàn (fail-safe).

**Cơ chế 2: Graceful shutdown (PR #114 + #136) — dạy pod chết lịch sự**

Vấn đề tinh vi nhất tuần. Khi K8s cần tắt một pod, **hai việc xảy ra song song, không hứa
việc nào xong trước**: (a) gửi tín hiệu **SIGTERM** ("chuẩn bị tắt đi") cho chương trình,
và (b) gỡ pod khỏi danh bạ lễ tân (endpoint). Vì chạy song song, có vài giây "cửa sổ tử
thần": pod đã nhận lệnh tắt nhưng lễ tân vẫn dẫn khách vào → khách bị cắt ngang giữa chừng.
Với checkout, "cắt ngang" nghĩa là một đơn hàng đang đặt dở bị hủy giữa chừng.

Cách sửa chuẩn của ngành:

- **preStop hook `sleep 5s`**: trước khi nhận SIGTERM, pod **đứng yên phục vụ thêm 5 giây**
  — đủ thời gian cho tin "pod này sắp nghỉ" lan ra khắp các lễ tân. Hết 5 giây, không còn
  khách mới nào được dẫn vào nữa, lúc đó mới bắt đầu tắt.
- **terminationGracePeriodSeconds: 30**: sau SIGTERM, cho pod tối đa ~25 giây nữa để làm
  nốt các request đang dở, xong xuôi mới tắt hẳn.
- Chi tiết kỹ thuật: dùng "sleep" bản tích hợp sẵn của K8s (có từ phiên bản 1.30), không
  cần gọi shell — quan trọng vì một số image của ta thuộc loại **distroless** (image tối
  giản đến mức không có cả shell bên trong, để giảm bề mặt tấn công).

**Câu chuyện PR #136 — chi tiết đắt giá nhất**: service `checkout` không deploy bằng
Deployment thường mà qua **Argo Rollouts** — công cụ deploy kiểu **canary** (chim hoàng
yến trong mỏ than): đưa phiên bản mới ra cho một phần nhỏ lưu lượng trước, đo đạc thấy ổn
mới mở toàn bộ, có vấn đề thì tự lùi. Vì đường deploy khác biệt này, đợt sửa PR #114
**không phủ tới checkout** — đúng service quan trọng nhất. Phát hiện khi rà soát trước
demo → vá riêng (PR #136) → và **kiểm tra tận pod đang chạy thật** (không chỉ tin vào
file cấu hình) rằng cả 2 pod checkout đã mang cấu hình mới, nằm trên 2 node khác nhau,
rồi mới dám quay demo. Nguyên tắc: *"verify ở cả code, cấu hình render ra, và thực tế
trên cluster"* — ba tầng có thể lệch nhau.

**Cơ chế 3: PDB** (đã có từ trước — REL-01): trong lúc drain, K8s bị luật này ép **đuổi
tuần tự**: chờ bản sao mới chạy tốt ở node khác rồi mới đuổi bản tiếp theo.

**Cơ chế 4: ALB graceful drain (PR #116)**: riêng cổng vào của website (`frontend-proxy`)
đứng sau **ALB** (Application Load Balancer — máy chia tải của AWS, phân phối khách vào
các pod). ALB cập nhật danh sách "ai còn phục vụ" **chậm hơn** danh bạ nội bộ K8s, nên
tầng này cần thời gian chờ dài hơn (preStop 20 giây + dặn ALB "rút lui từ từ trong 30
giây" — deregistration delay).

### Bước 3 — Quyết định KHÔNG làm gì (quan trọng ngang việc làm)

**Không nhân đôi 7 service phụ trợ** (quảng cáo, gợi ý sản phẩm, ảnh, email, kế toán,
chống gian lận, llm). Trước khi quyết, **đọc code** để chứng minh từng cái chết-mà-không-sao:

- Quảng cáo/gợi ý chết → giao diện hiện danh sách rỗng, trang vẫn chạy (code frontend có
  giá trị mặc định `[]`).
- Ảnh chết → ảnh vỡ, vẫn mua hàng được.
- Email chết → checkout chỉ ghi log cảnh báo, đơn vẫn thành công.
- Kế toán/chống gian lận chết → chúng là người **đọc thư từ Kafka sau khi đơn đã xong**;
  chết thì thư nằm chờ trong hộp, sống dậy đọc tiếp, không mất gì. (Hành vi "suy giảm êm
  thay vì sập" này gọi là **graceful degradation**.)

→ Nhân đôi 7 service này không cứu thêm được request nào của khách, chỉ tốn tiền — và với
kế toán còn **thêm rủi ro** (2 người đọc chung hộp thư phải chia việc lại mỗi khi một người
vào/ra — cơ chế "rebalance" của Kafka — là một nguồn lỗi mới). Đây là câu trả lời trực diện
cho ràng buộc *"đừng nhân đôi mọi thứ cho chắc"* của đề bài.

**Chấp nhận rủi ro còn lại ở database — công khai, có kế hoạch**: database một bản duy nhất
+ ổ RWO thì **về mặt nguyên lý** không thể sống qua việc drain chính node của nó (gỡ ổ ra
gắn sang node khác mất vài chục giây, kiểu gì cũng có khoảng lặng). Không giấu, mà:

- Viết hẳn quy trình **planned-failover** (chuyển đổi có kế hoạch — PR #117) với con số
  thật: gián đoạn ~30-60 giây mỗi datastore, làm ngoài giờ cao điểm.
- Ghi vào **ADR** (Architecture Decision Record — "biên bản quyết định kiến trúc": tài liệu
  ghi lại đã quyết gì, tại sao, đánh đổi gì, có chữ ký — để 6 tháng sau ai đọc cũng hiểu
  ngữ cảnh) rằng lời giải triệt để là chuyển sang dịch vụ database **có quản lý** của AWS
  (RDS cho Postgres, ElastiCache cho Valkey — AWS lo dự phòng, sao lưu, chuyển đổi tự động)
  — chính là nội dung **Mandate #8** kế tiếp, hạn 20/07.

Loại rủi ro "biết rõ, đã cân nhắc, chấp nhận có thời hạn kèm kế hoạch xử lý" gọi là
**residual risk có ý thức** — khác hoàn toàn với "không biết mà dính".

---

## Phần 9 — Cũng Thứ Tư 15/07: BTC bơm lỗi thật — Postmortem 0005

**Postmortem** = "biên bản mổ xẻ sau sự cố": tài liệu ghi lại chuyện gì xảy ra, lúc nào,
ở đâu, vì sao, bằng chứng, và rút ra gì — mục tiêu là học, không phải đổ lỗi.

### Chuyện xảy ra

18:48 tối, biểu đồ **"Checkout Success Rate"** trên Grafana tụt dưới ngưỡng SLO 99%.
Nhìn qua tưởng thảm họa: khách không đặt được hàng?

### Cuộc điều tra (đáng đọc từng bước — đây là mẫu chuẩn để điều tra sự cố)

Trước hết, một khái niệm: hệ thống của ta ghi lại **trace** — "nhật ký hành trình" của mỗi
request khi nó đi xuyên qua các service. Mỗi chặng trong hành trình gọi là một **span**
(ví dụ: request đặt hàng có span cha `PlaceOrder`, bên trong có các span con: gọi thanh
toán `Charge`, gọi giao hàng `ShipOrder`, gọi xóa giỏ `EmptyCart`...). Từ các span này,
hệ thống đếm ra chỉ số thành công/thất bại.

1. **Tách chỉ số theo từng span** thay vì nhìn con số gộp. Kết quả gây sốc:
   span `PlaceOrder` (đặt hàng) lỗi = **0**. Toàn bộ ~1050 lỗi đến từ đúng một span con:
   `EmptyCart` (xóa giỏ hàng sau khi đặt xong). Đối chiếu chéo: số đơn đặt thành công =
   số lần thanh toán = số thư gửi vào Kafka = ~1532, khớp nhau hoàn hảo.
   → **Không một đơn hàng nào của khách thất bại.**
2. **Mở Jaeger xem một trace cụ thể**: span cha `PlaceOrder` xanh, thanh toán xanh, giao
   hàng xanh — chỉ mỗi span con `EmptyCart` đỏ, và nó nằm **sau** bước thanh toán/giao hàng.
   Lỗi "cụt" tại đó, không lan lên cha.
3. **Đọc log pod `cart`**: đầy dòng lỗi `"Wasn't able to connect to redis"` (không kết nối
   được kho giỏ hàng). NHƯNG các thao tác khác trên giỏ (xem giỏ, thêm hàng) **cùng thời
   điểm vẫn thành công**, và pod Valkey thật hoàn toàn khỏe: 0 lần restart, log sạch.
   Kho thật không hề chết — vậy lỗi "không kết nối được" ở đâu ra?
4. **Đọc code service cart** — tìm ra thủ phạm: có đoạn code kiểm tra cờ `cartFailure` từ
   flagd; khi cờ bật, **riêng thao tác EmptyCart** bị cố tình chuyển sang một "kho giả hỏng"
   luôn ném lỗi (giả lập mất kết nối). Truy vấn flagd xác nhận: cờ `cartFailure` đã được
   BTC bật đúng 14 phút rồi tắt. **Vụ án khép lại: BTC bơm lỗi có chủ đích qua feature flag.**
5. **Vì sao khách không hề hấn gì?** Code checkout có dòng chủ động **bỏ qua lỗi xóa giỏ**
   (`_ = cs.emptyUserCart(...)` — dấu `_` trong Go nghĩa là "vứt kết quả trả về đi"). Xóa
   giỏ chỉ là bước dọn dẹp sau khi đơn đã xong — thiết kế đúng đắn: không để một bước phụ
   làm hỏng đơn hàng đã thanh toán thành công. Tác dụng phụ duy nhất với khách: trong 14
   phút đó, hàng vừa mua có thể còn sót trong giỏ — phiền nhẹ, tự hết.

### Phát hiện giá trị nhất: chính cái thước đo bị sai

Biểu đồ "Checkout Success Rate" thực chất đang đo *"tỷ lệ lỗi trên **mọi** span mà service
checkout phát ra"* — bao gồm cả span phụ `EmptyCart` vốn đã được nghiệp vụ cố tình bỏ qua.
Nó **không** đo điều SLO thực sự quan tâm: *"khách có đặt được hàng không?"*. Vì thế biểu
đồ báo động đỏ trong khi khách 100% vui vẻ — báo động giả, đốt cạn "ngân sách lỗi"
(error budget) một cách oan uổng.

Đề xuất sửa: thu hẹp phép đo về đúng span `PlaceOrder`. Và một ranh giới đạo đức được ghi
thẳng vào postmortem: đây là **đo đúng bản chất**, khác hoàn toàn với trò "sửa số cho đẹp"
— bằng chứng là nếu sau này đơn hàng fail thật (như đợt BTC bơm `paymentFailure` trước đó),
phép đo mới **vẫn bắt được** vì lúc đó span cha sẽ đỏ.

Kèm theo 2 đề xuất: (a) hai chuông báo động tách bạch — "đơn fail thật" (nghiêm trọng) và
"lỗi span phụ tăng đột biến" (dấu hiệu có bơm lỗi, mức nhẹ); (b) đổi chỗ nuốt-lỗi-im-lặng
trong code checkout thành ghi log cảnh báo, để lần điều tra sau có dấu vết ngay trong log.

### Điều KHÔNG làm — và tại sao

Không đụng vào flagd, không "sửa bug" `cartFailure` — vì nó không phải bug, nó là công cụ
bơm lỗi của BTC, và gỡ nó là **bị loại**. Cơ chế phòng thủ đúng đã có sẵn trong code (nuốt
lỗi bước phụ) và đã chứng minh hiệu quả. Việc còn lại chỉ là vá lỗ hổng **đo lường**.

---

## Phần 10 — Vệ sinh tài liệu (nghe phụ, hóa ra là xương sống)

- **PR #118**: bản kiểm kê trước đó ghi nhầm REL-02 là "chưa làm" trong khi thực tế đã làm
  và đang chạy → sửa công khai. Tài liệu sai còn nguy hiểm hơn không có tài liệu, vì người
  sau sẽ **làm lại việc đã xong** hoặc quyết định dựa trên hiện trạng ảo.
- **PR #119/#131**: cập nhật file bối cảnh dự án (CLAUDE.md) sau 2 biến cố lớn (chuyển tài
  khoản, chuyển nguồn deploy về nhánh `main`) — file bối cảnh chỉ có giá trị đúng bằng mức
  nó phản ánh hiện tại.
- **PR #152 (16/07)**: báo cáo demo Mandate #3 nộp BTC — có video, số liệu, câu truy vấn
  cho phép người chấm **tự chạy lại kiểm chứng**, và mục "trung thực" tự khai các điểm chưa
  đẹp (xem Phần 11).

Bộ ba loại tài liệu của đội, nên nhớ để dùng đúng chỗ:

| Loại | Trả lời câu hỏi | Khi nào viết |
|---|---|---|
| **ADR** | "Tại sao hồi đó quyết như vậy?" | Mỗi quyết định kiến trúc lớn |
| **Postmortem** | "Chuyện gì đã xảy ra và học được gì?" | Sau mỗi sự cố |
| **Runbook** | "Làm việc X thì bấm gì, theo thứ tự nào?" | Cho mọi thao tác vận hành lặp lại được |

---

## Phần 11 — Thứ Năm 16/07: Demo Mandate #3 — giờ G

### Kịch bản

Chọn node để drain **một cách có chủ đích**: `ip-10-0-43-83` — node đang gánh **6 pod thuộc
luồng ra tiền**, gồm cả checkout + cart + payment. Chọn node "nặng ký" nhất để demo có ý
nghĩa (drain node rỗng thì chứng minh được gì?), sau khi đã kiểm tra từng service trên đó
đều còn bản sao ở node khác.

Quy trình: `kubectl cordon` (cấm xếp pod mới vào node — "đóng cửa nhận khách mới") →
`kubectl drain` (đuổi pod dần, tôn trọng PDB + thời gian chết-lịch-sự) → theo dõi → xong
thì `kubectl uncordon` (mở cửa lại).

### Kết quả — đo trong đúng 10 phút drain, bằng Prometheus

(**Prometheus** = kho lưu chỉ số theo thời gian; Grafana chỉ là màn hình vẽ dữ liệu từ đây.)

| Chỉ số | Ngưỡng SLO | Kết quả | |
|---|---|---|---|
| Checkout thành công | ≥ 99% | **99.94%** | ✅ |
| Browse / Cart thành công | ≥ 99.5% | **100% / 99.95%** | ✅ |
| Độ trễ p95 | < 1000ms | **68.6ms** | ✅ |

Không pod nào của luồng ra tiền bị kẹt. (0.06% "lỗi" của checkout ~ 1 request, thực chất là
sai số của công thức ngoại suy ở mép cửa sổ đo — đã ghi chú trong báo cáo.) Câu truy vấn
được in kèm trong báo cáo để mentor tự chạy lại được — **bằng chứng tái lập được** luôn
thuyết phục hơn ảnh chụp màn hình.

### Hai chuyện "ngoài kịch bản" — và cách xử lý mẫu mực

1. **Grafana sập 502 đúng 1 phút giữa demo.** Vì Grafana chỉ có 1 bản, và nó nằm... đúng
   trên node đang bị drain. Phân tích tại chỗ: đây là **mặt phẳng giám sát** (công cụ của
   đội) chứ không phải **sản phẩm** (thứ khách dùng) — khách không ảnh hưởng, SLO không rớt.
   Xử lý: theo dõi tiếp qua terminal, lấy bằng chứng từ đồ thị lịch sử sau khi Grafana hồi
   (dữ liệu gốc trong Prometheus không mất). Trong báo cáo tự ghi câu mỉa mai:
   *"công cụ để xem SLO thì chớp tắt, còn thứ được đo thì ổn"* — **khai ra thay vì giấu**,
   và biến nó thành hạng mục cải thiện.
2. **Phát hiện quả bom mới**: cả 2 bản sao của cloudflared đang nằm **chung một node** —
   đúng cái lỗi "có 2 replica nhưng chung tòa nhà" mà tuần này đi sửa cho các service khác.
   Nếu hôm đó drain trúng node kia thì mất toàn bộ đường truy cập quản trị cùng lúc.
   → Ghi thành việc ưu tiên cao: thêm luật tách node (anti-affinity) cho cloudflared.

### Bảng đối chiếu đề bài

| Yêu cầu Directive #3 | Kết quả |
|---|---|
| 1. Không downtime khi bảo trì | ✅ Chứng minh live, số liệu vượt cả 3 ngưỡng |
| 2. Không SPOF luồng ra tiền | ✅ Tầng app xong; tầng database: có quy trình failover tạm + kế hoạch xóa hẳn ở Mandate #8 |
| 3. Pod chưa sẵn sàng không nhận khách | ✅ Probe toàn bộ (Phần 2) — chính là lý do success-rate không rớt lúc pod dời node |

---

## Phần 12 — Tổng kết: 5 nguyên tắc xuyên suốt tuần

Nếu chỉ nhớ được 5 điều từ tài liệu này:

1. **Bằng chứng trước, hành động sau.** Mọi việc đều bắt đầu bằng audit thực tế (soi
   cluster, đọc code) — không sửa theo phỏng đoán. Và verify ở cả 3 tầng: code trong Git,
   cấu hình render ra, và thực tế đang chạy trên cluster — ba tầng có thể lệch nhau
   (bài học PR #136).
2. **Biết rút lui.** Vụ Kafka PVC: khi chi phí của sự cố đang chạy vượt lợi ích đang cố
   giành, revert ngay và ghi chép lại. Revert là kỹ năng, không phải thất bại.
3. **Reliability không phải "nhân đôi mọi thứ".** Nó là hiểu chính xác cái gì được phép
   chết (7 service phụ trợ — chứng minh bằng code), cái gì không (luồng ra tiền), và cái
   gì chưa bảo vệ được thì khai báo công khai kèm kế hoạch (database → Mandate #8).
4. **Đo đúng thứ cần đo.** Vụ cartFailure: biểu đồ SLO báo động đỏ trong khi khách 100%
   đặt hàng thành công — vì phép đo sai tầng. Chỉ số sai còn nguy hiểm hơn không có chỉ số.
5. **Trung thực là chiến lược, không phải khẩu hiệu.** Báo cáo demo tự khai Grafana blip;
   ADR ghi thẳng downtime 30-60s của database; backlog được đính chính công khai. Người
   chấm (và đồng đội tương lai) tin được tài liệu của đội — đó là tài sản.

---

## Phụ lục A — Bảng thuật ngữ tra nhanh (A→Z)

| Thuật ngữ | Nghĩa ngắn gọn |
|---|---|
| ADR | Biên bản ghi lại quyết định kiến trúc: quyết gì, tại sao, đánh đổi gì |
| ALB | Máy chia tải của AWS — phân phối request của khách vào các pod |
| AOF | Chế độ của Valkey/Redis ghi mọi thao tác xuống đĩa để khôi phục sau restart |
| Argo Rollouts | Công cụ deploy kiểu canary: thả phiên bản mới cho ít khách trước, ổn mới mở hết |
| ArgoCD | Phần mềm GitOps: tự đồng bộ cluster theo khai báo trong Git |
| AZ | Availability Zone — "tòa nhà" trung tâm dữ liệu tách biệt trong một region |
| Bastion | Máy trung gian để truy cập cluster kín (không mở internet) |
| BTC | Ban tổ chức — người bơm sự cố và chấm điểm |
| Cache | Kho lưu tạm siêu nhanh (Valkey/Redis) |
| Canary | Chiến lược thả phiên bản mới cho phần nhỏ lưu lượng để dò rủi ro |
| Cascade failure | Sụp đổ dây chuyền — sự cố nhỏ kéo theo sự cố lớn |
| CI | Hệ thống tự build/kiểm thử code (GitHub Actions) |
| Cluster | Toàn bộ "khu chung cư" Kubernetes |
| Connection pooling | Gộp chung bể kết nối database để không cạn suất |
| Container / Image | Chương trình đóng gói kèm mọi thứ nó cần / bản "ảnh" của gói đó |
| Cordon / Drain / Uncordon | Cấm nhận pod mới / đuổi pod đi có trật tự / mở lại — chu trình bảo trì node |
| CrashLoopBackOff | Pod chết đi sống lại vòng lặp vô tận |
| Datastore | Gọi chung nơi lưu dữ liệu (Postgres, Valkey, Kafka) |
| Deploy / Deployment | Đưa bản mới lên chạy / bản khai báo "service X chạy N bản sao" trong K8s |
| Distroless | Image tối giản không có cả shell — giảm bề mặt tấn công |
| EBS | Ổ cứng mạng của AWS, gắn vào máy ảo; bị khóa theo AZ |
| ECR / EKS / EC2 | Kho image / dịch vụ Kubernetes / máy ảo — của AWS |
| Endpoint | Danh sách pod khỏe đứng sau một Service |
| Error budget | "Ngân sách lỗi" = 100% − SLO; phần được phép hỏng trong kỳ |
| Feature flag / flagd | Công tắc bật/tắt hành vi không cần sửa code / service phát công tắc (BTC điều khiển — CẤM GỠ) |
| Graceful degradation | Suy giảm êm: một phần chết, tổng thể vẫn phục vụ |
| Graceful shutdown | Chết lịch sự: làm nốt việc dở, không nhận việc mới, rồi mới tắt |
| Grafana / Jaeger / Prometheus | Màn hình biểu đồ / soi hành trình request / kho lưu chỉ số |
| gRPC | Giao thức các service nội bộ nói chuyện với nhau |
| Helm / chart / values | Công cụ khuôn mẫu cấu hình K8s / cái khuôn / file điền giá trị |
| HPA | Bộ tự thêm/bớt pod theo tải |
| IAM | Hệ thống phân quyền của AWS |
| Kafka / KRaft | Hàng đợi tin nhắn / cơ chế Kafka tự quản metadata (không cần ZooKeeper) |
| Karpenter | Bộ tự thuê/trả máy ảo theo nhu cầu |
| kubectl | Công cụ dòng lệnh điều khiển K8s |
| Liveness / Readiness probe | Que thăm dò "còn sống không?" (fail = giết) / "sẵn sàng chưa?" (fail = ngừng gửi khách) |
| Microservice | Kiến trúc nhiều chương trình nhỏ ghép lại |
| NetworkPolicy | Luật tường lửa nội bộ: pod nào được nói chuyện với pod nào (soi ở cổng container) |
| Node / Node group | Máy ảo trong cluster / nhóm máy cùng cấu hình |
| On-demand / Spot | Máy thuê ổn định giá đủ / máy giá rẻ 60-90% nhưng AWS đòi lại bất kỳ lúc nào |
| p95 | Mốc 95% khi xếp request theo độ trễ — đo trải nghiệm nhóm chậm |
| PDB | Luật "không được đuổi quá N pod cùng lúc" khi bảo trì |
| Pod / Replica | Đơn vị chạy nhỏ nhất trong K8s / số bản sao của một service |
| Postmortem | Biên bản mổ xẻ sau sự cố — để học, không để đổ lỗi |
| PR | Pull Request — đơn xin gộp thay đổi vào Git, cần người duyệt |
| preStop / SIGTERM / grace period | Việc làm trước khi tắt / tín hiệu "chuẩn bị tắt" / thời gian ân hạn để làm nốt việc dở |
| PVC / RWO | Đơn xin ổ cứng bền cho pod / loại ổ chỉ gắn 1 node một lúc |
| RDS / ElastiCache / MSK | Postgres / Redis / Kafka phiên bản "AWS quản hộ" (managed) |
| Region | Khu vực địa lý của trung tâm dữ liệu AWS |
| Residual risk | Rủi ro còn lại — đã biết, đã cân nhắc, chấp nhận có kế hoạch |
| Rollback / Revert | Quay về phiên bản trước / hoàn tác một thay đổi trong Git |
| Runbook | Tài liệu "làm việc X thì bấm gì theo thứ tự nào" |
| SLI / SLO | Chỉ số đo chất lượng / mục tiêu cam kết trên chỉ số đó |
| Span / Trace | Một chặng trong hành trình request / toàn bộ hành trình |
| SPOF | Điểm chết đơn lẻ — nó hỏng là cả hệ hỏng theo |
| SSM | Dịch vụ AWS kết nối vào máy không cần mở cổng mạng |
| SSO | Đăng nhập một lần bằng danh tính sẵn có |
| Stateful / Stateless | Có giữ dữ liệu (dễ vỡ) / không giữ (chết tạo lại thoải mái) |
| Taint / Toleration | "Biển cấm" trên node / "giấy phép" của pod để vào node có biển cấm |
| Terraform | Công cụ khai báo hạ tầng bằng code |
| topologySpread | Luật ép các bản sao của một service tách node/AZ |
| Tunnel | Đường hầm mạng tạm để truy cập hệ thống kín |
| VPC | Mạng riêng ảo trong AWS |
| Zero Trust | Triết lý bảo mật: không tin theo vị trí mạng, chỉ tin danh tính đã xác thực |
| 502 Bad Gateway | Lỗi "người trung gian không gọi được người đứng sau" |

## Phụ lục B — Đọc tiếp ở đâu

Tài liệu gốc trong repo (đọc theo thứ tự này sau khi xong file này):

1. `CLAUDE.md` (gốc repo) — bối cảnh và trạng thái mới nhất của cả dự án
2. `phase3 - information/RULES.md` — luật chơi, **đặc biệt các điều khoản bị loại**
3. `docs/adr/0007-mandate-03-maintenance-no-downtime-cdo02.md` — ADR mẫu tốt nhất để học cách viết
4. `docs/mandate-03-drain-node-report.md` — báo cáo demo, có video
5. `docs/postmortem/0005-btc-injected-cart-failure-flag.md` — postmortem mẫu, học cách điều tra
6. `docs/runbooks/mandate-03-drain-node-demo.md` — runbook mẫu
7. `docs/backlog/cdo02-reliability-cost-backlog.md` — danh sách việc và trạng thái thật
