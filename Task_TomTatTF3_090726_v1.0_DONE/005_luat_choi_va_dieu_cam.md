# 005 - Luat choi va dieu cam

Day la file can doc ky vi co nhung dieu vi pham la disqualify ca TF.

## Can nho trong 60 giay

- Khong tat, go, doi huong `flagd`.
- Khong bo `values-flagd-sync.yaml` khi `helm upgrade`.
- Khong commit secret that vao repo.
- Su co do BTC bom vao phai xu ly bang fallback/retry/containment, khong ne co che.
- Thay doi ha tang lon can ADR; incident can postmortem.

## Nguyen tac lon

Su co do BTC tao ra la de xu ly, khong phai de tat. TF phai lam he thong chiu loi tot hon bang fallback, retry, containment, observability, scaling, rollout an toan. Khong duoc pha co che BTC dung de tao su co.

## Dieu cam quan trong nhat: flagd

Khong duoc:

- Go `flagd`.
- Doi huong `flagd` sang nguon khac.
- Refactor service de no khong con doc flag incident.
- Bo `values-flagd-sync.yaml` khoi lenh `helm upgrade`.
- Sua TOKEN/URI trong tracked file thanh gia tri/nguon tuy tien.

Ly do: `flagd` va OpenFeature hook la duong day BTC dung de bom incident. Tat no tuong duong ne su co, khong phai van hanh.

Duoc lam:

- Them fallback khi flag bat mot hanh vi loi.
- Them timeout/retry/circuit breaker.
- Them alert de phat hien flag-induced incident.
- Them flag moi cua TF cho tinh nang cua minh, mien khong pha flag incident.

## Secret

Khong commit secret that:

- AWS credentials.
- flagd sync token that.
- LLM API key.
- kubeconfig certificate/token.
- Bearer token/private key.

Cach dung dung:

- File tracked giu placeholder.
- Secret that truyen qua `kubectl create secret`, `helm --set`, hoac file local bi `.gitignore`.
- Neu lo secret: rotate ngay, khong chi xoa khoi file.

## Quyen va audit

Moi quyet dinh lon can truy duoc ve nguoi:

- ADR cho thay doi ha tang/cau truc/rui ro/cost.
- Postmortem cho su co.
- Khong push thang main neu da co quy uoc PR.
- Gitleaks phai xanh.

## Fair play

Khong muon ket qua TF khac. Khong pha SLO cua nhau. Khong vuot ngan sach roi noi la "cho chac". Day la bai danh gia judgment, khong phai ai bat nhieu tai nguyen nhat.

## Checklist truoc khi dung vao ha tang

- Co cham vao `flagd`, OpenFeature, `values-flagd-sync.yaml` khong?
- Co ghi secret/token/API key vao file tracked khong?
- Co lam thay doi ton tien lon khong?
- Co can ADR truoc khi lam khong?
- Neu deploy loi, rollback nhu the nao?
