# LiveRelay Flutter 应用

应用源码入口。产品用途、安装包和操作入门见 [仓库 README](../../../README.md)。

## 环境

- Flutter stable，Dart 版本符合 `pubspec.yaml`（当前约束 `^3.13.2`）；依赖锁定于 `pubspec.lock`。
- Android SDK、Java 17+；Android 最低 API 24。最近可运行工具链和验证结果见 [质量记录](../../../docs/60_quality/00_测试与验证策略.md)。
- Agent 开发任务使用 [AGENTS.md](../../../AGENTS.md)指定的 Linux 工作区。
- Linux 桌面需要 Flutter desktop 工具链、GTK 与 libsecret 开发依赖。Windows 桌面需要 Visual Studio 的“使用 C++ 的桌面开发”工作负载；Windows debug／release 编译、启动和生产入口首次建库已在本机 Windows 11 验证，Windows 指纹与密钥环存储仍未验收。
- Linux 的音频格式转换及视频采样帧需要本机 `ffmpeg` 和 `ffprobe`。语音页接受 WAV、MP3、M4A、MP4、WebM，每次最多 2 MB，完整音轨最多 60 秒；超限明确拒绝，不截断。Agent 的视频预览可检查四帧，完整音轨需单独准备或转写核对后使用。Android 保持原有 WAV 语音入口。

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

Debug 使用 `app.liverelay.live_relay.verification`，显示为“留灯·联调”，与 Release 的 `app.liverelay.live_relay` 分属独立 Android 数据沙箱。测试安装不覆盖正式资料库；不同包之间不会自动共享资料或指纹槽。`integration_test` 的 APK 是测试入口，测试结束后不作为普通软件使用；手工联调须重新构建 `--debug --target lib/main.dart` 并安装。

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

桌面工作台的原生验证使用 `test_driver/native_driver.dart`，目标为 `integration_test/desktop_workbench_test.dart`。同一 checkout 的 Linux 构建共用 bundle，所有原生验证必须顺序执行；完成后重新以 `--target lib/main.dart` 构建正常客户端，集成入口不能作为交付软件。

普通生产入口的首次引导与重开验证使用 `integration_test/desktop_startup_test.dart`，直接调用 `lib/main.dart`，不注入业务服务。必须明确隔离 XDG 数据及临时目录；系统凭据存储使用空内存夹具，不读取本人密钥环。该用例通过真实页面创建 Header v3、回输恢复凭证、选择工作台、在防抖保存前保存锁定，然后卸载页面/控制器并重新调用生产入口解锁，验证加密草稿与起始布局保留。还覆盖双卡选择/数量对象核对/取消/确认回收/界面恢复、工作台切换/重新选择/默认恢复及输入框聚焦时的Ctrl+Shift+P命令。重建组装发生在同一个原生进程内，不冒充进程异常退出；后者见独立关闭用例。

```bash
task_startup_root=$(mktemp -d /tmp/liverelay-production-startup-XXXXXX)
mkdir -p "$task_startup_root/data" "$task_startup_root/cache"
env LIVERELAY_STARTUP_ROOT="$task_startup_root" \
  XDG_DATA_HOME="$task_startup_root/data" TMPDIR="$task_startup_root/cache" \
  flutter drive --driver=test_driver/native_driver.dart \
  --target=integration_test/desktop_startup_test.dart -d linux --no-pub
flutter build linux --debug --target lib/main.dart --no-pub
```

双屏自动验收使用 X11 窗口实际中心点确定当前显示器，再移至不包含该中心点的另一显示器，并断言目标窗口中心已离开原屏。镜像显示器不能证明跨屏；Wayland不使用X11的全局坐标断言。自动程序移动和本人手动标题栏跨屏分别记录。

Windows 生产入口验证在隔离的虚构资料库上运行，路径特意位于 `%APPDATA%` 下，以覆盖拒绝元数据重命名的 Windows 配置目录：

```powershell
flutter test integration_test/windows_vault_creation_test.dart -d windows
```

`test/core/file_commit_test.dart` 在 Windows 使用 `%APPDATA%` 沙箱；其中的跨卷用例默认跳过，指向另一块磁盘上的可写目录时运行，用来确定性地覆盖退化提交：

```powershell
flutter test test/core/file_commit_test.dart --dart-define=LIVERELAY_SECOND_VOLUME=E:/LiveRelayProbe
```

