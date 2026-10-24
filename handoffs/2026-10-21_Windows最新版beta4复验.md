# Windows 最新版 beta.4 复验

> 状态：已完成
> 日期：2026-10-21（Asia/Shanghai）
> 源码：`120e5d8`（`origin/main`，v1.0.0-beta.4）
> 分支：`codex/windows-adaptation`
> 基准：[Windows 桌面适配验证](../docs/60_quality/2026-10-18_Windows桌面适配验证.md)

## 本轮结果

远端没有新的独立开发分支，只有 `main`。主线已新增 beta.3／beta.4 的取件码交接和摇篮邮件功能，Windows 文件提交适配仍在主线中。本地分支已快进到 `120e5d8` 并完成 Windows 复验。

修改只有 `integration_test/windows_vault_creation_test.dart`：锁定页从旧的“查看交接内容”改为“打开交接包”后选择“查看本机交接内容”。业务代码和格式未改。

## 验收

| 检查 | 结果 |
|---|---|
| `flutter analyze --no-pub` | 无问题 |
| `flutter test` | 332 通过、7 跳过、0 失败 |
| Windows 原生生产入口用例 | 通过 |
| `flutter build windows --release --no-pub` | 通过 |

Windows 原生用例覆盖首次设置、Header v3 与 SQLCipher 建库、进入工作台、本机交接内容落盘、锁定后通过新入口查看。

## 产物

- `work/code/live_relay/build/windows/LiveRelay-v1.0.0-beta.4-Windows-x64.zip`
- 大小：29,276,357 字节
- SHA-256：`92f367ade08e67de9f267d698d8c1e2dc3f2157f07c571241f3b782cb91eb910`

解压后运行 `live_relay.exe`。产物位于 Git 忽略的 `build/` 目录，不进入源码提交。

## 未完成

- Windows 指纹与密钥环通信、身份严格模式、备份恢复、真实 WebDAV 取件和邮件收件未做人工走查。
- 未配置 Windows 代码签名和安装器；`Nuget.exe not found` 下载提示没有阻止构建。
- 本次测试交互修改尚未提交或推送。
