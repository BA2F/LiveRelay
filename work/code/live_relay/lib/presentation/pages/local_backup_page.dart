import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';

import '../controllers/app_controller.dart';
import '../dialogs/backup_dialogs.dart';
import '../dialogs/local_file_dialogs.dart';

class LocalBackupPage extends StatefulWidget {
  const LocalBackupPage({super.key});
  @override
  State<LocalBackupPage> createState() => _LocalBackupPageState();
}

class _LocalBackupPageState extends State<LocalBackupPage> {
  bool busy = false;
  int missing = 0;
  String? message;
  @override
  void initState() {
    super.initState();
    refresh();
  }

  Future<void> refresh() async {
    final count = await context.read<AppController>().missingOriginalCount();
    if (mounted) setState(() => missing = count);
  }

  Future<void> run(Future<void> Function() action) async {
    setState(() {
      busy = true;
      message = null;
    });
    try {
      await action();
      await refresh();
    } on Object catch (e) {
      if (mounted) setState(() => message = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> export() async {
    final controller = context.read<AppController>();
    if (controller.header?.formatVersion != 3) {
      throw StateError('请先在安全设置中主动升级资料库');
    }
    final credential = await showDialog<String>(
      context: context,
      builder: (_) => const PasswordPromptDialog(
        title: '验证备份：密码或独立恢复凭证',
        actionLabel: '准备分层备份',
      ),
    );
    if (credential == null) return;
    final result = await controller.exportSplitVault(credential);
    try {
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final db = await saveLocalBytes(
        result.database,
        'LiveRelay-$stamp-database.lvault',
      );
      if (!db) return;
      final attachments = await saveLocalBytes(
        result.attachments,
        'LiveRelay-$stamp-originals.lvault',
      );
      if (attachments) await controller.markBackupExported();
      if (mounted) {
        setState(
          () => message = attachments
              ? '两个配对备份包已保存。可将数据库包和原件包分别存放。'
              : '仅保存了数据库包；原件包还未保存，请重新完整导出这一组。',
        );
      }
    } finally {
      result.database.fillRange(0, result.database.length, 0);
      result.attachments.fillRange(0, result.attachments.length, 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    if (!controller.isUnlocked) {
      return const Scaffold(body: Center(child: Text('资料库已锁定')));
    }
    return Scaffold(
      appBar: AppBar(title: const Text('本地分层备份')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              const Text(
                '数据库包包含卡片、密码、修订、授权和身份密钥；原件补充包包含照片、录音等加密文件。两包绑定同一备份快照。数据库可先恢复，原件随后补齐。',
              ),
              const SizedBox(height: 16),
              Text('当前待补齐原件：$missing 个'),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: busy || missing > 0 ? null : () => run(export),
                icon: const Icon(Icons.inventory_2_outlined),
                label: const Text('导出数据库包与原件包'),
              ),
              OutlinedButton.icon(
                onPressed: busy
                    ? null
                    : () => restoreFromBackup(context, controller),
                icon: const Icon(Icons.settings_backup_restore),
                label: const Text('恢复完整包或数据库包'),
              ),
              OutlinedButton.icon(
                onPressed: busy || missing == 0
                    ? null
                    : () => run(() async {
                        final file = await FilePicker.pickFile(
                          dialogTitle: '选择对应备份的原件补充包',
                        );
                        if (file == null) return;
                        final bytes = await file.readAsBytes();
                        try {
                          await controller.importOriginalSupplement(bytes);
                          if (mounted) {
                            setState(() => message = '原件已核验并重新加密到当前资料库');
                          }
                        } finally {
                          bytes.fillRange(0, bytes.length, 0);
                        }
                      }),
                icon: const Icon(Icons.attach_file),
                label: const Text('导入配对原件补充包'),
              ),
              const SizedBox(height: 16),
              const Text('修改安全设置后，旧备份仍由旧凭证解锁。请在原件补齐后重新备份。'),
              if (message != null) Text(message!),
              if (busy) const LinearProgressIndicator(),
            ],
          ),
        ),
      ),
    );
  }
}
