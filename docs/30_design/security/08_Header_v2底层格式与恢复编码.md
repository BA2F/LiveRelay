# Header v2 底层格式与恢复编码

> 状态：K1 内部评估实现规格；公共协议／正式默认创建尚未冻结\
> 版本：0.1\
> 日期：2026-10-03\
> 任务：[K1 底层任务](../../../tasks/specs/2026-10-03_K1密钥格式与独立恢复底层.md)

## 决策与适用范围

按 [安全草案](07_正式版密钥恢复与接收者解密设计.md)的候选密钥图实现两个独立单因素分支：password 和 recovery 各保护随机 32-byte B，再由 B 派生密钥保护同一 VMK。不把 UI 条件作为密码学限制。使用完整 Header MAC 验证另一个分支以及全部元数据；取得 VMK 后仍须 MAC 成功才交给会话。

本片只实现默认任一模型的底层；新 suite 名为 `lr-or-recovery-v2-evaluation`。拒绝设备分支、AND、未知 suite 与可选扩展。正式上线前必须完成最弱 Android 设备性能、安全复核、设备因素 K2、保存／回输与备份 K3 的工程验收；生产默认 writer 继续 Header v1。不存在自动升级或私改 v1 格式。正式字段扩展需升 suite 并带旧样本，不能在 evaluation suite 下增加未声明字段。

## Wire schema 与规范字节

