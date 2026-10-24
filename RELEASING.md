# 版本与安装包发布

安装包发布到 [GitHub Releases](https://github.com/BA2F/LiveRelay/releases)。Git 只保留源码、版本说明和制品身份。APK、AAB、Linux 应用归档和构建缓存不加入源码历史。

## 命名和身份

- MVP 里程碑（历史）使用 `mvp-X.Y` 标签、`LiveRelay · MVP X.Y` 标题和 `LiveRelay-MVPX.Y-Android.apk` 附件。该序列已随 v1.0.0-beta.1 结束，保留为固定历史。
- 语义版本序列使用 `vX.Y.Z`，预发布加后缀如 `-beta.1`。发布前明确应用版本名和递增的 Android `versionCode`。版本在 `pubspec.yaml` 或构建参数中设置并记录。Tag 不会自动改变 APK 内部版本。
- 附件命名随 Tag：`LiveRelay-vX.Y.Z[-pre]-Android.apk`、`LiveRelay-vX.Y.Z[-pre]-Linux-x86_64.tar.gz` 与 `SHA256SUMS`。发布前明确 Android ABI 范围。当前发布包是 arm64 单架构，调试包保留 arm64 和 x86_64。
- 正式签名自 v1.0.0-beta.1 起使用专用 release keystore。`android/key.properties` 指向仓库外或被忽略目录中的密钥库。换签名必须同时说明「须卸载重装并先导出备份」。同一 keystore 丢失后无法再覆盖升级，因此密钥库与密码必须离线备份。
- Linux 附件归档完整 Flutter bundle，保留可执行权限。说明构建发行版、glibc 和运行依赖，不能只上传 runner。独立 demo 不混入生产 bundle。
- 每个版本记录源码 commit、构建日期、包名、最低 SDK、目标 SDK、内部版本和大小。同时记录 SHA-256、签名证书、验证范围与未验证能力。
- 已发布 Tag 和附件作为固定历史保留。修正说明可以更新正文。二进制变化创建新版本，不覆盖同名附件，也不移动 Tag。

## 提交和验证

代码、测试和直接对应的设计或验证文档作为一个完整变更提交。与实现独立的仓库维护文档可以另交一笔。不拆出不可运行的中间代码版本。

在发布的源码状态下完成静态分析、相关测试、Android 构建与签名校验。需要时，完成隔离资料库路径验证。保存确切的成功日志。有新的代码变化时，复核受影响的检查。真实 AI、真机和故障场景未验证时，按事实说明。

构建并记录制品。本地 Java 和 SDK 路径属于环境配置，不入库：

```bash
cd work/code/live_relay
flutter analyze
flutter test
flutter build apk --release --target lib/main.dart
# Linux 发行包从 Ubuntu22.04 基线构建，不能复用 Arch 的插件/CMake 缓存：
# 在仓库根目录调用 scripts/build_linux_ubuntu22.py，具体参数见应用 README。
```

确认 Release APK 的内部版本、签名和 hash。`aapt dump badging` 可以读取包信息。Android build-tools 的 `apksigner verify --verbose --print-certs` 验证证书。把已验证的制品复制到被忽略的 `work/exports/release-artifacts/<tag>/`。改名不重新构建，也不改变内容。

Linux 完整 bundle 不得混入测试或调试残留。Flutter 测试可能在 native_assets 目录留下 debugger 的 `native_assets.json`，其中指向开发路径。CMake 会把它复制到 `bundle/lib`。AOT 发布包不需要这个文件。打包时排除该元数据，保留真实原生库和运行资产。然后验证最终完整包能够启动。其他运行所需的 JSON 不得删除。

在附件目录生成校验文件：

```bash
sha256sum LiveRelay-MVPX.Y-Android.apk LiveRelay-MVPX.Y-Linux-x86_64.tar.gz > SHA256SUMS
```

## 发布顺序

Linux 候选使用[隔离构建脚本](scripts/build_linux_ubuntu22.py)。先审核全部 ELF 的 GLIBC、GLIBCXX、CXXABI 依赖。再在 Ubuntu 22.04 的真实用户空间完成启动和原生资料库验证。运行依赖包含 GTK3、GLib、libsecret、libstdc++。服务密钥存储另需会话 D-Bus 和已解锁的 Secret Service。录音、桌面 GPU 和其他发行版必须分别记录。无声卡的 Xvfb 测试不能写成完整桌面验收。2026-10-04 发现历史 MVP0.3 原包的插件要求 `GLIBC_2.38`。该附件不覆盖，兼容修复进入下一版本。

先推送源码，再发布 annotated Tag，指向明确的 commit。版本说明写入 `docs/60_quality/releases/<tag>.md`。变更摘要链接到 `CHANGELOG.md`。发布说明包含具体变化、安装与兼容性、验证和限制。历史包必须区分构建日期和补录日期。不得补造历史验证结果。

核对 Git 状态和远端状态后执行。以下参数替换为本次的真实值：

```bash
git push origin main
git tag -a <tag> <commit> -m '<version summary>'
git push origin refs/tags/<tag>
gh release create <tag> <apk-path> <checksum-path> \
  --verify-tag --prerelease --latest=false \
  --title '<release title>' --notes-file <release-notes-path>
```

未完成正式验收的包标记为 prerelease，包括 alpha、beta 和 Debug 签名的包。完成签名与验收后，再使用正式发布标记。仓库保持原可见性。发布 Release 不代表把仓库改为公开。

## 发布后核对

- 检查远端 Tag 指向的源码 commit。发布页不得是 draft，附件状态必须是 uploaded。
- 用 `gh release view <tag> --json assets` 核对 GitHub 附件的字节大小和服务端 `digest`。结果必须与本地原文件和 `SHA256SUMS` 一致。也可以下载后重新计算。
- `gh release verify-asset` 依赖 Release attestations，不是普通的 checksum 检查。当前手工发布的版本没有此证明。该命令提示缺少证明时，不得写成验证通过。配置证明后再使用该命令。
- 把实际 URL、发布时间和制品身份回写到 `docs/60_quality/releases/artifacts.json`。同时维护 README 的推荐下载入口和 CHANGELOG。
- 回写文档后提交并推送。确认工作区没有遗漏，`main` 与远端同步。

发布记录不替代产品或领域的正式设计。数据格式或释放规则变化仍按现有治理与兼容性要求处理。
