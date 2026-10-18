# Android 与桌面平台能力

> 状态：已确认  
> 版本：0.8
> 最后更新：2026-10-18
> 依赖文档：platform/00_应用实现架构总览.md


## 当前统一边界

MVP 只为确实需要替换的能力定义端口：

- `BiometricKeyStore`：生物识别保护的 VMK 保存/读取；
- `OcrProvider`：图像 bytes → OCRResult；
- `AiProvider`：脱敏文本 → Provider 响应；
- 正式基础新增 `SpeechProvider` 与 `AgentCommandProvider`，分别承接实际本地模型和 Linux 隔离命令。

Camera、File Picker、录音、播放和文件系统当前封装在表现层/基础设施层，不为了假想统一提前抽象成公共端口。

## Android 重点

- Camera/相册和录像：`image_picker`；
- 录音：`record`；
- 生物识别和 Android Keystore：`local_auth` + `flutter_secure_storage` biometric options；
- 文件导入导出：`file_picker`；
- 音视频回看：`just_audio` + `video_player`；
- 中文 OCR：Google ML Kit。

Secure Screen 与后台自动锁定尚未实现。复制密码后 30 秒会尝试清空仍等于该密码的剪贴板内容；这不能清除系统剪贴板历史或其他应用已取得的副本。

## Desktop 重点

2026-10-03 已完成 Linux 桌面第一切片：发布构建、原生临时加密库端到端回归、宽屏侧栏、统一卡片视图、首次设置及外观偏好。

2026-10-18 在 `main` 上完成 Windows 桌面适配：Windows 11 的 debug 与 release 构建、启动、生产入口首次设置到进入工作台（偏好、Header v3、SQLCipher 数据库）均已在本机验证。内嵌 PDF 与音视频预览仍只在 Linux 播放后端启用，其他平台显示不支持。Windows 指纹、Windows 密钥环存储、正式签名与分发未验收。

同一轮把文件提交对 `rename` 的隐含假设收口到 `core/storage/file_commit.dart`：先尝试原子 rename，平台拒绝元数据重命名时退化为覆盖写入后删除 sidecar，目录退化为递归复制后删除暂存目录。目录提交拒绝覆盖已存在目标。退化路径不是原子替换，裁判仍是调用方保留的已 flush 前序副本与安装后的核对，`.tmp` 不进归档、无法安全判断时保留文件的约定不变。

`application/device_capabilities.dart` 提供内部能力状态，普通 UI 保留不可用入口。当前 Linux／Windows 相机、ML Kit OCR、设备生物解锁及音视频播放显示设备不支持；导入和原件留存仍可使用。Agent 在 Responses 配置完成后显示可用，语音根据本地模型是否安装显示需配置／可用；报平安和拆分备份仍未提供。Linux 命令需真实探测并按本次授权，其他平台尚未实现该工具。状态表不代替实际麦克风权限、模型资源或硬件验收。

- 批量整理；
- 文件导入；
- 调试；
- 大屏管理。

长期产品方向可以概括为：

> Mobile Capture + Desktop Organize

## 2026-10-03 Agent／语音平台事实

Responses 文字整理不依赖本机模型，可在当前移动／桌面入口配置使用。Linux 使用可用的 bubblewrap user namespaces／Bash／prlimit，探测失败不运行宿主命令；没有 Windows 沙箱实现。

本地语音原生库已接入 Android／Linux／Windows，Linux 真模型及公开样本运行通过，Android／Linux release 构建通过。Android 实体录音和手机资源、Windows 构建／运行尚未验收。模型权重需主动下载或导入，首次未安装时显示真实状态。详见 [Agent](../ai/05_内置Agent与隔离命令.md)及 [语音](../capture/03_本地语音输入.md)。

## 其他基础设施原则

- Life Core 不直接依赖具体数据库 API；
- 文件系统负责加密 Blob、临时文件、导出路径和原子写入；平台拒绝原子替换时使用可核对的退化提交；
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
