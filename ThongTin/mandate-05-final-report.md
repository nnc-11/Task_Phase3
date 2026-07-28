# Mandate 5 — Báo cáo tổng hợp cuối cùng (dành cho cả CDO01 và CDO02)

**Ngày viết:** 18/07/2026 (mandate deadline gốc: 17/07/2026)
**Mục đích file này:** để bất kỳ ai ở TF3 — không chỉ người trực tiếp làm — đọc là hiểu ngay: mandate yêu cầu gì, team đã làm gì để đáp ứng, làm ở đâu trong code, và tự tay chạy lệnh nào để verify lại bất cứ lúc nào (không cần hỏi lại người đã làm).

**Nguồn:** mandate gốc
`/Users/tan/Desktop/notes-for-phase3/xbrain-learners/phase3/mandates/MANDATE-05-runtime-hardening.md`,
đối chiếu Jira (PM-92, PM-101, PM-104, PM-110-114), và verify trực tiếp trên cluster sống
`techx-corp-tf3` (account `197826770971`).

---

## Tóm tắt trạng thái

| Yêu cầu mandate | Trạng thái | Ghi chú |
|---|---|---|
| 1. Không container nào chạy root | ✅ Enforce, PolicyReport sạch | 1 gap kỹ thuật nhỏ còn tồn đọng (mục 1.4) |
| 2. Không xài image trôi, pin digest | ✅ Enforce, PolicyReport sạch | |
| 3. Mọi workload có resource request/limit | ✅ Enforce, PolicyReport sạch | |
| 4. Enforce tự động tại admission | ✅ Cả 4 `ClusterPolicy` đã Enforce | Cutover có kiểm soát, từng policy một |
| "Phải nộp": demo rejection cho mentor | ⏳ Chưa làm — mới tự test nội bộ | Cần lịch hẹn mentor thật |
| "Phải nộp": ADR ký tên | 🟡 Đã viết, chưa có chữ ký chính thức | `docs/adr/0010-mandate-05-runtime-hardening.md` |

**2 exception còn hiệu lực** (có chủ đích, ghi rõ trong `docs/evidence/mandate-05/exception-register.yaml`): `kafka` (init-container cần root để `chown` PVC) và `aiops-engine` (workload của AIO02, không nằm trong GitOps repo này, chưa có securityContext).

---

## Yêu cầu #1 — Không container nào chạy root

> *"Buộc `runAsNonRoot`, drop mấy capability thừa - chỉ giữ đúng cái thật sự cần."*

### 1.1. Đã làm gì

- **Pod Security Admission (PSA)** bật ở namespace `techx-tf3`, mức `baseline`, chế độ `audit`+`warn` (không `enforce` — PSA chỉ dùng để cảnh báo sớm, việc chặn thật giao cho Kyverno).
- **`securityContext` baseline** áp cho từng container: `runAsNonRoot: true`, `allowPrivilegeEscalation: false`, `capabilities.drop: ["ALL"]`, `seccompProfile.type: RuntimeDefault`. Áp theo 2 cơ chế khác nhau tuỳ loại component:
  - Component TF3 tự viết (`payment`, `checkout`, `flagd`...): field `components.<name>.securityContext` / `podSecurityContext`.
  - Subchart dependency (`prometheus`, `grafana`, `jaeger`, `opensearch`, `opentelemetry-collector`): field riêng của từng chart upstream (không dùng `components:`).
- **Vá base image** cho 3 service từng chạy root do thiếu `USER` directive trong Dockerfile (Alpine): `currency`, `llm`, `product-reviews`.
- **Kyverno `ClusterPolicy` `custom-baseline-security-context`** — 8 rule kiểm tra đủ 5 tiêu chí trên (cộng thêm chặn `privileged: true` và `runAsUser: 0`), ở admission-time.

### 1.2. Ở đâu trong code

| Thành phần | File |
|---|---|
| Nhãn PSA | `gitops/infrastructure/namespace-techx-tf3.yaml` |
| securityContext component TF3 | `phase3 - information/techx-corp-chart/values.yaml` (default) + `phase3 - information/deploy/values-prod.yaml` (override, thắng khi trùng) |
| securityContext subchart | 2 file trên, khối top-level riêng từng chart (`prometheus.server.securityContext`, `jaeger.allInOne.securityContext`...) |
| Dockerfile vá base image | `phase3 - information/techx-corp-platform/src/{currency,llm,product-reviews}/Dockerfile` |
| Kyverno policy | `gitops/policies/kyverno/baseline-security-context.yaml` |
| Exception có chủ đích | `docs/evidence/mandate-05/exception-register.yaml` |

