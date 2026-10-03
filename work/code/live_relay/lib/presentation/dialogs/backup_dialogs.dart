import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';

import '../../application/app_controller.dart';

class PasswordPromptDialog extends StatefulWidget {
  const PasswordPromptDialog({
    super.key,
    required this.title,
    required this.actionLabel,
  });

  final String title;
  final String actionLabel;

  @override
  State<PasswordPromptDialog> createState() => PasswordPromptDialogState();
}

class PasswordPromptDialogState extends State<PasswordPromptDialog> {
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _text,
        obscureText: true,
        autofocus: true,
        onSubmitted: (_) => Navigator.pop(context, _text.text),
        decoration: const InputDecoration(labelText: '主密码或中文词组'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _text.text),
          child: Text(widget.actionLabel),
        ),
      ],
    );
  }
}

/// Available both before setup and while locked: inspection authenticates the
/// selected archive before showing its date, scope or replacement decision.
Future<void> restoreFromBackup(
  BuildContext context,
  AppController controller,
) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    final picked = await FilePicker.pickFile(
      dialogTitle: '选择加密备份',
      type: FileType.custom,
      allowedExtensions: const ['lvault'],
    );
    if (picked == null || !context.mounted) return;
    final password = await showDialog<String>(
      context: context,
      builder: (_) =>
          const PasswordPromptDialog(title: '输入备份的口令', actionLabel: '验证备份'),
    );
    if (password == null || !context.mounted) return;
    final bytes = await picked.readAsBytes();
    try {
      final preview = await controller.inspectBackup(bytes, password);
      if (!context.mounted) return;
      final replacing = controller.header != null;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(replacing ? '核对备份并替换当前资料库' : '核对备份并恢复资料库'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('口令、完整性和数据库已验证。'),
                Text(
                  '备份时间：${preview.createdAt == null ? '未记录' : DateFormat('yyyy-MM-dd HH:mm').format(preview.createdAt!.toLocal())}',
                ),
                Text(
                  '${preview.cards} 张卡片 · ${preview.credentials} 条密码 · ${preview.originals} 个原件',
                ),
                Text(
                  '回收区：${preview.recycledCards} 张卡片、${preview.recycledCredentials} 条密码；修订和授权也会恢复。',
                ),
                const SizedBox(height: 12),
                Text(
                  replacing
                      ? '恢复成功后当前资料库全部由备份替换，不会合并。需要保留当前信息时，请先取消并导出。验证失败会保留当前资料库。'
                      : '无需先创建临时资料库。恢复后使用备份口令解锁。',
                ),
                const Text('恢复后指纹需重新启用。'),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: Text(replacing ? '确认替换并恢复' : '恢复资料库'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
      await controller.restoreVault(bytes, password);
      if (messenger.mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text(controller.recoveryNotice ?? '已从加密备份恢复')),
        );
      }
    } finally {
      bytes.fillRange(0, bytes.length, 0);
    }
  } on Object {
    if (messenger.mounted) {
      messenger.showSnackBar(
        SnackBar(content: Text(controller.lastError ?? '读取备份失败')),
      );
    }
  } finally {
    try {
      await FilePicker.clearTemporaryFiles();
    } on Object {
      /* retry on start */
    }
  }
}
