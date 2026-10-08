import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../controllers/app_controller.dart';
import '../../core/domain/entities.dart';
import '../design_system/atoms.dart';
import '../dialogs/credential_dialogs.dart';

class PasswordsPage extends StatefulWidget {
  const PasswordsPage({super.key, this.active = true});
  final bool active;

  @override
  State<PasswordsPage> createState() => _PasswordsPageState();
}

class _PasswordsPageState extends State<PasswordsPage> {
  final _search = TextEditingController();
  final _revealed = <String>{};
  final _hideTimers = <String, Timer>{};

  @override
  void didUpdateWidget(PasswordsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.active) {
      _revealed.clear();
      for (final timer in _hideTimers.values) {
        timer.cancel();
      }
      _hideTimers.clear();
    }
  }

  @override
  void dispose() {
    _search.dispose();
    for (final timer in _hideTimers.values) {
      timer.cancel();
    }
    super.dispose();
  }

  void _toggleReveal(CredentialEntry entry) {
    setState(() {
      if (_revealed.remove(entry.id)) {
        _hideTimers.remove(entry.id)?.cancel();
      } else {
        _revealed.add(entry.id);
        _hideTimers.remove(entry.id)?.cancel();
        _hideTimers[entry.id] = Timer(const Duration(seconds: 30), () {
          if (mounted) setState(() => _revealed.remove(entry.id));
        });
      }
    });
  }

  Future<void> _copySecret(CredentialEntry entry) async {
    await Clipboard.setData(ClipboardData(text: entry.secret));
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('已复制；30 秒后尝试清空剪贴板')));
    }
    unawaited(
      Future<void>.delayed(const Duration(seconds: 30), () async {
        final current = await Clipboard.getData(Clipboard.kTextPlain);
        if (current?.text == entry.secret) {
          await Clipboard.setData(const ClipboardData(text: ''));
        }
      }),
    );
  }

  Future<void> _importEdgeCsv(AppController controller) async {
    try {
      final picked = await FilePicker.pickFile(
        dialogTitle: '选择 Microsoft Edge 密码 CSV',
        type: FileType.custom,
        allowedExtensions: const ['csv'],
      );
      if (picked == null || !mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          icon: const Icon(Icons.warning_amber_rounded),
          title: const Text('导入明文密码文件？'),
          content: const Text(
            'Edge 导出的 CSV 是明文。留灯只读取并写入当前加密资料库，不保存原 CSV；'
            '导入后请从原位置安全删除该文件。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('确认导入'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      try {
        final result = await controller.importEdgePasswords(
          await picked.readAsBytes(),
        );
        if (mounted) {
          final skipped = result.skippedRows == 0
              ? ''
              : '，跳过 ${result.skippedRows} 行空记录';
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('已加密导入 ${result.entries.length} 条$skipped')),
          );
        }
      } on Object catch (error) {
        if (mounted) {
          final message = error is FormatException
              ? error.message
              : controller.lastError ?? '导入失败';
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(message)));
        }
      }
    } finally {
      try {
        await FilePicker.clearTemporaryFiles();
      } on Object {
        /* retried on start */
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    final entries = controller.findCredentials(_search.text);
    return RefreshIndicator(
      onRefresh: () => runUiAction(context, controller.refresh),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          const Text('先找到账号，再按需查看密码。密码默认遮挡。'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: controller.isBusy
                    ? null
                    : () => showCredentialEditor(context, controller),
                icon: const Icon(Icons.add),
                label: const Text('添加账号'),
              ),
              OutlinedButton.icon(
                onPressed: controller.isBusy
                    ? null
                    : () => _importEdgeCsv(controller),
                icon: const Icon(Icons.upload_file_outlined),
                label: const Text('导入 Edge CSV'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Semantics(
            label: '搜索账号',
            child: SearchField(
              controller: _search,
              hintText: '搜索名称、账号、网址或备注',
              leading: const Icon(Icons.search),
              onChanged: (_) => setState(() {}),
              trailing: [
                if (_search.text.isNotEmpty)
                  IconButton(
                    tooltip: '清除搜索',
                    icon: const Icon(Icons.clear),
                    onPressed: () => setState(_search.clear),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (controller.lastError != null) ErrorBanner(controller.lastError!),
          if (entries.isEmpty)
            EmptyState(
              icon: Icons.key_off_outlined,
              title: controller.credentials.isEmpty ? '密码库还是空的' : '没有匹配的账号',
              message: controller.credentials.isEmpty
                  ? '添加或导入账号，条目会加密保存在本机。'
                  : '试试其他关键词。',
              action: controller.credentials.isEmpty
                  ? FilledButton.tonal(
                      onPressed: () =>
                          showCredentialEditor(context, controller),
                      child: const Text('添加第一个条目'),
                    )
                  : TextButton(
                      onPressed: () => setState(_search.clear),
                      child: const Text('清除搜索'),
                    ),
            ),
          for (final entry in entries) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    InkWell(
                      onTap: () =>
                          showCredentialDetails(context, controller, entry),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              entry.title,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            if (entry.username.isNotEmpty) Text(entry.username),
                          ],
                        ),
                      ),
                    ),
                    Text(
                      _revealed.contains(entry.id)
                          ? entry.secret
                          : '••••••••••••',
                      style: const TextStyle(fontFamily: 'monospace'),
                    ),
                    Wrap(
                      spacing: 8,
                      children: [
                        TextButton.icon(
                          icon: Icon(
                            _revealed.contains(entry.id)
                                ? Icons.visibility_off
                                : Icons.visibility,
                          ),
                          label: Text(
                            _revealed.contains(entry.id) ? '立即遮挡' : '显示 30 秒',
                          ),
                          onPressed: () => _toggleReveal(entry),
                        ),
                        TextButton.icon(
                          icon: const Icon(Icons.copy),
                          label: const Text('复制密码'),
                          onPressed: () => _copySecret(entry),
                        ),
                        TextButton.icon(
                          icon: const Icon(Icons.more_horiz),
                          label: const Text('详情'),
                          onPressed: () =>
                              showCredentialDetails(context, controller, entry),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}
