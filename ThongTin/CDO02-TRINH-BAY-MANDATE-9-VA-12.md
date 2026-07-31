# CDO-02 — Trình bày Mandate #9 & #12

> **Nhóm:** CDO-02 · **Trụ:** Reliability + Cost Optimization (Auditability là trụ chung)
> **Người làm:** Lê Văn Hải · **Ngày chốt:** 30/07/2026 · **Account:** `197826770971` (`ap-southeast-1`)
> **Điền theo khung** [`format-trinh-bay-mandate-va-incident.md`](format-trinh-bay-mandate-va-incident.md) — Phần 1.
> **Nguyên tắc:** mỗi khẳng định kèm bằng chứng chạy lại được (PR/ADR/lệnh). Phần chưa xong nói trước, không đợi hỏi.

**⚠️ Hai lưu ý trung thực đặt ngay đầu (theo PHẦN 0 của khung):**
1. **Đề bài gốc không còn trong cây làm việc** (`phase3 - information/mandates/` chỉ còn `README.md`). Mục "Yêu cầu
   gốc" dưới đây được **dựng lại từ ADR + report + solution đã ký**, **không phải trích nguyên văn** directive.
2. **Cả hai mandate đều CHƯA "xanh hoàn toàn":** #12 đóng theo diện **SKIP có mentor duyệt** (không claim PASS);
   #9 mới xong **code + unit test của một task (M9-01) trên nhánh feature, CHƯA merge `main`, CHƯA deploy, CHƯA
   có live chaos evidence**. Tiến độ tới đâu nói tới đấy.

| Mandate | Trụ | Trạng thái thật (30/07) | Một dòng |
|---|---|---|---|
| **#12** Audit anti-defeat | Auditability + Cost | ⚪ **SKIP có phê duyệt** | Lớp *phát hiện* đã live; lớp *ngăn chặn cứng bằng SCP* không triển khai vì rào cản $200–460 tiền thật |
| **#9** Zero-downtime ops trên managed store | Reliability | 🛠️ **Code+test 1 task, chưa deploy** | Nền read-path (stale-cache + startup-latch) đã code + test; các change-window còn lại mới ở mức thiết kế |

---

# MANDATE #12 — Audit không thể bị đánh bại (Anti-Defeat)

## 1. Một câu tóm tắt

> *Mandate #12 yêu cầu **ngay cả người có quyền administrator cũng không được âm thầm tắt log/alert hay xoá bằng
> chứng**. Chúng tôi đã **thiết kế đầy đủ + validate lớp ngăn chặn bằng AWS Organizations/SCP và giữ nguyên lớp
> phát hiện đang chạy**, nhưng **cố ý KHÔNG attach SCP** vì việc join org giữa tháng phát sinh **$200–460 tiền thật
> không thu hồi được** — đã trình bày và **được mentor đồng ý SKIP**.*

## 2. Yêu cầu gốc — (dựng lại từ ADR/report, không phải trích nguyên văn)

| Mục | Nội dung |
|---|---|
| Directive yêu cầu | Audit trail phải **chống bị đánh bại**: (1) không cửa sổ mù — admin TF không tắt được logging; (2) đóng coverage gap (đọc S3/secret phải để lại vết); (3) toàn vẹn mật mã (log không sửa lén được); (4) giữ đủ lâu. Giải pháp lý tưởng cần **policy đứng trên quyền** trong workload account. |
| Phải nộp | ADR + báo cáo trạng thái; nếu triển khai: demo "3 đòn" (làm mù / làm hụt / làm mỏng log) bị chặn trước mentor |
| Hạn | Trong Phase 3 (kết thúc **31/07/2026**) |
| Trụ được nhìn | **Auditability** (+ Cost, vì rào cản là chi phí) |
| Người làm | CDO-02 (Lê Văn Hải) chủ trì |

> Nguồn dựng lại: ADR [`0011-mandate-12-audit-anti-defeat.md`](adr/0011-mandate-12-audit-anti-defeat.md) ·
> báo cáo [`mandate-12-report.md`](mandate-12-report.md) · kế hoạch [`mandate-12-org-scp-execution-plan.md`](mandate-12-org-scp-execution-plan.md).

## 3. TRƯỚC mandate — hệ thống thiếu gì (theo rủi ro)

