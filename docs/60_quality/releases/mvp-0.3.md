# LiveRelay · MVP 0.3 — 本机安全、交接与语音

本机功能预发布，构建于2026-10-03。提供Android Release APK和Linux x86_64完整应用包；应用内部版本 `1.0.0+2`。此里程碑已完成本机软件基础，真实设备、独立安全复核及正式签名仍待验收。

## 本次完成

- 五主导航与“我的”、明暗／文字大小及首次使用流程；密码库随机密码生成，卡片／修订／来源与原件保留。
- 新建库默认Header v3：独立恢复凭证离线保存及完整回输，恢复后先安全重设；密码或已启用指纹任选，可选密钥文件／全部条件组合。更换策略和恢复时更换主密钥、数据库和现存原件密钥。
- 加密身份资料、独立接收者入口与身份备份。完整指纹核对、签名及私钥挑战，手动逐项选择内容／级别／历史／原件，生成签名加密 `.lrshare`；接收端只读查看，拒绝重复及旧包。
- 完整备份与本地配对分层备份，可先恢复数据库，再补充原件；核对快照及认证清单，补充原件重加密到新资料库。
- 可选Responses Agent，单次外发检查／授权、结果确认和保留原始来源的草稿保存。Linux可选隔离Bash，不向命令环境开放私人目录或网络。
- 本地SenseVoice短录音／WAV转写、模型下载／导入、原件关联保存。语音模型另行下载或导入，未捆绑到安装包。
- 独立调试演示源码，每次独立虚构库，版本号连点七次展开模拟面板。下载附件使用正常main入口，不含演示种子／控制器。

## 下载与安装

- Android：`LiveRelay-MVP0.3-Android.apk`，Android7/API24+，targetAPI36，包名 `app.liverelay.live_relay`，内部版本名 `1.0.0`、构建号 `2`。与MVP0.1／0.2同包名、同签名证书，可覆盖安装；不要卸载旧应用，卸载会清理本机资料库。建议先导出并另存备份。
- Linux：`LiveRelay-MVP0.3-Linux-x86_64.tar.gz`。解压后进入 `LiveRelay-MVP0.3-Linux-x86_64`，运行 `./live_relay`；保留完整 `lib/`、`data/`，可执行权限已保留。本包在Linux x86_64／glibc2.44构建，需GTK3、GLib、libsecret和系统音频／编解码环境；其他发行版未验收。可选隔离Bash另需bubblewrap与util-linux的prlimit。
- 下载同页 `SHA256SUMS`，在两份附件所在目录运行 `sha256sum -c SHA256SUMS`。只下载一个附件时，用对应行核对即可。

旧Header v1／v2与旧备份reader保留；旧库不会自动改写为v3，由本人在安全设置主动升级。SQLCipher schema4→5迁移增加加密本地状态。独立恢复凭证和接收者密码请分别离线保管；新格式备份恢复先重设安全材料，再开放Owner内容。分层原件尚未补齐时不再导出“完整”备份。

## 验证与边界

144项完整测试、Linux原生2项、收尾相关3项和最终静态分析通过；Linux真实SQLCipher迁移／换钥／恢复／分层补齐通过。HPKE通过公开CFRG RFC9180 Base AES256精确向量。Linux真实SenseVoice模型／隔离Bash已验证；独立演示初始化启动通过。Android／Linux正常入口release构建成功，APK v2签名校验通过；生产依赖图及Linux制品与演示种子隔离检查通过。

尚未完成Android实体强生物识别、手机模型／大包资源、Windows运行、真实云Agent API、物理断电或独立安全复核。云摇篮／自动条件、同步／冲突合并、远程撤回、外部Agent／CLI／MCP、语言／视觉／资源优化后置。已经交付的副本无法撤回。接收者回放水位是本机持久状态，没有硬件单调保证。

APK使用现有Android Debug证书，只供内部侧载验收；Release构建模式不表示正式商店发布。仓库可见性保持不变。

## 制品身份

已发布于 `2026-10-03T15:03:07Z`，源码commit `9cf27684b296559748ae46e0223d2538f80d6b49`，`mvp-0.3` annotated tag固定指向该提交；服务端附件身份和源码commit回写仓库 [artifacts.json](https://github.com/BA2F/LiveRelay/blob/main/docs/60_quality/releases/artifacts.json)。

| 附件 | 字节数 | SHA-256 |
| --- | ---: | --- |
| `LiveRelay-MVP0.3-Android.apk` | 189907934 | `766fc249f9749f37e69231a7777a53a30bd65bdd88b3cde14b19ba0c8ac73b9e` |
| `LiveRelay-MVP0.3-Linux-x86_64.tar.gz` | 24132258 | `4f3f3b4c453517f35470d177e3d305420270063d1bdc44adb494dd9ae8bb948f` |

APK签名证书SHA-256：`71bf52ae69bf468f2a2257d81a3a6c5e2c1c0a9a91582925a7e7e82714b2e314`。完整实现与未验证边界见 [本机交付](https://github.com/BA2F/LiveRelay/blob/mvp-0.3/handoffs/2026-10-03_本机安全交接与备份完成.md)。
