# External watchdog

Tín hiệu read-only nằm ngoài AWS account: GitHub Actions dùng OIDC, không dùng access key. Nếu role bị xóa, trust bị sửa hoặc các check AWS fail thì workflow đỏ vẫn còn ở GitHub.

Đặt file khi được duyệt:

| File staging | Vị trí trong product repo |
|---|---|
| `github-oidc-watchdog.tf.example` | `infra/bootstrap/github-oidc/m12-watchdog.tf` |
| `m12-audit-watchdog.yml.example` | `.github/workflows/m12-audit-watchdog.yml` |
| `watchdog.sh` | `.github/scripts/m12-watchdog.sh` |

Workflow cần repository variables được liệt kê trong file YAML. `M12_PRIMARY_RULE_NAMES`, `M12_GLOBAL_RULE_NAMES`, `M12_HEARTBEAT_ALARM_NAMES` và `M12_EXPECTED_SUBSCRIPTION_ENDPOINTS` là danh sách phân cách bằng dấu phẩy, không có khoảng trắng; các giá trị khác là một exact name/ARN. Chỉ lấy giá trị sau foundation apply.

`M12_PRIMARY_RULE_PATTERNS_JSON` và `M12_GLOBAL_RULE_PATTERNS_JSON` là JSON object `rule-name -> EventPattern object`, lấy từ approved post-apply state rồi security owner lưu làm GitHub variable. Watchdog canonicalize JSON trước khi so sánh nên thay thứ tự key không gây false alarm, nhưng thêm/xóa/sửa source/eventSource/eventName sẽ fail.

Repository Actions settings phải cho `GITHUB_TOKEN` tạo issue; workflow dùng `issues: write` để tạo/cập nhật incident khi check fail. Bật notification cho security owner. Branch protection/CODEOWNERS phải chặn daily AWS operator sửa hoặc xóa role Terraform, script và workflow; nếu không, watchdog chưa độc lập về quyền vận hành.

Đây là gate bắt buộc để claim `VERIFIED` theo cách hiểu chặt “admin cùng account cũng phải bị phát hiện”. Không có watchdog chỉ claim `DEPLOYED/PARTIAL` và phải có signed risk acceptance.
