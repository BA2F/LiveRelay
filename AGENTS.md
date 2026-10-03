# LiveRelay AI Agent 工作规则

> 状态：当前有效  
> 版本：0.7
> 最后更新：2026-10-03
> 依赖文档：无


## 事实源

优先级：当前人类指令 > 已确认/冻结 docs > 论证完整且已接受 ADR > 当前 Task Spec > memory > notes > archive。

## 当前项目状态

LiveRelay 源码位于 `work/code/live_relay/`。正式版本机软件基础已完成密码库生成、Agent／语音，以及独立恢复、更多解锁／全库换钥、身份／独立接收者、真实限定范围交接、本地分层备份、独立调试演示。主界面新建 Header v3、SQLCipher schema v5；旧库由本人主动升级。硬件／Windows／手机资源／正式签名及安全复核仍待完成，云端和语言／视觉优化后置。内部端口和新格式尚未冻结为跨 package 或对外公共契约；模块文档是实现映射，不代表已拆 package。

新聊天从 `memory/当前项目上下文.md` 和 `handoffs/2026-10-03_本机安全交接与备份完成.md` 接续，已确认产品范围见 `docs/20_product/16_正式版演进与已确认范围.md`。先检查Git真实状态；本机功能源码已提交为 `9cf2768`，按人类要求推送到main和 `codex/formal-foundation`，MVP0.3预发布提供正常Android／Linux制品。发布记录见 `docs/60_quality/releases/mvp-0.3.md` 和 `artifacts.json`；后续文档提交不移动Tag，不沿用旧交接的未提交状态。

## 执行环境

- 唯一允许修改项目文件和运行开发任务的工作区是 Linux：`/home/tahzun/Development/Projects/LiveRelay`；
- Mac 仅作为 SSH 控制端，不在 Mac 项目副本中继续修改代码或文档；
- GitHub `main` 用于在控制端与 Linux 工作区之间同步已提交事实；开始任务前先确认 Linux 工作区和远端状态。

## 读取纪律

叶子开发任务通常读 4～6 篇，复杂尽量 ≤8；叶子设计任务通常读 5～8 篇，复杂尽量 ≤10。不要无目的扫描整个仓库。

## 执行纪律

- 没有真实内容，不创建占位 Markdown；
- 只有经过真实重复工作验证的流程才进入 `skills/`；
- 稳定契约不得由叶子 Agent 私改；
- 实现发现契约不足时进入阻塞并向上反馈；
- Task 完成后按需要写 Handoff，并回写真实设计变化。

详细规则见 `docs/00_governance/`。
