# LiveRelay · MVP 0.4 — 真机指纹与Linux兼容修复

2026-10-04实际联调修复预发布，提供正常main入口Android Release APK和Linux x86_64完整应用包，内部版本 `1.0.0+3`。源码commit `6fbee32819fdc50413f80ec8e8561c450a0b4735`，Tag为 `mvp-0.4`；MVP0.3及更早Tag／附件保持固定。

## 修复与实际联调

- 修复Android启用指纹失败：每次授权Keystore Cipher在实际指纹授权成功后提交AAD，再处理密文。
- 修复指纹解锁误报数据库错误：平台通道只读份额复制为自有可写缓冲区，清理不再抛UnsupportedError；取消／设备失效保留准确错误提示。
- 修复Linux包在Ubuntu22.04因 `GLIBC_2.38` 不能启动的问题：从Ubuntu22.04基线隔离构建，审核全部ELF的GLIBC／GLIBCXX／CXXABI。
- 小米13／Android13真实指纹启用、密码／指纹解锁、后台取消、换钥、独立恢复和分层补齐通过；两个独立身份的限定范围交付与重开在Android和Ubuntu22.04通过。
- 本人确认正常手机UI录音转写、草稿保存重开与来源音频播放正常；受控DeepSeek Responses／deepseek-flash真实Agent调用正常。本人按Linux电脑端语音测试指引反馈“测试了，ok”。这些为现场人类验收，不补造调用或分项录音日志。
- 修正架构／平台总览中过时实现事实，明确当前本机版边界与未来规划。

## 下载和升级

- Android：`LiveRelay-MVP0.4-Android.apk`，Android7／API24+，targetAPI36，包名 `app.liverelay.live_relay`，版本名 `1.0.0`、构建号 `3`，标签“留灯”。与MVP0.3同证书／包名，可覆盖升级；请先导出并另存加密备份，不通过卸载升级。手机当前的“留灯·联调”是独立 `.verification` 包，新发布正常包与它分别保留资料。
- Linux：`LiveRelay-MVP0.4-Linux-x86_64.tar.gz`，解压进入 `LiveRelay-MVP0.4-Linux-x86_64`，运行 `./live_relay`；保留全部 `lib/`、`data/`及可执行权限。构建基线Ubuntu22.04／glibc2.35，ELF最高GLIBC2.34、GLIBCXX3.4.29、CXXABI1.3.7；已在Ubuntu22.04隔离运行及EndeavourOS现场验证，其他发行版仍需验证。
- Linux基础依赖：GTK3、GLib、libsecret、libstdc++和桌面图形环境；服务密钥存储需会话D-Bus及已解锁的Secret Service。录音需parecord、ffmpeg及系统音频服务；可选隔离Bash需bubblewrap、prlimit和可用user namespaces。Ubuntu22.04录音依赖可安装 `pulseaudio-utils` 与 `ffmpeg`，兼容的Pulse音频服务可由PulseAudio或PipeWire提供。
- 下载同页 `SHA256SUMS`，在附件目录运行 `sha256sum -c SHA256SUMS`。仅下载一个附件时核对对应行。

语音模型另行在“本地语音输入”下载／导入，未内置安装包。原Header v1／v2和旧备份reader保持兼容；本轮不改变Header v3、schema v5或交付／备份格式，也不自动迁移旧库。

## 验证与限制

在发布源码状态下静态分析和13项必要安全回归通过；正常Android／Linux Release重新构建，Android包信息和v2签名核对通过，APK DEX含修复后的原生授权路径。Linux全部ELF ABI通过，最终完整包在独立Ubuntu22.04 HOME／D-Bus／Keyring／Xvfb下1280×720窗口实际显示。Linux最终20个运行文件与本人桌面试用候选逐文件摘要完全相同；排除了Flutter测试遗留的开发路径debugger元数据。隔离Xvfb启动不作为真实麦克风证明，桌面音频依据本人现场反馈。

公开5.592秒WAV在小米13本地转写1489ms；500ms周期采样VmRSS峰值约837MiB，仅为代表性链路，低资源设备仍需验收。详细现场证据见[实际联调记录](https://github.com/BA2F/LiveRelay/blob/main/docs/60_quality/2026-10-04_实际联调验证.md)。

已知缺口：Agent账号密码建议仍保存为普通LifeCard，未接通密码库Credential录入／转换，按本人要求后续修复；普通正文不享受专门密码字段的遮挡。更多Android机型、指纹重新录入失效、密钥文件／全部因素、更多Linux声卡／发行版与日常密钥环、Windows／macOS、正式签名及独立安全复核仍待验收。云端摇篮、同步、自动条件释放、外部Agent／CLI／MCP、语言和视觉优化后置。

APK为Release构建，但使用原内部Android Debug证书，仅供侧载验收，标记prerelease；仓库可见性保持不变。真实手机链路使用隔离verification包，没有覆盖／检查用户生产资料库。

## 制品身份

已发布于 `2026-10-04T10:16:31Z`，[Release](https://github.com/BA2F/LiveRelay/releases/tag/mvp-0.4)非draft且标记prerelease。3份GitHub附件大小／digest与下表本地身份逐一匹配，远端annotated Tag解引用指向上述源码commit。

| 附件 | 字节数 | SHA-256 |
| --- | ---: | --- |
| `LiveRelay-MVP0.4-Android.apk` | 189907938 | `ed2d92929272976dbbb97639b8835e3966208175e438d79cdc46252a7fe9a5fe` |
| `LiveRelay-MVP0.4-Linux-x86_64.tar.gz` | 24263999 | `4cfd839941b7223ec6862bfed25c80a772e1bbc6cc3dcd36dbfd63d4f1d1d77c` |
| `SHA256SUMS` | 198 | `dcd36fd994a8f065148fd0689794b4f30d47262bd1f742f4fdec7fbd400c565a` |

APK签名证书SHA-256：`71bf52ae69bf468f2a2257d81a3a6c5e2c1c0a9a91582925a7e7e82714b2e314`。发布URL、实际发布时间和服务端附件摘要核对回写[artifacts.json](https://github.com/BA2F/LiveRelay/blob/main/docs/60_quality/releases/artifacts.json)，不宣称存在Release attestation。
