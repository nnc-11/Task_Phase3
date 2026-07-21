# Mandate 12 — Runbook v2

## Phase 0 — Read-only discovery

Xác nhận live M11 trail/status/selectors/bucket lock/lifecycle/rules/Lambda/SNS, EKS logs, S3/secrets và IAM ownership. Không đọc secret value hoặc object production.

Kết quả discovery ngày 21/07/2026:

- đúng account `197826770971`, caller `cdo-2-admin-team`;
- trail M11 đang logging/validation healthy nhưng chưa có S3 data events;
- archive còn Governance 14/lifecycle 30;
- 6 rules và 2 routers tồn tại/enabled;
- EKS audit enabled, retention 90 ngày;
- 8 buckets và 5 secrets đã inventory metadata;
- primary SNS còn 3 pending, global còn 1;
- current user chưa MFA; apply role còn AdministratorAccess và không boundary;
- AdministratorAccess còn qua 1 group, 3 IAM users trực tiếp và apply role; `gitlab-ci-deployer` có 2 active keys/no MFA và nằm trong router allowlist;
- AWS Config chưa có recorder; không phải dependency của foundation M12 hiện chọn.

NO-GO khi M11 chưa rõ owner/state, live drift chưa giải thích, S3 selector chưa ký hoặc caller sai account `197826770971`.

Phase 0 chỉ được coi là complete về kỹ thuật. Các blocker owner/S3 classification/SNS/MFA vẫn phải đóng trước plan/apply.

## Phase 1 — Upgrade M11 audit foundation

Thực hiện theo [HD_audit_foundation-v2.2.md](code_audit/HD_audit_foundation-v2.2.md):

- sửa module M11 và production inputs;
- giữ nguyên trail/bucket/topic names;
- add S3 data selectors;
- Compliance 365/lifecycle 400 cho log mới;
- sửa router critical suppression;
- thêm regional group 7, global group 8, heartbeat exact-configuration checks và SNS fallback cùng region cho alarm.

Trước plan phải mở change ID và ghi Git SHA, identity, UTC window, action dự kiến. Sau khi tạo saved plan, bổ sung plan hash vào change ID. Critical group `1/2/3/4/7/8` vẫn alert trong approved change; không mute hoặc suppress.

Plan được phép update/add audit resources M11/M12. Không được có delete/replace trail hoặc bucket; không update EKS/network/datastore/workload.

## Phase 2 — Cutover gate

Ghi UTC cutover khi apply pass. Xác nhận:

- trail ARN/bucket không đổi;
- `IsLogging=true`, selectors mới đúng;
- object giao sau cutover có Compliance retain-until >=365 ngày;
- digest healthy và `validate-logs` pass;
- heartbeat `PASS`; toàn bộ recipient bắt buộc trên primary, global và heartbeat-fallback SNS ở trạng thái `Confirmed`;
- hai heartbeat alarm có chính xác primary + fallback cùng region trong `AlarmActions`; heartbeat Lambda có quyền và đã test publish độc lập primary/global;
- M11 alerts vẫn hoạt động.

Chỉ từ thời điểm này mới bắt đầu coverage M12.

## Phase 3 — Coverage tests

Canary secret + canary S3 object trong approved prefix; lấy parsed archive evidence và digest validation. Cleanup sau khi hash/review.

## Phase 4 — IAM hardening

Thực hiện riêng theo [HD_iam_hardening-v2.1.md](code_audit/HD_iam_hardening-v2.1.md). Thay đổi từng identity tại đúng owning root; không gộp với audit foundation PR.

## Phase 5 — Mentor tests

Chạy [m12-tests-v2.2.md](m12-tests-v2.2.md). Mutation chỉ bằng bounded test identity. Nếu action đáng lẽ deny nhưng thành công: dừng, preserve evidence, mở Critical incident.

## Rollback

- Không stop/delete trail hoặc xóa archive.
- Nếu selector/router/heartbeat lỗi: fix-forward trong production root.
- Không thể rút ngắn Compliance retention đã áp dụng.
- IAM rollback riêng theo identity/root sở hữu.

## Definition of Done

Coverage, integrity, retention, heartbeat, ba đường SNS, alerts, IAM deny tests và thin-log forensic diff pass; cutover timestamp rõ; root residual risk được ký; product không bị ảnh hưởng. Cost approval phải tính lifecycle 400 ngày trên cả object hiện có chưa bị xóa; storage tiering để change tùy chọn sau khi có cost model.

---

**Phiên bản:** v2.2
**Cập nhật:** 21/07/2026
**Trạng thái:** HANDOFF READY / NOT APPROVED FOR APPLY