| Hiện trạng trước | Rủi ro thật nếu để nguyên | Bằng chứng lúc đó |
|---|---|---|
| 4 IAM user + mentor đều `AdministratorAccess` | Bất kỳ admin nào (hoặc kẻ chiếm được key) đều có thể `StopLogging`/`DeleteTrail`/xoá bucket → **xoá dấu vết chính hành vi của mình** | Kiểm kê IAM (CLAUDE.md rủi ro mở) |
| Chỉ có **phát hiện** (M11), chưa có **ngăn chặn** | Admin tắt log xong mới bị "kêu" — kịp phá trước khi ai xử lý | Alert plane M11 chạy, nhưng không có lớp deny |
| Không có ranh giới quyền đứng trên workload account | Trong một account đơn, `AdministratorAccess` là trần cao nhất — không gì chặn được nó | `AWSOrganizationsNotInUseException` (account standalone) |

## 4. SAU mandate — hệ thống có thêm gì

| Khả năng mới | Cơ chế | Trạng thái | Bằng chứng |
|---|---|---|---|
| Hành vi kill-switch audit **kêu ngay** (StopLogging/DeleteTrail…) | CloudTrail + EventBridge rule `g1`–`g8` + Lambda router + SNS | **Đã live** (từ M11 + M12 v1) | PR **#403**; 8 rule + 2 router + 2 SNS đang chạy |
| Đọc S3 tfstate / secret **để lại vết** | CloudTrail **data events** (advanced selector) | **Đã live** | Trail `…-audit-detection-…-trail`, data events ON |
| Log **không sửa lén** được | S3 **Object Lock COMPLIANCE 14** + log file validation + 2 KMS CMK | **Đã live** | `get-object-lock-configuration`; validation ON |
| Thu hẹp quyền team audit | User `CDOAuditTeam`: `AdministratorAccess` → **`ReadOnlyAccess`** + inline `AssumeAuditMaintainerOnly` | **Đã áp trên account** (25/07) | `aws iam list-attached-user-policies --user-name CDOAuditTeam --profile prod` |
| **Ngăn chặn cứng** kill-switch (kể cả admin) | 2 SCP từ management account đứng **trên** `AdministratorAccess` | **❌ CHƯA attach** (thiết kế xong, validate xong) | SCP-1/SCP-2 JSON hợp lệ trong execution-plan |
| Break-glass role bảo trì R | `techx-corp-tf3-audit-maintainer` (chỉ role này sửa router/SNS, tự nó không sửa được) | **❌ CHƯA tạo** | `aws iam get-role techx-corp-tf3-audit-maintainer` → `NoSuchEntity` |

> ⚠️ **Cột trạng thái — chỗ dễ bị bắt lỗi nhất:** lớp *phát hiện* là **Đã live**; lớp *ngăn chặn* (SCP) là **Chưa
> attach**. Không viết "đã chống được admin" — mới chỉ "kêu ngay khi admin phá", chưa "chặn admin phá".

## 5. Cải thiện đo được

| Chỉ số | Trước | Sau | Cách đo | Ngày đo |
|---|---:|---:|---|---|
| Time-to-detect hành vi nguy hiểm | không có alert | **2–4 giây** | demo `CreateUser`/`AttachUserPolicy`/`GetSecretValue` → email thật (M11) | 23/07 |
| Quyền `CDOAuditTeam` | `AdministratorAccess` | **`ReadOnlyAccess`** | `list-attached-user-policies` | 25/07 |
| Volume audit đo được (làm nền cost) | — | **117.486** mgmt event/ngày | CloudTrail Lake / Cost Explorer | 24/07 |
| **Chi phí phần SKIP tránh được** | (nếu join org giữa tháng) **$200–460** | **$0** | Cost Explorer: run-rate $46–57/ngày × 8 ngày hở | 24/07 |

## 6. Vấn đề gặp phải và cách xử lý