### 1.3. Lệnh verify

```sh
# PSA labels
kubectl get ns techx-tf3 -o jsonpath='{.metadata.labels}'
# -> phải có pod-security.kubernetes.io/audit=baseline, .../warn=baseline

# % container đạt đủ baseline (mục tiêu DoD gốc: >=80%)
kubectl get pods -n techx-tf3 -o json > /tmp/allpods.json
python3 - << 'EOF'
import json
pods = json.load(open('/tmp/allpods.json'))
total=0; ok=0; bad=[]
for p in pods['items']:
    pod_sc = p['spec'].get('securityContext') or {}
    pod_seccomp = (pod_sc.get('seccompProfile') or {}).get('type')
    for c in p['spec'].get('containers',[]) + p['spec'].get('initContainers',[]):
        sc = c.get('securityContext') or {}
        total += 1
        ape = sc.get('allowPrivilegeEscalation')
        caps = (sc.get('capabilities') or {}).get('drop', [])
        seccomp = (sc.get('seccompProfile') or {}).get('type') or pod_seccomp
        if ape is False and 'ALL' in caps and seccomp == 'RuntimeDefault':
            ok += 1
        else:
            bad.append((p['metadata']['name'], c['name']))
print(f"{ok}/{total} = {ok/total*100:.1f}%")
print("Con thieu:", bad)
EOF
# Kết quả lần verify gần nhất (18/07): 58/61 = 95.1%. 3 container "thiếu" là 2
# exception có chủ đích (kafka init-container, aiops-engine) — không phải gap thật.

# Trạng thái Kyverno policy
kubectl get clusterpolicy custom-baseline-security-context -o jsonpath='{.spec.validationFailureAction} {.status.conditions[?(@.type=="Ready")].status}'
# -> phải ra "Enforce True"

# Demo chặn thật (Deployment root, tự chuẩn bị sẵn trong repo)
kubectl apply --dry-run=server -f docs/evidence/mandate-05/rejection-demo/bad-root.yaml
```

### 1.4. ⚠️ Gap kỹ thuật còn tồn đọng — cần biết trước khi demo mentor

`custom-baseline-security-context` **không có autogen rule** cho `Deployment/StatefulSet/DaemonSet/Job/CronJob` (verify: `kubectl get clusterpolicy custom-baseline-security-context -o jsonpath='{.status.autogen.rules[*].name}'` trả về rỗng, trong khi 3 policy còn lại đều có). Lý do khả năng cao: 2 rule (`require-effective-non-root`, `require-seccomp-profile-runtime-default`) dùng cú pháp `deny.conditions` trộn field cấp container (`element.securityContext.X`) và cấp pod (`request.object.spec.securityContext.X`) trong cùng 1 điều kiện — tổ hợp Kyverno autogen chưa viết lại được.

**Hệ quả thật đã verify bằng cách apply thật (không phải dry-run) 1 Deployment thiếu securityContext:**
- `kubectl apply` Deployment → **thành công** (không có autogen rule chặn kind Deployment).
- ReplicaSet controller cố tạo Pod thật → **bị Kyverno chặn thật** (`FailedCreate`, admission denied) — **không có Pod root nào thực sự chạy được**.

→ Bảo vệ đầu-cuối **vẫn có hiệu lực** (rule gốc viết cho `kind: Pod` vẫn đúng, Pod thật vẫn đi qua rule đó), nhưng rejection xảy ra **trễ hơn 1 bước** so với ý mandate ("ngay lúc apply"). Nếu mentor demo bằng Deployment và chỉ nhìn `kubectl apply` báo `created`, dễ hiểu lầm là không bị chặn — phải `kubectl get pods`/`describe rs` mới thấy Pod thật sự chưa từng được tạo.

