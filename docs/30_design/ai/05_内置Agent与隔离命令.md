# 内置 Agent 与隔离命令

> 状态：当前实现记录，真实云服务与平台验收待完成\
> 日期：2026-10-03\
> 依赖：ai/00_AI隐私处理总览.md；ai/04_AI服务提供方与本地AI.md

当前内置 Agent 提供供应商 URL、API Key、模型和 Responses 配置、限定工具循环、可见待核对结果与本人保存。Linux 增加可选隔离 Bash。Windows 命令工具、外部 Agent 和 CLI／MCP 尚未实现。配置不表示调用授权，不改变既有密码／指纹 OR。

## 范围与结果

本人粘贴本次文字并逐行标记敏感类型；`DraftAgentService` 在本机生成脱敏文本和独立 Token Map。每次展示实际外发文本，只有“仅允许本次”才调用 Provider。单次最多 32000 字符／200 行，脱敏 UTF-8 上限 64 KiB。

Provider 只持有供应商连接参数、脱敏文本和本次已许可的命令会话，不能取得 Repository、VMK、原件或 Token Map。`stage_card` 仅暂存本次脱敏卡片，`staged_count` 仅查询暂存数量；返回草稿经 Schema、允许类型、未知／遗漏／重复 Token 校验后才在本机还原。本人核对后整批事务保存，强制待整理状态并保留加密的原始文字来源和 Provider label；中途无效卡片整批回滚。拒绝、取消、锁定、关闭页面或失败均不会自动保存建议。

## Responses 运行约束

旧配置默认仍为 Chat Completions，可显式选择 Responses。请求使用 `store: false`，不依赖服务端会话；每轮回传完整 output（包括 encrypted reasoning）和匹配 call_id 的 function_call_output。此参数不是服务方零保留保证。

最多六个模型回合、24 个工具调用、20 个暂存草稿；同一个 call_id 不重复执行。整体三分钟、单请求 60 秒、流空闲 30 秒、每轮响应 1 MiB、上下文 2 MiB、工具参数 64 KiB。工具耗用同一回合预算，不保证一次能生成 20 张卡片；复杂资料应分批。拒绝重定向、非 HTTPS、未知工具、错误结构或未完成响应，不自动重试。取消中止 HTTP 并阻止下一回合。

依据：[OpenAI 官方 function calling](https://developers.openai.com/api/docs/guides/function-calling)、[Responses 迁移说明](https://developers.openai.com/api/docs/guides/migrate-to-responses)。供应商兼容性仍需实际 API Key 联调，离线 Provider 测试不能替代该验收。

## Linux 命令隔离

命令默认关闭。仅在本机能力探测成功、本人勾选本次授权并确认外发范围时，Provider 才收到 `run_command` 工具。手机与 Windows 不发布该工具，仍可进行云文字整理。设置 cwd 本身不构成隔离，失败也不回退宿主 Bash。

实际实现使用 `/usr/bin/bwrap`、Bash 和 prlimit：隔离用户／进程／IPC／网络等 namespace，禁用嵌套 user namespace、丢弃 capabilities、关闭继承环境和标准输入，使用新 session 与 die-with-parent。只读挂载 `/usr/bin`、`/usr/lib` 及必要 loader 别名，提供新的 `/proc` 和最小 `/dev`；不挂载 home、etc、run、Vault 或服务密钥存储。

命令只读 `/input/input.txt`，内容是本次已授权的脱敏文本；`/work` 与 `/tmp` 各 16 MiB，每次命令使用新的临时文件系统。没有宿主写入挂载，也没有网络、SSH agent、DBus socket 或继承的 API Key。prlimit 限制地址空间 512 MiB、CPU 5 秒、单文件 16 MiB、文件描述符 64 和进程数 256；命令最长 4096 UTF-8 字节、墙钟 10 秒、合计输出 64 KiB、每次任务最多六条。取消或超限杀掉 bubblewrap 父进程并清理会话，命令与输出可在结果页展开查看。

脱敏 input 暂存于应用支持目录 `live_relay/agent_runtime/request-*`，正常结束删除，启动仅清理专门运行目录的残留。未标记的文字已由本人授权为可外发范围，仍不得随意保留为长期日志。目录仅供当前 App 内部使用，不是跨进程公开 API；多实例并发管理后续需要独立设计。

Linux 原生实测验证脱敏输入可读、私人目录及环境隐藏、无外部路由、input 只读、临时写入、输出上限和取消。该实现共享宿主内核，不是虚拟机；仍需安全复核，不承诺抵抗内核漏洞或全部资源耗尽攻击。隔离参数依据 [bubblewrap 官方安全说明](https://github.com/containers/bubblewrap)，资源参数依据 [prlimit 手册](https://man7.org/linux/man-pages/man1/prlimit.1.html)。