文件最多 64 KiB。整个 JSON 为无空白 ASCII 字节，仅允许固定 schema 中的字符串、整数、bool、null、数组与对象。对象键按 ASCII 升序，数组顺序固定。整数 1～2147483647（epoch／generation）；时间为 `DateTime.toUtc().toIso8601String()` 的规范形式；binary 为严格无填充 Base64url，必须重新编码完全相等。解码后严格验证类型、字段集合、长度与值，再重建规范 JSON 并要求原字节完全一致。因此重复键、浮点、额外字段、非规范数字／转义／空白均拒绝。该受限编码参考 [RFC 8785](https://www.rfc-editor.org/rfc/rfc8785)，不实现或宣称支持任意 Unicode／数字的通用 JCS。

顶层精确字段：formatVersion=2、suite、vaultId（16 bytes 小写 hex）、headerEpoch、keyGeneration、createdAt、dailyPolicy="any"、biometricEnabled=false、passwordKind（custom 或 diceware-cn-v1）、wordCount（custom 为 null，词组为 4～12）、recoveryEnabled=true、branches、headerMac（32 bytes）。不含姓名、明文凭证或明文 VMK。

branches 精确为 password、recovery 两项且顺序不变。每项精确字段：branchId、kind（与 ID 相等）、kdfProfile、salt（16 bytes）、factorSlot、keySlot。Slot 精确字段：nonce（12 bytes）、cipherText（32 bytes）、mac（16 bytes）；算法固定 AES-256-GCM，不从外部参数选择。

password 的 kdfProfile 固定 `argon2id-v19-m65536-t3-p1-l32`；recovery 固定 `hkdf-sha256-lrr1`。不同 salt 和四个 nonce；创建使用 CSPRNG，必须拒绝同一 Header 内重复 salt／nonce。没有由外部提供的资源整数，更不进行自动参数降级。v2 密码输入最多 4096 UTF-8 bytes；v1 输入语义不变。

descriptor 是顶层去掉 headerMac，branches 每项去掉 factorSlot／keySlot 后的规范对象。D=SHA256(descriptor bytes)。它包含全部元数据、身份／代次、输入模式、分支用途及参数，密文不进入 D，避免循环。

AAD 是规范数组 `["LiveRelay/Header/v2/" + stage, hex(D), branchId]`，stage 仅 factor 或 master。即使相同凭证被重复使用，也不能跨库／分支／代次移植封装。

## 密钥推导及认证顺序

1. password 的 factor key = Argon2id v19(password UTF-8, salt, 64 MiB, 3 passes, 1 lane, output 32)。仅 canonicalPassword 输入；custom 不规范化，词组由当前 codec 规范化后传入。64 MiB／3 次来自 [RFC 9106 的受限内存推荐](https://www.rfc-editor.org/rfc/rfc9106)，1 lane 为评估选择，尚未通过弱设备性能验收。
2. recovery 的 factor key = HKDF-SHA256(R, salt, info="LiveRelay/Header/v2/RecoveryFactor", output 32)。R 为独立均匀 32-byte 秘密，不对低熵密码使用 HKDF 替代 Argon2。
3. factorSlot 在 factor key 下加密 B，使用 factor AAD。
4. master key wrap key = HKDF-SHA256(B, salt=D, info="LiveRelay/Header/v2/BranchKey/"+branchId, output 32)。keySlot 加密 VMK，使用 master AAD。
5. Header MAC key = HKDF-SHA256(VMK, salt=vaultId bytes, info="LiveRelay/Header/v2/HeaderMac", output 32)。HMAC-SHA256 覆盖去掉 headerMac 的整个规范 Header（包含所有封装密文）。比较采用固定长度常量时间比较。

[RFC 5869](https://www.rfc-editor.org/rfc/rfc5869)支持上述 HKDF 原语；LiveRelay 的用途标签、descriptor、AAD 和两层封装是本项目组合设计。读取先做所有结构／限制验证，再执行一次指定分支的 KDF、factor 解密、VMK 解密、整 Header MAC。任何一步失败不返回 VMK，错误消息合并，不输出输入秘密。B、临时 VMK 及可控制字节尽力清理；不保证 Dart 的隐含内存副本被证明擦除。

## LRR1 恢复编码

R 独立 CSPRNG 32 bytes。文本精确为 `LRR1-` + Base64url(R，无填充，43 字符) + `-` + Base64url(checksum，无填充，6 字符)，共 55 字符。checksum 为 SHA256(UTF8("LiveRelay/RecoveryCredential/LRR1") || R) 的前 4 bytes。校验仅用于输入错误检测，不是口令强化或授权证明。除最外层 trim 外，不纠正字符、不转换大小写、不接受标准 Base64 字符／填充。固定长度解析，错误版本／长度／校验均拒绝。

首片不实现中文恢复词组，避免复用当前权利／版本未固定的日常词表。生成／展示／回输确认交给 K3；R 不进入 Header／日志／默认设备偏好。

## 兼容和失败语义

2026-10-12 追加：v2/v3 的指纹设置更新当前在 `VaultKeyManager` 明确拒绝，原因是 `D = SHA256(descriptor)` 含全部分支与 `biometricEnabled`，增删设备分支会让全部分支密文失效、必须逐个重建，而重建恢复分支需要恢复秘密 R。本人 2026-10-12 确认：改指纹只验证当前主密码，不生成也不回输恢复凭证，因此设备因素要从凭证图解耦（独立设备槽或新 suite），做法与验收见 `tasks/specs/2026-10-12_K3设备因素解耦与指纹开关.md`；在这之前的正式行为不变。

VaultKeyManager 的 reader 支持旧 v1 与受限 v2；v1 writer 保持原状。v1 只接受现有 writer 的算法、19 MiB／2／1／32、16-byte salt 和 AES-GCM 的 12-byte nonce／16-byte tag／32-byte ciphertext；异常参数或未知封装算法在 KDF 前拒绝。未知版本／suite 失败关闭。v2 的指纹设置更新不可复用 v1 的裸 bool 写入，在 K2 完成认证重封装前明确拒绝。

`.lvault` v1 导出和暂存读取必须验证 Header 为 v1；不得把新 Header 隐藏在旧外层。新所有者备份另在 K3 设计 v2；K1 不提供新库的生产创建或备份入口。

完整 Header MAC 阻止内容篡改，不防持有有效旧 Header 的完整磁盘回滚；本片无可信高水位记录，不声称防旧版重放。改密码／撤销 R／强化权限没有实现；旧 VMK 的历史副本与全库换钥边界继续按安全草案解释。

## 验证与反转条件

Python cryptography／OpenSSL 独立生成固定虚构字节样本；Dart 对同样的规范字节、descriptor hash、AAD、密文和 MAC 做互操作。测试 RFC 原语、完整正反矩阵及真实 SQLCipher／Blob。任何组合／互操作缺陷、弱设备资源超预算，或设备上下文无法满足需求，均阻止正式创建上线，修订 suite／协议后重新验收。当前规格不标为已接受的跨模块正式 ADR；验证后记录实际范围与剩余条件。

2026-10-03 本评估片完成上述自动验证及 Android／Linux release 构建，实际结果与未完成条件见 [交付记录](../../../handoffs/2026-10-03_K1密钥格式与独立恢复底层.md)。这不改变正式创建入口的验收条件。

K2 增加独立设备 evaluation suite，旧 suite 字节不变；扩展与原生端口见 [设备分支规格](09_设备因素保护与Header设备分支.md)。
