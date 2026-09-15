# 图片采集与本地 OCR

> 状态：讨论中  
> 版本：0.4  
> 最后更新：2026-09-06  
> 依赖文档：capture/00_采集系统总览.md, provenance/01_原始资料与转换链.md


## 图片采集

当前需要考虑：

- Camera / 相册输入；
- 原图加密保存；
- 预览；
- 失败恢复；
- 删除。

原图加密的具体方式由 `security/` 定义。

## OCR

首版优先采用一个成熟的本地 OCR Provider，不追求多 Provider 并行。

OCR 结果至少需要：

- 文字；
- Bounding Box；
- 置信度；
- 阅读顺序。

OCR 接口与具体模型实现应分离。

## 当前开放问题

- 首版 OCR Provider 选择；
- 坐标系规范；
- 旋转/缩放后的 bbox 映射；
- OCR 失败和部分结果的表示；
- Capture/OCR 的物理模块关系。

## 历史来源

- `docs/07_capture/01_图片采集流程.md`
- `docs/07_capture/02_本地OCR架构.md`
- `docs/07_capture/03_OCR文字与坐标模型.md`
