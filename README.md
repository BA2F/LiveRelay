# LiveRelay · 留灯

把重要信息留在本人能掌控的地方。

LiveRelay 是本地优先的人生信息记录与交接准备工具。你可以记下资料位置、账户、资产、家庭事项和想交代的事，在本机加密保存，保留原件、来源与修改历史，并核对不同情境下授权展示的内容。

## 可以做什么

- **记录**：先保存一条内容，之后整理或本人确认；导入、拍摄和回看照片、录音及录像。
- **卡片**：按文字、类型和状态查找，查看完整来源与原件；编辑保留旧修订，支持拆分、组合、回收和恢复。
- **密码库**：默认遮挡密码，按需显示或复制，保留历史；支持 Edge CSV 导入。
- **交接准备**：查看授权总览，逐项核对实际输出，独立运行本机状态模拟。
- **备份与恢复**：导出完整性认证的 `.lvault` 加密备份，在首次使用或锁定时恢复；替换前核对备份时间和范围。
- **可选 AI**：端侧中文 OCR、独立手工整理，以及检查外发文本后按次授权的 AI 整理。AI/OCR 结果先成为草稿。

| 记录 | 交接准备 |
| --- | --- |
| <img src="work/paper/uiux-review-2026-10-01/implementation-screenshots/04-home-draft.png" width="280" alt="记录首页与待整理入口"> | <img src="work/paper/uiux-review-2026-10-01/implementation-screenshots/16-handoff-overview.png" width="280" alt="交接授权与保持私密内容总览"> |

界面示例使用虚构测试资料。[更多运行截图](work/paper/uiux-review-2026-10-01/截图索引.html)及 [验证证据](docs/60_quality/00_测试与验证策略.md)在仓库中保留。

## 下载和安装

Android 7 / API 24 及以上。安装包通过 [GitHub Releases](https://github.com/BA2F/LiveRelay/releases) 分发，不放入 Git 源码历史。

| 里程碑 | 用途 | 发布页 |
| --- | --- | --- |
| MVP 0.2 | 推荐的侧载验收包 | [下载 APK 与校验文件](https://github.com/BA2F/LiveRelay/releases/tag/mvp-0.2) |
| MVP 0.1 | 首个可运行版本的原包归档 | [历史安装包](https://github.com/BA2F/LiveRelay/releases/tag/mvp-0.1) |

下载 APK 和同页的 `SHA256SUMS`，在下载目录执行 `sha256sum -c SHA256SUMS` 核对文件，然后在 Android 设备上安装。两版使用同一包名和证书，可覆盖安装；不要通过卸载来升级，卸载会清理本机资料库。

这些 MVP 包标记为预发布，使用 Android Debug 证书供侧载验收。里程碑名称与 APK 内部版本分别记录，详情见 [版本记录](CHANGELOG.md)及各发布页。

## 开始使用

1. 创建加密资料库，妥善保管口令；已有 `.lvault` 时可直接恢复。
2. 在“记录”选择“记一条”。“先保存”加密存入待整理；内容已核对时可明确确认保存。
3. 在“卡片”搜索、整理并回看来源；删除的内容可以到设置中的回收区恢复。
4. 定期导出加密备份，另存到设备外并实际验证恢复。口令无法找回，指纹不能代替换设备时的恢复口令。
5. 在“交接”查看授权及精确预览。默认仅本人可见，改变授权前先核对输出。

## 数据与隐私

结构化资料使用 SQLCipher 整库加密；主密码通过 Argon2id 派生，随机主密钥和原件使用 AES-256-GCM 保护。修订、来源和原件在本机保留。技术依据见 [安全设计](docs/30_design/security/00_安全设计总览.md)。

云 AI 默认未配置，每次调用均须检查并授权。被本人标记的敏感文字先替换为 Token；**未标记文字仍会按预览发送**。原图、音视频、Token Map 和其他资料库条目不交给 AI Provider。手工整理可以独立完成。

交接目前是本机模拟及演示执行人，尚不提供真实接收者、远程发放、现实状态核验或自动交接。实体生物识别/媒体硬件、真实 AI 服务及安全复核的完成情况以 [验证记录](docs/60_quality/00_测试与验证策略.md)为准。

## 开发与仓库导航

Flutter/Android 应用在 [`work/code/live_relay/`](work/code/live_relay/)；安装开发环境、运行、测试和构建见 [应用开发说明](work/code/live_relay/README.md)。

| 位置 | 内容 |
| --- | --- |
| [docs/10_overview](docs/10_overview/) | 项目定位和系统总览 |
| [docs/20_product](docs/20_product/) | 产品设计 |
| [docs/30_design](docs/30_design/) | 架构、领域、来源、安全、AI 与交接设计 |
| [docs/40_modules](docs/40_modules/) / [docs/50_interfaces](docs/50_interfaces/) | 实现模块与内部端口映射 |
| [docs/60_quality](docs/60_quality/) | 验证策略、证据和版本制品记录 |
| [tasks](tasks/) / [handoffs](handoffs/) | 执行看板和交接事实 |
| [work](work/) | 应用源码、图示和报告成果 |
| [notes](notes/) / [records](records/) / [archive](archive/) | 讨论、决策原因和历史材料 |

开发协作先读 [AGENTS.md](AGENTS.md)。已确认设计是事实源；README 和发布页提供入口与输出视图，不另立一套产品契约。版本差异见 [CHANGELOG](CHANGELOG.md)，制品与发布约定见 [RELEASING](RELEASING.md)。
