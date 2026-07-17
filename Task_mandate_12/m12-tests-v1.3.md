# Mandate 12 — Kịch bản tấn công và bằng chứng

> **Trạng thái:** READY FOR PREPARATION · thiết kế cho single-account hardened audit; chưa chạy test.

## 1. Quy tắc an toàn

- Chỉ test sau approval, trong UTC window và có observer.
- Dùng canary object/secret, không dùng dữ liệu production.
- Không thử sửa/xóa object Compliance thật.
- Không chạy `StopLogging` nếu operator chưa được xác nhận bounded; dùng IAM simulation trước.
- Nếu lệnh tắt trail thành công ngoài dự kiến: dừng toàn bộ test và mở Critical incident.
- Không bật CLI debug hoặc lưu `SecretString`.
- Tester, operator và audit-admin là IAM identities trong cùng account Free Tier; không kiểm thử Organizations/SCP/cross-account.

## 2. Trạng thái

| Trạng thái | Ý nghĩa |
|---|---|
| `DESIGNED` | Test được thiết kế |
| `DEPLOYED` | Control đã apply nhưng chưa mentor test |
| `VERIFIED` | Test pass và có evidence |
| `FAILED` | Control/evidence không đạt |
| `BLOCKED` | Thiếu prerequisite, không được coi là pass |

## 3. Ma trận test tối thiểu

| ID | Đòn thử | Kỳ vọng |
|---|---|---|
| M12-T01 | Operator gọi `StopLogging` | Bị deny; attempt có event + alert; trail vẫn ghi |
| M12-T02 | Operator gọi `DeleteTrail`/đổi selector | Bị deny; config không đổi; có event + alert |
| M12-T03 | Đọc S3 canary object | Có `GetObject` data event |
| M12-T04 | Đọc canary secret | Có `GetSecretValue`; evidence không chứa secret value |
| M12-T05 | Xác minh integrity | `validate-logs` không missing/`INVALID` |
| M12-T06 | Thử xóa/ghi đè log | Production dùng deny evidence; không tamper object thật |
| M12-T07 | Forensic identity chain | Dựng actor/session/action/change trong timebox |

## 4. M12-T01 — StopLogging

### Tiền điều kiện

- Trail `IsLogging=true`.
- Operator role đã gắn và kiểm tra permissions boundary.
- EventBridge/SNS alert healthy.
- Audit-admin và observer sẵn sàng.

### Kỳ vọng

- `AccessDenied`.
- CloudTrail/EventBridge có `StopLogging` attempt, actor, time và error.
- Security owner nhận alert.
- Trail vẫn `IsLogging=true`, không có delivery gap.

### Fail

- Lệnh thành công.
- Không có alert/event.
- Trail ngừng ghi hoặc digest chain có gap.

## 5. M12-T02 — Xóa trail hoặc đổi coverage

Kiểm tra `DeleteTrail`, `UpdateTrail`, `PutEventSelectors` bằng bounded operator. Với mutation có thể thành công, dùng policy simulation thay vì gửi request production.

**PASS:** deny, attempt event/alert và cấu hình sau test không đổi.

## 6. M12-T03 — Đọc S3 object

### Fixture

- Object canary không nhạy cảm.
- Nằm đúng bucket/prefix trong advanced selector.

### Evidence

- `eventSource=s3.amazonaws.com`.
- `eventName=GetObject`.
- Đúng principal/session, bucket/key, UTC time và request ID.

**FAIL:** chỉ thấy bucket management event hoặc không có object data event.

## 7. M12-T04 — Đọc secret

### Fixture

- Canary secret vô giá trị, không được application sử dụng.
- Tester chỉ được đọc canary secret.

### Evidence

- `eventSource=secretsmanager.amazonaws.com`.
- `eventName=GetSecretValue`.
- Đúng principal/session, secret identifier, time và outcome.
- Không có `SecretString`/`SecretBinary` trong evidence.

## 8. M12-T05 — Integrity validation

Chờ digest bao phủ test window, sau đó chạy `validate-logs` theo trail ARN, region và UTC range.

