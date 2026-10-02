# LiveRelay Flutter/Android 应用

应用源码入口。产品用途、安装包和操作入门见 [仓库 README](../../../README.md)。

## 环境

- Flutter stable，Dart 版本符合 `pubspec.yaml`（当前约束 `^3.13.2`）；依赖锁定于 `pubspec.lock`。
- Android SDK、Java 17+；Android 最低 API 24。最近可运行工具链和验证结果见 [质量记录](../../../docs/60_quality/00_测试与验证策略.md)。
- Agent 开发任务使用 [AGENTS.md](../../../AGENTS.md)指定的 Linux 工作区。

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
```

`test/` 包含领域、安全、加密仓储/备份、Provider 边界和 Widget 行为测试。`integration_test/ux_flow_test.dart` 在独立临时资料库中使用真实 SQLCipher、Blob 和 Android ML Kit；离线 AI Provider 记录实际外发文本，验证单次授权，不使用真实 API Key。该测试生成虚构资料，Driver 将运行截图写入 `work/paper/uiux-review-2026-10-01/implementation-screenshots/`。

不要将原用户资料库或真实个人资料作为回归输入。真实服务和实体硬件的验收需单独记录，不用离线测试代替。

## 构建

```bash
flutter build apk --release
```

产物：`build/app/outputs/flutter-apk/app-release.apk`。Java 不在环境路径时，设置 `JAVA_HOME` 和对应 `PATH` 后构建。本机使用 Android Studio 自带 JBR；它是环境配置，不写入仓库。

当前 Release 配置使用内部 Android Debug 证书。正式发布前需配置发布签名并完成安全/真机验收。已发布 APK 的版本、源码提交、证书和校验值见 [发布记录](../../../docs/60_quality/releases/)，流程见 [RELEASING](../../../RELEASING.md)。

## 代码分层

```text
presentation/       Material 3 页面、对话框和设计组件
application/        会话、用例编排、搜索投影和实际释放预览
core/domain/        卡片、凭据、原件、状态和授权模型
core/ports/         Vault / OCR / AI / Biometric 内部端口
core/security/      口令派生与主密钥管理
infrastructure/     SQLCipher、Blob、OCR、AI、备份与平台适配
```

数据库必须检测到 SQLCipher，不会静默降级为明文 SQLite。当前 schema v4、Header/Blob v1、`.lvault` v1 的演进需保留兼容性与旧格式验证证据。新增信息默认仅本人可见，AI/OCR 结果先保存为草稿，编辑追加同记录的新修订。

端口是同一 Flutter package 内部 API，尚未冻结为跨 package 公共契约。具体职责见 [模块索引](../../../docs/40_modules/00_模块索引.md)和 [接口总览](../../../docs/50_interfaces/00_接口总览.md)。
