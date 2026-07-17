# Report M05 - Runtime hardening

Cap nhat: 2026-07-14
Pham vi: theo doi Directive #5; CDO02 chi ghi nhan tac dong Reliability/Cost neu co.

## 1. Ket luan nhanh

Directive #5 chua duoc assess bang evidence trong Task. Chua thay bang chung workload compliance, admission policy audit/enforce, rejection test, hoac ADR ky ten. Phan nay kha nang CDO01/Security lam chinh; CDO02 can theo doi nguy co hardening lam anh huong stateful/observability/revenue path.

## 2. BTC yeu cau gi

- Khong container chay root.
- Khong dung image tag troi nhu `latest`.
- Moi workload co resource request/limit.
- Admission policy tu choi manifest vi pham khi apply.
- Co ADR ve audit/enforce va cach cat chuyen khong pha SLO.

## 3. Trang thai evidence

| Evidence can co | Trang thai | Ghi chu |
| --- | --- | --- |
| Workload compliance report | MISSING | Chua co trong Task. |
| Admission policy list | MISSING | Chua co. |
| Audit/enforce status | MISSING | Chua co. |
| Reject test manifest/result | MISSING | Chua co. |
| ADR ky ten | MISSING | Chua co. |
| SLO impact sau enforce | MISSING | Chua co. |

## 4. Rui ro CDO02 can canh

| Rui ro | Anh huong |
| --- | --- |
| Enforce qua som | Co the chan nham workload dang chay. |
| SecurityContext lam service khong ghi duoc filesystem | Pod restart/readiness fail. |
| Resource limit qua thap | OOMKilled hoac CPU throttle, anh huong SLO. |
| Policy chan observability/stateful | Mat dashboard/trace/log hoac datastore loi. |

## 5. Read-only check can lam khi co runtime access

- Doc workload securityContext/resource/image tag.
- Doc policy resource va admission controller status.
- Doc event bi reject neu da co test.

Khong duoc lam:

- Khong apply manifest vi pham.
- Khong enforce policy.
- Khong sua securityContext/resource.
- Khong apply ADR/policy.

## 6. Next report update

Cap nhat khi CDO01/Security cung cap compliance report, policy status, rejection result hoac ADR.
