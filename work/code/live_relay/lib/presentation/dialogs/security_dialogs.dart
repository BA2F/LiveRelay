import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controllers/app_controller.dart';
import '../../core/security/owner_crypto.dart';
import '../../l10n/app_localizations.dart';

Future<Uint8List?> pickSecurityKeyFile() async {
  final item = await FilePicker.pickFile();
  if (item == null) return null;
  if (await item.length() != 32) throw const FormatException('密钥文件必须是 32 字节');
  final bytes = await item.readAsBytes();
  if (bytes.length != 32) throw const FormatException('密钥文件长度错误');
  return Uint8List.fromList(bytes);
}

Future<String?> confirmNewRecovery(
  BuildContext context,
  AppController controller,
) async {
  final text = await controller.generateRecovery();
  if (!context.mounted) return null;
  return showDialog<String>(
    barrierDismissible: false,
    context: context,
    builder: (_) => _RecoveryConfirmation(text),
  );
}

class _RecoveryConfirmation extends StatefulWidget {
  const _RecoveryConfirmation(this.text);
  final String text;
  @override
  State<_RecoveryConfirmation> createState() => _RecoveryConfirmationState();
}

class _RecoveryConfirmationState extends State<_RecoveryConfirmation> {
  final check = TextEditingController();
  bool saved = false;
  @override
  void dispose() {
    check.clear();
    check.dispose();
    super.dispose();
  }

  Future<void> copyRecovery() async {
    final text = widget.text;
    await Clipboard.setData(ClipboardData(text: text));
    unawaited(
      Future<void>.delayed(const Duration(seconds: 60), () async {
        try {
          if ((await Clipboard.getData(Clipboard.kTextPlain))?.text == text) {
            await Clipboard.setData(const ClipboardData(text: ''));
          }
        } catch (_) {
          /* Clipboard permission may be restricted. */
        }
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.recoveryTitle),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(l10n.recoveryWarning),
              const SizedBox(height: 16),
              SelectableText(widget.text),
              TextButton.icon(
                onPressed: copyRecovery,
                icon: const Icon(Icons.copy),
                label: Text(l10n.recoveryCopy),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: saved,
                onChanged: (v) => setState(() => saved = v!),
                title: Text(l10n.recoverySavedCheck),
              ),
              TextField(
                controller: check,
                onChanged: (_) => setState(() {}),
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(labelText: l10n.recoveryConfirmField),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: saved && check.text == widget.text
              ? () => Navigator.pop(context, widget.text)
              : null,
          child: Text(l10n.recoveryConfirmed),
        ),
      ],
    );
  }
}

Future<void> beginIndependentRecovery(
  BuildContext context,
  AppController controller,
) async {
  final text = TextEditingController();
  try {
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('独立恢复'),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('认证后只进入安全设置重设流程。完成换钥后才能查看资料。'),
              TextField(
                controller: text,
                obscureText: true,
                autocorrect: false,
                enableSuggestions: false,
                decoration: const InputDecoration(labelText: 'LRR1 恢复凭证'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, text.text),
            child: const Text('恢复'),
          ),
        ],
      ),
    );
    if (result != null) await controller.beginRecovery(result);
  } on Object {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(controller.lastError ?? '恢复失败')));
    }
  } finally {
    text.clear();
    text.dispose();
  }
}

Future<void> unlockWithKeyFile(
  BuildContext context,
  AppController controller,
  String password,
) async {
  Uint8List? key;
  try {
    key = await pickSecurityKeyFile();
    if (key == null) return;
    await controller.unlockDaily(
      password: controller.header?.dailyPolicy == 'all' ? password : null,
      keyFile: key,
      preferred: 'keyFile',
    );
  } on Object {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(controller.lastError ?? '密钥文件解锁失败')),
      );
    }
  } finally {
    OwnerCrypto.wipe(key);
  }
}