**Khuyến nghị trước khi demo:** sửa lại 2 rule trên (bỏ phần fallback pod-level trong `deny.conditions`, chỉ giữ container-level — theo đúng hướng PR #229 đã làm cho 2 rule khác) để autogen sinh được, rồi test lại đúng `bad-root.yaml` tới khi `kubectl apply` Deployment bị từ chối ngay.

---

## Yêu cầu #2 — Không xài image trôi, cấm tag "latest", pin theo digest

> *"Cấm tag kiểu `latest`; pin theo digest hoặc tag cố định để biết chính xác đang chạy version nào."*

### 2.1. Đã làm gì

**Ở tầng CI (build ra image) — `.github/workflows/build-push-ecr.yml`:**
- Mọi image build ra được gắn tag **duy nhất, không bao giờ lặp lại**: `<git-short-sha>-<github-run-id>-<service>` — không bao giờ dùng `latest` hay tag tĩnh.
- Sau khi push, workflow **tự tra lại ECR** (`aws ecr describe-images`) để lấy đúng digest `sha256:...` thật của image vừa push — không tin vào tag, luôn lấy digest xác thực từ registry. Có validate bằng regex (`^sha256:[0-9a-f]{64}$`) trước khi chấp nhận.
- Digest này được đóng gói vào `approved-images.json` — **manifest gốc, có chữ ký nguồn** (source SHA, run ID, run attempt) cho các bước sau dùng.
- ECR repository có bật **tag immutability** (tag không ghi đè được — comment trong workflow: *"ECR immutability makes a full rerun fail closed instead of overwriting an existing image"*).

**Ở tầng deploy (đưa digest vào production) — PM-113 pipeline:**
- `scripts/ci/update-image-overrides.py`: đọc `approved-images.json`, sửa **đúng dòng** `imageOverride.digest`/`tag` trong `deploy/values-prod.yaml` (giữ nguyên comment/format, không re-dump cả file), validate chặt (chống trùng key, sai định dạng digest, sai thứ tự service).
- `scripts/ci/verify-rendered-images.py`: render `helm template` thật sau khi sửa, verify digest đúng service đúng chỗ (bắt được cả lỗi "tráo digest giữa 2 service").
- Không commit thẳng vào `main` — luôn mở PR riêng (`ci/bump-image-<sha>`) để review trước khi merge.

**Ở tầng admission (chặn nếu ai đó cố deploy sai) — Kyverno:**
- `ClusterPolicy` `disallow-latest-tag` — regex chặn mọi image dùng tag `:latest` hoặc không ghi tag (implicit latest).
- `ClusterPolicy` `require-first-party-image-digest` — bắt buộc mọi image thuộc registry ECR `techx-corp` phải dùng `@sha256:<64 hex>`, không chấp nhận tag (kể cả tag cố định, không phải `latest`).

### 2.2. Ở đâu trong code

| Thành phần | File |
|---|---|
| Build + gắn tag + resolve digest | `.github/workflows/build-push-ecr.yml` (job `build-scan`, step "Resolve pushed image metadata") |
| Ghi digest vào values-prod | `scripts/ci/update-image-overrides.py` |
| Verify render đúng digest | `scripts/ci/verify-rendered-images.py` |
| Kyverno cấm latest | `gitops/policies/kyverno/disallow-latest-tag.yaml` |
| Kyverno bắt buộc digest | `gitops/policies/kyverno/require-first-party-image-digest.yaml` |
| Digest thật đang chạy | `phase3 - information/deploy/values-prod.yaml`, field `components.<name>.imageOverride.digest` |

### 2.3. Lệnh verify

```sh
# Không còn image nào :latest hoặc thiếu tag/digest cố định
kubectl get pods -n techx-tf3 -o jsonpath='{range .items[*]}{range .spec.containers[*]}{.image}{"\n"}{end}{end}' \
  | sort -u | grep -E ':latest$|^[^@:]+$' && echo "CO VI PHAM" || echo "OK"

# Đếm image ECR techx-corp có digest hợp lệ (kết quả lần verify gần nhất: 20/20)
kubectl get pods -n techx-tf3 -o jsonpath='{range .items[*]}{range .spec.containers[*]}{.image}{"\n"}{end}{end}' \
  | grep '197826770971.dkr.ecr.ap-southeast-1.amazonaws.com/techx-corp' | grep -c '@sha256:'

# Trạng thái Kyverno
kubectl get clusterpolicy disallow-latest-tag require-first-party-image-digest \
  -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.spec.validationFailureAction}{" "}{.status.conditions[?(@.type=="Ready")].status}{"\n"}{end}'
# -> cả 2 phải "Enforce True"

# Demo chặn thật (2 file riêng biệt, test đúng 2 lỗi khác nhau)
kubectl apply --dry-run=server -f docs/evidence/mandate-05/rejection-demo/bad-latest-image.yaml   # test cấm :latest
kubectl apply --dry-run=server -f docs/evidence/mandate-05/rejection-demo/bad-digest.yaml          # test bắt buộc digest (tag cố định KHÔNG phải latest vẫn bị chặn)
```

### 2.4. Exception còn hiệu lực

`kafka` — main container hiện **đã** dùng digest thật (`@sha256:efc188d0...`), exception cho phần digest coi như hết cần thiết trên thực tế nhưng vẫn giữ tường minh trong register vì team CDO02 (chủ workload này) chưa chính thức gỡ — không ảnh hưởng chức năng vì nó đã tự đạt.

---

## Yêu cầu #3 — Mọi workload phải định nghĩa resource request/limit

> *"Để trống là một pod có thể ngốn sạch resources của node rồi kéo sập cả cluster."*

### 3.1. Đã làm gì

- Mọi component (kể cả sidecar/init container) khai báo tường minh **cả 4 field** `requests.cpu`, `requests.memory`, `limits.cpu`, `limits.memory` trong `values.yaml`/`values-prod.yaml` — không dựa vào default ngầm. Trường hợp duy nhất từng thiếu (`flagd-ui` sidecar, chỉ có `limits.memory`) đã được vá (xem mục 3.4).
- `LimitRange` `techx-limits` (namespace `techx-tf3`) làm lưới an toàn cho trường hợp edge-case (Pod tạo trực tiếp, không qua Deployment) — không dùng cho workload thật vì tất cả đều deploy qua Deployment/StatefulSet, nơi luôn khai tường minh.
- **Kyverno `ClusterPolicy` `require-resource-requests`** — bắt buộc đủ 4 field ở admission-time cho `Pod` lẫn tự động sinh rule tương đương cho `Deployment/StatefulSet/DaemonSet/Job/CronJob`.

### 3.2. Ở đâu trong code

| Thành phần | File |
|---|---|
| Resource declaration | `phase3 - information/techx-corp-chart/values.yaml` + `phase3 - information/deploy/values-prod.yaml`, field `resources:` (component TF3: trong `components.<name>`; subchart: khối top-level riêng) |
| LimitRange | `gitops/infrastructure/` (ArgoCD app `techx-infrastructure-app`, resource `LimitRange/techx-limits`) |
| Kyverno policy | `gitops/policies/kyverno/require-resource-requests.yaml` |

### 3.3. Lệnh verify

```sh
# Xem số liệu request/limit thật từng container
kubectl get pods -n techx-tf3 -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{range .spec.containers[*]}{"  "}{.name}{"  req.cpu="}{.resources.requests.cpu}{"  req.mem="}{.resources.requests.memory}{"  lim.cpu="}{.resources.limits.cpu}{"  lim.mem="}{.resources.limits.memory}{"\n"}{end}{end}'

# LimitRange hiện có (để đối chiếu, không nhầm giá trị default với giá trị khai thật)
kubectl -n techx-tf3 get limitrange techx-limits -o yaml

# Trạng thái Kyverno
kubectl get clusterpolicy require-resource-requests -o jsonpath='{.spec.validationFailureAction} {.status.conditions[?(@.type=="Ready")].status}'
# -> "Enforce True"

# Demo chặn thật — BẮT BUỘC dùng Deployment, KHÔNG dùng Pod trần (xem mục 3.4 giải thích)
kubectl apply --dry-run=server -f docs/evidence/mandate-05/rejection-demo/bad-missing-resources.yaml
```

### 3.4. Lưu ý quan trọng — vì sao demo phải dùng Deployment, không dùng Pod trần

Pod trần tạo trực tiếp trong `techx-tf3` (không qua Deployment) sẽ được `LimitRange techx-limits` **tự động điền giá trị default** trước khi Kyverno kịp đánh giá (đúng thứ tự chuẩn Kubernetes: mutating admission chạy trước validating webhook) — nên 1 Pod trần thiếu resources **sẽ KHÔNG bị Kyverno chặn**, vì lúc Kyverno nhìn thấy nó đã có đủ 4 field (do LimitRange điền) rồi. **Đây không phải lỗi** — Deployment/StatefulSet (100% cách production thật deploy) không bị LimitRange đụng vào, nên vẫn được kiểm tra và chặn đúng khi thiếu resources thật. File `bad-missing-resources.yaml` trong repo đã cố ý dùng `kind: Deployment` để tránh nhầm lẫn này.

---

## Yêu cầu #4 — Enforce tự động tại admission, không rà tay

> *"Đẩy mấy luật trên vào admission (policy-as-code): manifest vi phạm bị từ chối ngay lúc apply... đi từ audit sang enforce có kiểm soát."*

### 4.1. Đã làm gì

- Cài **Kyverno** vào cluster qua GitOps (`gitops/apps/kyverno-app.yaml`), 4 controller (`admission`, `background`, `cleanup`, `reports`) đều Running, không gián đoạn deploy hiện có.
- Viết 4 `ClusterPolicy` **ở chế độ `Audit` trước** (PR #194, 16/07) — chỉ cảnh báo, chưa chặn — để đo lường tác động thật trước khi siết.
- Rà soát + vá dần từng vi phạm thật trên cluster sống trong nhiều ngày (loạt PR `fe2adde`, #207-#209, #222-#223) cho tới khi **0 vi phạm thật** (đối chiếu `PolicyReport` với pod đang sống, loại bỏ report cũ của ReplicaSet đã chết).
- Dọn sạch exception thừa (từ 11 xuống còn đúng 2 exception có chủ đích).
- **Chuyển từng policy 1 sang `Enforce`**, không dồn 1 lần (PR #224, #226, #227, #230 — theo đúng thứ tự: resources → digest/latest → baseline security context), mỗi bước verify ArgoCD Synced/Healthy + storefront còn HTTP 200 trước khi sang bước tiếp.
- Viết `docs/adr/0010-mandate-05-runtime-hardening.md` ghi rõ quyết định Audit/Enforce, exception, kế hoạch rollback.

### 4.2. Ở đâu trong code

| Thành phần | File |
|---|---|
| Cài Kyverno | `gitops/apps/kyverno-app.yaml` |
| 4 ClusterPolicy | `gitops/policies/kyverno/{baseline-security-context,disallow-latest-tag,require-first-party-image-digest,require-resource-requests}.yaml` |
| Exception register | `docs/evidence/mandate-05/exception-register.yaml` |
| ADR quyết định | `docs/adr/0010-mandate-05-runtime-hardening.md` |
| Bằng chứng cutover | `docs/evidence/mandate-05/enforce-cutover-20260718.md` |
| Bộ test Kyverno CLI (regression, chạy lại được) | `tests/kyverno/mandate-05/kyverno-test.yaml` + `tests/kyverno/mandate-05/resources/*.yaml` |
| 4 manifest demo rejection thật (dùng cho mentor) | `docs/evidence/mandate-05/rejection-demo/*.yaml` |

### 4.3. Lệnh verify

```sh
# Cả 4 policy phải Enforce + Ready
kubectl get clusterpolicy -o jsonpath='{range .items[*]}{.metadata.name}{"  action="}{.spec.validationFailureAction}{"  ready="}{.status.conditions[?(@.type=="Ready")].status}{"\n"}{end}'

# PolicyReport phải sạch (0 fail trên pod đang sống — không tính report cũ của ReplicaSet đã chết)
kubectl get pods -A -o json > /tmp/allpods.json
kubectl get policyreports -A -o json > /tmp/policyreports.json
python3 - << 'EOF'
import json
pods = json.load(open('/tmp/allpods.json'))
reports = json.load(open('/tmp/policyreports.json'))
live = {(p['metadata']['namespace'], p['metadata']['name']) for p in pods['items']}
for r in reports['items']:
    s = r.get('scope', {})
    if s.get('kind') != 'Pod' or (s.get('namespace'), s.get('name')) not in live:
        continue
    for res in r.get('results', []):
        if res.get('result') == 'fail':
            print(s['namespace'], s['name'], res.get('policy'), res.get('rule'))
EOF
# Kết quả lần verify gần nhất (18/07): rỗng — 0 fail thật.

# Chạy lại toàn bộ test suite Kyverno CLI (cần cài `kyverno` CLI)
kyverno test tests/kyverno/mandate-05/

# Demo rejection thật cho mentor — 4 lệnh, tất cả phải bị từ chối (trừ mục 1.4, bad-root.yaml
# hiện tại KHÔNG bị chặn ngay ở bước apply Deployment, cần sửa trước khi dùng để demo)
for f in docs/evidence/mandate-05/rejection-demo/*.yaml; do
  echo "=== $f ==="
  kubectl apply --dry-run=server -f "$f"
done
```

### 4.4. PM-101 (Trivy scan gate + Cosign ký) — hỗ trợ trực tiếp cho yêu cầu #2, không phải 1 trong 4 yêu cầu cốt lõi

- Trivy scan chặn CI nếu image build ra có lỗ hổng CRITICAL/HIGH (2 lần scan: trước push local candidate, và sau push trên digest thật) — trong `build-push-ecr.yml`.
- Cosign keyless (GitHub OIDC) ký từng digest ngay sau khi push — verify được **20/20 digest first-party đang chạy sống** hiện tại:

```sh
aws ecr get-login-password --region ap-southeast-1 | docker login --username AWS --password-stdin 197826770971.dkr.ecr.ap-southeast-1.amazonaws.com
kubectl get pods -n techx-tf3 -o jsonpath='{range .items[*]}{range .spec.containers[*]}{.image}{"\n"}{end}{end}' \
  | grep 'techx-corp@sha256:' | sort -u | while read -r img; do
    cosign verify --certificate-identity-regexp="https://github.com/tuu-ngo/Phase3-TF3-Infra-Sentinel" \
      --certificate-oidc-issuer="https://token.actions.githubusercontent.com" "$img" >/dev/null 2>&1 \
      && echo "PASS $img" || echo "FAIL $img"
  done
```

**Chưa làm (PM-114, không phải yêu cầu cốt lõi của mandate):** Kyverno `verifyImages` bắt buộc chữ ký Cosign tại admission-time. Cả PM-101 lẫn PM-104 tự ghi rõ đây là phần "nâng cao/tuỳ chọn" — mandate gốc không yêu cầu.

---

## Ngoại lệ đang còn hiệu lực

| ID | Workload | Policy | Lý do | Chủ sở hữu |
|---|---|---|---|---|
| `m05-baseline-kafka-init-chown` | `kafka` (init-container `init-kafka-data`) | `custom-baseline-security-context` | Cần chạy root để `chown` volume PVC trước khi container `kafka` (non-root) khởi động | CDO02 / TF3 Reliability |
| `m05-baseline-aiops-engine-runtime` | `aiops-engine` | `custom-baseline-security-context` | Deployment không nằm trong GitOps repo này (`kubectl apply` trực tiếp bởi AIO02), chưa có securityContext | AIO02 |

---

## Việc còn tồn đọng, chưa đóng hoàn toàn mandate

1. **[Mục 1.4]** Sửa 2 rule của `custom-baseline-security-context` để Kyverno autogen sinh được rule cho Deployment/StatefulSet/DaemonSet — hiện rejection chỉ xảy ra ở bước tạo Pod (qua ReplicaSet), trễ hơn ý mandate "ngay lúc apply".
2. **Lịch demo thật với mentor** — mandate yêu cầu mentor tự tay `kubectl apply` và tận mắt thấy bị từ chối; những gì trong file này là team tự test, chưa phải bàn giao chính thức.
3. **Ký chính thức ADR 0010** — hiện đã cập nhật nội dung đúng thực tế nhưng chưa có chữ ký reviewer/mentor.
4. **Chốt dứt điểm 2 exception còn lại**: `aiops-engine` cần AIO02 tự thêm securityContext hoặc xác nhận giữ exception dài hạn; `kafka` cần đánh giá phương án non-root ownership (fsGroup/pre-provisioned volume) nếu muốn gỡ hẳn exception.
5. **(Không gấp, không phải core requirement)** PM-114 — Kyverno `verifyImages` Cosign + allow-list image external, vẫn "To Do" trên Jira.

---

## Phụ lục — toàn bộ PR liên quan Mandate 5 (theo thời gian)

`PR #139` (rebrand ban đầu) → `PR #145` (mandate-5/integration gộp) → `PR #148` (PM-101 Trivy/Cosign) → `PR #194` (4 policy Audit) → `fe2adde`/`PR #207` (flagd/postgresql securityContext) → `PR #208` (fix Kyverno operator sync) → `PR #209` (aiops exception ban đầu) → `PR #215/#217/#218` (payment flagd-provider fix, không liên quan trực tiếp nhưng cùng đợt) → `PR #222` (flagd-ui resources) → `PR #223` (dọn exception + sửa scope `require-run-as-non-root`) → `PR #224` (Enforce resources) → `PR #225` (fix bug pattern resources) → `PR #226` (Enforce disallow-latest-tag) → `PR #227` (Enforce require-first-party-image-digest) → `PR #229` (fix baseline validation JMESPath) → `PR #230` (Enforce baseline-security-context) → `PR #231` (enforce closeout docs).

Tài liệu liên quan khác: `docs/mandate-05-gap-analysis-20260718.md` (nhật ký điều tra chi tiết, có timeline từng phát hiện/đính chính), `docs/mandate-05-kyverno-audit-fail-remediation.md`, `docs/mandate-05-nonroot-container-audit.md`, `docs/mandate-05-runtime-hardening-completion-plan.md`.
