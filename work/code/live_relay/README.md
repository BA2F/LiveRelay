# LiveRelay Flutter 应用

应用源码入口。产品用途、安装包和操作入门见 [仓库 README](../../../README.md)。

## 环境

- Flutter stable，Dart 版本符合 `pubspec.yaml`（当前约束 `^3.13.2`）；依赖锁定于 `pubspec.lock`。
- Android SDK、Java 17+；Android 最低 API 24。最近可运行工具链和验证结果见 [质量记录](../../../docs/60_quality/00_测试与验证策略.md)。
- Agent 开发任务使用 [AGENTS.md](../../../AGENTS.md)指定的 Linux 工作区。
- Linux 桌面需要 Flutter desktop 工具链、GTK 与 libsecret 开发依赖；Windows runner 已生成，Windows 编译及安全存储需在 Windows 验证。

## 运行

从仓库根目录进入应用目录：

```bash
cd work/code/live_relay
flutter pub get
flutter devices
flutter run -d <device-id>
```

Drift 生成文件已纳入源码。修改数据库表定义后重新生成：

```bash
dart run build_runner build
```

Debug 使用 `app.liverelay.live_relay.verification`，与 Release 的 `app.liverelay.live_relay` 分属独立 Android 数据沙箱。测试安装不覆盖正式资料库；不同包之间不会自动共享资料或指纹槽。

## 检查与测试

```bash
flutter analyze
flutter test
flutter drive --driver=test_driver/ux_driver.dart --target=integration_test/ux_flow_test.dart -d <android-device-id>
flutter test integration_test/formal_foundation_desktop_test.dart -d linux
flutter test integration_test/restore_recovery_desktop_test.dart -d linux --dart-define=RESTORE_TEST_PROJECT="$PWD"
```

`test/` 包含领域、安全、加密仓储/备份、Provider 边界和 Widget 行为测试。`integration_test/ux_flow_test.dart` 在独立临时资料库中使用真实 SQLCipher、Blob 和 Android ML Kit；离线 AI Provider 记录实际外发文本，验证单次授权，不使用真实 API Key。该测试生成虚构资料，Driver 将运行截图写入 `work/paper/uiux-review-2026-10-01/implementation-screenshots/`。

不要将原用户资料库或真实个人资料作为回归输入。真实服务和实体硬件的验收需单独记录，不用离线测试代替。

`formal_foundation_desktop_test.dart` 使用临时目录和真实 SQLCipher，验证首次设置、偏好保存、统一卡片视图、平台能力提示、重新解锁和备份核对。可传入 `--dart-define=FOUNDATION_SCREENSHOTS=/绝对输出目录` 保存虚构资料截图。

## 构建

```bash
flutter build apk --release
flutter build linux --release
# 在 Windows 主机运行
flutter build windows --release
```

产物：`build/app/outputs/flutter-apk/app-release.apk`。Java 不在环境路径时，设置 `JAVA_HOME` 和对应 `PATH` 后构建。本机使用 Android Studio 自带 JBR；它是环境配置，不写入仓库。

当前 Release 配置使用内部 Android Debug 证书。正式发布前需配置发布签名并完成安全/真机验收。已发布 APK 的版本、源码提交、证书和校验值见 [发布记录](../../../docs/60_quality/releases/)，流程见 [RELEASING](../../../RELEASING.md)。

正式版第一切片新增首次设置、我的、可持久化外观和宽屏导航。设备偏好只存外观、字级与引导标记，不包含密钥或身份权限；已有 Vault 不重新创建。密码卡片摘要与密码库操作同一凭据，秘密仅在专门操作中出现。语言目前仅完成简体中文。后续产品范围见 [正式版演进](../../../docs/20_product/16_正式版演进与已确认范围.md)。

## 代码分层

```text
presentation/       Material 3 页面、对话框和设计组件
application/        会话、用例编排、搜索投影和实际释放预览
core/domain/        卡片、凭据、原件、状态和授权模型
core/ports/         Vault / Blob / OCR / AI / Biometric 内部端口
core/security/      口令派生与主密钥管理
infrastructure/     SQLCipher、Blob、OCR、AI、备份与平台适配
```

数据库必须检测到 SQLCipher，不会静默降级为明文 SQLite。当前 schema v5、主界面新建 Header v3／Blob v1、Owner `.lvault` v2；兼容旧 Header v1／v2 reader 与 `.lvault` v1。旧库仅在本人安全设置操作时升级 Header。新增信息默认仅本人可见，AI/OCR 结果先保存为草稿，编辑追加同记录的新修订。

端口是同一 Flutter package 内部 API，尚未冻结为跨 package 公共契约。具体职责见 [模块索引](../../../docs/40_modules/00_模块索引.md)和 [接口总览](../../../docs/50_interfaces/00_接口总览.md)。

恢复事务记录、incoming 与 rollback 位于运行库外；未完成恢复启动时保守找回原库，无法安全判断时保留文件并停止创建。Header 暂存／前序文件以 `.tmp` 结尾，不进入 `.lvault`。日常仍支持密码或已启用的生物识别；独立恢复进入受限安全重设；保存新凭证并完成全库换钥后才转普通会话。

