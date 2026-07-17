# CDO02 - Xử lý Mandate BTC #1: Storefront public, operational ports private

Ngày lập: 13/07/2026  
Owner chính: CDO01 cho Security boundary và public/private ingress decision  
CDO02 phối hợp: Reliability, observability access, smoke test checkout/cart/browse, rollback evidence  
Mandate nguồn: `MANDATE-01-network-exposure.md`

## 1. Phạm vi CDO02

Directive #1 thuộc Security là chính, nhưng CDO02 vẫn liên quan vì mọi thay đổi network/ingress có thể làm hỏng storefront, checkout, observability hoặc khả năng xử lý incident.

Security boundary do CDO01 phụ trách chính. Phần CDO02 trong mandate này là kiểm soát tác động vận hành, đảm bảo storefront và các flow SLO không bị ảnh hưởng sau thay đổi.

| Hạng mục | Trách nhiệm CDO02 |
|---|---|
| Storefront vẫn public | Smoke test browse/cart/checkout sau mỗi thay đổi |
| Grafana/Jaeger private | Đảm bảo vẫn có đường truy cập riêng để vận hành, load test và lấy evidence |
| ArgoCD/private control plane | Nắm runbook GitOps để không bị khóa khi incident |
| Datastore flow | Đảm bảo NetworkPolicy không chặn product-catalog/product-reviews/accounting/cart/checkout |
| Rollback | Có cách quay lại nhanh nếu thay đổi làm tụt SLO |

## 2. Hiện trạng cần giả định khi xử lý

| Thành phần | Trạng thái theo repo/context hiện tại |
|---|---|
| EKS API | Private-only, truy cập qua SSM bastion |
| Storefront | Có CloudFront public, ALB HTTP public vẫn cần chốt boundary |
| ArgoCD | Đã quản lý app qua GitOps, `selfHeal=true`, `prune=true` |
| Grafana/Jaeger | Cần verify runtime xem còn public route nào không |
| Postgres | Đã có NetworkPolicy tối thiểu |
| Valkey/Kafka/observability | Cần tiếp tục rà soát exposure và NetworkPolicy |

## 3. Cách xử lý

### Bước 1 - Lập endpoint matrix

CDO01 làm chính, CDO02 cần review để đảm bảo không thiếu operational surface.

| Endpoint | Kỳ vọng | Ghi chú CDO02 cần kiểm tra |
|---|---|---|
| Storefront CloudFront | Public | Phải vào được từ internet |
| ALB frontend-proxy | Tạm public hoặc restrict theo quyết định CDO01 | CDO02 chỉ verify CloudFront/storefront path sau khi CDO01 đổi boundary |
| Grafana | Private | Mentor phải có hướng dẫn vào qua tunnel/VPN/bastion |
| Jaeger | Private | Vẫn cần dùng được khi incident |
| ArgoCD | Private | Không public UI/admin |
| Prometheus/OpenSearch nếu có UI | Private | Không expose dashboard/log trực tiếp |
| EKS API | Private | Đã qua SSM bastion |

CDO01 cần ghi output cho bước này:

| Output cần từ CDO01 | CDO02 dùng để làm gì |
|---|---|
| Danh sách endpoint public/private cuối cùng | Đối chiếu với mandate BTC và checklist smoke test |
| Quyết định CloudFront-only hay ALB public tạm thời | Biết endpoint nào là storefront chính thức để test |
| Danh sách operational UI bị đóng public | Chuẩn bị private access guide và negative test |
| Rollback path cho ingress/security group/network policy | Dùng khi storefront hoặc observability bị ảnh hưởng |

### Bước 2 - Chốt đường truy cập private cho vận hành

Yêu cầu của BTC không phải cấm truy cập operational UI, mà là cấm public internet truy cập trực tiếp.

Các lựa chọn chấp nhận được:

| Cách | Ghi chú |
|---|---|
| SSM bastion + port-forward | Phù hợp với trạng thái EKS private-only hiện tại |
| VPN/tunnel riêng | CDO01 quyết nếu cần |
| ArgoCD/Grafana chỉ qua private network | Tốt nếu có hướng dẫn mentor rõ |

CDO02 cần đảm bảo hướng dẫn truy cập đủ để xem dashboard khi load test hoặc incident. Nếu operational UI bị đóng public nhưng chưa có private access guide, coi như mandate chưa done ở góc vận hành.

Input cần từ CDO01:

