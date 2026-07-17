# 008 - Deploy, Helm, image va flagd

Deploy TechX gom 3 lop: build image, push ECR, Helm install/upgrade.

## Can nho trong 60 giay

- Image app phai build tu source va push vao ECR TF3.
- Helm chart deploy app + observability.
- `default.image.repository` phai tro dung ECR.
- `values-flagd-sync.yaml` bat buoc trong moi deploy/upgrade Phase 3.
- Khong ghep nham `values-observability.yaml` va `values-app-stamp.yaml` vao baseline.
- ECR lifecycle policy da tung gay incident xoa nham image.

## Image

Moi TF phai build image tu source va push vao ECR account cua minh. Seed image chi de bootstrap nhanh, khong phai registry van hanh co dinh.

Workflow CI `build-push-ecr.yml`:

- Chay khi push vao `main` co thay doi trong platform source.
- Co `workflow_dispatch` de build thu cong.
- Dung GitHub OIDC assume AWS role.
- Build multi-arch `linux/amd64,linux/arm64`.
- Push cac app image vao ECR `techx-corp`.

Can nho su co da xay ra:

- ECR lifecycle policy da tung xoa nham nhieu image vi giu 15 image tren toan repo, khong theo tung service.
- Neu viet lifecycle policy lai, phai test ky va tach theo prefix/pattern service.

## Helm chart

Chart nam o:

`phase3 - information/techx-corp-chart/`

File quan trong:

- `values.yaml`: cau hinh mac dinh toan he thong.
- `templates/component.yaml`: lap qua tung component enabled.
- `templates/_objects.tpl`: render Deployment, Service, Ingress, ConfigMap.
- `templates/_pod.tpl`: render env va port.

Chart default deploy ca app va observability. Trong `CLAUDE.md` co luu y quan trong: khong dung `values-observability.yaml` va `values-app-stamp.yaml` chung trong mot deploy baseline, vi hai file do danh cho tach namespace.

## Values files

`values-flagd-sync.yaml`

- Bat buoc khi deploy trong Phase 3.
- Doi flagd tu file local sang central HTTP source cua BTC.
- Go sidecar flagd-ui local de TF khong toggle flag bang web local.
- Khong duoc bo khoi lenh Helm upgrade.

`values-observability.yaml`

- Bat observability subcharts.
- Tat tat ca app components.
- Dung khi muon tach observability namespace rieng.

`values-app-stamp.yaml`

- Tat observability subcharts.
- App tro OTLP ve collector chung.
- Dung khi da co observability namespace rieng.

`values-aio-llm.yaml`

- Dung khi AIO cam LLM that thay mock.
- API key phai la Kubernetes secret, khong commit vao repo.

`quota.yaml`

- ResourceQuota mau cho namespace.

## flagd la diem song con

Khi `helm upgrade`, luon nho merge lai `values-flagd-sync.yaml`. Neu quen, flagd co the quay ve file local, mat ket noi central source cua BTC. Day co the bi xem la vi pham luat choi.

## Checklist truoc khi deploy

- Dang dung dung namespace TF3?
- `default.image.repository` tro ECR TF3?
- Image tag ton tai tren ECR?
- Co merge `values-flagd-sync.yaml`?
- Secret LLM/API co tao bang Kubernetes secret neu can?
- Co ADR neu thay doi ton tien/rui ro?
- Co ke hoach rollback neu pod CrashLoop/ImagePullBackOff?

## Chuoi deploy de nho

`source code -> CI/buildx -> ECR image tag -> Helm values -> Kubernetes Deployment -> Pod pull image -> Service route traffic`

Neu loi deploy, debug theo chuoi nguoc lai: pod event/log -> image tag/ECR -> Helm values -> workflow build.
