# LiveRelay MVP（留灯）

LiveRelay 是一个 local-first 的人生信息连续性工具。当前 MVP 优先 Android，核心领域、仓储端口和 Provider 端口不依赖 Android UI，为后续桌面端保留替换边界。

## 已有能力

- Argon2id 主密码派生、AES-256-GCM VMK 封装、SQLCipher 整库加密；
- 中文随机词组口令与拼音解锁，Android Keystore 指纹密钥槽；
- 轻量记录的加密“先保存”和本人确认保存、待整理入口、独立搜索和类型/状态筛选；
- 卡片原位编辑、不可覆盖的修订历史、拆分/组合、完整来源片段及原件链接、回收/恢复；
- 密码库的显示/复制/历史/回收/彻底删除，Edge 原生 CSV 导入；
- 照片、录音、录像的导入或现场采集，AES-GCM 原件 Blob 与安全回看；全部原件搜索/筛选、查看与手工整理；
- 端侧中文 OCR（文本、bbox、置信度、顺序），结果只生成待确认草稿；
- AI Privacy：行级 Account/Secret/Money/Note 人工标记、本地 Tokenization、单次授权、OpenAI-compatible Provider、Schema/Token 校验与本地复原；
- 交接准备总览、全部六级授权的精确输出预览、默认遮挡密码和独立本机状态模拟；
- 完整性认证的 `.lvault` 加密备份、成功导出记录、首次使用/锁定时恢复和恢复前核对；
- 中文界面与 AI 外发原文/发送文本对照，320dp 小屏、200% 字体和系统深色主题。

## 分层

```text
presentation/       Material 3 UI 与原子组件
application/        用例编排、会话密钥生命周期
core/domain/        卡片、原件、交接、敏感标记模型
core/ports/         Vault / OCR / AI / Biometric 端口
core/security/      中文口令与 Vault 密钥管理
infrastructure/     SQLCipher、Blob、OCR、AI、备份、平台适配器
```

## 本地开发

```bash
cd /home/tahzun/Development/Projects/LiveRelay/work/code/live_relay
flutter pub get
dart run build_runner build
flutter analyze
flutter test
flutter run -d emulator-5554
```

Android 需 API 24+。数据库必须检测到 SQLCipher，不会静默降级成明文 SQLite。

## 最近验证

2026-10-02 的验证结果：

- `flutter analyze` 无问题，`flutter test` 38 项全部通过；
- Android 16 模拟器完整 UI 集成回归通过，真实 SQLCipher/Blob/端侧 ML Kit OCR；AI 使用离线测试 Provider，验证实际外发范围及单次授权；
- 搜索隔离、草稿/修订/来源、撤销/恢复、备份核对与替换、六级授权输出、默认遮挡密码均有行为回归；
- 明暗主题、320dp/200% 字体及键盘布局、主要操作读屏标签/触控尺寸/对比度的 Widget 验证通过；
- Release APK 构建及 v2 签名校验通过；验收包仍使用 Debug 证书，仅供内部侧载。

完整范围、截图、命令和限制见 [实施与验证交付](../../paper/uiux-review-2026-10-01/实施与验证交付.md)。2026-09-23 已有数据库 v1 → v4、图片/相机/录音/视频及清理的设备验证记录；本次没有 schema 升级。

Debug 构建使用独立 Android 包名 `app.liverelay.live_relay.verification`，避免测试安装覆盖正式资料库。Release 保持原包名。运行集成回归：

```bash
flutter drive --driver=test_driver/ux_driver.dart --target=integration_test/ux_flow_test.dart -d emulator-5554
```

该回归生成虚构资料并保存截图到上述交付目录，不携带示例资料到正式应用。

## 安全与当前边界

- 云 AI 默认未配置、未授权；每次调用都必须由用户查看范围并选择“仅允许本次”。
- 原图、音视频、Token Map 和其他资料库条目不发给 AI Provider；本人标记的敏感文字先替换为 Token。未标记文字仍会按外发预览发送，需逐次核对；不合法或遗漏/重复/伪造 Token 的返回会被拒绝。
- 音视频回看期间会生成受控临时文件，退出即删除，启动时再清理已知异常遗留。
- 当前交接是本地演示流程，不代表现实世界的失能/身故核验、法律效力或远程发放。
- 音频转写、视频理解、自动填充、真实同步与桌面媒体 Provider 不在当前 MVP 内。
- 指纹密钥槽已接入和编译，但需在已录入强生物识别的实体 Android 设备上做最终硬件验证。
