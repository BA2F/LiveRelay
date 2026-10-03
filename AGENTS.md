# LiveRelay AI Agent 工作规则

> 状态：当前有效  
> 版本：0.5
> 最后更新：2026-10-03
> 依赖文档：无


## 事实源

优先级：当前人类指令 > 已确认/冻结 docs > 论证完整且已接受 ADR > 当前 Task Spec > memory > notes > archive。

## 当前项目状态

LiveRelay 已完成首个可运行的 Flutter/Android MVP，源码位于 `work/code/live_relay/`。当前开始正式版分阶段开发：首个基础切片及创建密码校验修正已完成，Android／Linux 构建通过，Windows runner 已准备但未在 Windows 验证；真机验证与安全复核仍待完成。内部端口尚未冻结为跨 package 或对外公共契约。`40_modules/` 和 `50_interfaces/` 记录当前实现映射，不代表模块已经拆成独立 package。

新聊天从 `memory/当前项目上下文.md` 和 `handoffs/2026-10-03_正式版基础.md` 接续，已确认产品范围见 `docs/20_product/16_正式版演进与已确认范围.md`。先检查 Git 实际状态；截至本次交接，基础代码与文档位于 Linux 主工作区 `codex/formal-foundation` 分支的未提交／未跟踪改动中，不能只从远端 main 判断当前实现。

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
