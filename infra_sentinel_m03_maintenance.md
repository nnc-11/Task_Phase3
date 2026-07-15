# Report M03 - Maintenance no downtime

Cap nhat: 2026-07-14
Pham vi: theo doi Directive #3 va phan CDO02 lien quan Reliability.

## 1. Ket luan nhanh

Directive #3 chua duoc assess bang runtime evidence trong Task. Hien moi co mandate BTC va backlog CDO02 lien quan REL-01/PDB/revenue path. Chua co lich mentor, kich ban drain/rolling restart, dashboard SLO trong luc bao tri, hoac ket qua mentor confirm.

## 2. BTC yeu cau gi

- Drain node hoac rolling restart trong gio van hanh ma khach khong downtime.
- Browse -> cart -> checkout giu SLO.
- Khong con single point of failure tren revenue path.
- Pod chua ready/healthy khong nhan traffic.

## 3. CDO02 lien quan the nao

CDO02 can dam bao revenue path co redundancy, PDB, readiness dung va observability du de chung minh trong cua so maintenance.

## 4. Trang thai evidence

| Evidence can co | Trang thai | Ghi chu |
| --- | --- | --- |
| Lich hen mentor | MISSING | Chua thay trong Task. |
| Kich ban drain/rolling restart | MISSING | Chua co report cu the. |
| REL-01 runtime verify | NEED_VERIFY | Backlog noi da merge repo nhung chua verify runtime. |
| PDB revenue path | NEED_VERIFY | Can check read-only khi co runtime access. |
| SLO dashboard trong bao tri | MISSING | Chua co. |
| Mentor confirm | MISSING | Chua co. |

## 5. Blocker

- AWS/EKS runtime verification dang block do AWS CLI credential loi.
- Chua co lich mentor va evidence bao tri.
- Observability co issue OOMKilled theo incident report, can verify lai truoc khi dung dashboard.

## 6. Read-only check can lam khi co quyen

- `kubectl get deploy,pdb,hpa,pods` de xem redundancy/PDB.
- `kubectl describe` de xem readiness/liveness va events.
- `kubectl logs --tail` neu can xem loi gan nhat.

Khong duoc lam:

- Khong drain node.
- Khong rollout restart.
- Khong delete pod.
- Khong scale.
- Khong cordon/uncordon.

## 7. Next report update

Cap nhat khi co runtime read-only evidence ve REL-01/PDB hoac lich mentor/kich ban maintenance.
