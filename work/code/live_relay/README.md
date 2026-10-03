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

数据库必须检测到 SQLCipher，不会静默降级为明文 SQLite。当前 schema v4、Header/Blob v1、`.lvault` v1 的演进需保留兼容性与旧格式验证证据。新增信息默认仅本人可见，AI/OCR 结果先保存为草稿，编辑追加同记录的新修订。

端口是同一 Flutter package 内部 API，尚未冻结为跨 package 公共契约。具体职责见 [模块索引](../../../docs/40_modules/00_模块索引.md)和 [接口总览](../../../docs/50_interfaces/00_接口总览.md)。

恢复事务记录、incoming 与 rollback 位于运行库外；未完成恢复启动时保守找回原库，无法安全判断时保留文件并停止创建。Header 暂存／前序文件以 `.tmp` 结尾，不进入 `.lvault`。日常仍支持密码或已启用的生物识别；独立恢复凭证尚待实现，不能把当前日常口令标成恢复钥匙。

应用组装入口为 `infrastructure/app_composition.dart`，由 main 和隔离原生测试调用。`VaultSession` 统一管理会话密钥、数据库与原件访问，`VaultBackupService` 编排认证核对／导出／恢复；控制器保留页面状态和数据投影。新会话测试覆盖密钥副本清理、数据库替换、关闭失败及 dispose；不把界面测试的模拟状态写回真实会话。