应用组装入口为 `infrastructure/app_composition.dart`，由 main 和隔离原生测试调用。`VaultSession` 统一管理会话密钥、数据库与原件访问，`VaultBackupService` 编排认证核对／导出／恢复；控制器保留页面状态和数据投影。新会话测试覆盖密钥副本清理、数据库替换、关闭失败及 dispose；不把界面测试的模拟状态写回真实会话。

K1 已有 `VaultHeaderV2` evaluation codec、独立 LRR1、整 Header MAC 和 v1/v2 reader；该评估片当时默认创建 v1；当前主流程用独立 v3，`.lvault` v1 仍拒绝 v2／v3 Header。工程规格与正式创建前置条件见 [Header v2](../../../docs/30_design/security/08_Header_v2底层格式与恢复编码.md)，不把独立测试样本当成用户库升级方案。

新格式原生验证（仅独立虚构资料库）：

```bash
flutter test integration_test/header_v2_desktop_test.dart -d linux --no-pub --dart-define=HEADER_TEST_PROJECT="$PWD"
```

`test/fixtures/header_v2/` 全部为公开虚构密码／密钥样本；Python reference 与 Dart writer 支持双向互操作，使用带 Argon2id 的 Python cryptography（本轮 50.0.1）。独立验证代码位于 `test/support/header_v2_reference.py` 和 `header_v2_dart_writer.dart`，不会读取真实用户库。

K2 新增 Android 原生 DeviceFactorChannel 和 DeviceFactorProtection，只保护随机设备分支秘密并要求每次强生物识别授权；新设备 suite 与旧 VMK namespace 分离，桌面返回不支持。本机设置与恢复已在 v3 实现，Android 真机验证未完成。测试软件设备替身位于 test/support，不作为生产回退。独立 writer 可添加 --device 生成公开虚构设备 suite 样本；Python reader 可认证其密码／恢复路径和整 Header，不能代替 Keystore 测试。

## 软件基础使用

密码库新建／编辑凭据可选择随机密码生成，调整长度与字符类别后选用；已有中文词组生成器保留，默认遮挡和限时复制不变。

“我的 → AI 服务设置”选择 Responses，填写兼容 HTTPS 地址（例如 `https://api.openai.com/v1/responses`）、模型与自己的服务密钥；“Agent 整理”粘贴本次文字、标记敏感行并确认外发范围。结果需本人核对后保存。Linux 支持本次可选隔离命令，需系统 `/usr/bin/bwrap`、Bash、prlimit 及可用 user namespaces；探测失败不会运行宿主命令，其他平台仍能云文字整理。真实服务尚未用受控 Key 联调。

“记录／我的 → 本地语音输入”明确下载约 156 MB 官方模型或导入相同官方包，预留约 1 GB 安装空间。录音最长 60 秒，或导入 16 kHz 单声道 PCM16 WAV；原件加密保存，本地识别后核对文字、保存关联草稿。模型单独存储和卸载，APK 不内置权重。Linux 真模型已跑通，手机资源与 Windows 运行仍待验收。

公开样本验证工具（不用真实资料库／音频／API Key）：

```bash
dart run test/support/speech_smoke.dart <官方模型压缩包> <隔离模型目录> <公开WAV>
dart run test/support/agent_sandbox_smoke.dart
```

当前软件基础进度见 [交付](../../../handoffs/2026-10-03_软件基础加速交付.md)，恢复产品流程、真实限定范围交接、摇篮／分层备份继续开发。

## 本机安全、身份、交接与分层备份

新建库会显示独立 LRR1 恢复凭证，要求单独保存并完整回输。已有库在“我的→资料库设置→解锁方式与独立恢复”主动升级，选择主密码、可选随机32字节密钥文件／本机指纹，以及任一或全部方式；保存新 R 后重新加密数据库和原件。旧备份继续使用旧凭证。

锁定页可用独立 R 进入安全重设，不能直接查看资料；新格式备份恢复也经过重设和换钥。“本人身份与接收者”可编辑加密身份资料，导出公开身份并验证接收者挑战；“交接→真实限定范围交接”逐次核对记录、可见级别、历史及原件后导出 `.lrshare`。接收者首次使用／锁定入口独立存在，使用独立密码和 `.lridentity`，接收包只读保存，既无 Owner VMK 也无 Owner 数据库。

“我的→拆分备份”导出同一快照的数据库包和原件包，可先恢复数据库再导入配对原件，明确显示缺失数量。当前按内存构建，单组大包及手机资源仍需后续优化和验收。详细内部格式见 [安全10](../../../docs/30_design/security/10_本机安全流程与格式v3.md)和[安全11](../../../docs/30_design/security/11_本机交接与分层备份格式.md)。

独立演示启动：

```bash
flutter run -d linux --target lib/main_debug_demo.dart
flutter test integration_test/local_completion_desktop_test.dart -d linux
```

演示每次使用新的系统临时目录，内置虚构 Owner／接收者；“我的”版本号连续七次点击可展开浮层。默认 main 不导入演示实现。说明见 [独立演示构建](../../../docs/30_design/platform/03_独立调试演示构建.md)。云端摇篮／同步、其他语言和外观优化由人类明确后置；软件实现不代替真实硬件与正式发行验收。
