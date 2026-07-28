# Solution Proposal – Mandate #9: Zero-Downtime Operations on Managed Services

## 1. Mục tiêu triển khai
Mục tiêu của mandate này không chỉ là “thay đổi được” mà là “thay đổi được trong production mà khách không nhận thấy gì”. Vì vậy, giải pháp tập trung vào hai trụ cột chính:
- Reliability: giữ zero-downtime và không làm rớt request khách.
- Cost Optimization: thực hiện thay đổi với rủi ro vừa phải và tránh chi phí phát sinh không cần thiết.

> Các trụ cột khác không được mở rộng trong tài liệu này; các nội dung liên quan sẽ được bàn giao cho CD01.

## 2. Nguyên tắc triển khai
1. Thay đổi phải được thực hiện trên nền hệ thống đang chịu tải thật, không phải lúc idle.
2. Mỗi thay đổi phải có checkpoint rõ ràng trước và sau mỗi bước.
3. Mỗi thao tác phải có điều kiện dừng hoặc rollback nếu metric bắt đầu đi xa khỏi baseline.
4. Mọi quyết định thay đổi cần cân đối giữa an toàn và chi phí.

## 3. Phương án thực hiện theo bước

### 3.1 Chuẩn bị trước thao tác
Trước khi bắt đầu, cần có 4 nhóm chuẩn bị:

1. Chuẩn bị traffic và baseline
   - kích hoạt load-generator để tạo traffic giả lập production liên tục;
   - ghi baseline metrics: success rate, error rate, latency p95/p99, connection failures, pool saturation.

2. Chuẩn bị ứng dụng
   - đảm bảo connection pool có thể tái sử dụng;
   - app có retry logic với backoff;
   - thao tác phải idempotent để tránh double effect khi retry;
   - log rõ lỗi kết nối tạm thời để theo dõi.

3. Chuẩn bị hạ tầng
   - xác định instance/store đang chạy, backup/restore point, và phương án thay thế nếu cần rollback;
   - nếu là thay đổi cần reboot thì phải có phương án giữ traffic liên tục trong lúc cutover.

4. Chuẩn bị chi phí
   - xác định cost impact trước khi thực hiện, đặc biệt nếu cần bật Multi-AZ, tăng instance, tạo bản sao mới, hoặc mở thêm capacity tạm thời;
   - ghi lại lý do vì sao phương án được chọn.

### 3.2 Schema migration dưới tải
Áp dụng pattern chuẩn sau để giảm rủi ro:

1. Expand
   - thêm cột mới hoặc schema mới, nhưng vẫn giữ cấu trúc cũ hoạt động;
   - ưu tiên nullable hoặc có default để app cũ không bị lỗi.

2. Backfill
   - chạy backfill theo batch nhỏ để tránh lock lớn và giảm áp lực DB;
   - nên có giới hạn concurrency để không làm tăng latency nghiêm trọng.

3. Dual read/write
   - app viết cả schema cũ và schema mới trong giai đoạn chuyển tiếp;
   - đọc ưu tiên từ schema mới khi việc đồng bộ đã ổn định.

4. Contract
   - sau khi xác nhận app chạy ổn định, chuyển toàn bộ đọc/ghi sang schema mới;
   - sau đó mới tiến hành clean-up schema cũ.

Lợi ích của phương án này:
- giảm rủi ro liên quan đến lock và blocking;
- giảm khả năng làm service lỗi ngay khi thay đổi schema;
- giúp bảo vệ Reliability và kiểm soát chi phí do rollback/khắc phục ít hơn.

### 3.3 Nâng version managed store
Đối với nâng engine version hoặc đổi bản build managed service, cần ưu tiên phương án không làm đổi endpoint của app:
- dùng replica hoặc instance mới trước;
- kiểm tra toàn bộ kết nối, auth và query compatibility trên bản sao;
- giữ endpoint ứng dụng ổn định bằng cấu trúc proxy hoặc cutover có kiểm soát;
- chỉ chuyển traffic sang endpoint mới sau khi xác nhận metrics ổn định.

Điểm quan trọng:
- không nên làm trực tiếp trên production active endpoint trong một bước duy nhất;
- việc tách “ready” và “cutover” giúp giảm rủi ro và tránh chi phí do phải scale lại / rollback.

### 3.4 Thay đổi parameter cần reboot
Với parameter-group cần restart instance, phương án phù hợp là:
- thay đổi trên instance mới hoặc bản sao trước;
- kiểm tra hiệu quả và độ tương thích trước khi cutover;
- nếu restart bắt buộc, thực hiện khi app đã sẵn sàng xử lý connection đổi;
- không làm restart đồng thời cho toàn bộ hệ thống nếu không cần.

Lợi ích:
- giảm nguy cơ connection reset và request loss;
- bảo vệ reliability trong khi vẫn duy trì chi phí ở mức hợp lý.

### 3.5 Rotate credential live
Quy trình đề xuất:
1. cập nhật secret mới trong Secrets Manager;
2. để ExternalSecret refresh secret trên cluster;
3. kiểm tra app đọc được secret mới mà không cần restart toàn bộ hệ thống;
4. theo dõi error rate để chắc chắn không có lỗi kết nối do credential mới.

Mục tiêu là app vẫn hoạt động trong khi credential thay đổi, không cần phá vỡ deployment hay gây downtime.

## 4. Cơ chế ứng dụng chịu được blip kết nối
Để zero-downtime có ý nghĩa, app cần có các cơ chế sau:
- retry với backoff;
- connection pool tái sử dụng;
- tránh fail-fast ở tầng request;
- ưu tiên thao tác idempotent;
- nếu có thể, dùng proxy hoặc abstraction layer để che được thời điểm cutover.

Những điều này quan trọng vì các thay đổi managed service thường gây lỗi kết nối ngắn, dù không nhất thiết làm hỏng dữ liệu.

## 5. Tiêu chí chấp nhận
Một thao tác được coi là thành công khi:
- error count = 0 trong toàn bộ cửa sổ thay đổi;
- latency không có spike gây ảnh hưởng lớn tới trải nghiệm khách;
- app vẫn kết nối được store sau khi cutover;
- không có rollback hoặc chỉ rollback rất nhỏ và có kiểm soát.

## 6. Cân đối chi phí và độ tin cậy
Với giới hạn ngân sách khoảng $300/tuần cho TF, nên ưu tiên phương án sau:
- chọn thay đổi có rủi ro thấp hơn trước; tránh “đổi cho chắc” bằng cách tăng tài nguyên không cần thiết;
- ưu tiên phương án dùng bản sao/instance mới thay vì tăng toàn bộ capacity ngay lập tức;
- nếu cần Multi-AZ hoặc tăng capacity, phải ghi lại lý do rõ ràng và so sánh lợi ích với chi phí.

Nói ngắn gọn: không phải thay đổi càng nhiều càng tốt, mà là thay đổi đủ an toàn để đạt zero-downtime với chi phí hợp lý.

## 7. Kết luận
Giải pháp này phù hợp với kiến trúc hiện tại của dự án vì hệ thống đã có managed datastore, secret sync và nền Kubernetes có thể hỗ trợ rollout có kiểm soát. Mấu chốt là không làm thay đổi “độc lập” trên production mà phải thực hiện theo flow có checkpoint, có observability và có đánh giá chi phí từng bước.
