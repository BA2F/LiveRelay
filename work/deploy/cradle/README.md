# LiveRelay 摇篮服务（报平安提醒与取件通知）

> 状态：已部署并真发邮件（2026-10-17）。2026-10-24 已更新到计划 v2 与测试邮件代码。
> 日期：2026-10-24
> 依赖：Docker 与 Docker Compose。一个可发信的 SMTP 账号。copyparty 客户卷，见 [../copyparty/](../copyparty/)。
> 设计：[报平安与自动交接](../../../tasks/specs/2026-10-15_报平安与自动交接.md)、[交接取件包与摇篮邮件](../../../tasks/specs/2026-10-21_交接取件包与摇篮邮件.md)

App 把三样东西写进云端客户卷。路径是 `/srv/tttahzun/data/liverelay-drive/users/<客户>/`，属于 copyparty 的云布局：

- `liverelay-checkin.json`：最近一次报平安。覆盖写。手动按钮和「打开 App 自动记一次」都会写它。
- `liverelay-cradle-plan.json`：摇篮计划。包含周期、提前提醒、宽限期、提醒邮箱、接收者名单和每人的邮件草稿。
- `liverelay-cradle-test.json`：App 请求发送的一封测试邮件。服务发送后删除它，把结果写进 `liverelay-cradle-test-result.json`。

摇篮服务读取这些文件发邮件。数据目录以可写方式挂载。服务只写结果文件、删除测试请求，其余文件不动。

| 距上次报平安 | 动作 |
| --- | --- |
| ≥ 周期 − 提前（默认第 6 天） | 每天一次提醒本人。收件人是计划里的 `ownerEmail`。 |
| ≥ 周期 + 宽限（默认第 10 天） | 给每个接收者各发一次取件邮件。版本 2 计划按 `subject` 和 `body` 原样发送。版本 1 计划走旧模板，包含网址、账号、密码和文件名。 |

时间基准用文件修改时间，取服务器时钟。不用记录里的设备时间。还没有报平安记录时，用计划的修改时间兜底。本人重新报平安后自动重置，提醒和通知重新开始计。

信任边界见 spec，本人已确认接受。服务端控制何时通知，理论上可以提前通知。版本 2 计划的邮件正文由本人在 App 里写，默认包含取件码。服务端保存并原样发送，所以这一版服务端能看到取件码，也能据此解密对应的包。包内容本身仍是加密的。如果本人从草稿里删除取件码，服务端只拿到加密包，读不到内容。这是 2026-10-21 取件包流程的明确取舍。后续再改成每人只读账号或一次性取件链接。

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

SMTP 用 `CRADLE_SMTP_MODE=ssl`（端口 465）或 `starttls`（端口 587）。发信源可以用普通邮箱的授权码（QQ、163 等），也可以用阿里云邮件推送。发信账号只需要能发信。收信地址都写在 App 的摇篮计划里。

## 运维

- 状态文件：`./state/<客户>.json`。内容是基线时间戳、最近提醒日和已通知的接收者。删除后全部重置。
- 加客户自动生效。客户卷里出现计划文件后，下一轮巡检开始纳入。不需要改配置。
- 复盘日志：`docker compose logs --since 24h`。
- 状态目录随服务器备份一起保存。状态丢失只会导致可能的重复提醒或通知，不会发错人。

## 本地干跑验证（2026-10-15，本机 python3 直跑）

四个场景一轮通过。记录 6.5 天时提醒本人。记录 11 天时通知接收者。只有计划、记录 2 天时无动作。坏计划跳过并记日志。

第二轮验证了同日不重复提醒，已通知的接收者不重发。把报平安时间刷新后，状态正确重置。

## ECS 实测记录（2026-10-15，干跑模式）

