# Android 与桌面平台能力

> 状态：已确认  
> 版本：0.5  
> 最后更新：2026-09-23  
> 依赖文档：platform/00_应用实现架构总览.md


## 当前统一边界

MVP 只为确实需要替换的能力定义端口：

- `BiometricKeyStore`：生物识别保护的 VMK 保存/读取；
- `OcrProvider`：图像 bytes → OCRResult；
- `AiProvider`：脱敏文本 → Provider 响应。

Camera、File Picker、录音、播放和文件系统当前封装在表现层/基础设施层，不为了假想统一提前抽象成公共端口。

## Android 重点

- Camera/相册和录像：`image_picker`；
- 录音：`record`；
- 生物识别和 Android Keystore：`local_auth` + `flutter_secure_storage` biometric options；
- 文件导入导出：`file_picker`；
- 音视频回看：`just_audio` + `video_player`；
- 中文 OCR：Google ML Kit。

Secure Screen、后台自动锁定和剪贴板自动清理尚未实现，不能计入当前 Android 安全能力。

## Desktop 重点

- 批量整理；
- 文件导入；
- 调试；
- 大屏管理。

长期产品方向可以概括为：

> Mobile Capture + Desktop Organize

## 其他基础设施原则

- Life Core 不直接依赖具体数据库 API；
- 文件系统负责加密 Blob、临时文件、导出路径和原子写入；
- 网络只服务明确功能，Local-first 下应能够审计联网行为。

## 当前开放问题

- 实体 Android 设备上的强生物识别、权限和厂商 ROM 行为；
- Secure Screen、生命周期自动锁定和剪贴板清理策略；
- Android 与 Desktop 哪些 UI/媒体能力经过实践后值得统一；
- Desktop 的安全存储实现。

## 历史来源

- `docs/10_platform/03_平台能力抽象.md`
- `docs/10_platform/04_Android能力适配.md`
- `docs/10_platform/05_桌面端能力适配.md`
- `docs/10_platform/06_数据库访问实现.md`
- `docs/10_platform/07_文件系统实现.md`
- `docs/10_platform/08_网络访问实现.md`
