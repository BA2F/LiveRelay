# LiveRelay 摇篮服务（报平安提醒与取件通知）

> 状态：脚本与本地干跑验证完成（2026-10-15）；ECS 部署与真发邮件待 SMTP 凭据
> 日期：2026-10-15
> 依赖：Docker 与 Docker Compose；一个可发信的 SMTP 账号；copyparty 客户卷（见 ../copyparty/）
> 设计：tasks/specs/2026-10-15_报平安与自动交接.md

App 把两样东西写进云端客户卷（`/srv/tttahzun/data/liverelay-drive/<客户>/`）：

- `liverelay-checkin.json`：最近一次报平安（覆盖写；手动按钮与"打开 App 自动记一次"）
- `liverelay-cradle-plan.json`：摇篮计划（周期／提前提醒／宽限期／提醒邮箱／接收者名单）

摇篮服务只读这些文件（数据目录只读挂载），按下面的规则发邮件：

| 距上次报平安 | 动作 |
| --- | --- |
| ≥ 周期 − 提前（默认第 6 天） | 每天一次提醒本人（plan 里的 ownerEmail） |
| ≥ 周期 + 宽限（默认第 10 天） | 给每个接收者各发一次取件邮件（网址／账号／密码／文件名） |

时间基准用**文件修改时间（服务器时钟）**，不用记录里的设备时间；还没有报平安记录时用计划的修改时间兜底。本人重新报平安后自动重置，提醒与通知重新开始计。

信任边界（本人已拍板接受，见 spec）：服务端控制何时通知，理论上可以提前通知；包内容始终是加密的（HPKE，只有接收者能打开），服务端读不到。

## 部署（ECS / 1Panel）

```bash
# 1. 上传本目录到服务器（例：ttt-ecs-lan）
scp -r work/deploy/cradle ttt-ecs-lan:/opt/1panel/docker/compose/liverelay-cradle
# 2. 服务器上先干跑（不需要 SMTP 凭据，只记日志）
cd /opt/1panel/docker/compose/liverelay-cradle
CRADLE_DRY_RUN=1 docker compose up -d --build
docker compose logs -f
# 3. 填 SMTP 凭据后正式发信（改 compose 里的 CHANGE-ME，去掉干跑）
$EDITOR docker-compose.yml && chmod 600 docker-compose.yml
docker compose up -d
```

SMTP：`CRADLE_SMTP_MODE=ssl`（端口 465）或 `starttls`（端口 587）。发信源可以用普通邮箱的授权码（QQ／163 等）或阿里云邮件推送；发信账号只需要能发，收信地址都写在 App 的摇篮计划里。

## 运维

- 状态：`./state/<客户>.json`（基线时间戳、最近提醒日、已通知的接收者）；删掉即全部重置
- 加客户自动生效：客户卷里出现计划文件后，下一轮巡检开始纳入，无需改配置
- 复盘日志：`docker compose logs --since 24h`
- 状态目录随服务器备份一起；丢了只会导致可能的重复提醒／通知，不会发错人

## 本地干跑验证（2026-10-15，本机 python3 直跑）

四个场景一轮通过：6.5 天 → 提醒本人；11 天 → 通知接收者；只有计划（2 天）→ 无动作；坏计划 → 跳过并记日志。第二轮验证了同日不重复提醒、已通知的接收者不重发；把报平安时间刷新后状态正确重置。ECS 干跑与真发邮件见下节实测记录。

## ECS 实测记录

（部署后回写）
