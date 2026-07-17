# 011 - Backlog, pitch, ADR va postmortem

Phase 3 cham nang luc chon viec va bao ve quyet dinh. Lam nhieu viec nhung sai uu tien se thua.

## Can nho trong 60 giay

- Backlog tot = co bang chung + tac dong SLO/business + cost + rollback.
- CDO khong pitch "best practice"; CDO pitch "bao ve checkout/cart/browse SLO voi chi phi hop ly".
- ADR cho quyet dinh ha tang/cost/rui ro lon.
- Postmortem cho incident, ke ca incident tu gay ra trong luc fix.

## Cong thuc xep uu tien

Uu tien = rui ro x tac dong business.

Rui ro gom:

- Kha nang xay ra.
- Muc nghiem trong.
- Co tung xay ra trong incident history chua.
- Co bang chung trong chart/code/metrics khong.

Tac dong business gom:

- Anh huong checkout/doanh thu.
- Anh huong gio hang/trai nghiem khach.
- Anh huong SLO/error budget.
- Anh huong chi phi.
- Anh huong du lieu/audit.
- Anh huong uy tin/sai AI output.

## Vi du backlog tot

Day la cac vi du hop voi team CDO vi chung nam o platform/ha tang/cau hinh van hanh.

P0 - Rollout safety cho checkout path:

- Bang chung: chart thieu readiness/liveness; incident history co loi deploy do pod chua san sang.
- Tac dong: checkout la revenue-critical SLO 99%.
- Pham vi: probe that, dependency health co y nghia, replica cho service critical.
- Cost: thap hon migrate managed DB.
- Rollback: revert values/code health check neu probe sai.

P1 - Resource requests/limits + OOM alert:

- Bang chung: accounting da OOMKilled, nhieu limit thap, thieu requests.
- Tac dong: giam crash loop, giup autoscaling/scheduling.
- Cost: co the tang node usage, can do thuc te.

P1 - DB connection control:

- Bang chung: product-catalog khong set pool limit, product-reviews mo connect moi request.
- Tac dong: tranh lap lai INC-1.
- Cost: chu yeu code/config, khong can managed ngay.

P2 - Managed datastore evaluation:

- Bang chung: Postgres/Valkey/Kafka single replica.
- Tac dong: reliability cao.
- Cost: lon, can tinh trong 300 USD/tuan va co ADR.

## Goc pitch rieng cho CDO

Khi bi hoi "khach duoc gi neu cac ban chi lam ha tang?", cau tra loi khong nen la "vi best practice". Nen noi bang ngon ngu business:

- Probe/rollout an toan giup khach khong gap loi thanh toan trong luc deploy.
- Resource requests/limits dung giup service khong OOM va checkout on dinh luc co traffic.
- DB connection pool giup tranh checkout timeout gio cao diem.
- Observability alert giup phat hien loi bat dong bo nhu accounting truoc khi thanh mat du lieu.
- Cost guardrail giup TF khong dot ngan sach khi scale/migrate.

CDO pitch manh khi noi duoc bang chung ky thuat + anh huong SLO + chi phi + rollback.

## Pitch cuoi tuan 1

Can trinh bay:

- Hieu he thong.
- SLO va luong quan trong.
- Rui ro lon nhat.
- Backlog top-N.
- Vi sao viec A truoc viec B.
- Viec gi co y bo lai.

Hoi dong se hoi theo vai:

- PM: khach duoc gi?
- CFO: ton bao nhieu, ROI dau?
- SRE lead: rui ro, test, rollback?

## ADR

Viet ADR khi:

- Doi kien truc/ha tang.
- Them managed service.
- Doi network/IAM/security boundary.
- Doi chi phi dang ke.
- Doi rollout strategy quan trong.

ADR nen co:

- Context.
- Decision.
- Options considered.
- Consequences.
- Owner/nguoi ky.
- Ngay.

## Postmortem

Viet postmortem khi:

- SLO bi anh huong.
- Co incident production.
- Co su co tu gay ra trong luc fix.
- Co mat du lieu/rui ro mat du lieu.

Postmortem nen co:

- Tom tat.
- Timeline.
- Impact.
- Root cause.
- What went well.
- What went wrong.
- Action items.
- Owner va deadline.

## Bai hoc tu postmortem hien co

Su co `accounting` cho thay:

- Incident khong phai luc nao cung hien ra o frontend.
- Sua mot loi co the gay loi khac neu dung tai nguyen chung sai cach.
- CI/CD chung dang tin hon build tay khi can khoi phuc image hang loat.
- Alert restart/OOM can tu dong hoa.

## Mau 1 dong backlog de hoc thuoc

`[Priority] Viec can lam - Bang chung - SLO/business impact - Cost - Rollback/test`

Vi du:

`P0 Rollout safety cho checkout path - chart thieu readiness/liveness, incident history co loi deploy - bao ve checkout SLO 99% - cost thap - test rollout va rollback Helm values neu probe sai.`
