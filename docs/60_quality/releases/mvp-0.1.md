# LiveRelay · MVP 0.1 — 首个可运行版本

历史构建日期：2026-09-23。本次补录首次构建的原 APK，未重新打包。

## 能力

- Android 四个主导航：记录、卡片、密码库、交接。
- Argon2id 主密码派生、SQLCipher 整库加密、AES-GCM 原件 Blob、中文词组口令及指纹密钥槽。
- 卡片与密码库、修订历史、拆分组合、Edge CSV 导入、照片/录音/录像导入与回看。
- 端侧中文 OCR、人工敏感标记、脱敏文本 AI 单次授权和草稿保存。
- 本机生命状态与交接演示、释放策略、`.lvault` 加密备份与恢复。

## 历史验证与边界

2026-09-23 记录：静态分析、25 项测试、Android 16 模拟器路径、数据库 v1 → v4 迁移、APK v2 签名验证通过。真实 AI 服务、实体生物识别与媒体硬件仍需验证。

这是历史 MVP，推荐安装 [MVP 0.2](https://github.com/BA2F/LiveRelay/releases/tag/mvp-0.2)。其搜索共享状态、回收入口、授权预览和 Android 备份导出问题已在 MVP 0.2 修复；本版保留用于追溯。交接仅本机演示，包使用 Android Debug 证书，不是商店正式发行包。

## 制品记录

- Tag：`mvp-0.1`；首个 MVP 源码提交：`4b4032e15c276ec4806b087b1a0f8a832bc488e6`。
- 原始文件：`LiveRelay-MVP-2026-09-23.apk`；附件：`LiveRelay-MVP0.1-Android.apk`。
- 大小：107,919,086 bytes；Android 7/API 24+，target API 36。
- 包名：`app.liverelay.live_relay`；APK 内部版本：`1.0.0` / versionCode `1`。
- SHA-256：`3cb8c581a01293ef91a07d7e8b9c7d6859b37bcd9ed1f743b6bab883dc31abf1`。
- 签名证书 SHA-256：`71bf52ae69bf468f2a2257d81a3a6c5e2c1c0a9a91582925a7e7e82714b2e314`。

`MVP 0.1` 是里程碑名称，不等同 APK 的内部版本。附件 `SHA256SUMS` 可用于校验原文件。历史安装包的源码基线和历史验证可追溯，不宣称历史构建环境可逐字节复现。
