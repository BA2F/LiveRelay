# 关键节点与连线来源索引

图版 v1.0；源码 `6fbee32`；文档 `a586349`；2026-10-04。原生 mxCell 的 `evidence` 属性存来源编号，cell ID 与下面一致。来源行号由生成器检查锚点后生成；版本变动时需重建。

## 来源目录

| 编号 | 来源 | 位置 |
| --- | --- | --- |
| D01 | 当前系统架构 | [docs/30_design/architecture/00_系统架构总览.md:9](../../../docs/30_design/architecture/00_系统架构总览.md#L9) |
| D02 | 分层与内部端口 | [docs/30_design/architecture/01_系统分层与模块边界.md:9](../../../docs/30_design/architecture/01_系统分层与模块边界.md#L9) |
| D03 | 平台实现与验收边界 | [docs/30_design/platform/00_应用实现架构总览.md:9](../../../docs/30_design/platform/00_应用实现架构总览.md#L9) |
| D04 | Header v3／恢复／换钥规格 | [docs/30_design/security/10_本机安全流程与格式v3.md:7](../../../docs/30_design/security/10_本机安全流程与格式v3.md#L7) |
| D05 | 身份／范围／分层备份规格 | [docs/30_design/security/11_本机交接与分层备份格式.md:7](../../../docs/30_design/security/11_本机交接与分层备份格式.md#L7) |
| D06 | 10月4日实际联调 | [docs/60_quality/2026-10-04_实际联调验证.md:20](../../../docs/60_quality/2026-10-04_实际联调验证.md#L20) |
| D07 | 已确认的后续方向 | [docs/20_product/16_正式版演进与已确认范围.md:40](../../../docs/20_product/16_正式版演进与已确认范围.md#L40) |
| D08 | Agent密码录入已知缺口 | [docs/60_quality/2026-10-04_实际联调验证.md:55](../../../docs/60_quality/2026-10-04_实际联调验证.md#L55) |
| C01 | 集中组合根 | [work/code/live_relay/lib/infrastructure/app_composition.dart:37](../../../work/code/live_relay/lib/infrastructure/app_composition.dart#L37) |
| C02 | Controller初始化与启动恢复 | [work/code/live_relay/lib/application/app_controller.dart:230](../../../work/code/live_relay/lib/application/app_controller.dart#L230) |
| C03 | 会话密钥临时副本 | [work/code/live_relay/lib/application/vault_session.dart:172](../../../work/code/live_relay/lib/application/vault_session.dart#L172) |
| C04 | 受限恢复会话 | [work/code/live_relay/lib/application/vault_session.dart:328](../../../work/code/live_relay/lib/application/vault_session.dart#L328) |
| C05 | 全库换钥与提交 | [work/code/live_relay/lib/application/vault_security_service.dart:25](../../../work/code/live_relay/lib/application/vault_security_service.dart#L25) |
| C06 | 备份认证与恢复 | [work/code/live_relay/lib/application/vault_backup_service.dart:66](../../../work/code/live_relay/lib/application/vault_backup_service.dart#L66) |
| C07 | 配对导出与补充恢复 | [work/code/live_relay/lib/application/vault_backup_service.dart:222](../../../work/code/live_relay/lib/application/vault_backup_service.dart#L222) |
| C08 | 恢复目录安装事务 | [work/code/live_relay/lib/infrastructure/backup/vault_restore_transaction.dart:231](../../../work/code/live_relay/lib/infrastructure/backup/vault_restore_transaction.dart#L231) |
| C09 | 启动中断恢复 | [work/code/live_relay/lib/infrastructure/backup/vault_restore_transaction.dart:112](../../../work/code/live_relay/lib/infrastructure/backup/vault_restore_transaction.dart#L112) |
| C10 | Owner挑战与限定快照 | [work/code/live_relay/lib/application/local_handoff_service.dart:104](../../../work/code/live_relay/lib/application/local_handoff_service.dart#L104) |
| C11 | 限定范围导出 | [work/code/live_relay/lib/application/local_handoff_service.dart:200](../../../work/code/live_relay/lib/application/local_handoff_service.dart#L200) |
| C12 | Recipient独立接收验证 | [work/code/live_relay/lib/application/recipient_service.dart:305](../../../work/code/live_relay/lib/application/recipient_service.dart#L305) |
| C13 | Recipient独立密码身份 | [work/code/live_relay/lib/application/recipient_service.dart:106](../../../work/code/live_relay/lib/application/recipient_service.dart#L106) |
| C14 | 身份指纹与双钥 | [work/code/live_relay/lib/core/identity/local_identity.dart:9](../../../work/code/live_relay/lib/core/identity/local_identity.dart#L9) |
| C15 | HPKE实现 | [work/code/live_relay/lib/core/identity/hpke.dart:11](../../../work/code/live_relay/lib/core/identity/hpke.dart#L11) |
| C16 | Agent单次授权UI | [work/code/live_relay/lib/presentation/pages/agent_page.dart:49](../../../work/code/live_relay/lib/presentation/pages/agent_page.dart#L49) |
| C17 | Agent Tokenization与请求 | [work/code/live_relay/lib/application/draft_agent_service.dart:19](../../../work/code/live_relay/lib/application/draft_agent_service.dart#L19) |
| C18 | Token校验与本机回填 | [work/code/live_relay/lib/core/ai/ai_privacy.dart:37](../../../work/code/live_relay/lib/core/ai/ai_privacy.dart#L37) |
| C19 | Agent结果保存 | [work/code/live_relay/lib/application/app_controller.dart:618](../../../work/code/live_relay/lib/application/app_controller.dart#L618) |
| C20 | Linux命令隔离 | [work/code/live_relay/lib/infrastructure/agent/linux_bash_command_provider.dart:42](../../../work/code/live_relay/lib/infrastructure/agent/linux_bash_command_provider.dart#L42) |
| C21 | 本地转写与isolate | [work/code/live_relay/lib/infrastructure/speech/local_sense_voice_provider.dart:157](../../../work/code/live_relay/lib/infrastructure/speech/local_sense_voice_provider.dart#L157) |
| C22 | 语音来源草稿 | [work/code/live_relay/lib/application/app_controller.dart:626](../../../work/code/live_relay/lib/application/app_controller.dart#L626) |
| C23 | 数据库实体映射 | [work/code/live_relay/lib/infrastructure/persistence/app_database.dart:9](../../../work/code/live_relay/lib/infrastructure/persistence/app_database.dart#L9) |
| C24 | SQLCipher打开／schema v5 | [work/code/live_relay/lib/infrastructure/persistence/app_database.dart:191](../../../work/code/live_relay/lib/infrastructure/persistence/app_database.dart#L191) |
| C25 | 原件AES-GCM／换钥 | [work/code/live_relay/lib/infrastructure/blob/encrypted_blob_store.dart:23](../../../work/code/live_relay/lib/infrastructure/blob/encrypted_blob_store.dart#L23) |
| C26 | 采集与OCR应用用例 | [work/code/live_relay/lib/application/app_controller.dart:478](../../../work/code/live_relay/lib/application/app_controller.dart#L478) |
| C27 | Provider配置的系统安全存储 | [work/code/live_relay/lib/infrastructure/ai/ai_provider_settings_store.dart:22](../../../work/code/live_relay/lib/infrastructure/ai/ai_provider_settings_store.dart#L22) |
| C28 | 纯领域生命状态规则 | [work/code/live_relay/lib/core/domain/lifecycle.dart:15](../../../work/code/live_relay/lib/core/domain/lifecycle.dart#L15) |
| C29 | 接收入口先锁Owner | [work/code/live_relay/lib/presentation/pages/recipient_page.dart:18](../../../work/code/live_relay/lib/presentation/pages/recipient_page.dart#L18) |
| C30 | Header任一／全部密码学 | [work/code/live_relay/lib/core/security/vault_header_v3.dart:13](../../../work/code/live_relay/lib/core/security/vault_header_v3.dart#L13) |
| C31 | 设备因素MethodChannel | [work/code/live_relay/lib/infrastructure/security/android_device_factor_protection.dart:7](../../../work/code/live_relay/lib/infrastructure/security/android_device_factor_protection.dart#L7) |
| C32 | Android Keystore强生物识别 | [work/code/live_relay/android/app/src/main/kotlin/app/liverelay/live_relay/DeviceFactorChannel.kt:26](../../../work/code/live_relay/android/app/src/main/kotlin/app/liverelay/live_relay/DeviceFactorChannel.kt#L26) |
| C33 | 正常入口 | [work/code/live_relay/lib/main.dart:12](../../../work/code/live_relay/lib/main.dart#L12) |
| C34 | 虚构演示入口 | [work/code/live_relay/lib/main_debug_demo.dart:23](../../../work/code/live_relay/lib/main_debug_demo.dart#L23) |
| C35 | Responses工具循环 | [work/code/live_relay/lib/infrastructure/ai/responses_agent_provider.dart:11](../../../work/code/live_relay/lib/infrastructure/ai/responses_agent_provider.dart#L11) |
| C36 | 数据来源查询 | [work/code/live_relay/lib/infrastructure/persistence/sqlite_vault_repository.dart:449](../../../work/code/live_relay/lib/infrastructure/persistence/sqlite_vault_repository.dart#L449) |

## 01 系统上下文与外部参与者

| 原生 cell ID | 类型／关键语义 | 来源 |
| --- | --- | --- |
| `p01-systemLabel` | 当前系统边界：本地优先 LiveRelay 客户端 | D01 |
| `p01-owner` | 所有者 Owner  录入、核对、保存；保管恢复材料 逐次批准 AI 外发与指定范围交付  [现场] | D01, D05 |
| `p01-app` | LiveRelay 客户端  加密资料库 · 记录／卡片／密码库 本地语音 · 受控 Agent · 手动交接 完整／分层备份 · 独立恢复  [实现／现场] | D01, C01 |
| `p01-recipient` | 独立接收者 Recipient  自有身份、密码与目录 核对身份；只读查看获授权快照  [现场] | D05, C12 |
| `p01-ai` | 本人配置的网络 AI  HTTPS · Chat Completions／Responses 只接收获准文本；属于外部信任域  [实现／受控Provider现场] | C17, C35, C27 |
| `p01-os` | 操作系统／本地能力  摄像／录音／文件选择 强生物识别、Keystore／Secret Service  [实现／按平台] | D03, C31 |
| `p01-files` | 本人控制的文件媒介  设备外冷备份 .lvault 公开身份、挑战响应、.lrshare  [实现] | D05, C06, C11 |
| `p01-ownerUse` | 解锁／编辑／授权 | D01 |
| `p01-recipientUse` | 独立接收入口／快照 | C29, C12 |
| `p01-useOS` | 平台能力 | C01 |
| `p01-sendAi` | 单次预览后发送 | C16, C17 |
| `p01-manualFiles` | 手动导出／导入 | C06, C11 |
| `p01-plans` | [规划] 后续外部系统  同步／WebDAV／云备份 · 摇篮通知与自动条件释放 · 外部 Agent／CLI／MCP。当前没有运行连接。 | D07 |

## 02 应用与存储的运行边界

| 原生 cell ID | 类型／关键语义 | 来源 |
| --- | --- | --- |
| `p02-clientLabel` | 同一 Flutter package：应用进程 + 运行时工作 isolate | D01, D03 |
| `p02-ui` | Material 3 表现层  记录／卡片／密码库／交接／我的 首次使用、锁定、独立接收入口  [实现] | D02, C29 |
| `p02-uses` | Application 用例协调  AppController 页面状态；VaultSession 会话 安全、备份、身份、交接、Agent、语音服务  [实现] | C01, D02 |
| `p02-native` | 基础设施／原生适配  SQLCipher 数据库工作 isolate；sherpa_onnx 转写 isolate／FFI Android MethodChannel／插件；具体 Provider 与文件适配  [实现] | C01, C21, C24 |
| `p02-ownerDisk` | Owner 资料目录  live_relay/vault/ Header + SQLCipher + 加密 Blob  [实现] | C01, C24, C25 |
| `p02-recipDisk` | Recipient 独立目录  live_relay/recipient/ 加密身份／信任状态 + .lrshare 密文  [实现] | C01, C12, C13 |
| `p02-support` | 辅助本地资源  speech/：模型与安装状态 系统安全存储：AI 配置及 API Key  [实现] | C01, C21, C27 |
| `p02-usecases` | 页面调用用例 | D02 |
| `p02-adapters` | 端口调用／实现适配 | C01 |
| `p02-writeOwner` | 会话仓储／原件接口 | C03, C24 |
| `p02-writeRecipient` | RecipientService | C12, C13 |
| `p02-readSupport` | 模型／安全配置 | C21, C27 |
| `p02-processes` | 另外启动的进程与服务  Linux 隔离 Bash：bubblewrap + prlimit，本次启用后只读遮蔽文本；远端 AI：HTTPS 服务。Dart isolate 是应用运行单元，均不是独立微服务。 | C20, C17, D03 |

## 03 逻辑分层、组件、内部端口与组合根

| 原生 cell ID | 类型／关键语义 | 来源 |
| --- | --- | --- |
| `p03-presentationLabel` | Presentation | D02 |
| `p03-pages` | 页面与设计系统  页面交互、投影、主题和导航 | D02 |
| `p03-applicationLabel` | Application：状态与用例 | D02 |
| `p03-controller` | AppController  忙碌／错误／投影；不持有 VMK | C01, D02 |
| `p03-vaultUse` | VaultSession + Security／Backup  会话、凭证重设、换钥、恢复 | C03, C05, C06 |
| `p03-identityUse` | LocalHandoff／Recipient  独立身份、授权快照和接收 | C10, C12 |
| `p03-aiUse` | DraftAgent／Speech  授权工具循环、本地转写 | C17, C21 |
| `p03-coreLabel` | Core：纯领域／隐私／安全逻辑 + 内部端口 | D02 |
| `p03-domain` | Domain／AI Privacy／Security  InformationCard、LifeState、ReleasePolicy 来源／修订；Token 遮蔽／校验／回填 Header v3、身份、HPKE 密码学 | C18, C28, C30, C14, C15 |
| `p03-ports` | core/ports 内部替换端口  VaultRepository · VaultBlobStore AiProvider · OcrProvider · SpeechProvider AgentCommandProvider · DeviceFactorProtection  [内部未冻结] | C01, D02 |
| `p03-infrastructureLabel` | Infrastructure：当前实现 | D02 |
| `p03-impl` | 具体适配器  SqliteVaultRepository／EncryptedBlobStore ConfiguredAiProvider／ML Kit OCR LocalSenseVoiceProvider／Linux Bash AndroidDeviceFactorProtection | C01, C20, C21, C31 |
| `p03-transactions` | 归档与文件事务  LifeVaultArchive／VaultRestoreTransaction 系统安全配置、CSV、平台路径 | C06, C08, C27 |
| `p03-root` | main.dart → app_composition.createAppController  集中创建默认实现、解析目录、准备环境；具名注入控制器与用例服务  [组合根] | C01, C33 |
| `p03-presDep` | 依赖 | D02 |
| `p03-appDepDomain` | 依赖 Core | D02 |
| `p03-appDepPorts` | 调用端口 | C01, C03 |
| `p03-infraDep` | 实现端口 | C01, D02 |
| `p03-injectApp` | 注入服务 | C01 |
| `p03-buildInfra` | 创建／装配 | C01 |
| `p03-exception` | 渐进分层事实：部分 Application 仍引用具体归档／错误与配置类型；并未宣称所有基础设施依赖已完全反转。 | D02, C05, C06 |

## 04 部署结构与平台能力

| 原生 cell ID | 类型／关键语义 | 来源 |
| --- | --- | --- |
| `p04-androidLabel` | Android 设备  ／  API 24+ · target 36 | D03 |
| `p04-apk` | Flutter APK／Dart 运行时  MVP0.4 · 内部 1.0.0+3 小米13／Android13 代表链路已验证  [现场] | D03, D06 |
| `p04-androidNative` | 插件／FFI／MethodChannel  SQLCipher · sherpa_onnx ML Kit 中文 OCR · 采集／播放插件 Kotlin CryptoObject + 强生物识别  [实现／部分现场] | D03, C24, C21, C32 |
| `p04-keystore` | Android Keystore  保护设备因素份额 每次授权后 AAD／doFinal 平台结果复制为可写32字节  [小米13现场] | C31, C32, D04 |
| `p04-androidRuntime` | 插件／FFI | D03 |
| `p04-factor` | 份额 | C31, C32 |
| `p04-linuxLabel` | Linux 桌面  ／  x86_64 · Ubuntu22.04 构建基线 | D03, D06 |
| `p04-bundle` | Flutter runner + bundle  SQLCipher／sherpa_onnx 动态库随包 Ubuntu22.04 启动与 EndeavourOS 现场试用  [现场] | D03, D06 |
| `p04-linuxNative` | 桌面插件与系统服务  GTK／音频／文件／播放 本地短录音／WAV → 草稿／来源重开 Secret Service：AI 配置安全存储  [现场／限定环境] | C21, C27, D06 |
| `p04-bash` | 可选隔离命令  bwrap + Bash + prlimit user/network namespace 只读 /input；限时／限资源  [实现／Linux] | C20 |
| `p04-linuxRuntime` | 本地库／插件 | D03 |
| `p04-sandbox` | 单次启用工具 | C20, C16 |
| `p04-pending` | [待验] Windows 与发行安全  Windows runner 已准备，尚未构建／运行验收。正式签名、安全外部复核、更多指纹组合／机型／声卡／日常密钥环仍待完成。 | D03, D06 |
| `p04-demo` | 隔离调试与未来平台  main_debug_demo：独立临时目录、虚构资料、注入控制；正常入口不复用演示资料。macOS 尚无工程；云端不在当前部署中。 | C34, D03 |

## 05 数据、来源、VMK 所有权与信任边界

| 原生 cell ID | 类型／关键语义 | 来源 |
| --- | --- | --- |
| `p05-credentialLabel` | 本人保管／平台凭证域 | D04 |
| `p05-daily` | 日常因素 → Header v3 分支  密码：Argon2id 64MiB／3／1 可选随机文件：精确32字节 可选设备：Keystore 保护份额  [实现／组合待扩验] | C30, D04 |
| `p05-branches` | any / all 的密码学强制  any：各因素独立单因素分支 all：n-of-n 份额 XOR 组合分支 B HKDF 分支钥 → 解封 VMK  [内部格式] | C30, D04 |
| `p05-recovery` | 离线独立恢复 R / LRR1  随机 R；独立恢复分支 不保存到 Header／偏好／日志 绕过日常因素，只进入受限重设  [现场／受限] | D04, C04 |
| `p05-factors` | 解封份额 | C30 |
| `p05-ownerLabel` | Owner 解锁会话与加密存储域 | C03, C24, C25 |
| `p05-vmk` | VaultSession 持有 VMK  随机32字节；受控临时副本供安全／备份 AppController／UI／网络 AI 不持有 VMK 锁定时关闭仓储并清除会话密钥  [实现] | C03, C05, C06, D02 |
| `p05-db` | SQLCipher schema v5  LifeCard／Credential 与各自 Revision Sources、EncryptedBlobs 元数据、关系 ReleasePolicy／LifeState／Audit vault_local_state：身份私钥、绑定、缺失状态  [实现] | C23, C24, C10, C07 |
| `p05-blob` | AES-256-GCM 原件 Blob  随机 ID 文件名；AAD 绑定 Blob ID 原始名／哈希／OCR／标注在加密数据库 修订 → Source → blobId；按来源回看  [实现] | C25, C23, C36 |
| `p05-dailyUnlock` | 认证 Header MAC／解封 | C30 |
| `p05-recoveryUnlock` | 受限会话 | C04 |
| `p05-dbKey` | VMK 打开数据库 | C24 |
| `p05-blobKey` | VMK 加解密原件 | C25 |
| `p05-sourceRef` | 逻辑引用／来源链 | C23, C36 |
| `p05-header` | 磁盘公开 Header v3  元数据 + 被封装因素／VMK槽 Descriptor／AAD／Header HMAC 保留 v1／v2 reader；主动升级旧库  [实现] | D04, C30 |
| `p05-recipientKeys` | Recipient 自有钥域  自有密码保护 .lridentity X25519／Ed25519 私钥与信任状态 从不取得 Owner VMK  [实现] | C13, C14, D05 |
| `p05-aiBoundary` | AI 外部信任域  只见预览获准文本／敏感行Token Token Map 留本机；API Key 单独 不访问库、原件、主密钥或私钥  [实现] | C17, C18, C27, D08 |

## 06 采集、本地语音与来源保留

| 原生 cell ID | 类型／关键语义 | 来源 |
| --- | --- | --- |
| `p06-localLabel` | 全部识别与来源保存步骤位于设备内 | C21, C22, C26 |
| `p06-capture` | 本人主动采集／导入  照片／文件／录音／录像 平台能力与权限明确显示  [实现／按平台] | D03, C26 |
| `p06-store` | 加密保存原件  VaultSession → VaultBlobStore Blob + 元数据；来源可回看  [实现／现场] | C25, C26 |
| `p06-vault` | 草稿／来源持久化  LifeCard 草稿 + Revision + Source 引用原件 blobId；锁定／重开后回看  [现场] | C22, C23, C36 |
| `p06-ocr` | 端侧中文 OCR  Google ML Kit／OcrProvider 行文本 + 坐标；人工敏感标注  [实现／Android] | C26, D03 |
| `p06-speech` | 本地语音转写  SpeechService → LocalSenseVoiceProvider PCM WAV 校验 → Isolate.run SenseVoice INT8／sherpa_onnx FFI／CPU  [Android／Linux现场] | C21 |
| `p06-review` | 本人校对派生内容  转写／OCR 草稿、来源关系 可继续手工整理或另行授权 AI 不因采集或识别自动上传原件  [实现] | C22, C16, C26 |
| `p06-encrypt` | 字节／媒体类型 | C25, C26 |
| `p06-decodeOCR` | 授权读取原件 | C26 |
| `p06-decodeWav` | WAV 字节 | C21 |
| `p06-textReview` | 本地识别文本 | C21, C22 |
| `p06-ocrReview` | OCR 派生文本 | C26 |
| `p06-saveReview` | 确认后保存关联草稿 | C22, C26 |
| `p06-model` | 模型安装边界  模型下载／离线导入／校验安装与删除独立于录音识别；下载模型产生网络流量，但转写不向网络发送音频。未安装模型显示真实状态。 | C21 |
| `p06-limits` | 资源边界：单 Blob 当前上限 256MiB，内存加解密；代表性手机语音约837MiB峰值，不作为低资源设备保证。 | C25, D06 |

## 07 Agent 隐私、单次授权与结果确认

| 原生 cell ID | 类型／关键语义 | 来源 |
| --- | --- | --- |
| `p07-owner` | 本人／Agent 页面 | C16 |
| `p07-app` | Controller／DraftAgent | C17 |
| `p07-privacy` | 本机 Privacy／工具 | C18, C20 |
| `p07-provider` | 网络 AI Provider | C35 |
| `p07-input` | 1  输入文字与敏感行标注 | C16, C17 |
| `p07-token` | 2  Tokenize；Token Map 留本机 | C18 |
| `p07-preview` | 3  显示精确外发预览与可选命令范围 | C16 |
| `p07-approve` | 4  仅允许本次；拒绝即停止 | C16 |
| `p07-request` | 5  HTTPS：获准文本／模型／协议；敏感行仅发 Token | C17, C35 |
| `p07-toolCall` | 6a  可选工具请求：已启用的受限命令 | C20, C35 |
| `p07-toolResult` | 6b  无网络 Bash；只读遮蔽输入；返回有限结果 | C20, C35 |
| `p07-response` | 7  cards JSON → Schema／Token 校验 → 本机回填 | C18, C35 |
| `p07-draft` | 8  显示建议；本人确认后保存 LifeCard 草稿与来源 | C19, C16 |
| `p07-guard` | 取消／锁定与安全配置  锁定取消任务并丢弃结果；命令会话 finally 关闭。API Key 来自系统安全存储；Provider 没有仓储、原件或 VMK 入口。 | C17, C27, C19 |
| `p07-gap` | 已知后置缺口：Credential 录入／转换  Agent 仅保存 LifeCard；正文中的回填密码不是 Secret 字段，会进入通用预览／搜索。尚未贯通密码类型候选与转换。 | D08, C19 |

## 08 独立身份、指纹核对与双钥挑战

| 原生 cell ID | 类型／关键语义 | 来源 |
| --- | --- | --- |
| `p08-owner` | Owner 身份／加密状态 | C10, C14 |
| `p08-channel` | 本人手动文件／独立渠道 | D05 |
| `p08-recipient` | Recipient 自有身份 | C13, C14 |
| `p08-public` | 1  .lrpublic：名称 + X25519／Ed25519 公钥 | C14, D05 |
| `p08-verifyFp` | 2  独立渠道核对并回输完整64位指纹 | C10, D05 |
| `p08-challenge` | 3  .lrchallenge：随机32字节，HPKE加密 + Owner签名 | C10, C15 |
| `p08-verifyOwner` | 4  核对Owner指纹；验签并用自有X25519私钥解密 | C13, D05 |
| `p08-proof` | 5  .lrproof：挑战ID／双方指纹／随机值 + Recipient签名 | C13, D05 |
| `p08-verifyProof` | 6  Owner验签、匹配唯一挑战与7天期限；持久绑定并消费挑战 | C10, D05 |
| `p08-ownerKey` | Owner 私钥与持久状态  身份双钥／profile／recipient绑定／sequence 在 schema v5 加密 local_state 内。改显示名称或换日常密码不改变身份指纹。 | C10, C14, D05 |
| `p08-recipientKey` | Recipient 身份可独立备份  自有密码经 Argon2id 保护 .lridentity；RecoverableFile 写入。加密身份备份可以在另一独立目录恢复；不含 Owner VMK。 | C13, D05 |
| `p08-identityLimits` | 本机信任边界与回退限制  切换接收入口先锁 Owner。无私钥及备份不能按名称找回；本机 sequence 不具硬件单调性，不宣称抗设备回滚。 | C29, D05 |

## 09 限定范围交接与独立接收查看

| 原生 cell ID | 类型／关键语义 | 来源 |
| --- | --- | --- |
| `p09-ownerLabel` | Owner 已解锁域：每次手动授权 | C11, D05 |
| `p09-selection` | 选择接收者与本次范围  已绑定指纹；记录ID／可见级别 历史另行选择；原件逐个勾选  [现场] | C11, D05 |
| `p09-snapshot` | ReleasePreview → 范围快照  卡片摘要前80个UTF-16单元；完整正文按级别 密码仅“含密码”交付Secret；历史要求相应级别 核验原件归属；不展开关联卡片／回收区／来源链  [实现] | C11, D05 |
| `p09-package` | Ed25519 签名 + HPKE Base 封装  X25519／HKDF-SHA256／AES-256-GCM .lrshare · 新ephemeral会话 packageId + sequence + scopeDigest；不含 Owner VMK | C11, C15, D05 |
| `p09-recipientLabel` | Recipient 自有身份／密码域 | C12, C13 |
| `p09-verify` | 接收验证后才展示  严格envelope／签名／双方指纹 packageId去重、sequence高水位 HPKE解密、摘要、记录／历史／原件范围  [现场] | C12, D05 |
| `p09-persist` | 提交加密接收状态  保存 .lrshare 密文 Owner公钥／最高sequence／包SHA256 先成功保存身份状态，再显示快照 | C12 |
| `p09-readonly` | 独立只读查看／再打开  自有密码解锁；再打开核对已记录包SHA256 当前密码／修订密码默认遮挡；原件显式另存 不打开、不克隆 Owner 数据库  [现场] | C12, C13, D05 |
| `p09-selectScope` | 本人核对 | C11 |
| `p09-seal` | 实际选定快照 | C11 |
| `p09-fileTransfer` | 手动传递 | D05, C11, C12 |
| `p09-receipt` | 拒绝错误／旧包／重复；通过才提交 | C12 |
| `p09-view` | 提交成功 | C12 |
| `p09-limit` | 工程限额与真实授权边界  最多200条；原件合计64MiB；快照128MiB／wire180MiB。当前 scopeEpoch 固定1；没有自动撤权、远程到达证明或可信离线时间锁。 | D05, C11, C12 |
| `p09-simulation` | 生命状态模拟独立于真实交付  Active ↔ Incapacitated；两者可到Deceased Deceased无恢复转换（调试重置另行处理） 模拟／Executor View不调用真实导出服务。 | C28, D05 |

## 10 完整／分层备份与原件补充恢复

| 原生 cell ID | 类型／关键语义 | 来源 |
| --- | --- | --- |
| `p10-export` | Owner 暂停数据库后导出  当前凭证认证；all便携认证用独立 R 同次暂停：配对snapshotId + 同一Header  [实现／现场] | C07, D05 |
| `p10-full` | 完整 .lvault v2 / full  Header v3 + DB + 全部加密Blob 认证manifest；不能有 omitted | D05, C06 |
| `p10-dbOnly` | 数据库 .lvault v2 / database  Header + DB；manifest.omitted 精确列出 省略Blob的路径、密文字节长度、SHA256 | D05, C07 |
| `p10-attachments` | 原件 .lvault v2 / attachments  Header + 加密Blob；共享snapshotId 仅补充包，不能单独恢复完整库 | D05, C07 |
| `p10-restore` | 认证暂存 → 目录事务安装  核验清单／MAC／路径／规模；验证新库 Header v3恢复进入受限重设与全库换钥 密码单分支或 R；异机all用 R  [现场] | C06, C08, D05 |
| `p10-missing` | 加密 backup.missing 状态  omitted哈希／snapshotId／旧Blob解密钥 全部保存在SQLCipher内；重设时保留 读取缺失原件提示；已有原件可先换钥  [现场] | C06, C07, C05 |
| `p10-supplement` | 补齐原件：旧钥 → 当前新 VMK  验证旧manifest MAC／相同snapshotId 逐项核验密文长度／SHA256并解密 用当前VMK重加密，逐项清除缺失状态  [现场] | C07, D05 |
| `p10-fullExport` | full | C06 |
| `p10-dbExport` | database | C07 |
| `p10-attExport` | attachments | C07 |
| `p10-fullRestore` | 恢复 | C06 |
| `p10-dbRestore` | 仅DB恢复后记录缺失 | C06 |
| `p10-reset` | 受限重设 | C06, C05 |
| `p10-pair` | 导入配对补充包 | C07 |
| `p10-oldKey` | 旧钥 | C07 |
| `p10-constraints` | 认证与中断约束  不同snapshotId即使内容相同也拒绝；补充失败可重试，已完成项保留。未补齐时拒绝导出新完整包／配对组；设备引用不承诺异机可用。 | C07, D05 |
| `p10-compat` | 兼容与资源边界  v1容器只支持Header v1；保留旧reader。 v2支持Header v3。上限10000条目／展开2GiB；当前内存构建，大包待验。 | D05 |

## 11 独立恢复、全库换钥与中断恢复

| 原生 cell ID | 类型／关键语义 | 来源 |
| --- | --- | --- |
| `p11-sessionLabel` | 会话状态：Header v3 独立恢复路径 | C04, C05 |
| `p11-locked` | locked  等待日常凭证／独立R | C04 |
| `p11-restricted` | recovering：受限重设  R认证后只可设置全部新日常材料 新R回输确认；普通资料投影不可达 | C04, C05 |
| `p11-unlocked` | unlocked  新库核验提交后正常会话 日常认证也可从locked进入 | C05 |
| `p11-rUnlock` | 独立 R | C04 |
| `p11-resetFinish` | 重设 + 全库换钥 + 提交 | C05 |
| `p11-transactionLabel` | VaultSecurityService／VaultBackupService → VaultRestoreTransaction（共用安装机制） | C05, C06, C08 |
| `p11-prepare` | 1  认证与 staging  新VMK／Header v3；导出逻辑状态 新SQLCipher导入；重加密现有Blob 保留ID／修订／身份／缺失状态 | C05 |
| `p11-intent` | 2  写入安装意图  关闭旧会话／清除投影 journal → incoming 旧库 → rollback → 新库安装 | C08, C06 |
| `p11-verify` | 3  核验新库后提交  验证打开；换钥核验现有原件 写独立 commit marker 提交点前失败：关闭并 recover | C05, C08 |
| `p11-cleanup` | 4  清理与进入新会话  提交后清理旧加密目录／记录 清理失败：保留新库与残留副本 旧设备引用提交后清理 | C08, C05 |
| `p11-stageToIntent` | 已准备 | C05, C08 |
| `p11-installToVerify` | 已安装 | C08 |
| `p11-verifyToCommit` | 已提交 | C08 |
| `p11-rollback` | 下次启动：先 recover，再选择创建／解锁  有旧库且未提交：核对旧Header摘要后保守回滚；有匹配commit：保留新库，不因清理失败回滚。首次恢复无旧库：保留认证暂存库并锁定，要求重新认证。异常目录／journal：进入failure，不创建空库覆盖。 | C02, C09 |
| `p11-boundaries` | 旧库升级与旧备份的边界  旧Header由本人主动升级，不在启动时自动迁移。 旧VMK不能解开新数据；旧备份仍可能读旧资料。 Journal／commit不是密码学信任锚，不含秘密。 | D04, C05, C09 |

## 文档／实现差异核对

1. 安全11（2026-10-03）末尾仍将Android真机强生物识别列为待验；安全10与10月4日实际联调证据记录小米13启用／解锁／取消／换钥／恢复已通过。本图使用后续事实，保留更多机型／新指纹／all与文件因素／正式安全复核待验边界。
2. 产品范围文档（2026-10-03）的部分段落仍用“未来”描述独立恢复、任一／全部、真实本机接收身份；其自身声明不是实现状态。安全10／11与当前源码已实现本机切片，本图不把旧阶段文字当作当前未实现结论。
3. 安全10说“保留加密旧副本”；`vault_restore_transaction.dart` 的正常成功路径核对旧Header摘要后删除rollback目录（install末尾），提交后清理失败与启动recover才保留残留。第11页按真实代码表达成功清理／失败保留，未修改规范或架构；后续应澄清该句的适用条件。
4. Header升级与SQLCipher schema迁移不同：旧Header不在启动自动升级；数据库自身仍有Drift onUpgrade（含schema v5 local_state）。本图明确限定“Header主动升级”，不声称数据库没有迁移。
5. 本机最高sequence用于拒绝重复／旧包，但身份备份回退没有硬件单调计数。图中没有宣称抗离线设备回滚或远程撤销。

本次仅记录实现证据与差异，不改应用源码、稳定契约或已确认架构原则。