`test/core/recoverable_header_test.dart` 与 `test/infrastructure/vault_restore_transaction_test.dart` 覆盖提交的可恢复性，后者在 Windows 通过 SDK 自带 `dart` 拉起崩溃子进程。范围与取舍见 [Windows 桌面适配验证](../../../docs/60_quality/2026-10-18_Windows桌面适配验证.md)。

`formal_foundation_desktop_test.dart` 使用临时目录和真实 SQLCipher，验证首次设置、偏好保存、统一卡片视图、平台能力提示、重新解锁和备份核对。可传入 `--dart-define=FOUNDATION_SCREENSHOTS=/绝对输出目录` 保存虚构资料截图。

## 构建

```bash
flutter build apk --release
flutter build linux --release
# 在 Windows 主机运行
flutter build windows --release
```

产物：`build/app/outputs/flutter-apk/app-release.apk`。Java 不在环境路径时，设置 `JAVA_HOME` 和对应 `PATH` 后构建。本机使用 Android Studio 自带 JBR；它是环境配置，不写入仓库。

Release 配置在 `android/key.properties` 存在时使用专用 release keystore；文件缺失时才回退 debug 证书，回退产物不得对外发布。已发布 APK 的版本、源码提交、证书和校验值见 [发布记录](../../../docs/60_quality/releases/)，流程见 [RELEASING](../../../RELEASING.md)。

Arch／新 glibc 环境的原生插件可能引入旧发行版不存在的符号；MVP0.3 的 secure-storage 插件实际要求 `GLIBC_2.38`，无法在 Ubuntu22.04 启动。MVP0.4已从Ubuntu22.04构建并检查全部ELF；后续Linux发布继续使用已验证的 [隔离构建脚本](../../../scripts/build_linux_ubuntu22.py)：

```bash
# 从仓库根目录；rootfs 须预先安装 clang、cmake、ninja-build、pkg-config、
# libgtk-3-dev、libsecret-1-dev、git、curl、unzip、xz-utils、ca-certificates。
python3 scripts/build_linux_ubuntu22.py --rootfs <Ubuntu22.04独立rootfs目录> \
  --flutter-sdk <FlutterSDK目录> --pub-cache <Pub缓存目录> --build-number 3
```

宿主需 Python3、readelf、bubblewrap 和可用 user namespaces。只挂载应用、SDK 和 hosted 包缓存，不挂载真实资料库；脚本清理 release CMake 缓存，防止混用宿主路径，输出 GLIBC／GLIBCXX／CXXABI 审计。完整 bundle 运行需 GTK3、GLib、libsecret、libstdc++、桌面图形环境；AI Key 存储另需会话 D-Bus 和 Secret Service（例如已解锁的 GNOME Keyring），Linux录音另需parecord、ffmpeg和系统音频服务。已验证 Ubuntu22.04 隔离 Xvfb 启动、原生交接及Secret Service；EndeavourOS正常桌面候选和语音现场试用由本人确认正常。无声卡的 rootfs 不代表完整桌面音频验收，更多发行版／声卡仍待覆盖。已有 Tag／附件保持原样。

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

K2 新增 Android 原生 DeviceFactorChannel 和 DeviceFactorProtection，只保护随机设备分支秘密并要求每次强生物识别授权；新设备 suite 与旧 VMK namespace 分离，桌面返回不支持。本机设置与恢复已在 v3 实现；2026-10-04小米13Android13已验证真实启用／解锁／后台取消和换钥恢复，其他机型及录入新指纹失效仍待验证。测试软件设备替身位于 test/support，不作为生产回退。独立 writer 可添加 --device 生成公开虚构设备 suite 样本；Python reader 可认证其密码／恢复路径和整 Header，不能代替 Keystore 测试。

## 桌面工作台使用

Linux正常客户端解锁后选择“资料工作台”或“助手工作台”；选择会保存，右上菜单可以重新选择或恢复默认。左侧图标打开资料、助手、关系、变更、原件等；拖动图标或标签到四侧分屏、中央合并，拖到左侧浮动入口在工作台内浮动。浮动标题可移动、右下角可缩放；“移到独立桌面窗口”打开真实OS窗口，可移到另一显示器。独立窗口关闭/合并回主工作台，锁定后全部撤销。

