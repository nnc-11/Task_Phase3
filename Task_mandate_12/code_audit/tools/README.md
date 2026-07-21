# Evidence tools

`Export-M12CloudTrailEvidence.ps1` chỉ đọc bản sao local `.json`/`.json.gz`, lọc `EventName` và optional resource text, rồi xuất metadata redacted. Script không gọi AWS và không sửa archive.

Ví dụ:

```powershell
.\Export-M12CloudTrailEvidence.ps1 `
  -LogFile .\cloudtrail-log.json.gz `
  -EventName GetObject `
  -ResourceContains "bucket/prefix/" `
  -OutputPath .\M12-T03-redacted.json
```

Hash cả log copy và output. Không coi output này là integrity proof; phải kèm `aws cloudtrail validate-logs` trên cùng UTC window.

---

**Phiên bản:** v2.0
**Cập nhật:** 21/07/2026
**Trạng thái:** LOCAL-ONLY TOOL
