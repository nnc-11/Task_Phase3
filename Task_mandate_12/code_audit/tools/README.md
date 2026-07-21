# Evidence tools

`Export-M12CloudTrailEvidence.ps1` chỉ đọc bản sao local `.json`/`.json.gz`, lọc `EventName` và optional resource text, rồi xuất evidence redacted. Script không gọi AWS và không sửa archive.

- `Access` (mặc định): xuất metadata identity/session/action/resource/UTC/request ID cho `GetObject`, `GetSecretValue` và các access event.
- `ConfigChange`: ngoài metadata, chỉ giữ các trường cấu hình nằm trong allowlist để nối saved plan với post-state cho T10. Không xuất secret/token/body/payload/policy document hoặc object content.

Ví dụ:

```powershell
.\Export-M12CloudTrailEvidence.ps1 `
  -LogFile .\cloudtrail-log.json.gz `
  -EventName GetObject `
  -ResourceContains "bucket/prefix/" `
  -OutputPath .\M12-T03-redacted.json
```

Hash cả log copy và output. Không coi output này là integrity proof; phải kèm `aws cloudtrail validate-logs` trên cùng UTC window.

Ví dụ T10:

```powershell
.\Export-M12CloudTrailEvidence.ps1 `
  -LogFile .\cloudtrail-config-change.json.gz `
  -EventName PutMetricAlarm,PutRule `
  -EvidenceProfile ConfigChange `
  -OutputPath .\M12-T10-config-change.json
```

Nếu output `ConfigChange` không có `changeParameters`, event đó không đủ chứng minh nội dung thay đổi; chọn đúng log file/event trong approved change window. Luôn lưu SHA-256 của raw copy và redacted output.

---

**Phiên bản:** v2.1
**Cập nhật:** 21/07/2026
**Trạng thái:** LOCAL-ONLY TOOL
