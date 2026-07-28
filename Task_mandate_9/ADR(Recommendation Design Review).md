# ADR – Recommendation Design Review

## Title
Recommendation for zero-downtime operations on managed data services for Mandate #9.

## Status
Proposed

## Context
Directive #9 yêu cầu thực hiện thay đổi trên managed data store trong khi hệ thống đang phục vụ traffic thật, với tiêu chuẩn không có request khách nào bị rớt. Đây là một bài vận hành thực tế, không phải chỉ “deploy thành công” ở môi trường thử.

Trong bối cảnh dự án hiện tại, hệ thống đã có các thành phần phù hợp để thực hiện mandate này:
- managed datastore đã được dùng cho các service quan trọng;
- secret injection đã có cơ chế chuẩn qua ExternalSecret;
- nền Kubernetes và observability đã sẵn sàng để hỗ trợ rollout có kiểm soát.

Tuy nhiên, để làm đúng mandate, cần một thiết kế vận hành có kiểm soát về độ tin cậy và chi phí, thay vì thực hiện thay đổi theo kiểu thủ công.

## Decision
Chúng tôi đề xuất chọn phương án vận hành sau:

1. Dùng pattern expand → backfill → dual-read/write → contract cho schema change.
   - Đây là cách giữ tương thích ngược và giảm rủi ro gây lỗi khi thay đổi production.

2. Dùng cutover có kiểm soát cho nâng version hoặc đổi instance managed service.
   - Không đổi endpoint trực tiếp và đột ngột; ưu tiên bản sao/instance mới trước rồi mới chuyển traffic.

3. Dùng secret rotation thông qua Secrets Manager và ExternalSecret.
   - App nhận credential mới mà không cần restart toàn hệ thống.

4. Dùng load-generator và observability trong toàn bộ window thay đổi.
   - Theo dõi error rate, latency, connection failures và các chỉ số liên quan đến service quality.

5. Dùng app-side resilience controls.
   - retry, connection pool, idempotency và logging rõ ràng là điều bắt buộc để chịu được blip kết nối.

## Rationale
Việc đổi schema hoặc thay đổi engine/version trên managed datastore luôn có rủi ro gây block, connection reset hoặc vấn đề đồng bộ dữ liệu. Phương án trên giúp giảm rủi ro bằng cách chia thành các bước nhỏ, kiểm tra từng bước, và chỉ chuyển traffic sang trạng thái mới khi đã chắc chắn ổn định.

Về mặt chi phí, phương án này còn giúp tránh việc phải rollback, tăng capacity quá mức, hoặc phải tái thực hiện thao tác nhiều lần. Vì vậy, nó phù hợp với mục tiêu Reliability và Cost Optimization trong mandate này.

## Consequences
### Positive
- Giảm nguy cơ downtime và request loss.
- Tăng khả năng chứng minh zero-downtime trong thực tế.
- Giảm chi phí phát sinh do rollback, điều chỉnh lại capacity hoặc khắc phục trễ.
- Tạo một chuẩn vận hành có thể dùng cho các thay đổi production tiếp theo.

### Trade-offs
- Tăng thời gian chuẩn bị và giám sát trong window thay đổi.
- Cần kiểm soát chặt hơn ở tầng app và tầng database.
- Yêu cầu đội vận hành phải theo dõi liên tục và có trách nhiệm với các metric.

## Alternatives considered
1. Thực hiện thay đổi trực tiếp trên production mà không dùng pattern kiểm soát.
   - Bị loại vì rủi ro cao và khó chứng minh zero-downtime.

2. Dừng service hoặc cắt bảo trì trước khi thao tác.
   - Bị loại vì vi phạm nguyên tắc của mandate.

3. Chỉ dùng restart app để thay credential hoặc đổi endpoint.
   - Bị loại vì không đủ an toàn và có thể gây lỗi request tập trung.

## Recommendation
Nên triển khai bằng một runbook có checkpoint rõ ràng: chuẩn bị baseline, chạy dry run, thực hiện thay đổi từng bước, giám sát liên tục, và chỉ kết thúc khi error count = 0 và hệ thống vẫn ổn định. Các trụ cột khác ngoài Reliability và Cost Optimization được xem là bàn giao cho CD01.