卡片编辑自动保存，仍保持原草稿/确认状态；✓明确确认，×核对后进入回收站。引用、来源和收纳分别管理，确认来源及旧修订不会随新会话改变。关系视图显示实际引用及共享来源，分类标签不会生成两两关系。

助手保留多轮对话，每次发送核对当前文字、历史重放和附件范围；附件只在会话中，另存原件需单独选择。Linux音频/视频预览可准备完整WAV音轨或转写并核对后采用文字；视频先检查采样帧。AI建议和模型计划可编辑/逐项采用，最终确认才存入资料库；默认私密，真实交接仍另行选择接收者与范围。

主窗口Ctrl+Shift+P打开命令面板；独立窗口有命令面板及资料库工具菜单。资料库工具回主窗口处理密码、安全设置、身份交接和回收。扩展页可安装本地JSON声明式扩展、启停、调整已注册设置、移除；停用撤销贡献的视图和命令，不删除本人资料。桌面听写默认不存录音，核对回填不自动发送；手机保留既有默认。软件Logo/Icon使用work/design/brand/2026-10-04-icon-draft的静态产品标识，动效后置。

## 软件基础使用

密码库新建／编辑凭据可选择随机密码生成，调整长度与字符类别后选用；已有中文词组生成器保留，默认遮挡和限时复制不变。

“我的 → AI 服务设置”选择 Responses，填写兼容 HTTPS 地址（例如 `https://api.openai.com/v1/responses`）、模型与自己的服务密钥；“Agent 整理”粘贴本次文字、标记敏感行并确认外发范围。结果需本人核对后保存。Linux 支持本次可选隔离命令，需系统 `/usr/bin/bwrap`、Bash、prlimit 及可用 user namespaces；探测失败不会运行宿主命令，其他平台仍能云文字整理。本人已在手机确认受控DeepSeek服务／deepseek-flash真实调用正常；当前Agent建议仍保存为普通卡片，密码子类型录入／转换尚未贯通。

“记录／我的 → 本地语音输入”明确下载约 156 MB 官方模型或导入相同官方包，预留约 1 GB 安装空间。录音最长 60 秒，或导入 16 kHz 单声道 PCM16 WAV；原件加密保存，本地识别后核对文字、保存关联草稿。模型单独存储和卸载，APK 不内置权重。Linux和小米13真模型已跑通；5.592秒公开WAV真机转写1489ms、500ms采样进程RSS峰值约837MiB，更低资源手机与Windows运行仍待验收。

公开样本验证工具（不用真实资料库／音频／API Key）：

```bash
dart run test/support/speech_smoke.dart <官方模型压缩包> <隔离模型目录> <公开WAV>
dart run test/support/agent_sandbox_smoke.dart
```

当前软件基础进度见 [交付](../../../handoffs/2026-10-03_软件基础加速交付.md)，本机恢复、真实限定范围交接和分层备份已实现，云摇篮仍后置；最新实际验收见 [2026-10-04验证](../../../docs/60_quality/2026-10-04_实际联调验证.md)。

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

原生主窗口关闭/强制退出验证目标为 `integration_test/desktop_close_test.dart`，同样使用 `test_driver/native_driver.dart`。子进程只创建公开密码的临时合成库，复用生产 NativeCloseGuard/WorkbenchRuntime；测试拒绝关闭、保存退出以及 SIGKILL 后已提交数据恢复，不保证强杀时尚未保存的编辑。证据目录应预先创建，最后必须重建正常 main。

真实多模态补验使用 `test/support/deepseek_vision_smoke.dart`，固定只读取仓库公开色块图片、生成公开视频并发送采样帧。普通测试不执行这个工具；仅在本人授权真实请求后，关闭终端回显并从 stdin 提供密钥，结束恢复回显，密钥不进入参数、环境或文件。DeepSeek Flash 的图片能力需在服务设置中显式勾选，PDF／音频能力不随之启用。

真实本地模型补验目标 `integration_test/desktop_public_speech_test.dart` 使用同一 native driver；必须指定公开模型根目录 `LIVERELAY_PUBLIC_SPEECH_MODEL_ROOT` 和公开样本 `LIVERELAY_PUBLIC_SPEECH_WAV`，否则跳过。测试导入公开 WAV，验证识别、默认不存原件、回填和明确存库重开，不自动录麦克风。正常交付仍最后重建 `lib/main.dart`。
