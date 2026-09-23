# 图片采集与本地 OCR

> 状态：已确认  
> 版本：0.5  
> 最后更新：2026-09-23  
> 依赖文档：capture/00_采集系统总览.md, provenance/01_原始资料与转换链.md


## 图片采集

MVP 已支持：

- Android Camera / 相册输入；
- 原图 AES-GCM 加密保存；
- 应用内解密预览；
- 采集插件临时文件在导入后清理；
- 启动时再次清理已知媒体/OCR 临时缓存。

原图加密方式和 256 MB 单文件上限由 `security/04_加密数据库与原始资料安全.md` 定义。原件删除及其衍生来源链清理尚未完整实现。

## OCR

首版采用 Google ML Kit Chinese Text Recognition，通过 `OcrProvider` 与核心隔离，不追求多 Provider 并行。当前实现仅在 Android/iOS 可用，桌面端调用会明确拒绝。

OCR 结果至少需要：

- 文字；
- Bounding Box；
- 置信度；
- 阅读顺序。

OCR 接口与具体模型实现应分离。

ML Kit 需要文件路径，因此实现会在系统临时目录创建随机命名图片，识别结束后在 `finally` 中删除。结果按 block/line 阅读顺序展平，保存每行文字、原图坐标 bbox、可用时的置信度和顺序。

## 当前开放问题

- 旋转/缩放后的 bbox 映射；
- OCR 失败和部分结果的表示；
- OCR 临时文件在进程被强杀瞬间的通用清理保障；
- 桌面 OCR Provider 和跨平台坐标一致性；
- 原件删除、OCR 中间产物与草稿来源链的清理策略。

## 历史来源

- `docs/07_capture/01_图片采集流程.md`
- `docs/07_capture/02_本地OCR架构.md`
- `docs/07_capture/03_OCR文字与坐标模型.md`
