# AI 服务提供方与本地 AI

> 状态：讨论中  
> 版本：0.4  
> 最后更新：2026-09-06  
> 依赖文档：ai/00_AI隐私处理总览.md


## 当前方向

首版只实现一个 OpenAI-compatible Provider。

长期希望 DeepSeek、Ollama、其他云服务或自托管模型都只通过 Provider 替换，不让单一厂商成为 LifeVault 数据格式依赖。

本地/自托管 AI 属于后续兼容方向，不是当前必须实现能力。

## 当前开放问题

- Provider 最小接口；
- 模型能力差异如何暴露；
- 超时、限流和重试语义；
- Provider metadata 哪些需要进入 Provenance。

## 历史来源

- `docs/08_ai/11_AI服务提供方抽象.md`
- `docs/08_ai/12_未来本地AI与自托管AI.md`
