# Android 明文 HTTP 放行 A/B 实测证据（2026-10-15）

目的：验证 Android 平台是否拦截 App 的明文 HTTP 请求。此前按 Flutter 官方文档判断"明文会被拦、需要放行配置"，本次用实测确认这个判断在当前 Flutter 版本上是否成立。

方法：临时探针入口（验证后已删除）向云端 `http://47.121.136.8:3923/test3/` 发 WebDAV PROPFIND（故意用错密码），在 Android 模拟器（flutter_chain_demo）上分别以两种配置运行：

1. 基线：未做任何明文配置 → `probe-baseline.png`、`build-baseline.log`
2. 放行后：AndroidManifest 加 `android:usesCleartextTraffic="true"` → `probe-cleartext-on.png`、`build-cleartext-on.log`

结果：两种配置下探针都收到服务器的 401（文案"云端拒绝访问：检查网址、账号密码与目录权限"），请求都到达了云端。当前 Flutter 引擎在 Android 上不拦 Dart 层明文请求；放行配置作为厂商 ROM 与后续 Android 版本收紧的兼容性保险保留。

同日在宿主机用真实测试账号核对服务器：PROPFIND 207、坏密码 401。

附带：本日构建曾被 `dl.google.com` 网络问题卡死（integration_test 插件的动态版本依赖需联网列版本），修复见同轮 `android/build.gradle.kts` 的钉版本改动。
