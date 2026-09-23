# OCR 坐标与人工字段标注

> 状态：已确认  
> 版本：0.5  
> 最后更新：2026-09-23  
> 依赖文档：capture/01_图片采集与本地OCR.md


## 本文是首版人工标注类别的定义所有者

当前首版人工标注类别：

- `Account`
- `Secret`
- `Money`
- `Note`

后续才考虑人物、地址、证件等更多类型。

AI Privacy 可以依据这些类别生成 Token，但不在 AI 子域维护另一套字段分类。

## MVP 交互

首版选择**整条 OCR line** 作为标注粒度。用户在 AI Privacy 面板中为每行选择 `Account`、`Secret`、`Money`、`Note` 或“不替换”，标记以行顺序关联并加密保存。

OCR line 保存 ML Kit 返回的 left/top/right/bottom 原图坐标、置信度和阅读顺序。当前 UI 尚不提供自由框选、字符区间、涂抹、错框修正或区域合并/拆分；这些仍是后续交互方向。

OCR 只是草稿，不应自动提升为正式事实。

OCR 结果不能脱离原图；Provenance 需要能够指回原图及具体区域。

## 当前开放问题

- 从 line 标注升级到字符区间或自由区域的兼容方式；
- 图片旋转、EXIF 和缩放显示后的 bbox 映射；
- 人工修改后怎样保留原 OCR 和修订关系；
- `Note` 中哪些内容需要视作敏感内容。

## 历史来源

- `docs/07_capture/04_图片字段框选与涂抹交互.md`
- `docs/07_capture/05_账号密码金额备注字段标注.md`
- `docs/07_capture/06_OCR纠错与人工确认.md`
- `docs/07_capture/07_原始图片与OCR结果关联.md`
