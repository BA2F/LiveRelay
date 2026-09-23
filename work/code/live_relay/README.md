# LiveRelay MVP（留灯）

LiveRelay 是一个 local-first 的人生信息连续性工具。当前 MVP 优先 Android，核心领域、仓储端口和 Provider 端口不依赖 Android UI，为后续桌面端保留替换边界。

## 已有能力

- Argon2id 主密码派生、AES-256-GCM VMK 封装、SQLCipher 整库加密；
- 中文随机词组口令与拼音解锁，Android Keystore 指纹密钥槽；
- 卡片增改查、标签搜索、草稿确认、拆分/组合、不可覆盖的修订历史与来源链；
- 密码库的显示/复制/历史/回收/彻底删除，Edge 原生 CSV 导入；
- 照片、录音、录像的导入或现场采集，AES-GCM 原件 Blob 与安全回看；
- 端侧中文 OCR（文本、bbox、置信度、顺序），结果只生成待确认草稿；
- AI Privacy：行级 Account/Secret/Money/Note 人工标记、本地 Tokenization、单次授权、OpenAI-compatible Provider、Schema/Token 校验与本地复原；
- Active / Incapacitated / Deceased 状态演示、显式释放策略与 Executor View；
- 完整性认证的 `.lvault` 加密备份、导出和原子恢复。

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

2026-09-23 的本机验证结果：

- `flutter analyze` 无问题；
- `flutter test` 共 25 项，全部通过；
- Android 16 模拟器完成数据库 v1 → v4 迁移、覆盖安装和冷启动；
- 图片、相机、中文 OCR、录音/播放、视频回看和临时文件清理已运行验证；
- Release APK 构建及 v2 签名校验通过；验收包使用 Debug 证书，不可直接上架。

## 安全与当前边界

- 云 AI 默认未配置、未授权；每次调用都必须由用户查看范围并选择“仅允许本次”。
- 原图、音视频、Token Map 和密码原文不发给 AI Provider；不合法或遗漏/重复/伪造 Token 的返回会被拒绝。
- 音视频回看期间会生成受控临时文件，退出即删除，启动时再清理已知异常遗留。
- 当前交接是本地演示流程，不代表现实世界的失能/身故核验、法律效力或远程发放。
- 音频转写、视频理解、自动填充、真实同步与桌面媒体 Provider 不在当前 MVP 内。
- 指纹密钥槽已接入和编译，但需在已录入强生物识别的实体 Android 设备上做最终硬件验证。
