# 版本记录

记录对使用者有影响的版本变化。安装包、校验文件和最终发布说明以 [GitHub Releases](https://github.com/BA2F/LiveRelay/releases)为准；制品身份另见 [发布记录](docs/60_quality/releases/)。

## MVP 0.2 — 2026-10-02

[Release](https://github.com/BA2F/LiveRelay/releases/tag/mvp-0.2) · [完整版本说明](docs/60_quality/releases/mvp-0.2.md)

- 修复搜索影响首页、状态/按钮对比度和 Android 备份导出。
- 轻量加密记录、待整理、同卡片修订、完整来源/原件、类型筛选和准确空状态。
- 删除撤销/回收恢复，首次使用与锁定恢复备份，认证后核对范围和替换影响。
- 中文 AI 外发检查、单次授权和独立手工路径。
- 交接准备总览、六级授权精确预览、密码默认遮挡、独立本机模拟。
- 小屏、大字体、明暗主题、键盘与主要可访问性调整。
- 静态分析、38 项测试、Android 完整路径与原生系统走查通过；数据和备份格式保持兼容。

## MVP 0.1 — 构建于 2026-09-23，归档发布于 2026-10-02

[Release](https://github.com/BA2F/LiveRelay/releases/tag/mvp-0.1) · [完整版本说明](docs/60_quality/releases/mvp-0.1.md)

首个可运行 Android MVP：本地加密资料库、四主导航、卡片/密码库/历史、媒体采集/回看、端侧 OCR、AI 隐私流水线、本机交接演示及 `.lvault`。保留当时原 APK，未重新构建。历史记录为 25 项测试及模拟器验证通过。

两版均为 Debug 证书签名的预发布里程碑。`mvp-0.1` / `mvp-0.2` 表示里程碑；为保留原构建，两版 APK 内部版本都为 `1.0.0+1`，不据此宣称正式 1.0 发布。
