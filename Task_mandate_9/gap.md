# Gap Analysis – Mandate #9: Managed Zero-Downtime Operations

## 1. Mục tiêu
Directive #9 yêu cầu thực hiện thay đổi trên tầng managed data store trong điều kiện hệ thống đang phục vụ tải thật, đồng thời chứng minh rằng không có request khách nào bị rớt. Với bối cảnh dự án hiện tại, điểm cần tập trung là hai trụ cột chính:
- Reliability: thay đổi phải thực hiện mà không làm gián đoạn dịch vụ.
- Cost Optimization: mọi thay đổi phải được cân đối với ngân sách hạ tầng và tránh chi phí không cần thiết.

> Các trụ cột khác trong chấm điểm được xem là bàn giao cho CD01 và không được mở rộng trong tài liệu này.

## 2. Phân tích hiện trạng từ dự án
Dự án đã có nền tảng kỹ thuật phù hợp để thực hiện mandate này:
- RDS PostgreSQL đã được dùng cho các service như product-catalog, product-reviews và accounting.
- ElastiCache/Valkey và MSK đã hiện diện trong kiến trúc, cho thấy hệ thống có thể chuyển sang managed layer một cách có kiểm soát.
- GitOps và ExternalSecret đã sẵn sàng cho việc quản lý secret và credential rotation.

Tuy nhiên, hiện tại vẫn thiếu các artefact vận hành để làm việc này đúng cách trong production:
- không có runbook riêng cho online schema change dưới tải;
- chưa có quy trình cutover cho nâng version managed service;
- chưa có checklist cho parameter change cần restart mà không gây lỗi khách;
- chưa có bằng chứng thực nghiệm cho việc app chịu được blip kết nối và retry đúng.

## 3. Bảng phân tích khoảng trống

| Mục | Hiện trạng | Khoảng trống | Tác động đến Reliability | Tác động đến Cost Optimization |
|---|---|---|---|---|
| Online schema migration | Repo có kiến trúc và datastore managed, nhưng chưa có playbook cụ thể | Thiếu quy trình expand → backfill → dual-read/write → contract | Cao: nếu làm trực tiếp có thể gây blocking, lỗi query và request thất bại | Trung bình: sai cách có thể làm tăng rollback, tăng thời gian vận hành và phát sinh chi phí khắc phục |
| Managed engine version upgrade | Chưa có kế hoạch cutover và đánh giá rủi ro cho production | Thiếu bước kiểm tra trước và sau nâng version, thiếu phương án giữ endpoint ổn định | Cao: lỗi cutover có thể làm service không kết nối được | Trung bình: nếu phải rollback hoặc scale lại có thể làm tăng chi phí vận hành |
| Parameter change cần reboot | Chưa có quy trình đối với change yêu cầu restart | Thiếu kiểm soát để tránh downtime khi restart hoặc đổi tham số | Cao: restart không kiểm soát dễ gây connection reset và request loss | Thấp đến trung bình: tuy không trực tiếp tăng cost lớn nhưng có thể dẫn đến khắc phục kéo dài |
| Credential rotation live | Có secret sync qua ExternalSecret, nhưng chưa có quy trình vận hành rõ | Chưa có check vận hành cho việc update secret mới và app nhận đúng credential | Cao: nếu app không nhận secret mới đúng, lỗi kết nối sẽ xuất hiện ngay | Trung bình: lỗi secret có thể gây outage và phát sinh chi phí khẩn cấp |
| Chứng minh zero-downtime | Chưa có template, metric và acceptance criteria thống nhất | Thiếu cơ sở để chứng minh error count = 0 và không gây ảnh hưởng cho khách | Cao: đây là phần cốt lõi của mandate | Trung bình: nếu không có bằng chứng cần thiết, team khó bảo vệ quyết định chi phí và thay đổi |

## 4. Phân tích theo trụ cột
### Reliability
Khoảng trống lớn nhất nằm ở việc chưa có một flow vận hành có kiểm soát cho các thay đổi production. Điều này làm tăng rủi ro đối với:
- lỗi kết nối giữa app và DB,
- lock/blocking trong PostgreSQL,
- retry sai hoặc fail-fast gây request bị rớt,
- khó xác nhận zero-downtime trong thực tế.

### Cost Optimization
Dự án có ngân sách hạ tầng cố định và cần tránh quyết định làm tăng chi phí mà không có giá trị rõ ràng. Khoảng trống hiện tại là:
- chưa có đánh giá chi phí trước/sau mỗi thay đổi managed service;
- chưa có khung để cân nhắc giữa “đổi an toàn” và “chi phí hợp lý”;
- chưa có hồ sơ ghi lại vì sao một phương án được chọn thay vì phương án khác.

## 5. Kết luận
Dự án đã có nền tảng kỹ thuật để làm mandate này, nhưng thiếu một thiết kế vận hành và một chứng minh thực tế cho zero-downtime. Nếu không bổ sung runbook, acceptance criteria và đề xuất chi phí/đánh đổi, việc thực hiện sẽ rủi ro về độ tin cậy và dễ vượt ngưỡng chi phí trong quá trình vận hành.
