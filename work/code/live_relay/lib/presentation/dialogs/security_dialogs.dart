import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controllers/app_controller.dart';
import '../../core/security/owner_crypto.dart';

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
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('保存独立恢复凭证'),
    content: SizedBox(
      width: 480,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('此凭证可以绕过日常解锁条件并重设整库安全设置。请单独离线保存；丢失后无法代为找回。'),
            const SizedBox(height: 16),
            SelectableText(widget.text),
            TextButton.icon(
              onPressed: copyRecovery,
              icon: const Icon(Icons.copy),
              label: const Text('复制恢复凭证'),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: saved,
              onChanged: (v) => setState(() => saved = v!),
              title: const Text('我已单独保存恢复凭证'),
            ),
            TextField(
              controller: check,
              onChanged: (_) => setState(() {}),
              autocorrect: false,
              enableSuggestions: false,
              decoration: const InputDecoration(labelText: '完整回输凭证确认'),
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: saved && check.text == widget.text
            ? () => Navigator.pop(context, widget.text)
            : null,
        child: const Text('已确认，继续'),
      ),
    ],
  );
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
