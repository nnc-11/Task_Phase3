# Kế hoạch Kiểm thử (Test Plan) chi tiết cho Mandate #12 — Xây dựng hệ thống kiểm toán không thể bị đánh bại

> **Mục tiêu:** Chứng minh hệ thống kiểm toán (Audit Trail) được bảo vệ toàn diện trước 3 đòn tấn công: Làm mù, Làm hụt và Làm mỏng/sửa. Hệ thống sẽ phát hiện, báo động ngay lập tức và giữ bằng chứng an toàn kể cả khi kẻ tấn công có quyền quản trị cao nhất.

---

## 1. Bài test 1: Đòn "Làm mù" (Tắt camera)

**Mục đích:** Kẻ tấn công cố gắng tắt hệ thống ghi log (CloudTrail) trước khi thực hiện hành vi mờ ám để không để lại dấu vết.

### Kịch bản 1.1: Tắt CloudTrail bằng tài khoản có quyền admin
- **Bước thực hiện:** Mentor sử dụng tài khoản có quyền cao (VD: `AdministratorAccess` hoặc tài khoản CI/CD `gha-terraform-apply`) thực hiện lệnh tắt CloudTrail thông qua AWS CLI:
  ```bash
  aws cloudtrail stop-logging --name <trail-name> --region ap-southeast-1
  ```
- **Kết quả mong đợi (PASS khi):**
  1. Nếu tài khoản bị giới hạn bởi **Permissions Boundary**, lệnh sẽ thất bại ngay lập tức với lỗi `AccessDenied`.
  2. Nếu lệnh lọt qua (do dùng root user hoặc principal chưa gắn boundary), hệ thống CloudTrail bị tắt nhưng **ngay lập tức** một cảnh báo (CRITICAL alert) sẽ được gửi đến kênh cảnh báo chính (Mandate 11 primary SNS topic) qua email/Slack.
  3. Cảnh báo nêu rõ: **Ai** (actor) đã tắt, **vào lúc mấy giờ** (timestamp), và **từ IP nào**.
  4. Lambda **Heartbeat** chạy mỗi 5 phút sẽ phát hiện cấu hình CloudTrail sai lệch (không còn ghi log) và gửi cảnh báo liên tục thông qua CloudWatch Alarm.

### Kịch bản 1.2: Xoá rule cảnh báo (EventBridge) hoặc cập nhật Lambda Router
- **Bước thực hiện:** Mentor thử tắt hệ thống cảnh báo trước khi tắt camera bằng lệnh:
  ```bash
  aws events disable-rule --name g1-audit --region ap-southeast-1
  ```
  hoặc thử đổi code của Lambda router (`aws lambda update-function-code ...`).
- **Kết quả mong đợi (PASS khi):**
  1. Các hành động tác động vào "Audit Plane" (nhóm 7) này không bị automation allowlist bỏ qua dù được thực hiện bởi CI/CD role.
  2. Một alert CRITICAL được bắn ra ngay lập tức qua SNS với target rõ ràng.

---

## 2. Bài test 2: Đòn "Làm hụt" (Trốn góc khuất camera)

**Mục đích:** Kẻ tấn công cố tình không đụng vào cấu hình hệ thống (Management Events), mà thay vào đó là **đọc trộm dữ liệu nhạy cảm** (Data Events) như file state của Terraform từ S3. 

### Kịch bản 2.1: Đọc file Terraform state
- **Bước thực hiện:** Mentor dùng bất kỳ tài khoản nào có quyền đọc, tải một file canary từ S3 bucket đang được giám sát (ví dụ: Terraform state bucket):
  ```bash
  aws s3 cp s3://techx-tf3-197826770971-tfstate/m12-canary/m12-canary-<timestamp>.txt ./
  ```
- **Kết quả mong đợi (PASS khi):**
  1. Hành động tải file thành công (nếu tài khoản có quyền).
  2. Dùng AWS Athena hoặc CloudTrail Event history tra cứu sẽ thấy một dòng log sự kiện `GetObject` (Data Event) chỉ rõ: **Actor nào** tải file, **bucket nào**, **key nào**, và **thời gian/IP** tải file.
  3. Không có lỗ hổng "không thấy gì cả" khi đọc file nhạy cảm.

---

## 3. Bài test 3: Đòn "Làm mỏng / Sửa lén" (Xoá băng/Sửa log)

**Mục đích:** Kẻ tấn công đã bị ghi hình nhưng muốn quay lại xoá dấu vết hoặc chỉnh sửa file log.

### Kịch bản 3.1: Xóa file log từ S3 Archive
- **Bước thực hiện:** Mentor thử xoá một file log cũ trong bucket S3 lưu trữ của CloudTrail bằng cách sử dụng flag đặc quyền:
  ```bash
  aws s3api delete-object \
      --bucket <trail-logs-bucket> \
      --key <log-file-key> \
      --bypass-governance-retention
  ```
- **Kết quả mong đợi (PASS khi):**
  1. Lệnh trả về lỗi `AccessDenied` do file đang bị khoá bởi chế độ **Object Lock COMPLIANCE** (thay vì GOVERNANCE).
  2. Ngay cả Root User của tài khoản AWS cũng không thể vượt qua COMPLIANCE mode trước khi thời hạn 14 ngày kết thúc. Log được bảo toàn 100% (WORM - Write Once, Read Many).

### Kịch bản 3.2: Chứng minh tính toàn vẹn của chuỗi log (Cryptographic Validation)
- **Bước thực hiện:** Mentor yêu cầu chứng minh rằng không có bất kỳ file log nào bị thay đổi nội dung (sửa lén).
- **Lệnh thực thi:**
  ```bash
  aws cloudtrail validate-logs \
      --trail-arn <trail-arn> \
      --start-time 2026-07-21T00:00:00Z \
      --region ap-southeast-1
  ```
- **Kết quả mong đợi (PASS khi):**
  1. Lệnh chạy và phân tích các Digest files (được ký bằng private key của AWS).
  2. Kết quả trả về cho tất cả các file log đều là `Valid`.
  3. Không có file nào báo trạng thái `INVALID` hoặc bị đứt gãy chuỗi digest.

---

## 4. Bài test 4: Bài test "Phòng bảo vệ được bảo vệ" (Heartbeat & Alarm)

**Mục đích:** Chứng minh rằng nếu hệ thống Heartbeat bị vô hiệu hóa, sẽ có báo động dự phòng để chống lại đòn làm mù 3 lớp.

### Kịch bản 4.1: Làm hỏng Heartbeat
- **Bước thực hiện:** Cố tình xóa hoặc sửa đổi cấu hình quyền (IAM Role) của Heartbeat Lambda để hàm không thể publish message, hoặc vô hiệu hoá EventBridge rule kích hoạt Heartbeat.
- **Kết quả mong đợi (PASS khi):**
  1. Hai CloudWatch Alarm giám sát lịch chạy (Invocation) và Lỗi (Errors) của Heartbeat sẽ không nhận được dữ liệu (hoặc báo Error).
  2. CloudWatch Alarm chuyển trạng thái sang `ALARM`.
  3. Alarm tự động kích hoạt và gửi email cảnh báo thông qua kênh Mandate 11 primary SNS topic, thông báo rõ việc Heartbeat đã chết mà không có điểm chết duy nhất nào.

---
**Tổng kết:** Test plan này được thiết kế để Mentor tự tay thao tác với tư cách kẻ tấn công thực sự. Bất cứ hành động phá hoại nào lọt qua các kịch bản trên mà không có bằng chứng lưu lại hoặc cảnh báo tức thời đều bị coi là hệ thống có lỗ hổng.
