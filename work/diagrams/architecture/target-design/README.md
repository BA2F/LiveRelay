# LiveRelay 总体目标架构

日期：2026-10-04；设计版本：v1.0。

## 单张提交

主图把参与者、客户端逻辑分层、核心模块、加密数据、平台适配、连续性服务、外部 AI、安全治理和非功能目标汇在一张图上。

- [系统总体架构 PNG](LiveRelay-系统总体架构.png)：3602 × 2552，可直接作为图片提交。
- [系统总体架构 PDF](LiveRelay-系统总体架构.pdf)：单页 A3 横向，适合打印和文档附件。
- [系统总体架构 draw.io](LiveRelay-系统总体架构.drawio)：原生单页，节点、文字、边界和连接均可编辑。
- [系统总体架构 SVG](LiveRelay-系统总体架构.svg)：矢量导出，附带可回读的原生图源；显示中文需要支持字体和 HTML 标签的浏览器。

## 五张完整视图

[多页 draw.io](LiveRelay-总体目标架构.drawio) 与 [五页 PDF](LiveRelay-总体目标架构.pdf) 顺序一致：

| 页 | 视图 | 主要内容 | PNG | SVG |
|---|---|---|---|---|
| 1 | 系统总体架构 | 全系统层次、参与者、服务与信任边界 | [图片](png/01-system-overview.png) | [矢量](svg/01-system-overview.svg) |
| 2 | 业务架构 | 业务目标、场景、价值链、能力和业务对象 | [图片](png/02-business.png) | [矢量](svg/02-business.svg) |
| 3 | 应用架构 | 模块化单体、应用用例、内部端口、组合根和会话隔离 | [图片](png/03-application.png) | [矢量](svg/03-application.svg) |
| 4 | 数据架构 | 来源、处理、逻辑对象、存储所有权与授权消费 | [图片](png/04-data.png) | [矢量](svg/04-data.svg) |
| 5 | 技术架构 | 终端框架、识别与 Agent、密码技术、持久化、部署协议 | [图片](png/05-technology.png) | [矢量](svg/05-technology.svg) |

这些图表达项目总体目标，图内不包含研发完成度或验收状态。云端标注“可选”，表示本地独立运行、自部署与托管的产品拓扑选择。上一组 MVP0.4 实现映射图保留在上级目录，便于分别使用。

## 阅读语义

蓝色实线表示调用或数据流，橙色实线表示授权或投递控制，灰色虚线表示依赖，虚线框表示逻辑分层、应用边界或信任边界。客户端各层属于同一个 Flutter package 的逻辑模块。云端边界表示另一个部署与信任域。

Owner（所有者）控制运行库与 VMK。Recipient（接收者）使用独立身份、私钥、目录和会话，只解密被授权的快照。协助录入、对象关联、来源关联和分组不会自动扩大查看权限。

外部 AI 接收本次预览获准的文本，敏感标记行以 Token 替代；Token Map、VMK 和原件保留在本机。普通摘要不包含 Secret。原件、来源、修订、事实确认与 AI 推断保持可追溯关系。

连续性服务保存密文和必要调度信息；Owner VMK 与恢复凭证保留在本人侧。预授权投递由调度控制，接收者通过自有私钥解密。持有完整信封的投递方属于被信任的投递角色；图中没有将时间或状态标签解释为密码学强制时间锁。无响应进入提醒与宽限流程，不直接认定失能或身故。

## 设计依据与复现

内容依据项目产品、领域、架构、来源追踪、AI 隐私和密钥设计，重点节点及连线见 [来源索引](design-index.md)，完整节点映射见 [JSON 索引](design-index.json)。[参考文章](https://blog.csdn.net/kunwen123/article/details/122854209)仅用于借鉴业务、应用、数据、技术视角的组织方式；图形与项目内容重新绘制。

使用本机 draw.io 30.2.4 实际导出 PNG、SVG 和 PDF。PDF 字体嵌入并保持 Unicode 文本，统一为 A3 横向。原生图源用标准 mxGraph XML，不以截图替代节点。

```bash
python3 work/diagrams/architecture/target-design/build_target_architecture.py
/home/tahzun/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3 work/diagrams/architecture/target-design/export_target_architecture.py
/home/tahzun/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3 work/diagrams/architecture/target-design/verify_target_exports.py
```

导出记录和页面检查位于 `qa/`，最终文件校验和位于 `SHA256SUMS`。直接在 draw.io 编辑交付文件时，不要再次运行生成器覆盖人工修改。