| # | Vấn đề gặp | Phát hiện lúc nào / bằng cách nào | Cách tiếp cận (và hướng đã cân nhắc khác) | Kết quả |
|---|---|---|---|---|
| 1 | Join workload account vào Organization **giữa tháng** làm **credit ngừng phủ** phần usage từ ngày join đến cuối tháng → tiền thật trên thẻ | Đọc kỹ quy tắc billing AWS + đo Cost Explorer **trước khi** join (không phải sau khi mất tiền) | Lượng hoá rủi ro: run-rate $46–57/ngày × 8 ngày hở (24→31/07) = **$200–460**. Vì bài kết thúc 31/07, không thể "chờ join ngày 01/08 cho hở=0". Trình mentor → **xin SKIP** thay vì chi khoản không thu hồi | Mentor **đồng ý SKIP**; chi phí thực **$0** |
| 2 | Nếu vẫn muốn "chống đánh bại" trong 1 account, có nên dùng **organization-trail** thay SCP? | Khi so phương án trong execution-plan | Loại: organization-trail **+$71/tháng** và **vẫn không** cho ranh giới đứng-trên-admin thật (SCP mới làm được) → cost cao hơn mà không đạt cốt lõi | Chọn thiết kế SCP, **để lại dùng khi có org** |
| 3 | Bằng chứng SCP không thể demo (chưa attach) — làm sao chứng minh "đã làm thật"? | Tự soi trước khi trình | **Validate JSON tĩnh**: SCP-1 minify **1.436 ký tự / 4 statement / 30 action**; SCP-2 **2.701 ký tự / 9 statement / 43 action**; kèm ma trận kiểm chứng A/B/C/D + quy trình 3 đòn viết sẵn | Thiết kế **sẵn sàng attach**, tái dùng được |

## 7. Cách tiếp cận chung + đường lui

```
Audit hiện trạng (IAM, trail, org?)  →  Thiết kế SCP + validate JSON  →  ĐO CHI PHÍ  →  [Cổng quyết định: mentor]
                                                                          ↑ DỪNG Ở ĐÂY: rào cản $200–460 → SKIP
   (nếu tiếp)  Tạo account A + Org  →  B join  →  attach SCP ở audit-mode  →  verify 3 đòn  →  enforce
```

**Đường lui:** phần đã áp trên account **rất mỏng và an toàn** — không tạo org/SCP/role (cả ba đều chưa tồn tại),
chỉ đổi quyền 1 user. Cần dọn thì **1 lệnh**:
```bash
aws iam delete-user-policy --user-name CDOAuditTeam --policy-name AssumeAuditMaintainerOnly --profile prod
```

## 8. Đánh đổi: cố ý KHÔNG làm gì

| Việc đã cân nhắc | Vì sao không làm |
|---|---|
| Join org + attach SCP (phần cốt lõi mandate) | **$200–460 tiền thật** không thu hồi được, trước hạn 31/07 — giá trị < chi phí; mentor duyệt SKIP |
| Organization-trail thay SCP | **+$71/tháng** mà **không** đạt "đứng trên admin" — đắt hơn và không đúng cốt lõi |
| Tạo trước role R + attach SCP "để có cái demo" | SCP không có org thì vô nghĩa; tạo nửa vời làm bẩn account, khó audit |

## 9. Còn nợ

| Việc | Vì sao chưa xong | Ai làm | Bao giờ |
|---|---|---|---|
| Tạo Account A + bật Organization, B join | Rào cản credit giữa tháng | CDO-02 | Nếu chương trình gia hạn, join **đúng ngày 01** để hở = 0 |
| Attach SCP-1/SCP-2 + tạo role R + demo 3 đòn | Phụ thuộc bước join ở trên | CDO-02 | sau join |
| Quyết định dọn/giữ inline `AssumeAuditMaintainerOnly` (đang trỏ role không tồn tại — vô hại) | Chờ quyết có làm lại M12 không | CDO-02 | trước khi đóng sổ |

## 10. Kinh nghiệm rút ra

1. **Kỹ thuật:** "miễn phí" của AWS Organizations/SCP che một **quy tắc billing ẩn** (credit ngừng phủ khi join
   giữa tháng) — lần sau **đọc điều khoản billing của thao tác one-way trước khi bấm**, không chỉ đọc giá dịch vụ.
2. **Quy trình:** đo chi phí **trước** cổng quyết định giúp biến "không kịp/không dám" thành "SKIP có số, có phê
   duyệt" — trung thực và chấm được, thay vì im lặng bỏ.
3. **Phối hợp:** trình bày rõ *phát hiện đã có / ngăn chặn chưa có* ngay từ đầu tránh mentor hiểu nhầm "SKIP = trắng".

## 11. Câu hỏi có thể bị hỏi (chuẩn bị sẵn, có số)

