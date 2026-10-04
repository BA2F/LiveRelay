# 版本与安装包发布

安装包发布到 [GitHub Releases](https://github.com/BA2F/LiveRelay/releases)，Git 保留源码、版本说明和制品身份，APK/AAB、Linux应用归档与构建缓存不加入源码历史。

## 命名和身份

- MVP 里程碑使用 `mvp-X.Y` 标签、`LiveRelay · MVP X.Y` 标题及 `LiveRelay-MVPX.Y-Android.apk` 附件。
- 正式语义版本使用 `vX.Y.Z`；发布前明确应用版本名及递增的 Android `versionCode`，在 `pubspec.yaml` 或构建参数中设置并记录。Tag 不会自动改变 APK 内部版本。
- MVP 0.1/0.2 是原包归档例外：两版内部 `1.0.0+1` 保持原样；后续新构建必须递增 Android build number。
- Linux附件使用 `LiveRelay-MVPX.Y-Linux-x86_64.tar.gz`，归档完整Flutter bundle，保留可执行权限；说明构建发行版／glibc及运行依赖，不能只上传runner。独立demo不混入生产bundle。
- 每个版本记录源码 commit、构建日期、包名、最低/目标 SDK、内部版本、大小、SHA-256、签名证书、验证范围及未验证能力。
- 已发布 Tag 和附件作为固定历史保留。修正说明可以更新正文；二进制变化创建新版本，不覆盖同名附件或移动 Tag。

## 提交和验证

代码、测试及直接对应的设计/验证文档作为一个完整变更提交。与实现独立的仓库维护文档可以另交一笔，不拆出不可运行的中间代码版本。

在发布的源码状态下完成静态分析、相关测试、Android 构建与签名校验，以及必要的隔离资料库路径验证。保存确切成功日志；有新的代码变化就复核受影响检查。真实 AI、真机与故障场景未验证时按事实说明。

构建并记录制品；本地 Java/SDK 路径属于环境配置，不入库：

```bash
cd work/code/live_relay
flutter analyze
flutter test
flutter build apk --release --target lib/main.dart
# Linux 发行包从 Ubuntu22.04 基线构建，不能复用 Arch 的插件/CMake 缓存：
# 在仓库根目录调用 scripts/build_linux_ubuntu22.py，具体参数见应用 README。
```

确认 Release APK 的内部版本、签名和 hash。`aapt dump badging` 可读取包信息；Android build-tools 的 `apksigner verify --verbose --print-certs` 验证证书。复制已验证制品到被忽略的 `work/exports/release-artifacts/<tag>/`；改名不重新构建，也不改变内容。

Linux完整bundle不得混入测试／调试残留。Flutter测试可能在native_assets目录留下指向开发路径的debugger `native_assets.json`，继而被CMake复制到bundle/lib；AOT发布包不需要该文件。打包时排除该元数据，保留真实原生库和运行资产，再验证最终完整包启动；不删除其他运行所需JSON。

在附件目录生成校验文件：

```bash
sha256sum LiveRelay-MVPX.Y-Android.apk LiveRelay-MVPX.Y-Linux-x86_64.tar.gz > SHA256SUMS
```

## 发布顺序

Linux 候选使用 [隔离构建脚本](scripts/build_linux_ubuntu22.py)，审核全部 ELF 的 GLIBC、GLIBCXX、CXXABI 依赖后，在 Ubuntu22.04 真实用户空间完成启动／原生资料库验证。运行依赖包含 GTK3、GLib、libsecret、libstdc++；服务密钥存储另需会话 D-Bus 和已解锁 Secret Service。录音、桌面 GPU 和其他发行版须分别记录，不能把无声卡 Xvfb 测试写成完整桌面验收。2026-10-04 已发现历史 MVP0.3 原包的插件要求 `GLIBC_2.38`；其附件不覆盖，兼容修复进入下一版本。

先推送源码，再发布指向明确 commit 的 annotated Tag。版本说明写入 `docs/60_quality/releases/<tag>.md`，变更摘要链接于 `CHANGELOG.md`。发布说明包含具体变化、安装/兼容性、验证与限制；历史包须区分构建日期和补录日期，不补造历史验证结果。

在 Git 状态和远端状态已核对后执行（替换参数为本次真实值）：

```bash
git push origin main
git tag -a <tag> <commit> -m '<version summary>'
git push origin refs/tags/<tag>
gh release create <tag> <apk-path> <checksum-path> \
  --verify-tag --prerelease --latest=false \
  --title '<release title>' --notes-file <release-notes-path>
```

MVP、Debug 签名或未完成正式验收的包标记为 prerelease。正式发布完成签名与验收后再使用正式发布标记。仓库保持原可见性；发布 Release 不代表改为公开仓库。

## 发布后核对

- 检查远端 Tag 指向的源码 commit；发布页不是 draft，附件状态为 uploaded。
- 通过 `gh release view <tag> --json assets` 核对 GitHub 附件字节大小和服务端 `digest`，与本地原文件及 `SHA256SUMS` 一致；也可下载后重新计算。
- `gh release verify-asset` 依赖 Release attestations，并非普通 checksum 检查。当前手工发布的 MVP 没有此证明，不能将该命令的缺失证明提示写成验证通过；后续配置证明后再使用。
- 将实际 URL、发布时间和制品身份回写 `docs/60_quality/releases/artifacts.json`；维护 README 的推荐下载入口及 CHANGELOG。
- 文档回写后提交并推送，确认工作区无遗漏、`main` 与远端同步。

发布记录不替代产品/领域的正式设计。数据格式或释放规则变化仍按现有治理与兼容性要求处理。
