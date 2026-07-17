# Thiết kế flow Mandate 12 — Audit không thể bị đánh bại

## 1. Mục tiêu thiết kế

Thiết kế audit flow cho AWS account TF3 `197826770971` sao cho:

- TF3 operator, kể cả principal có quyền admin trong member account, không thể âm thầm dừng hoặc thay đổi đường ghi log;
- hành vi đọc S3 object nhạy cảm và đọc Secrets Manager đều truy được actor, thời gian và resource;
- log sau khi giao vào S3 được bảo vệ bằng Object Lock và kiểm chứng bằng chuỗi digest ký số;
- hành vi tấn công audit plane tạo cảnh báo tới security owner nằm ngoài blast radius của TF3;
- không thay đổi storefront public, cổng vận hành private hoặc flagd.

## 2. Ranh giới sở hữu

```mermaid
flowchart TB
    subgraph ORG["AWS Organizations — Management/Delegated Security Admin"]
        OT["Organization CloudTrail\nAll regions · Global events\nManagement read/write"]
        POLICY["SCP / organization controls"]
    end

    subgraph TF3["TF3 member account — 197826770971"]
        ADMIN["TF3 operator/admin"]
        AWSAPI["AWS control-plane APIs"]
        S3DATA["Sensitive S3 object/prefix"]
        SECRET["Secrets Manager"]
        EKS["EKS / edge / IAM / KMS / network"]
    end

    subgraph ARCHIVE["Log-archive account"]
        BUCKET["S3 audit bucket\nVersioning + Object Lock\nCOMPLIANCE 365 ngày"]
        KEY["Audit KMS key"]
        DIGEST["CloudTrail digest chain"]
    end

    subgraph SECURITY["Security/detection account"]
        RULE["EventBridge anti-audit rules"]
        HEALTH["Trail/digest delivery health check"]
        ALERT["SNS / on-call security"]
    end

    ADMIN --> AWSAPI
    ADMIN --> S3DATA
    ADMIN --> SECRET
    AWSAPI --> OT
    S3DATA --> OT
    SECRET --> OT
    EKS --> AWSAPI
    POLICY -. "không cho member sửa audit plane" .-> ADMIN
    OT -->|"log files"| BUCKET
    OT -->|"signed digest mỗi giờ"| DIGEST
    DIGEST --> BUCKET
    KEY --> BUCKET
    AWSAPI --> RULE
    RULE --> ALERT
    HEALTH --> ALERT
    BUCKET --> HEALTH
```

### Nguyên tắc ownership

| Thành phần | Owner | TF3 operator được làm gì |
|---|---|---|
| Organization trail | Management/delegated security admin | Xem status và dùng log theo quyền auditor; không sửa/dừng/xóa |
| SCP/organization controls | Management account | Không sửa |
| Audit bucket/Object Lock | Log-archive account | Không xóa, đổi retention hoặc bucket policy |
| Audit KMS key | Log-archive/security account | Không disable, schedule deletion hoặc sửa key policy |
| Detection và alert destination | Security account | Không tắt rule, target hoặc subscription |
| Resource inventory/test fixture | TF3 | Quản lý theo PR/change process |

## 3. Flow ghi log bình thường

```mermaid
sequenceDiagram
    autonumber
    participant Actor as User/Role/Service trong TF3
    participant API as AWS API
    participant CT as Organization CloudTrail
    participant KMS as Audit KMS key
    participant S3 as Log-archive S3 WORM
    participant Auditor as Auditor

    Actor->>API: Gọi API quản trị hoặc data operation được chọn
    API-->>Actor: Kết quả thành công/thất bại
    API-->>CT: CloudTrail event
    CT->>KMS: Mã hóa log delivery
    KMS-->>CT: Data key/cipher operation
    CT->>S3: Giao log file
    CT->>S3: Giao signed digest theo giờ
    S3-->>S3: Versioning + COMPLIANCE retention 365 ngày
    Auditor->>S3: Đọc log/digest bằng quyền read-only
    Auditor->>Auditor: Query actor, time, resource, action, outcome
```

### Nội dung tối thiểu cần truy được

- `eventTime` theo UTC;
- `recipientAccountId`, region và event source;
- `userIdentity`/principal/session issuer;
- `eventName`, resource ARN hoặc bucket/key phù hợp;
- source IP, user agent và request ID;
- success/error code;
- không ghi credential hoặc giá trị secret.

## 4. Flow đóng coverage gap

### 4.1 Đọc S3 object nhạy cảm

S3 object operation là **data event**, không được bảo đảm chỉ bằng management event.

```mermaid
flowchart LR
    A["Mentor/attacker gọi GetObject"] --> B["Sensitive bucket/prefix"]
    B --> C{"Advanced event selector\nkhớp ARN/prefix?"}
    C -->|Có| D["CloudTrail S3 data event"]
    C -->|Không| X["Coverage gap — FAIL mandate"]
    D --> E["Log-archive S3 WORM"]
    E --> F["Auditor tìm GetObject\nprincipal + time + bucket/key"]
```

