# 设备因素保护与 Header 设备分支

> 状态：内部评估实现；Android 真机与正式安全验收未完成
> 版本：0.1
> 最后更新：2026-10-03
> 依据：[K1 受限格式](08_Header_v2底层格式与恢复编码.md)、[安全设计草案](07_正式版密钥恢复与接收者解密设计.md)

## 契约与兼容

K1 的 `lr-or-recovery-v2-evaluation` 字节不变，仍只接受 password／recovery 两分支。K2 增加独立 suite `lr-or-recovery-device-v2-evaluation`，格式版本仍 2，biometricEnabled 必须 true，三个分支固定顺序 password、recovery、device。默认应用创建仍 v1；旧 VMK store 仅供 v1 兼容，不参与新 suite。AND、设备变更／关闭后的认证重封装尚未接入设置工作流。

前两个分支遵循 K1。device 精确字段为 branchId=`device`、kind=`device`、deviceProfile=`android-keystore-aes256-gcm-biometric-per-use-v1`、deviceReference（16-byte 随机小写 hex）、factorSlot、keySlot；不接受 salt 或 kdfProfile。两个 slot 都使用 nonce 12、cipherText 32、mac 16 的严格无 padding Base64url。Header 总预算、整数、输入、编码、nonce 唯一限制均保留。未知 profile 或旧 suite 中出现第三分支失败关闭。

## 密钥图与上下文

生成 deviceReference 后再计算三分支 descriptorHash。deviceReference／profile、库 ID、epoch 与 keyGeneration 因此进入所有分支 AAD 与整 Header MAC。device 的随机 B（32 bytes）交给原生 protectFactor，factor AAD 与 K1 同规则；原生只保护 B，不存 VMK。keySlot 继续用 HKDF(B, D, `LiveRelay/Header/v2/BranchKey/device`) 派生钥封装 VMK，使用 master AAD。设备解封后必须验证整 Header MAC 才交还 VMK／打开数据库。

设备取消、失效或缺失返回错误；用户可另选密码或恢复凭证。不在一次失败操作中自动读取旧 namespace、设备 PIN 或其他凭证。旧 Header 合法回滚限制不因加入设备分支而解决。

## 内部端口与 Android

DeviceFactorProtection 提供 capability、protectFactor(context, share)、unprotectFactor(context, wrapped)、deleteFactor(reference)、cancel。上下文只能是 32 字符引用与 1～1024 bytes AAD；份额必须 32 bytes。能力明确声明 strongBiometricOnly、perOperationAuthorization、invalidatedByEnrollment；三个条件都满足才允许创建／显示新设备能力。未报告硬件背书，不声称一定 StrongBox／TEE。

原生桥 `app.liverelay/device-factor-v1` 使用 Android Keystore alias `liverelay.factor.v2.<reference>`，AES-256-GCM、随机 nonce、每次操作授权、录入变更失效；API 30+ 设置授权时长 0 和 AUTH_BIOMETRIC_STRONG，较旧系统设置 -1 并使用 CryptoObject。AndroidX BiometricPrompt 只允许 BIOMETRIC_STRONG，无 PIN 回退。加密、解密都由本次认证返回的 Cipher 执行，并以 updateAAD 绑定上下文。实现依据：[Keystore 参数](https://developer.android.com/reference/android/security/keystore/KeyGenParameterSpec.Builder)、[BiometricPrompt](https://developer.android.com/reference/androidx/biometric/BiometricPrompt)。这些 API 选择不代替目标设备验证。

同时只执行一次原生操作，重复请求返回 busy；60 秒超时、取消、进入后台或 Activity 销毁结束本次授权。取消不自动重试。受控失败类型为 unavailable／cancelled／invalidated／missing／busy／rejected／failed，错误不包含秘密或平台堆栈。Linux／Windows 返回未支持，无文件模拟替代。

## 生命周期及剩余工作

reference 单次创建，存在即拒绝覆盖。失败创建由 adapter 删除本次 key；Header 工厂仅在 protect 成功后，后续编码失败时清理该 reference，不删除未确认归属的 key。成功产出 Header 但未提交的调用方负责撤销设备引用。进程中断可能留下不含 VMK 的孤立设备 key，清理／策略更新事务留给后续设置工作流。

会话关闭／销毁取消授权并递增操作代次；迟到结果不能重新打开数据库。认证错误在数据库工厂调用前返回，用户锁定期间数据库打开完成的结果也会关闭。

本片接通既有解锁按钮对新设备 suite 的 reader／会话路径，但没有提供默认 v2 创建或旧库迁移开关。K3 仍需恢复凭证生成／回输／重设、保留凭证收集、认证重封装、显式新版备份、设备解绑／重建工作流。正式上线前仍需 Android 实体设备验证每次授权、取消、后台、录入变化、设备锁状态与旧 namespace 隔离，以及最弱配置性能和安全复核。
