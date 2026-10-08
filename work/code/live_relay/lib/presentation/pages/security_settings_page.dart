import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/app_controller.dart';
import '../../core/security/owner_crypto.dart';
import '../../core/security/vault_password_policy.dart';
import '../dialogs/security_dialogs.dart';

class SecuritySettingsPage extends StatefulWidget {
  const SecuritySettingsPage({super.key, this.recovery = false});
  final bool recovery;
  @override
  State<SecuritySettingsPage> createState() => _SecuritySettingsPageState();
}

class _SecuritySettingsPageState extends State<SecuritySettingsPage> {
  final oldPassword = TextEditingController(),
      password = TextEditingController(),
      confirmation = TextEditingController();
  Uint8List? oldFile, newFile;
  bool biometric = false, all = false, fileSaved = false;
  String? error;
  @override
  void dispose() {
    oldPassword.clear();
    password.clear();
    confirmation.clear();
    oldPassword.dispose();
    password.dispose();
    confirmation.dispose();
    OwnerCrypto.wipe(oldFile);
    OwnerCrypto.wipe(newFile);
    super.dispose();
  }

  Future<void> fileAction({bool old = false}) async {
    try {
      final key = await pickSecurityKeyFile();
      if (key == null) return;
      if (!mounted) {
        OwnerCrypto.wipe(key);
        return;
      }
      setState(() {
        if (old) {
          OwnerCrypto.wipe(oldFile);
          oldFile = key;
        } else {
          OwnerCrypto.wipe(newFile);
          newFile = key;
          fileSaved = true;
        }
      });
    } on Object catch (e) {
      if (mounted) setState(() => error = '$e');
    }
  }

  Future<void> generateFile() async {
    final key = OwnerCrypto.random(32);
    try {
      final saved = await FilePicker.saveFile(
        dialogTitle: '保存独立密钥文件',
        fileName: 'LiveRelay.lrkey',
        bytes: key,
      );
      if (saved == null || !mounted) return;
      setState(() {
        OwnerCrypto.wipe(newFile);
        newFile = Uint8List.fromList(key);
        fileSaved = true;
      });
    } on Object catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      OwnerCrypto.wipe(key);
    }
  }

  Future<void> submit(AppController controller) async {
    final validation = VaultPasswordPolicy.creationError(password.text);
    if (validation != null ||
        password.text != confirmation.text ||
        (all && newFile == null && !biometric)) {
      setState(
        () => error =
            validation ??
            (password.text != confirmation.text
                ? '两次新密码不一致'
                : '全部方式解锁至少需要两种方式'),
      );
      return;
    }
    final r = await confirmNewRecovery(context, controller);
    if (r == null || !mounted) return;
    try {
      await controller.configureSecurity(
        oldPassword: oldPassword.text,
        newPassword: password.text,
        recoveryText: r,
        recoveryConfirmation: r,
        policy: all ? 'all' : 'any',
        oldKeyFile: oldFile,
        newKeyFile: newFile,
        biometric: biometric,
      );
      if (mounted && !widget.recovery) Navigator.pop(context);
    } on Object {
      if (mounted) setState(() => error = controller.lastError ?? '更新失败，原库已保留');
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    final busy = controller.isBusy;
    if (!widget.recovery && !controller.isUnlocked && !busy) {
      return Scaffold(
        appBar: AppBar(title: const Text('安全更新结束')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(controller.lastError ?? '会话已锁定，请重新解锁'),
              TextButton(
                onPressed: () => Navigator.popUntil(context, (r) => r.isFirst),
                child: const Text('返回解锁'),
              ),
            ],
          ),
        ),
      );
    }
    return PopScope(
      canPop: !busy && !widget.recovery,
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.recovery ? '重设安全设置' : '解锁方式与恢复凭证'),
          automaticallyImplyLeading: !widget.recovery,
          actions: [
            if (widget.recovery)
              TextButton(
                onPressed: busy ? null : controller.lock,
                child: const Text('取消并锁定'),
              ),
          ],
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Text(
                  widget.recovery
                      ? '恢复认证已通过。请设置新密码并保存新的恢复凭证。'
                      : '更新会重新加密资料库和原件，并废止当前库的旧凭证。旧备份仍使用旧凭证，请更新备份。',
                ),
                if (!widget.recovery) ...[
                  const SizedBox(height: 16),
                  TextField(
                    controller: oldPassword,
                    obscureText: true,
                    enabled: !busy,
                    decoration: const InputDecoration(labelText: '当前密码 / 中文词组'),
                  ),
                  if (controller.header?.keyFileEnabled == true &&
                      controller.header?.dailyPolicy == 'all')
                    OutlinedButton(
                      onPressed: busy ? null : () => fileAction(old: true),
                      child: Text(oldFile == null ? '选择当前密钥文件' : '当前密钥文件已选择'),
                    ),
                ],
                const SizedBox(height: 16),
                TextField(
                  controller: password,
                  obscureText: true,
                  enabled: !busy,
                  decoration: const InputDecoration(
                    labelText: '新主密码（至少 8 个字符）',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: confirmation,
                  obscureText: true,
                  enabled: !busy,
                  decoration: const InputDecoration(labelText: '重复新主密码'),
                ),
                const SizedBox(height: 16),
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: false, label: Text('任一种方式')),
                    ButtonSegment(value: true, label: Text('全部方式')),
                  ],
                  selected: {all},
                  onSelectionChanged: busy
                      ? null
                      : (v) => setState(() => all = v.single),
                ),
                const SizedBox(height: 8),
                const Text('主密码始终启用。日常可以选择密码、密钥文件或本机指纹；独立恢复始终可用。'),
                SwitchListTile(
                  title: const Text('本机指纹'),
                  subtitle: Text(
                    controller.biometricAvailable
                        ? '每次使用需要系统生物识别授权'
                        : '此设备暂不可用',
                  ),
                  value: biometric,
                  onChanged: !busy && controller.biometricAvailable
                      ? (v) => setState(() => biometric = v)
                      : null,
                ),
                Wrap(
                  spacing: 8,
                  children: [
                    OutlinedButton(
                      onPressed: busy ? null : generateFile,
                      child: const Text('生成并保存密钥文件'),
                    ),
                    OutlinedButton(
                      onPressed: busy ? null : () => fileAction(),
                      child: const Text('选择已有密钥文件'),
                    ),
                    if (newFile != null)
                      TextButton(
                        onPressed: busy
                            ? null
                            : () => setState(() {
                                OwnerCrypto.wipe(newFile);
                                newFile = null;
                                fileSaved = false;
                              }),
                        child: const Text('不使用文件'),
                      ),
                  ],
                ),
                if (fileSaved) const Text('新密钥文件已准备。请与设备分开保存。'),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Text(
                      error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                if (busy) ...[
                  const LinearProgressIndicator(),
                  Text(controller.securityProgress),
                ],
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: busy ? null : () => submit(controller),
                  child: const Text('保存新的恢复凭证并更新'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