| Input | Yêu cầu tối thiểu |
|---|---|
| Private access method | VPN/tunnel/bastion/port-forward, dùng cách nào là chính |
| Danh sách user/mentor được cấp quyền | Ai có quyền vào Grafana/Jaeger/ArgoCD |
| Lệnh hoặc hướng dẫn truy cập | Đủ cụ thể để mentor tự kiểm tra |
| Cơ chế audit nếu có | Ai truy cập, thời điểm, qua đường nào |

### Bước 3 - Smoke test sau thay đổi network

Sau mỗi thay đổi ingress/network, CDO02 chạy checklist logic sau:

| Flow | Kỳ vọng |
|---|---|
| Browse product | Success rate không tụt |
| Cart | Add/view cart hoạt động |
| Checkout | Đặt hàng test không lỗi |
| Product reviews/AI summary | Không bị chặn Postgres/LLM path |
| Observability | Grafana/Jaeger vẫn vào được qua đường private |
| ArgoCD | App không OutOfSync bất thường |

Nếu có lỗi, không tiếp tục hardening thêm. Rollback hoặc pause ArgoCD theo runbook rồi xử lý.

Output CDO02 trả lại cho CDO01:

| Output | Nội dung |
|---|---|
| Smoke test result | Browse/cart/checkout/review/observability pass hoặc fail |
| SLO impact | Có lỗi 5xx, timeout, p95 tăng hoặc không |
| Datastore impact | Postgres/Valkey/Kafka flow có bị policy chặn không |
| Rollback recommendation | Giữ change, rollback, hoặc cần chỉnh allowlist |

## 4. Acceptance criteria cho phần CDO02

| Tiêu chí | Cách chứng minh |
|---|---|
| Storefront vẫn public | URL storefront truy cập được; browse/cart/checkout pass |
| Operational UI không public | Public negative test cho Grafana/Jaeger/ArgoCD |
| Operational UI vẫn dùng được | Hướng dẫn mentor vào qua private path |
| Không phá datastore flow | product-catalog/product-reviews/accounting/cart/checkout không lỗi sau NetworkPolicy |
| Có rollback | Ghi rõ manifest/commit/ArgoCD action để quay lại |

## 5. Rủi ro CDO02 cần canh

| Rủi ro | Ảnh hưởng | Cách giảm thiểu |
|---|---|---|
| Restrict nhầm ALB/CloudFront | Storefront down | CDO01 đổi boundary từng bước; CDO02 test CloudFront/browse/cart/checkout ngay |
| NetworkPolicy chặn nhầm Postgres | Browse/review/accounting lỗi | Test từng service có dependency Postgres |
| Private hóa observability nhưng không có access guide | Không điều tra được incident | Chuẩn bị port-forward/tunnel guide trước khi đóng public |
| ArgoCD selfHeal revert hotfix | Incident quay lại | Pause ArgoCD trước khi patch tay |
| `prune=true` xóa tài nguyên lệch Git | Rủi ro với stateful singleton | Không tạo tài nguyên tay lâu dài; codify vào Git |

## 6. Evidence cần nộp

| Evidence | Nội dung |
|---|---|
| Endpoint matrix | Public/private status của storefront, Grafana, Jaeger, ArgoCD |
| Storefront positive test | Browse/cart/checkout sau khi private hóa operational ports |
| Operational negative test | Public internet không vào được Grafana/Jaeger/ArgoCD |
| Private access guide | Cách mentor vào operational UI |
| Rollback note | Nếu change gây lỗi thì quay lại thế nào |

## 7. Note owner/input-output với CDO01

| Việc | Owner | Input CDO02 cần | Output CDO02 trả |
|---|---|---|---|
| Chốt CloudFront/ALB boundary | CDO01 | Entry point chính thức và rollback path | Smoke test storefront qua entry point đó |
| Đóng public Grafana/Jaeger/ArgoCD | CDO01 | Cách đóng và private access path | Xác nhận vẫn vào được qua private path |
| NetworkPolicy operational/datastore | CDO01 | Allowlist dự kiến | Kết quả test flow app/datastore |
| Mentor access | CDO01 | User/permission/access guide | Xác nhận guide đủ dùng cho evidence |

## 8. Kết luận

Với CDO02, Mandate #1 không phải chỉ là "đóng port". Việc đúng cần làm là đóng operational surface nhưng giữ được khả năng vận hành:

```text
storefront public -> operational UI private -> observability vẫn dùng được -> checkout/cart/browse không tụt SLO
```

CDO02 chịu trách nhiệm phần kiểm soát rủi ro vận hành và chứng minh SLO sau thay đổi; phần thiết kế Security boundary cần thống nhất theo đầu mối CDO01.
