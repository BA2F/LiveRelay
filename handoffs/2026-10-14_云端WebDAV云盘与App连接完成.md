# 云端 WebDAV 云盘与 App 连接完成检查点

> 状态：部署资产与 App 内连接页完成、验证并提交（本地，未推送）
> 日期：2026-10-14（Asia/Shanghai）
> Linux 唯一工作区：/home/tahzun/Development/Projects/LiveRelay
> 源码：work/code/live_relay；分支：codex/desktop-rebuild
> 基准：tasks/specs/2026-10-14_云端WebDAV云盘与App连接.md（含选型与设计边界）
> 证据：work/deploy/copyparty/README.md 的实测记录；提交 13edbe5、c97fe6f、27254ff

## 这一轮做了什么

**部署线**（`work/deploy/copyparty/`）：自建 1:1 与云服务 1:N 两套 Docker Compose＋copyparty 配置模板＋Caddy 自动 HTTPS；云服务模式每客户一个卷、只给自己账号权限（`rwmd`，不含管理位），管理员账号只进管理面板、不碰客户文件。README 写了部署步骤、加客户步骤、备份与升级、注意事项。

**App 线**：`WebDavTransferMedium`（PROPFIND 列目录、Range 下载前缀、GET、PUT 到 `.tmp` 再 MOVE 覆盖）实现既有 `TransferMedium` 端口，C 模式搬运的业务层零改动即接入云端；连接配置（网址＋账号＋密码）存设备安全存储（与外发授权同层，不进加密库、不随整库搬运）；搬运页新增"云端：未配置／管理云端"一行与"介质选择（云端／本地目录）"，连接对话框可"测试连接"后再保存。

## 实测（本机 copyparty v1.20.25 直跑）

- 服务端行为（curl，见部署 README）：配置解析、卷权限、启动期账号校验、PUT 覆写（`daw`）、MOVE 与覆盖式 MOVE（`Overwrite: T`）、Range 206、客户隔离、坏密码 403、管理面板 `/?h`、tmpfs 数据盘会被剥写权限。
- Dart 客户端：假服务器单测 5 项；对着真 copyparty 的现场往返测试 2 项（介质级 PUT/列目录/范围读/覆写；整库搬运闭环：A 导出→B 经网络导入→卡与原件可读→A 二次导出零重传）。两项现场测试需要 `--dart-define=COPYPARTY_URL/USER/PASS`，平时自动跳过。
- 常规面：analyze 零问题；295 项单元测试通过；transfer_desktop 原生套件通过。

## 未验证

- Docker 镜像与 compose、Caddy 没有实跑（本机无 Docker）；开服时按 README 步骤走一遍即可确认。
- 云端介质的界面人工走查未做（连接对话框、介质选择弹窗）。
- 手机端 SAF 介质路径仍如第 4 步交接所述。

## 留下的东西

- 客户可用的"简单页面"目前就是 copyparty 自带浏览器页；自有品牌最小页等本人意见再定。
- 多客户用量/配额报表后置；服务端不放开根路径（客户只见自己的卷）。
- 断点续传按分卷＋文件级跳过（已验证二次导出零重传）；不实现 up2k 客户端。

## 快速复现命令

```bash
# 本机验证实例（回环、wram 允许 tmpfs 写入）
python3 -m venv /tmp/cpv-venv && /tmp/cpv-venv/bin/pip install copyparty
XDG_CONFIG_HOME=/tmp/cpv-test/config /tmp/cpv-venv/bin/copyparty \
  -c /tmp/cpv-test/cloud.conf -i 127.0.0.1 --wram
# 现场测试（另开终端，cwd=work/code/live_relay）
flutter test test/infrastructure/webdav_live_copyparty_test.dart \
  --dart-define=COPYPARTY_URL=http://127.0.0.1:3923/alice/ \
  --dart-define=COPYPARTY_USER=alice --dart-define=COPYPARTY_PASS=alicepass
flutter test test/application/device_transfer_webdav_live_test.dart --dart-define=...
```

## 纪律不变

不合并 main、不移动 Tag、不安装手机、不读真实库与 Key；接近额度界限先保存提交推送并写交接。