**PASS:** không có missing digest/log hoặc `INVALID`.

**FAIL:** validation gap, signature/hash failure hoặc team chỉ chứng minh file tồn tại.

## 9. M12-T06 — WORM protection

- Không tamper log thật.
- Dùng authorization/deny evidence để chứng minh operator không thể delete/overwrite.
- Hiển thị Object Lock `COMPLIANCE`, retain-until và versioning.
- Nếu cần minh họa tamper detection, dùng fixture sandbox riêng.

## 10. M12-T07 — Forensic identity chain

Mentor thực hiện một action canary qua assumed role hoặc EKS. Team phải dựng:

```text
IAM identity
→ STS assumed-role session
→ AWS/EKS username
→ action/verb/resource
→ Git/Argo CD change nếu liên quan
→ UTC timeline
```

**FAIL:** chỉ biết role dùng chung, không truy về người/session hoặc không xác định được nội dung thay đổi.

## 11. Test bổ sung sau MVP

- Vô hiệu hóa EventBridge/SNS trong sandbox.
- Burst `GetObject` có giới hạn để kiểm tra exfiltration detection.
- Low-and-slow reads để kiểm tra hunting dài ngày.
- Resource mới ngoài selector để kiểm tra coverage drift.
- Boundary/policy tamper attempts.
- Root/break-glass tabletop exercise; không dùng root để test live thông thường.

## 12. Evidence pack

```text
M12-Txx/
├── metadata.md
├── request-redacted.txt
├── result-redacted.txt
├── cloudtrail-event-redacted.json
├── alert-redacted.txt
├── trail-health.json
├── integrity-result.txt
└── verdict.md
```

Metadata ghi UTC window, account, region, principal/session, target resource, approver, observer và SHA-256 của evidence files sau redaction.

## 13. Verdict table

| Test | UTC window | Principal | Event found | Alert | Integrity | Verdict |
|---|---|---|---|---|---|---|
| M12-T01 | | | | | | `DESIGNED` |
| M12-T02 | | | | | | `DESIGNED` |
| M12-T03 | | | | N/A | | `DESIGNED` |
| M12-T04 | | | | theo policy | | `DESIGNED` |
| M12-T05 | | | N/A | N/A | | `DESIGNED` |
| M12-T06 | | | | | | `DESIGNED` |
| M12-T07 | | | | N/A | | `DESIGNED` |

## 14. Điều kiện mentor sign-off

- Anti-audit attempt bị chặn hoặc alert đúng SLA.
- S3 object/secret reads có vết đầy đủ.
- Integrity chain pass.
- WORM retention pass.
- Identity/forensic attribution pass.
- Không ảnh hưởng storefront, private ops hoặc flagd.

## 15. Chuẩn bị test từ static review

Static review xác định được hai fixture bắt buộc: một secret chỉ đọc qua `Secrets Manager` (không đọc giá trị secret) và object tại bucket/prefix được owner phê duyệt. Không dùng Terraform state, manifest secret, EKS workload, storefront hoặc flagd làm fixture test.

Mọi test trong tài liệu này chỉ được chạy sau khi audit foundation đã deploy và delivery healthy. Trước đó, test matrix là checklist chuẩn bị evidence; không phải bằng chứng Mandate 12 đã đạt.

## 16. Fixture sau AWS CLI discovery

Discovery xác nhận có hai secret production (`sosflow/db-password`, `techx-corp-tf3/flagd-sync-token`) và 7 S3 bucket, nhưng không xác định được fixture an toàn cho mentor test. Vì vậy Phase 1 phải tạo **canary secret mới không có giá trị nghiệp vụ** và **canary S3 object mới, không nhạy cảm** trong prefix đã được owner duyệt. Không dùng Terraform state, secret hiện hữu, object production hoặc log archive thật làm fixture.

---

**Phiên bản:** v1.3  
**Cập nhật:** 17/07/2026  
**Trạng thái:** READY FOR PREPARATION — chưa được phép apply
