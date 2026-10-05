# LiveRelay MVP0.4 总体架构图

图版 v1.0，2026-10-04。采用C4静态层级，补充部署、数据／安全、工作流、时序和状态／事务视图。源码基线 `6fbee32819fdc50413f80ec8e8561c450a0b4735`（MVP0.4，1.0.0+3），文档基线 `a586349b9b5693084d74deeac5317d5a0ae7df0b`。开始时Linux工作区干净，HEAD及两条远端分支一致。本次只写图示目录，未提交或上传。

## 打开与阅读

主产物：[原生11页.drawio](LiveRelay-MVP0.4-system-architecture.drawio)。本机draw.io 30.2.4可直接打开，底部页签切换。业务节点、边界、文字、连线均为原生mxGraph对象；没有截图或位图节点。画布／页脚装饰锁定，业务图形可编辑和重新连线。

整套：[11页PDF](LiveRelay-MVP0.4-system-architecture.pdf)。逐页 [PNG目录](png/)（2702×1682）与 [SVG目录](svg/)（含原生图数据）同步导出。字体Noto Sans CJK SC；PNG／PDF适合固定展示，另一台机器查看SVG可能依赖相同字体及foreignObject支持。

| 页 | 视图 | 重点 |
| --- | --- | --- |
| 01 | 系统上下文／C4 L1 | 参与者、外部能力与规划边界 |
| 02 | 应用与存储／C4 L2 | 单客户端部署、工作isolate、Owner／Recipient目录 |
| 03 | 组件／C4 L3 | 分层、内部端口、组合根、渐进依赖反转 |
| 04 | 部署 | Android／Linux实测范围、Windows待验、独立演示 |
| 05 | 数据与安全 | Header分支、VMK所有权、SQLCipher／Blob、来源 |
| 06 | 采集与语音 | 原件、端侧OCR／SenseVoice、关联草稿 |
| 07 | Agent时序 | 单次授权、Token、隔离工具、确认保存与后置缺口 |
| 08 | 身份绑定时序 | 指纹核对、HPKE挑战、Ed25519响应 |
| 09 | 范围交接 | 精确字段／历史／原件、签名封装、只读接收 |
| 10 | 分层备份 | 同快照认证、受限恢复、缺失状态、补充重加密 |
| 11 | 恢复与换钥 | 会话状态、staging安装、提交点、中断与清理 |

## 统一图例与口径

绿色实线为运行调用／数据流；灰色虚线为代码依赖（依赖者指向被依赖者）；紫色点线为组合装配／注入；橙色实线为本人授权或凭证动作。虚线边界不默认代表进程或独立部署。节点浅色：绿为应用，蓝为核心，灰为存储／适配，棕为人，橙为授权／限制，粉为外部信任域；灰色虚线节点为规划。

`[实现]`表示有代码，`[现场]`表示特定代表链路有现场证据，`[待验]`表示额外硬件／平台／正式安全验收尚未完成，`[规划]`表示当前未实现。内部端口、新格式均未冻结为第三方契约。现场标记不得推断为所有功能／平台已验收。

- 单Flutter package是模块化单体；逻辑模块和Dart isolate不是微服务。
- VMK由VaultSession及受控安全／备份工作流使用；存储实现按操作接收必要临时材料。AppController、UI和网络AI不持有VMK。
- Owner／Recipient身份、私钥、密码、目录、会话独立，切换先锁Owner；接收者只取得授权快照。
- AI仅发送预览获准文本，人工标记敏感行才替换Token；Token Map留本机。Agent只保存LifeCard，Credential候选／转换后置，普通正文密码不是Secret字段。
- 新建Header v3、schema v5；旧Header主动升级，与数据库schema自动迁移不同。
- 独立R及v3备份恢复先进入受限重设；凭证／策略变更换VMK并重加密数据库和实际存在的原件。缺失原件专用旧钥仅存加密状态。
- 真实手动交付与生命状态模拟分离，已交付副本无法远程撤回；云端／同步／摇篮／外部Agent仅为规划。

## 来源与差异

[来源索引](evidence-index.md)映射44个正式文档／源码锚点；[JSON索引](evidence-index.json)包含版本、原生cell ID、来源编号、路径、行号。原生mxCell的`evidence`属性与索引一致。

索引末尾记录5项文档／实现表述差异，包括安全11旧验收状态、安全10“保留旧副本”与正常成功清理实现、Header与schema迁移区别。本次记录证据，没有改变应用源码、稳定契约或已确认架构原则。

## 再生成与验收

生成器只读源码／文档定位锚点，不读取真实资料库或私人Key；只写本目录。基线变化时须先更新版本和事实。直接在draw.io人工编辑后，重新生成会覆盖主文件，需先保留人工版本。

在项目根目录运行：

```bash
python3 work/diagrams/architecture/build_architecture.py
python3 work/diagrams/architecture/export_architecture.py
```

导出使用本机`/usr/bin/drawio`。可给导出器传页码只重导受影响图片，整套PDF始终重导。页索引从1开始。

结构检查见[native-structure-check.json](native-structure-check.json)，导出／PDF检查见[qa/verification.json](qa/verification.json)，逐页观察记录见[qa/visual-review.md](qa/visual-review.md)。检查包括中文、文字越界、线条穿字、裁切、版本和分页；已修正首轮发现的文字空间／连线落点。PDF由Poppler实际渲染后复核，11页标题／页码／版本完整，中文字体嵌入且有Unicode映射。Wayland／GLib诊断不影响本次返回0的实际导出。
