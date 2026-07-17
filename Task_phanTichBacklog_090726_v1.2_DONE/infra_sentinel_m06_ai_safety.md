# Report M06 - AI trust and safety

Cap nhat: 2026-07-14
Pham vi: theo doi Directive #6; CDO02 chi ghi nhan dependency Reliability/observability/cost neu co.

## 1. Ket luan nhanh

Directive #6 chua duoc assess bang evidence trong Task. Chua thay thong tin model that, fallback, guardrail, eval result, mentor test case hoac ADR. Phan nay co ve thuoc nhom AIO chinh; CDO02 lien quan o fallback, p95, logging/observability va cost/token.

## 2. BTC yeu cau gi

- Dung LLM that, khong mock.
- Co fallback khi model loi/cham.
- Output bam review nguon, khong bia.
- Chan prompt injection, loc PII, khong lo system prompt.
- Eval tai tao duoc tu script/du lieu commit.
- Mentor co the tu thu injection va cau hoi khong co thong tin.

## 3. Trang thai evidence

| Evidence can co | Trang thai | Ghi chu |
| --- | --- | --- |
| Model dang dung | MISSING | Chua thay trong Task. |
| Fallback design/result | MISSING | Chua co. |
| Eval hallucination/faithfulness | MISSING | Chua co. |
| Eval prompt injection/PII | MISSING | Chua co. |
| Mentor test cases | MISSING | Chua co. |
| ADR ky ten | MISSING | Chua co. |
| p95/cost impact | MISSING | Chua co. |

## 4. CDO02 can quan tam gi

| Dependency | Ly do |
| --- | --- |
| Fallback khi model cham/loi | Tranh treo trang product, giu Reliability. |
| p95 latency | Guardrail/eval khong duoc lam vo SLO. |
| Observability/log | Can log AI/tool call de audit va debug. |
| Cost/token | Khong dung model qua dat neu khong can. |

## 5. Read-only check can lam khi co evidence

- Doc eval report/result neu da xuat ra file.
- Doc dashboard latency/error/cost neu co export.
- Doc ADR va mentor test result.

Khong duoc lam:

- Khong sua prompt/model config/secret.
- Khong chay test gay thay doi du lieu.
- Khong call model that neu co chi phi khi chua duoc yeu cau.

## 6. Next report update

Cap nhat khi nhom AIO cung cap model/fallback/eval/ADR hoac evidence mentor test.
