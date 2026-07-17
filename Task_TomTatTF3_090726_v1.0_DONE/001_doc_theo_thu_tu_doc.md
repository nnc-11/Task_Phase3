# 001 - Doc theo thu tu doc

Tat ca file nam truc tiep trong thu muc `Phase3`, khong nam trong repo `Phase3-TF3-Infra-Sentinel`.<br>
Time: 090726 v1.0

Goc nhin chinh cua bo doc nay: **team CDO**. Nghia la khi doc, uu tien hieu platform/ha tang, SLO, cost, reliability, performance, security va auditability. Phần AI nắm overview để hiểu tính năng sản phẩm.

## Thu tu doc mac dinh

1. `001_doc_theo_thu_tu_doc.md` - Danh mục đọc.
2. `002_buc_tranh_lon_phase3.md` - Phase 3 la gi, vi sao khong phai bai code thong thuong.
3. `003_repo_nay_co_gi.md` - repo TF3 gom nhung phan nao.
4. `004_kien_truc_he_thong.md` - microservice, data store, request flow.
5. `005_luat_choi_va_dieu_cam.md` - nhung dieu vi pham la bi disqualify.
6. `006_slo_ngan_sach_va_danh_doi.md` - SLO, error budget, cost cap.
7. `007_ha_tang_aws_terraform.md` - VPC, EKS, IAM, remote state.
8. `008_deploy_helm_image_flagd.md` - build image, Helm chart, values files, flagd.
9. `009_observability_va_oncall.md` - Grafana, Jaeger, Prometheus, logs, cach truc.
10. `010_rui_ro_ky_thuat_da_thay.md` - cac diem yeu da doc thay trong chart/code.
11. `011_backlog_pitch_adr_postmortem.md` - cach xep backlog, pitch, ADR, postmortem.
12. `012_ke_hoach_hoc_trong_toi_nay.md` - lich doc va thuc hanh suy nghi trong mot toi.

## Thu tu doc neu muc tieu la hieu ha tang truoc

Neu toi nay ban chi can nam ha tang/platform truoc, doc theo thu tu nay:

1. `003_repo_nay_co_gi.md` - biet Terraform, Helm, deploy, source nam o dau.
2. `007_ha_tang_aws_terraform.md` - hieu VPC/EKS/node/IAM/remote state.
3. `008_deploy_helm_image_flagd.md` - hieu image, ECR, Helm chart, values, flagd sync.
4. `009_observability_va_oncall.md` - hieu monitoring/logs/traces va can alert gi.
5. `010_rui_ro_ky_thuat_da_thay.md` - hieu cac diem yeu ha tang/cau hinh dang co.
6. `006_slo_ngan_sach_va_danh_doi.md` - gan ha tang voi SLO va cost.
7. `005_luat_choi_va_dieu_cam.md` - doc ky truoc khi dung deploy/secret/flagd.
8. `004_kien_truc_he_thong.md` - doc sau de biet ha tang dang phuc vu cac luong app nao.

Voi muc tieu "hieu ha tang", tam thoi khong can doc sau tung dong code service. Can nam du de biet service nao critical, dependency nao single point of failure, va thay doi ha tang nao co the anh huong SLO.

## Neu chi co 60-90 phut

Doc nhanh theo thu tu rut gon:

1. `003_repo_nay_co_gi.md`
2. `007_ha_tang_aws_terraform.md`
3. `008_deploy_helm_image_flagd.md`
4. `010_rui_ro_ky_thuat_da_thay.md`
5. `012_ke_hoach_hoc_trong_toi_nay.md`

Sau do tu tra loi 5 cau:

- EKS/VPC baseline cua TF3 gom gi?
- App duoc deploy bang Helm nhu the nao?
- `values-flagd-sync.yaml` vi sao bat buoc?
- Rui ro ha tang lon nhat hien tai la gi?
- Neu phai pitch CDO ngay mai, ban chon top 3 backlog nao?

## Cach dung bo doc

Doc nhanh lan 1 de nam ban do. Lan 2, mo song song repo va doi chieu cac duong dan duoc nhac den. Muc tieu cua toi nay khong phai thuoc tung service, ma la tra loi duoc:

- He thong nay ban cai gi cho khach?
- Request quan trong nhat di qua dau?
- Neu service loi, SLO nao bi anh huong?
- Thay doi nao ton tien, thay doi nao tang reliability?
- Viec nao can ghi ADR/postmortem?

## Neu ban la CDO, uu tien doc ky nhat

- `005_luat_choi_va_dieu_cam.md`: CDO hay cham vao deploy/Helm/IaC/secret, nen rui ro vi pham flagd va secret rat cao.
- `006_slo_ngan_sach_va_danh_doi.md`: moi quyet dinh ha tang phai quy ve SLO va cost.
- `007_ha_tang_aws_terraform.md`: day la phan CDO so huu truc tiep.
- `008_deploy_helm_image_flagd.md`: CDO can nam Helm, image, ECR, flagd sync.
- `009_observability_va_oncall.md`: CDO phai dung metrics/logs/traces de van hanh.
- `010_rui_ro_ky_thuat_da_thay.md`: day la nguyen lieu backlog CDO.

## Tu khoa can nam

- TF3: Task Force gom AIO02, CDO01, CDO02.
- TechX Corp: storefront thuong mai dien tu microservice ma TF3 tiep quan.
- Operate: giu he thong song, truc incident, bao ve SLO.
- Build: ship cai tien co uu tien.
- SLO: muc tieu dich vu phai giu.
- Error budget: phan loi duoc phep truoc khi phai dong bang thay doi rui ro.
- flagd: feature flag duoc BTC dung de bom su co. Khong duoc tat/doi huong.
- ADR: bien ban quyet dinh ky thuat.
- Postmortem/COE: bien ban sau su co.

## Ket qua mong doi sau khi doc bo file

Ban khong can thuoc tung service. Ban can noi duoc mach nay:

`Terraform tao AWS/EKS baseline -> Helm deploy app + observability -> frontend-proxy nhan traffic -> checkout/cart/product path co SLO -> chart hien co nhieu single replica/thieu probes/thieu requests -> CDO phai uu tien rollout safety, resource sizing, observability alert, DB connection control, va cost guardrail.`
