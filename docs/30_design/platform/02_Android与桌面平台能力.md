# Android 与桌面平台能力

> 状态：讨论中  
> 版本：0.4  
> 最后更新：2026-09-06  
> 依赖文档：platform/00_应用实现架构总览.md


## 统一能力方向

Android/Desktop 通过统一平台能力边界提供：

- Keystore；
- Biometric；
- Camera；
- File Picker；
- 文件系统；
- 网络访问。

## Android 重点

- Camera；
- Keystore；
- Biometric；
- Secure Screen；
- 自动锁定。

成熟插件优先。

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

- 平台能力最小接口；
- Android 与 Desktop 哪些能力真正需要统一；
- Secure Screen/KeyStore 等功能的插件选型；
- Desktop 的安全存储实现。

## 历史来源

- `docs/10_platform/03_平台能力抽象.md`
- `docs/10_platform/04_Android能力适配.md`
- `docs/10_platform/05_桌面端能力适配.md`
- `docs/10_platform/06_数据库访问实现.md`
- `docs/10_platform/07_文件系统实现.md`
- `docs/10_platform/08_网络访问实现.md`
