# 003 - Repo nay co gi

Repo `Phase3-TF3-Infra-Sentinel` la repo van hanh cua TF3. No vua chua thong tin de hieu de bai, vua chua Terraform, workflow CI/CD, Helm chart va source ung dung duoc BTC cap.

## Can nho trong 60 giay

- Muon hieu tinh hinh hien tai: doc `CLAUDE.md`.
- Muon hieu ha tang AWS: doc `infra/`.
- Muon hieu deploy Kubernetes: doc `phase3 - information/techx-corp-chart/` va `phase3 - information/deploy/`.
- Muon hieu app: doc `phase3 - information/onboarding/ARCHITECTURE.md`.
- Muon hieu luat cam: doc `phase3 - information/RULES.md`.

## Cac vung chinh

`README.md`

- Gioi thieu repo.
- Noi ve secret scanning bang gitleaks.
- Nhac khong commit secret that.

`CLAUDE.md`

- File boi canh van hanh cua TF3.
- Ghi baseline deploy, trang thai hien tai, cac diem yeu da doc thay.
- La file nen doc dau tien khi mo lai repo.

`infra/`

- Terraform dung VPC + EKS.
- Co remote state S3, lock DynamoDB.
- Co IAM/IRSA cho controller sau nay.

`phase3 - information/`

- Packet goc cua Phase 3.
- Gom rules, onboarding, getting started, source platform, Helm chart, deploy values.

`phase3 - information/techx-corp-platform/`

- Source code storefront microservice.
- Nhieu ngon ngu: Go, Python, .NET, Java, Node.js, Rust, PHP, Ruby, C++, TypeScript.

`phase3 - information/techx-corp-chart/`

- Helm chart deploy toan bo app + observability.
- `values.yaml` la noi thay rat nhieu diem yeu baseline: replicas, resources, probe, env, data store.

`docs/postmortem/`

- Luu postmortem su co.
- Hien co postmortem ve `accounting` OOMKilled va ECR lifecycle policy xoa nham image.

`.github/workflows/`

- `build-push-ecr.yml`: build multi-arch image va push ECR.
- `secret-scan.yml`: chay gitleaks tren push/PR vao main.

`scripts/setup-hooks.sh`

- Cai pre-commit hook secret scanning local.

## File nen mo khi can tra loi nhanh

- Muon hieu luat: `phase3 - information/RULES.md`.
- Muon hieu kien truc: `phase3 - information/onboarding/ARCHITECTURE.md`.
- Muon hieu SLO: `phase3 - information/onboarding/SLO.md`.
- Muon hieu cost: `phase3 - information/onboarding/BUDGET.md`.
- Muon deploy: `phase3 - information/GETTING_STARTED.md`.
- Muon hieu cluster AWS: `infra/README.md` va cac file `.tf`.
- Muon hieu app deploy ra sao: `phase3 - information/techx-corp-chart/values.yaml`.

## Ban do CDO nen ghi nho

| Cau hoi | File/thu muc |
|---|---|
| AWS/EKS dung nhu the nao? | `infra/` |
| App deploy len K8s bang gi? | `techx-corp-chart/values.yaml` |
| Image build/push ra sao? | `.github/workflows/build-push-ecr.yml` |
| Secret scan o dau? | `.github/workflows/secret-scan.yml`, `.gitleaks.toml` |
| Incident da xay ra? | `docs/postmortem/` |
| Luat disqualify? | `phase3 - information/RULES.md` |
