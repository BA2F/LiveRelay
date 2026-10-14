# 云端 WebDAV 云盘与 App 连接

> 状态：部署资产已完成并实测；App 内"连接 WebDAV"页待施工
> 日期：2026-10-14
> 来源：本人 2026-10-13 确认（"采用 copyparty"；要求：一对一自建、一对多云服务、2C2G 部署、Docker、断点续传、服务器主管理页、客户只填网址＋账号密码）
> 依赖：work/paper/desktop-redesign-2026-10-12/桌面重设计决策单.md 第 4 节（C 模式互通）

## 要解决的产品问题

C 模式互通已把"介质=目录"做进应用（第 4 步，2026-10-13 完成）。云端要补上两件事：

1. 一个 LiveRelay 提供/推荐的 WebDAV 服务端，让用户不必自备 Nextcloud 之类重家伙就能有云介质：自建（1:1）与云服务（1:N）同软件、2C2G 可跑、Docker 交付、断点续传、服务器主有管理页看情况；
2. App 内的"连接 WebDAV"页：手机没有系统挂载 WebDAV 的能力，直连（填网址＋账号＋密码）是手机走云端的必需件；桌面也可用同一入口，不必依赖系统挂载。

## 选型结论（2026-10-13 本人确认）

采用 [copyparty](https://github.com/9001/copyparty)：MIT、单文件、活跃；WebDAV+HTTP 浏览器页+账号/按卷权限+管理面板+可续传上传（up2k，浏览器页用）齐全；官方 Docker 镜像（`copyparty/ac`，另有 im/iv/dj 变体）；2C2G 足够。

当时评估过并落选的：dufs（无管理页）、SFTPGo（AGPL-3.0 与主题版权约束）、OxiCloud（要外挂 PostgreSQL、项目新）、Hi-DAV（项目年轻，不适合直接上公网）。自写 Go 服务的方案保留为备选：若日后需要自有品牌页面或更精细配额，再换，App 协议不变。

## 已完成：部署资产（2026-10-14）

位置 `work/deploy/copyparty/`：`selfhost/`（1:1 的 compose + 配置模板）、`cloud/`（1:N 的 compose + 配置模板 + Caddyfile 自动 HTTPS）、`README.md`（部署与使用说明、本机实测记录、注意事项）。

用 copyparty v1.20.25 在本机以等价的 pip 直跑实例逐项实测（记录见该 README）：配置解析、账号与卷权限、启动期校验（卷里引用的账号缺定义则拒绝启动）、PROPFIND/PUT/覆写（`daw`）/MOVE/覆盖式 MOVE（`Overwrite: T`）/Range、客户间隔离（每人只看到自己的卷，越权访问 403）、认证失败码、管理面板 `/?h`、tmpfs 数据目录会被剥写权限。

未验证：Docker 镜像与 compose 未实跑（本机无 Docker）；Caddy 部分未实跑。README 已如实标注。

## 待施工：App 内连接页

设计边界（施工前另出实施计划）：

- 新基础设施适配 `WebDavTransferMedium implements TransferMedium`（端口见 `lib/core/ports/transfer_medium.dart`），业务层（DeviceTransferService 及搬运页面/对话框）零改动即获得云端介质：
  - `list` = PROPFIND Depth:1（解析 D:href 与 D:getcontentlength）；
  - `readPrefix` = Range GET（服务端已验证支持 206）；
  - `read` = GET；
  - `writeAtomic` = PUT 到 `<name>.tmp` 再 MOVE 覆盖（服务端已验证 `Overwrite: T`），配合服务端卷标志 `daw`；201 与 204 都算成功；
  - 认证失败认 401 与 403（copyparty 对坏密码回 403）。
- 凭证（网址、账号、密码）存设备本地安全存储，与"首次外发授权记录"同层：不进加密库、不随整库搬运；连接页显示当前配置、可清除；移除配置即断开。
- 入口：设备间搬运页增加"云端介质"选择（与"选择介质目录"并列），锁定态不可用；将来 gate 不加入口（首次导入仍走本地介质，云端连接需要先进设置）。
- 不依赖服务器扩展：断点续传按既有分卷＋文件级跳过实现（传失败重跑只补缺失卷文件），不实现 up2k 客户端，不做字节级续传协议。
- 测试：单元测试用本地 httpd 替身（或直接对本机 copyparty 实例跑集成用例，测试环境允许回环直跑）；桌面原生套件加一条走云端介质的往返用例（本机起 copyparty 或 httpd 替身）。

## 明确不做

- 服务器端的 LiveRelay 专用协议或代理：介质语义保持在 WebDAV 标准子集上；
- 多介质同时在线、云端与本地双向自动同步（B 模式课题）；
- 面向客户的注册/计费页面（云服务账号由服务器主在配置里开）。

## 遗留与后续

- 客户页面：目前客户可用的"简单页面"就是 copyparty 自带浏览器页（登录后存取）。是否做 LiveRelay 自有品牌的最小页，等 App 连接页落地后按本人意见再定。
- 服务器主"了解情况"：copyparty 管理面板（`/?h`）加本 README 的运维说明；更细的用量报表后置。
