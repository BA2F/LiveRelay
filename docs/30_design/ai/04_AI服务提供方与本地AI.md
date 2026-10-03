# AI 服务提供方与本地 AI

> 状态：已确认  
> 版本：0.10
> 最后更新：2026-10-03
> 依赖文档：ai/00_AI隐私处理总览.md


## 正式版当前实现

2026-10-03 按人类要求优先软件基础，增加 Responses 内置 Agent、卡片暂存工具及 Linux 可选隔离 Bash。Chat Completions 兼容路径保留，配置可显式选择协议。每次授权、敏感 Token、本机还原及本人保存规则不变。Agent 操作页与来源事务已落地，真实 Provider 尚无受控 API Key 联调。

详见 [当前 Agent 与隔离命令](05_内置Agent与隔离命令.md)。以下首版方向描述历史 MVP 范围，不再用于断言正式版 Agent 未实现。

## 首版方向

首版只实现一个 OpenAI-compatible 云 Provider，且必须由用户主动启用；调用前按 AI Privacy 流程在本地处理敏感信息。禁用或不可用时，手动整理路径仍应成立。

MVP 已实现上述 Provider。用户配置 HTTPS Chat Completions endpoint、模型和 API Key；配置保存在平台安全存储命名空间中。配置本身不产生调用授权，每次仍必须查看范围并选择“仅允许本次”。

云调用发起前采用 Agent 式权限请求，首版仅可允许本次或拒绝；用户拒绝时不得调用 Provider。授权范围仅限本次选中资料的脱敏内容，不能把连接好 Provider 等同于允许自动读取或发送 Vault 内容。

长期希望 DeepSeek、Ollama、其他云服务或自托管模型都只通过 Provider 替换，不让单一厂商成为 LifeVault 数据格式依赖。

桌面端本地/自托管 AI 属于后续兼容方向，不是当前必须实现能力。手机端可为将来的本地 AI 保留入口，但不能把入口误写成已具备本地推理能力。

未来的本地 Agent 即使不走网络，读取卡片或原始资料也需要按任务申请明确范围的权限，不能默认读取整个 Vault。首版不因此增加本地 Agent 实现范围。

OpenCode、Codex 等外部 Agent 的连接器属于首版之后的能力；首版先完成手动整理与获本次授权的云 AI 整理闭环。后续连接器仍须遵守按任务授权和最小资料范围，不因连接成功就获得全库权限。

## MVP Provider 边界

- 内部接口输入只有 endpoint、API Key、模型和本次脱敏文本；
- 只接受 HTTPS，禁用 HTTP redirect；
- 单次超时 60 秒，响应上限 1 MiB；
- 非 2xx、重定向和错误响应结构统一失败；
- 当前不自动重试，避免在授权语义不清时重复外发；
- Provider label 随 AI 草稿来源保存，API Key、请求原文和 Token Map 不进入卡片。

## 当前开放问题

- 模型能力差异如何暴露；
- 429/限流的用户可见反馈和是否允许用户主动重试；
- Provider metadata 哪些需要进入 Provenance；
- 真实 Provider 的兼容联调和证书/代理环境；
- 桌面端本地或自托管 Provider。

## 历史来源

- `docs/08_ai/11_AI服务提供方抽象.md`
- `docs/08_ai/12_未来本地AI与自托管AI.md`
