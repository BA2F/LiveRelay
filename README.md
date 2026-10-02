# LiveRelay 项目说明

> 状态：当前有效\
> 版本：0.4\
> 最后更新：2026-10-02\
> 依赖文档：无


LiveRelay 是一个面向中文社会环境的本地优先人生信息连续性与交接系统。

当前已具备可运行的 Flutter/Android MVP，源码位于 `work/code/live_relay/`。已完成本地加密资料库、记录与原件、密码库及本机交接模拟，并落实已确认的 UI/UX 改造。当前继续真机验证和安全复核；内部端口尚未冻结为跨 package 或对外公共契约。

运行说明见 [应用 README](work/code/live_relay/README.md)，本次实现与证据见 [UI/UX 交付](work/paper/uiux-review-2026-10-01/实施与验证交付.md)。

## 第一次阅读

人类：
1. `docs/10_overview/00_项目总览.md`
2. `docs/20_product/00_产品设计总览.md`
3. `docs/30_design/architecture/00_系统架构总览.md`
4. `docs/10_overview/04_当前阶段.md`

AI Agent：
1. `AGENTS.md`
2. `memory/当前项目上下文.md`
3. 当前专题或 Task 指定的文档

## 工作区角色

`docs` 当前正式知识；`notes` 讨论过程；`records` 决策原因；`memory` 派生缓存；`tasks` 执行看板；`handoffs` 执行事实；`work` 项目成果；`archive` 历史与初始化规范。

## 当前纪律

**治理结构已冻结。** 后续以真实实现、验证及必要设计回写为主；不再为了未来可能需要而预建 Markdown、Skill、契约或任务。

报告、PPT、README、简历都是项目事实的不同输出视图，不维护第二套项目真相。