Selector phải ưu tiên bucket/prefix đã phân loại nhạy cảm. Không bật wildcard mọi bucket trước khi có baseline volume và cost.

### 4.2 Đọc secret

`GetSecretValue` và `BatchGetSecretValue` tạo CloudTrail entry từ Secrets Manager. Đây là API event của Secrets Manager, không phải S3 data event.

```mermaid
flowchart LR
    A["Mentor/attacker gọi GetSecretValue"] --> B["AWS Secrets Manager"]
    B --> C["CloudTrail management read event"]
    C --> D["Log-archive S3 WORM"]
    D --> E["Auditor tìm principal/time/secret ARN"]
    B -. "SecretString chỉ trả về caller\nkhông ghi vào audit evidence" .-> A
```

Demo dùng secret canary vô giá trị. Không bật debug CLI và không lưu raw response chứa `SecretString`.

### 4.3 Thay đổi cấu hình quan trọng

Management read/write events phải cover ít nhất:

- CloudTrail và audit configuration;
- IAM/STS và access policy;
- KMS key/policy/grant;
- S3 bucket policy, lifecycle, encryption và Object Lock;
- Secrets Manager configuration/rotation/deletion;
- EKS, EC2/VPC, CloudFront/WAF và networking;
- AWS Organizations, delegated administrator, trusted access và SCP.

## 5. Flow chống làm mù

```mermaid
sequenceDiagram
    autonumber
    participant Attacker as TF3 admin/mentor
    participant CTAPI as CloudTrail API
    participant Org as Organization control
    participant EB as Security EventBridge
    participant SOC as Security on-call
    participant Trail as Organization trail

    Attacker->>CTAPI: StopLogging/DeleteTrail/UpdateTrail
    CTAPI->>Org: Authorization check
    Org-->>CTAPI: Deny member account mutation
    CTAPI-->>Attacker: AccessDenied
    CTAPI-->>Trail: Ghi API attempt + actor + error
    CTAPI-->>EB: AWS API Call via CloudTrail
    EB->>SOC: Critical anti-audit alert
    SOC->>SOC: Acknowledge + mở incident
    SOC->>Trail: Xác minh IsLogging=true
```

### Event cần cảnh báo

| Nhóm | Event điển hình | Mức |
|---|---|---|
| Trail | `StopLogging`, `DeleteTrail`, `UpdateTrail`, `PutEventSelectors` | Critical |
| Archive S3 | đổi bucket policy/Object Lock/lifecycle/encryption, delete attempt | Critical |
| KMS | disable key, schedule deletion, sửa key policy/grant | Critical |
| Organizations | disable trusted access, deregister delegated admin, leave/remove account, sửa SCP bảo vệ | Critical |
| Detection | disable/delete rule/target/topic/subscription | Critical |

EventBridge delivery là đường cảnh báo nhanh nhưng không phải bằng chứng duy nhất. Health check độc lập phải phát hiện `IsLogging=false`, delivery error, digest trễ hoặc alert heartbeat thất bại.

## 6. Flow toàn vẹn mật mã

```mermaid
flowchart TB
    L1["CloudTrail log file giờ N"] --> H1["SHA-256 hash"]
    L2["CloudTrail log file giờ N"] --> H2["SHA-256 hash"]
    PREV["Chữ ký digest trước"] --> D["Digest giờ N"]
    H1 --> D
    H2 --> D
    D --> SIGN["CloudTrail ký SHA-256 with RSA"]
    SIGN --> STORE["S3 Object Lock COMPLIANCE"]
    STORE --> VALIDATE["aws cloudtrail validate-logs"]
    VALIDATE --> OK{"Kết quả"}
    OK -->|Valid| PASS["Không phát hiện thêm/xóa/sửa\ntrong chain được kiểm tra"]
    OK -->|Missing/INVALID| FAIL["Integrity incident — FAIL mandate"]
```

Integrity validation chứng minh file đã được delivery không bị sửa/xóa và phát hiện chain gap. Nó **không chứng minh coverage đầy đủ** nếu selector chưa thu sự kiện; do đó coverage test và digest validation là hai gate riêng.

## 7. Flow triển khai

```mermaid
flowchart LR
    A["Xác nhận owner/account boundary"] --> B["Inventory bucket, secret, principal"]
    B --> C["Đo volume và forecast cost"]
    C --> D{"Trong ngân sách?"}
    D -->|Không| E["Thu hẹp noisy selector\nkhông bỏ control bắt buộc"]
    E --> C
    D -->|Có| F["Review IaC ba state độc lập"]
    F --> G["Test sandbox: delivery, deny, alert, digest"]
    G --> H{"Tất cả gate pass?"}
    H -->|Không| F
    H -->|Có| I["Tạo archive + detection"]
    I --> J["Tạo organization trail"]
    J --> K["Verify delivery + digest"]
    K --> L["Bật data selector theo batch"]
    L --> M["Mentor chạy ba đòn"]
    M --> N["Evidence pack + sign-off"]
```