- 部署位置：`/opt/1panel/docker/compose/liverelay-cradle/`。1Panel 面板可见可管。镜像用 `python:3.12-slim` 构建。容器 `liverelay-cradle` 常驻，interval 600 秒，`CRADLE_DRY_RUN=1`。首次部署和脚本更新各执行一次 `docker compose up -d --build`。
- 端到端测试用 test3 卷、假计划和假报平安记录，单轮模式 `CRADLE_ONCE=1`：
  - 报平安记录 6.5 天前：打印提醒邮件，发给计划里的 `ownerEmail`，内容是「你已经 7 天没有报平安」。
  - 记录 11 天前：打印取件通知，发给接收者，内容是「测试接收者 给你留了内容」。
  - 记录刷新为当前时间：状态正确重置，提醒日和已通知标记清空，当轮无动作。
- 测试数据已清理，包括假计划、假记录和状态文件。
- 2026-10-15 晚修复：初版按「客户卷等于数据根一级子目录」扫描。实际 copyparty 布局是 `users/<客户>/`。本人手机实测报平安时，记录落进 `users/test3/`，暴露了这个问题。已改为最多三层递归发现，客户键用相对路径，例如 `users__test3`。深浅两种布局都验证过。容器已更新。

## SMTP 真发（2026-10-17）

- 发信源：网易企业邮箱 `smtphz.qiye.163.com:994`，SSL。发件地址和授权码由本人提供，只写入服务器上的 compose，权限 600，不入库。容器从干跑切为真发。
- 首封真发暴露了干跑掩盖的 bug。`EmailMessage["Subject"] = Header(...)` 在 Python 3.12 抛 `'Header' object is not subscriptable`，因为干跑不经过 smtplib，测不出这个问题。改为字符串赋值后重发成功，见提交 `7476b28`。
- 全真演练：把真实报平安记录模拟成 6.5 天前。本人 QQ 邮箱收到提醒邮件「【留灯】你已经 7 天没有报平安」。演练后记录时间已恢复。

## 取件包与测试邮件（2026-10-21）

- App 的「交接 → 交给他人」为每位接收者生成一份密码包，算法是 Argon2id + AES-256-GCM。文件名 `liverelay-handoff-<8 位 ASCII ID>.lrshare`，上传到客户卷。
- 计划升为版本 2。每位接收者带 `subject` 和 `body`。正文由本人在 App 内编辑，默认包含取件链接、WebDAV 账号密码、取件码、App 下载地址和留言。服务端原样发送。版本 1 计划继续走旧模板。
- 测试邮件：App 写 `liverelay-cradle-test.json`。服务端发送后写 `liverelay-cradle-test-result.json`，字段是 `requestedAt`、`sentAt` 和 `error`，然后删除请求。测试不影响正式提醒和通知状态。
- 取件码由 App 生成，12 位，分组显示。也可以自定义，至少 12 位。

## 部署更新（2026-10-24）

- 症状：App 点「发送测试邮件」后，云端一直不产生结果文件。App 显示「还没有留下测试结果」。
- 原因有两层：
  1. 容器镜像停在 2026-10-17，不含 2026-10-21 的计划 v2 与测试邮件代码。v2 计划每轮被拒，日志写 `invalid plan (kind/version)`。
  2. `/data` 按 2026-10-15 的设计只读挂载。新代码要写结果文件、删除请求文件，报 `[Errno 30] Read-only file system`。邮件在写结果前已经发出，请求文件删不掉，所以每 10 分钟重复发送。
- 处理：上传仓库版 `cradle.py`，执行 `docker compose up -d --build`。挂载由 `:ro` 改为 `:rw`。
- 代价：摇篮进程现在可以写客户卷。取件包不被改动的保证从挂载层降到代码层。当前代码只写 `liverelay-cradle-test-result.json`，只删 `liverelay-cradle-test.json`。
- 快照：`/srv/tttahzun/backups/20261024-174424-cradle-v2-update/`。内容包含 `SHA256SUMS`、旧 `cradle.py` 和改前的 compose。

## 待办

- 结果文件写回依赖可写挂载。要恢复只读挂载，需要改成每人一个可写子目录，或者取消结果文件协议。
- 第二步安全收口：每人一个只读账号或一次性取件链接，避免把同一个 WebDAV 账号发给所有接收者。同时补 HTTPS、发送状态回写，并让服务端不存取件码。
- 接收者目前需要手动下载 `.lrshare`，再用 App 的「打开交接包」打开。浏览器直接查看的取件页后置。