- **"Cái này native hay cài thêm công cụ?"** → Native hoàn toàn: CloudTrail + EventBridge + SCP + Object Lock, **0
  công cụ bên thứ ba**.
- **"SKIP là bỏ trắng à?"** → Không. *Phát hiện* live (PR #403, TTD 2–4s, Object Lock COMPLIANCE 14). Chỉ *ngăn
  chặn SCP* bỏ, vì **$200–460** tiền thật, **mentor đã duyệt**.
- **"Vượt trần chi phí không?"** → Phần này **$0** phát sinh; khoản $200–460 là thứ **đã tránh** nhờ SKIP.
- **"Rollback thế nào?"** → Gần như không có gì để rollback (0 org/SCP/role). 1 lệnh dọn inline policy nếu cần.
- **"Ai chịu trách nhiệm nếu mai bị tắt log mà không ai biết?"** → Hiện lớp phát hiện M11/M12v1 vẫn **kêu trong
  2–4s** tới SNS; nhưng thành thật: **chưa chặn được** — đó chính là phần còn nợ #9.

---

# MANDATE #9 — Vận hành managed store zero-downtime dưới tải

## 1. Một câu tóm tắt

> *Mandate #9 yêu cầu **sau khi lên managed (RDS/MSK/ElastiCache), hệ thống vẫn phải chịu migration/nâng
> version/reboot/xoay credential/failover mà 0 request khách bị rớt**. Chúng tôi đã **thiết kế trọn bộ (solution
> v3.2) và code+test xong nền read-path chống-failover cho `product-catalog` (task M9-01)**, hiện **đang ở nhánh
> feature, chưa deploy, chưa có live chaos evidence**.*

## 2. Yêu cầu gốc — (dựng lại từ solution/ADR, không phải trích nguyên văn)

| Mục | Nội dung |
|---|---|
| Directive yêu cầu | Managed store rồi vẫn phải làm được **trong giờ có tải, 0 request rớt**: (1) online schema migration; (2) nâng **major version**; (3) đổi parameter **cần reboot**; (4) **xoay credential**; (5) chịu **blip/failover** của datastore |
| Phải nộp | Solution + demo/chaos chứng minh browse/checkout không rớt khi datastore failover/upgrade |
| Hạn | Trong Phase 3 (kết thúc 31/07/2026) |
| Trụ được nhìn | **Reliability** |
| Người làm | CDO-02 (Hải) chủ trì; reviewer Đông; hợp nhất ADR ở M9-11 (Mến) |

> Nguồn dựng lại: [`mandate-09-zero-downtime-ops-solution.md`](docx_cdo02/mandate-09-zero-downtime-ops-solution.md) ·
> [`mandate-09-m9-01-catalog-implementation-notes.md`](docx_cdo02/mandate-09-m9-01-catalog-implementation-notes.md).

## 3. TRƯỚC mandate — hệ thống thiếu gì (theo rủi ro)

| Hiện trạng trước | Rủi ro thật nếu để nguyên | Bằng chứng lúc đó |
|---|---|---|
| `product-catalog` **query DB mỗi request** | RDS failover/reboot (**60–120s**) → mọi browse lỗi trong suốt cửa sổ | `main.go` cũ: list/get/search gọi thẳng DB |
| Health goroutine **ping DB mỗi 5s → NOT_SERVING khi ping fail** (REL-02) | Đây là **lỗ hổng chết người của stale-cache**: DB down → K8s rút pod khỏi endpoints → **cache có đúng cũng không nhận traffic** | REL-02 health dependency-aware |
| `initDatabaseWithRetry` block startup + `os.Exit(1)` | Cold-start **trong lúc DB outage** = CrashLoopBackOff, càng làm nặng sự cố | REL-14 retry-then-exit cũ |

## 4. SAU mandate — hệ thống có thêm gì

| Khả năng mới | Cơ chế | Trạng thái | Bằng chứng |
|---|---|---|---|
| Read path (list/get/search) **không chạm DB** | `productSnapshot` bất biến, swap bằng `atomic.Pointer`, reader không khoá | **Code xong (nhánh), chưa deploy** | [`product-catalog/main.go` L243–333](<../phase3 - information/techx-corp-platform/src/product-catalog/main.go>) |
| DB down mà **browse vẫn phục vụ** (serve stale) | Refresh nền 30s; refresh lỗi → **giữ last-known-good**, không xoá cache | **Code xong, chưa live-verify** | notes §2.2; test `TestRefreshFailureKeepsLastKnownGood` |
| Pod **không rớt khỏi endpoint** khi DB down (chỉ degraded) | **Startup-latch**: `ready() = ever_primed && !shutdown && schema_valid` — **DB reachability KHÔNG** nằm trong readiness | **Code xong, chưa deploy** | `ready()` L298–300; test `TestReadinessStartupLatch` |
| Cold-start trong outage **không CrashLoop** | Decouple gRPC start khỏi DB init (lazy handle), prime nền | **Code xong** | notes §2.3 (thay REL-14 retry-then-exit) |
| Quan sát được "đang phục vụ trong outage" | 7 metric: `cache_primed`/`ever_primed`/`cache_age_seconds`/`served_stale_total`/`db_retry_*` | **Code xong; wiring alert bàn giao M9-00** | notes §2.4 |

> ⚠️ **Trạng thái đúng mức:** tất cả là **"đã code + đã test đơn vị"**, **KHÔNG** phải "đã có trên production".
> Commit `c8958ec` nằm trên nhánh `feat/m9-01-catalog-stale-cache-readiness-startup-latch-go` — **chưa merge
> `main`, chưa build image, chưa ArgoCD sync** (kiểm chứng: `git merge-base --is-ancestor c8958ec origin/main` → sai).

## 5. Cải thiện đo được → thay bằng tình huống trước/sau (chưa có số live)

Mandate này **chưa tạo số runtime** vì chưa deploy — theo khung, thay bảng số bằng **tình huống**:

> **Trước:** RDS failover 60–120s → `product-catalog` ping DB fail → K8s rút pod khỏi endpoint → **toàn bộ browse
> lỗi** suốt cửa sổ failover, kể cả khi dữ liệu sản phẩm không đổi.
> **Sau (theo thiết kế, đã chứng minh bằng unit test, CHƯA chứng minh live):** DB down chỉ là *degraded-signal* —
> pod vẫn Ready, browse đọc **snapshot stale** trong bộ nhớ, `served_stale_total` tăng, `ever_primed` giữ `1`;
> khi DB về, refresh kế tiếp swap snapshot mới.

**Số duy nhất verify được ngay bây giờ (không cần deploy):**

| Chỉ số | Giá trị | Cách đo (chạy lại được) |
|---|---:|---|
| Số hàm test | **18** | `grep -c '^func Test' "phase3 - information/techx-corp-platform/src/product-catalog/main_test.go"` |
| `go test -race` | **PASS** (theo notes §4, `golang:1.26.5`) | *chưa tự chạy được ở máy này (không có Go) — cần chạy lại live khi demo* |
| Budget retry blip | **700ms** (4 lần: 100/200/400ms) | test `TestRetryBudgetIs700ms`; hằng số `retryBackoffs` trong `main.go` |

> **Ghi chú số thật thà:** implementation notes §4 ghi **"19 test"** (tính thêm 1 subtest `t.Run`); đếm hàm `func
> Test` bằng grep ra **18**. Khi demo nói **18 hàm test / 19 test-case** cho khớp cả hai cách đếm.

## 6. Vấn đề gặp phải và cách xử lý

| # | Vấn đề gặp | Phát hiện lúc nào / bằng cách nào | Cách tiếp cận (và hướng cân nhắc khác) | Kết quả |
|---|---|---|---|---|
| 1 | Stale-cache **vô nghĩa** nếu readiness vẫn ping DB: DB down → pod bị rút khỏi endpoint → cache đúng cũng không ai đọc được | Khi thiết kế, đối chiếu với REL-02 đã có | **Tiến hoá REL-02, không gỡ nó**: tách "cái gì *drive* gRPC health `""`" — dùng **latch** thay vì DB ping; DB reachability hạ xuống *degraded-signal*. Ép `""`=NOT_SERVING **trước** `srv.Serve()` để đóng race health-server | Readiness phản ánh **cache**, không phản ánh DB → serve stale khi outage |
| 2 | Sau RDS failover, connection cũ **ghim vào endpoint RDS cũ** → refresh treo trên TCP chết | Thiết kế theo failure-mode (không phải sau khi sập) | `ConnMaxLifetime` **5m → 60s** (recycle conn); mỗi attempt bounded `dbAttemptTimeout=2s` để retry **xoay vòng** thay vì treo | Cửa sổ refresh có thể trúng conn chết bị thu hẹp |
| 3 | Dockerfile build **single-file** (`go build main.go`) → tách file production ra sẽ **vỡ image build** | Khi cấu trúc code | **Toàn bộ code production trong 1 `main.go`**; test để riêng `main_test.go` (không vào image). Không đổi probe/`values.schema.json` → 0 churn Helm | Image build nguyên vẹn; 0 rủi ro schema ArgoCD |
| 4 | Không được đụng đường đọc flagd (`checkProductFailure` cho `OLJCESPC7Z`) — luật cấm | Rà guardrail trước khi sửa | Giữ **nguyên** `checkProductFailure`, chạy **trước** cache lookup trong `GetProduct` | Không vi phạm luật; fault-injection vẫn hoạt động |

**Ảnh hưởng production:** **0** — chưa deploy nên chưa gây sự cố nào. Đó vừa là điểm an toàn, vừa là điểm còn nợ
(chưa có bằng chứng live).

## 7. Cách tiếp cận chung + đường lui

```
Audit read path + REL-02  →  Thiết kế cache+latch  →  Unit test + go test -race  →  [ĐÃ TỚI ĐÂY]
   (tiếp)  build image (CI)  →  update values-prod imageOverride  →  ArgoCD sync (2/2 Ready, ever_primed=1)
        →  chạy chaos runbook (RDS reboot/failover, browse 200 stale, 0 fail)  →  lấy evidence
```

**Đường lui:** M9-01 là thay đổi **cộng thêm** (chỉ đổi *cái gì drive* readiness + bỏ query DB trên read path),
**không** thêm field values, **không** đổi probe trong `values-prod.yaml`. Khi deploy: mọi thứ qua GitOps → **revert
= 1 PR**; và vì hiện **chưa deploy**, rủi ro production đang là **0**.

## 8. Đánh đổi: cố ý KHÔNG làm gì

| Việc đã cân nhắc | Vì sao không làm |
|---|---|
| Cache theo **từng search query** | Phức tạp + rủi ro sai lệch; snapshot in-memory đã đủ, **giữ nguyên semantics SQL** (LIKE name/desc, order id) |
| Đổi liveness sang gRPC "liveness service" | `tcpSocket` đơn giản hơn, độc lập hẳn DB/cache — đủ thoả "process alive", ít rủi ro |
| **Tự deploy M9-01 luôn cho có số** | Deploy là scope **M9-00/integration**, cần image build + chaos rehearsal có kiểm soát; tự deploy vội = rủi ro không cần thiết. Nói thẳng "chưa deploy" đúng hơn |
| Gỡ REL-02 để "đơn giản hoá" | REL-02 vẫn đúng cho service khác; ta **tiến hoá**, không phá — tránh regression |

## 9. Còn nợ

| Việc | Vì sao chưa xong | Ai làm | Bao giờ |
|---|---|---|---|
| Merge `main` + build image + update `values-prod` imageOverride | M9-01 chỉ làm code+test; deploy là bước sau, cần CI digest | CDO-02 + M9-00 (Đông) | bước kế tiếp |
| **Live chaos 60–120s** (RDS reboot/failover, browse 200 stale, 0 fail; cold-start không vào endpoint) | Cần image live mới đo được | CDO-02 | integration/rehearsal |
| Change-window còn lại: **schema migration (expand/contract), major version upgrade (MSK/RDS), reboot parameter, xoay credential (alternating-user)** | Mới ở mức **thiết kế** trong solution v3.2, chưa thực thi | CDO-02 | phần sau của Mandate #9 |
| Wiring alert **max-staleness 15′** | Bàn giao M9-00 khi image live | Đông | khi image live |

## 10. Kinh nghiệm rút ra

1. **Kỹ thuật:** "managed HA" (RDS Multi-AZ) **không** tự cho zero-downtime — application vẫn phải có stale-cache +
   readiness **không phụ thuộc DB ping**; nếu readiness còn ping DB thì Multi-AZ failover vẫn làm rớt browse.
2. **Quy trình:** tách rõ **"code+test xong"** với **"deployed + live-verified"** — dán nhãn đúng ngay từ nhánh
   feature tránh báo cáo lố; số nào tự chạy được (18 test) tách khỏi số cần deploy (chaos browse 0 fail).
3. **Phối hợp:** giữ REL-02 và chỉ *tiến hoá* nó (không gỡ) giúp không đạp lên việc reviewer/nhóm khác đã làm; ranh
   giới task rõ (M9-01 code / M9-00 deploy+alert / M9-11 ADR) giảm giẫm chân.

## 11. Câu hỏi có thể bị hỏi (chuẩn bị sẵn, có số)

- **"Đã test chưa hay chỉ code rồi tin?"** → **18 hàm test** (`grep -c '^func Test'`), `go test -race` PASS theo
  notes; **thành thật: chưa có live chaos** — mới unit test.
- **"Đã vào Git chưa hay apply tay?"** → Vào Git (commit `c8958ec`), nhưng **trên nhánh feature, chưa merge `main`,
  chưa deploy** — kiểm chứng bằng `git merge-base --is-ancestor c8958ec origin/main`.
- **"Có chạy được khi mất 1 AZ / khi DB failover không?"** → Theo thiết kế + unit test **có** (serve stale, pod vẫn
  Ready); **live chưa chứng minh** — đó là việc còn nợ đầu tiên.
- **"Con số này p50 hay p99?"** → Chưa claim số latency runtime nào (chưa deploy). Số duy nhất là **18 test** và
  **budget retry 700ms** — cả hai chạy lại được từ source.
- **"Native hay cài thêm?"** → Thuần Go stdlib (`atomic.Pointer`, `database/sql`) + gRPC health check **native** của
  K8s readiness; **0 thư viện cache bên thứ ba**.
- **"Nếu deploy hỏng thì sao?"** → Cộng thêm, không đổi values schema/probe → **revert 1 PR** qua GitOps; hiện chưa
  deploy nên rủi ro production = 0.

---

## Phụ lục — Chỉ mục bằng chứng (đã kiểm chứng tồn tại 30/07)

| Mandate | Loại | Đường dẫn / lệnh |
|---|---|---|
| #12 | Báo cáo (ký) | [`mandate-12-report.md`](mandate-12-report.md) |
| #12 | Kế hoạch Org/SCP | [`mandate-12-org-scp-execution-plan.md`](mandate-12-org-scp-execution-plan.md) |
| #12 | ADR | [`adr/0011-mandate-12-audit-anti-defeat.md`](adr/0011-mandate-12-audit-anti-defeat.md) |
| #12 | CI boundary | [`infra/bootstrap/github-oidc/ci-audit-boundary.tf`](../infra/bootstrap/github-oidc/ci-audit-boundary.tf) |
| #12 | commit | [`bb11e1c`](https://github.com/tuu-ngo/Phase3-TF3-Infra-Sentinel/commit/bb11e1c) · detection live PR #403 |
| #12 | Verify | `aws iam get-role techx-corp-tf3-audit-maintainer --profile prod` → `NoSuchEntity` (SCP chưa triển khai) |
| #9 | Solution | [`docx_cdo02/mandate-09-zero-downtime-ops-solution.md`](docx_cdo02/mandate-09-zero-downtime-ops-solution.md) |
| #9 | Implementation notes | [`docx_cdo02/mandate-09-m9-01-catalog-implementation-notes.md`](docx_cdo02/mandate-09-m9-01-catalog-implementation-notes.md) |
| #9 | Chaos runbook | [`runbooks/mandate-09-m9-01-catalog-cache-chaos.md`](runbooks/mandate-09-m9-01-catalog-cache-chaos.md) |
| #9 | Code | [`product-catalog/main.go`](<../phase3 - information/techx-corp-platform/src/product-catalog/main.go>) · [`main_test.go`](<../phase3 - information/techx-corp-platform/src/product-catalog/main_test.go>) |
| #9 | commit (nhánh, **chưa vào main**) | `c8958ec` trên `feat/m9-01-catalog-stale-cache-readiness-startup-latch-go` |

*Điền theo khung `format-trinh-bay-mandate-va-incident.md`. Mọi trạng thái phản ánh đúng hiện trạng 30/07/2026; phần
chưa deploy / chưa attach được ghi rõ, không tô xanh quá mức.*