### Thứ tự bảo đảm không có blind window

1. Archive bucket, KMS và alert path sẵn sàng trước.
2. Organization trail bắt đầu ghi management events và validation.
3. Xác minh log/digest thực sự đến archive.
4. Bật data event selector theo batch.
5. Chỉ bỏ trail cũ sau khi trail mới đã có delivery/digest hợp lệ; overlap tối đa khoảng một ngày để hạn chế duplicate cost.

## 8. Flow mentor kiểm thử

Flow dưới đây là luồng tổng quát. Test ID, giới hạn production/sandbox, expected events và mẫu verdict chi tiết nằm trong `06-kich-ban-tan-cong-va-bang-chung-mandate-12.md`.

```mermaid
flowchart TB
    START["Bắt đầu demo — ghi UTC window"] --> BLIND["Đòn 1: Stop/Delete/Update trail"]
    BLIND --> B1{"Bị deny hoặc alert\nvà trail vẫn logging?"}
    B1 -->|Không| FAIL["FAIL Mandate 12"]
    B1 -->|Có| GAP["Đòn 2A: GetObject canary"]
    GAP --> G1{"Tìm được S3 data event?"}
    G1 -->|Không| FAIL
    G1 -->|Có| SECRET["Đòn 2B: GetSecretValue canary"]
    SECRET --> G2{"Tìm được Secrets Manager event?"}
    G2 -->|Không| FAIL
    G2 -->|Có| WAIT["Chờ digest bao phủ demo window"]
    WAIT --> VERIFY["Đòn 3: validate-logs"]
    VERIFY --> V1{"Không missing/INVALID?"}
    V1 -->|Không| FAIL
    V1 -->|Có| PASS["PASS + đóng gói evidence"]
```

### Evidence pack

| Đòn | Evidence đầu vào | Evidence đầu ra |
|---|---|---|
| Làm mù | principal, command/API, UTC time | AccessDenied hoặc alarm, CloudTrail attempt event, `IsLogging=true` |
| Làm hụt — S3 | canary bucket/key, request ID | `GetObject` data event đúng actor/time/resource |
| Làm hụt — secret | canary secret ARN, request ID | `GetSecretValue` event; không chứa secret value |
| Làm mỏng/sửa | trail ARN, account, region, UTC range | `validate-logs` summary không có missing/`INVALID` |

## 9. Flow xử lý sự cố audit

```mermaid
flowchart LR
    A["Anti-audit alert hoặc health failure"] --> B["SEC_ONCALL acknowledge"]
    B --> C["Xác định actor/account/region/eventName"]
    C --> D["Kiểm tra IsLogging + delivery + digest"]
    D --> E{"Có blind window/integrity gap?"}
    E -->|Có| F["Critical incident\nCô lập credential + ORG_ADMIN khôi phục"]
    E -->|Không| G["Blocked attempt\nđiều tra intent và access"]
    F --> H["Legal hold evidence + chain of custody"]
    G --> H
    H --> I["Postmortem + policy correction"]
```

Không xóa/recreate trail vội khi điều tra vì có thể làm đứt continuity. Không nới bucket/KMS policy thành quyền rộng để chữa delivery error.

## 10. Flow cost control

```text
S3 data-event count
        × CloudTrail data-event unit price
      + delivered log GB
        × delivery/storage price theo region và tier
      + KMS requests + alerting/query
      = audit stack cost
```

Kiểm soát chi phí theo thứ tự:

1. Loại noisy bucket/prefix không nhạy cảm khỏi data selector.
2. Dùng lifecycle tiering nhưng không rút ngắn Object Lock.
3. Tắt tính năng tùy chọn như Insights/Lake nếu chưa có use case.
4. Loại duplicate trail sau migration gate.
5. Không tắt management logging, integrity validation hoặc anti-audit alert để giảm chi phí.

## 11. Acceptance gates

| Gate | Điều kiện pass |
|---|---|
| Ownership | TF3 admin không quản trị organization trail/archive/KMS/detection |
| Blind-window | Stop/Delete/Update attempt bị deny hoặc báo động; trail tiếp tục ghi |
| S3 coverage | `GetObject` canary xuất hiện đúng dưới dạng data event |
| Secret coverage | `GetSecretValue` canary xuất hiện và không lộ secret value |
| Integrity | `validate-logs` pass, không missing/`INVALID` trong demo window |
| Retention | Versioning + Object Lock Compliance 365 ngày; không thể rút ngắn |
| Detection | Alert đến security owner, có actor/time/account/region |
| Cost | Forecast và actual không làm tổng TF vượt khoảng `$300/tuần` |
| Product safety | Không diff storefront, private ops path hoặc flagd |

Chỉ khi tất cả gate đều pass mới chuyển trạng thái từ `DEPLOYED` sang `VERIFIED`.
