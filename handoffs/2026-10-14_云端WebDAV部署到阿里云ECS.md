# 云端 WebDAV 部署到阿里云 ECS 完成检查点

> 状态：部署完成，内网与公网均验证、已提交（本地本分支，未推送）
> 日期：2026-10-14（Asia/Shanghai）
> Linux 唯一工作区：/home/tahzun/Development/Projects/LiveRelay
> 源码：work/code/live_relay；分支：codex/desktop-rebuild
> 基准：work/deploy/copyparty/README.md；服务器管理档案 /srv/tttahzun/（inventory、gateway、backups）
> 证据：本文件"实测"段

## 这一轮做了什么

按本人决定（1:N 云服务、走服务器既有的 OpenResty 网关、先用系统盘、IP+HTTP 先行、密码由我生成）把 copyparty 真实部署到阿里云 ECS：

- 服务器：`i-f8zgef4blsfjh2pyvm6v`（Debian 13，2C/1.6G，40G 系统盘），SSH 走既有 `ttt-ecs-lan`（EasyTier 10.77.77.1）；
- 编排放 1Panel 标准目录 `/opt/1panel/docker/compose/liverelay-drive/`（本人确认面板"容器→编排"可见、可启停）；copyparty 只绑回环 `13923`；
- OpenResty 网关新增路由（源 `/srv/tttahzun/gateway/routes/liverelay-drive.conf`，装到 conf.d 后 `nginx -t && nginx -s reload`）：公网 `3923` → `127.0.0.1:13923`，WebDAV 全方法透传、`client_max_body_size 0`、不落盘缓冲、Host 带端口透传、`xff-src: 127.0.0.1` 传真实客户端 IP；
- 数据 `/srv/tttahzun/data/liverelay-drive/`；变更前快照 `/srv/tttahzun/backups/20261014T150515+0800-liverelay-drive-deploy/`；inventory 的 ports.yaml / services.yaml 已回写（含安全组 3923 放行记录）；
- 账号：`owner`（仅管理面板 `/?h`）＋ `demo` 与 `test1`–`test3`（测试用）；密码只存在于服务器 conf（600）与交付清单，不进 git。客户模板在 conf 内注释里（建目录＋[accounts] 一行＋卷块六行＋restart）。

## 实测

- 协议级（curl；回环直连与网关、内网与公网各过一遍）：PROPFIND 207、PUT 201、同名覆写（`daw`）、MOVE 覆盖（`Overwrite: T`）、Range 206、20MB 单文件 PUT、坏密码 401、匿名 401、客户互访被拒、owner 根目录文件对客户不可见、容器重启后自动恢复且可读写；
- 仓库两条现场测试对公网地址全过：`webdav_live_copyparty`（介质级）与 `device_transfer_webdav_live`（整库搬运闭环），URL `http://47.121.136.8:3923/demo/`；现场测试残留文件已清；
- 网关 `nginx -t` 通过、graceful reload，既有站点不受影响。

## 踩坑与修正（已回写仓库）

- `rp-loc` 只接受路径（子路径部署用），填完整 URL 会让 copyparty 拒绝启动并报明确错误——cloud 模板里那条误导注释已修正；
- `copyparty/ac` 镜像自动读取 `/cfg` 下 `*.conf`，`PRTY_CONFIG` 环境变量被忽略（无害，编排里已去掉）；
- 坏密码状态码：本机 pip 直跑见 403，ECS 部署见 401——客户端两种都按认证失败处理，README 已改。

## 未验证

- HTTPS 未做（本人决定 IP+HTTP 先行）；Let's Encrypt 纯 IP 证书（2026-01 GA，约 6 天自动轮换）路径已调研可行，等本人指示后在网关一处加；
- `selfhost/` 与 `cloud/`（Caddy）两套模板仍未实跑；
- 云端介质的桌面/手机界面人工走查未做；
- 防爆破的真实 IP 计数（xff-src）只验证到配置被接受，未做封禁压力验证。

## 留下的东西

- 客户交付三项：网址 `http://47.121.136.8:3923/<客户名>/`、账号、密码；浏览器页与 App 连接页同址；
- 服务器侧事实源仍是 `/srv/tttahzun/`（inventory + gateway/routes + backups 快照惯例）；仓库 `work/deploy/copyparty/ecs-gateway/` 是已部署形态的脱敏副本。

## 快速复现命令

```bash
# 公网探活（任意机器）
curl -s -o /dev/null -w '%{http_code}\n' -X PROPFIND -H 'Depth: 1' \
  -u '<客户名>:<密码>' http://47.121.136.8:3923/<客户名>/
# 现场测试（cwd=work/code/live_relay）
flutter test test/infrastructure/webdav_live_copyparty_test.dart \
  --dart-define=COPYPARTY_URL=http://47.121.136.8:3923/demo/ \
  --dart-define=COPYPARTY_USER=demo --dart-define=COPYPARTY_PASS=<demo密码>
flutter test test/application/device_transfer_webdav_live_test.dart --dart-define=...  # 同上三项
# 服务器侧：编排状态与日志
docker ps --filter name=liverelay-drive
cd /opt/1panel/docker/compose/liverelay-drive && docker compose logs -f
```

## 纪律不变

不合并 main、不移动 Tag、不安装手机、不读真实库与 Key；接近额度界限先保存提交推送并写交接。
