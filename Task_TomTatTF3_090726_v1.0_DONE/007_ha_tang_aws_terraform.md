# 007 - Ha tang AWS Terraform

Thu muc `infra/` dung Terraform de tao baseline AWS cho TF3.

## Can nho trong 60 giay

- Region: `ap-southeast-1`.
- EKS: `techx-corp-tf3`, Kubernetes `1.31`.
- VPC 3 AZ, worker nodes private.
- Node group: `t3.large`, min/desired 3, max 6, on-demand.
- Single NAT la quyet dinh tiet kiem chi phi.
- Co VPC endpoints cho S3/ECR de giam phu thuoc NAT khi pull image.
- KMS encrypt secrets, IRSA bat san.

## Thanh phan duoc tao

Region:

- `ap-southeast-1`.

Cluster:

- EKS cluster ten `techx-corp-tf3`.
- Kubernetes version mac dinh `1.31`.

VPC:

- CIDR `10.0.0.0/16`.
- 3 AZ: `ap-southeast-1a`, `1b`, `1c`.
- Private subnets cho worker nodes.
- Public subnets cho NAT/future load balancer.

NAT:

- Single NAT Gateway.
- Day la quyet dinh cost: re hon one NAT per AZ.
- Doi lai la NAT tro thanh diem rui ro cho egress.

VPC endpoints:

- S3 gateway endpoint.
- ECR API interface endpoint.
- ECR Docker interface endpoint.
- Muc tieu: image pulls/ECR traffic bot phu thuoc NAT va giam network cost.

EKS nodes:

- Managed node group.
- Instance type mac dinh `t3.large`.
- desired/min = 3, max = 6.
- On-demand, chua dung Spot vi baseline app con nhieu single replica.
- Nodes o private subnets.

Security:

- EKS public endpoint chi cho `allowed_admin_cidrs`, khong default `0.0.0.0/0`.
- Cluster endpoint private access bat.
- KMS encrypt Kubernetes secrets trong etcd.

IAM/IRSA:

- IRSA bat san.
- Role cho `cluster-autoscaler`.
- Role cho `aws-load-balancer-controller`.
- Hai controller nay chua duoc install trong Terraform baseline, chi chuan bi IAM.

Remote state:

- S3 bucket `techx-corp-tf3-terraform-state`.
- DynamoDB table `techx-corp-tf3-terraform-lock`.

## So do mot dong

`Internet/admin -> EKS API public restricted by allowed_admin_cidrs; worker nodes nam private subnets; egress ra ngoai qua single NAT, rieng S3/ECR qua VPC endpoints; app deploy bang Helm len EKS.`

## Dieu can nho khi sua Terraform

Moi thay doi lon nen co ADR:

- Doi instance type.
- Tang node desired/min.
- Chuyen NAT 1 cai sang NAT per AZ.
- Them managed DB/cache/queue.
- Doi network exposure.

Ly do: cac thay doi nay vua ton tien vua anh huong reliability/security.

## Cau hoi nen tu hoi

- Thay doi nay giam rui ro SLO nao?
- Ton them bao nhieu trong 300 USD/tuan?
- Co cach re hon nhung du tot khong?
- Neu apply loi, rollback ra sao?
- Co can thong bao team/on-call khong?

## Rui ro ha tang nen nho

- Single NAT tiet kiem cost nhung la rui ro egress.
- Chua dung Spot vi app con nhieu single replica.
- Autoscaler/LB controller moi co role, chua phai da cai add-on.
- Doi node/NAT/managed service deu co tac dong cost va can ADR.
