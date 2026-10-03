import 'package:flutter/material.dart';

import '../../application/app_controller.dart';
import '../../application/release_preview.dart';
import '../../core/domain/entities.dart';
import '../design_system/atoms.dart';
import 'card_dialogs.dart';
import '../widgets/credential_secret_actions.dart';
import '../widgets/release_preview_panel.dart';

Future<void> showCredentialEditor(
  BuildContext context,
  AppController controller, {
  CredentialEntry? entry,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) =>
        _CredentialEditorSheet(controller: controller, entry: entry),
  );
}

class _CredentialEditorSheet extends StatefulWidget {
  const _CredentialEditorSheet({required this.controller, required this.entry});

  final AppController controller;
  final CredentialEntry? entry;

  @override
  State<_CredentialEditorSheet> createState() => _CredentialEditorSheetState();
}

class _CredentialEditorSheetState extends State<_CredentialEditorSheet> {
  late final TextEditingController _title;
  late final TextEditingController _username;
  late final TextEditingController _secret;
  late final TextEditingController _website;
  late final TextEditingController _notes;
  late final TextEditingController _tags;
  bool _obscure = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.entry?.title);
    _username = TextEditingController(text: widget.entry?.username);
    _secret = TextEditingController(text: widget.entry?.secret);
    _website = TextEditingController(text: widget.entry?.website);
    _notes = TextEditingController(text: widget.entry?.notes);
    _tags = TextEditingController(text: widget.entry?.tags.join(', '));
  }

  @override
  void dispose() {
    for (final text in [_title, _username, _secret, _website, _notes, _tags]) {
      text.dispose();
    }
    super.dispose();
  }

  Future<void> _generateSecret() async {
    final phrase = widget.controller.generatePassphrase();
    final usePinyin = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('中文词组密码'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SelectableText(
              phrase.chinese,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            SelectableText(phrase.pinyin),
            const SizedBox(height: 8),
            Text('约 ${phrase.entropyBits.toStringAsFixed(1)} bit'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('使用拼音'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('使用汉字'),
          ),
        ],
      ),
    );
    if (usePinyin != null && mounted) {
      _secret.text = usePinyin ? phrase.pinyin : phrase.chinese;
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await widget.controller.saveCredential(
        CredentialDraft(
          title: _title.text,
          username: _username.text,
          secret: _secret.text,
          website: _website.text,
          notes: _notes.text,
          tags: _tags.text.split(RegExp(r'[,，]')),
        ),
        id: widget.entry?.id,
      );
      if (mounted) Navigator.pop(context);
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(widget.controller.lastError ?? '保存失败')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        20,
        20,
        MediaQuery.viewInsetsOf(context).bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.entry == null ? '新建密码条目' : '编辑密码条目',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 18),
            TextField(
              controller: _title,
              autofocus: true,
              decoration: const InputDecoration(labelText: '名称'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _username,
              decoration: const InputDecoration(labelText: '账号 / 用户名'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _secret,
              obscureText: _obscure,
              decoration: InputDecoration(
                labelText: '密码 / PIN / 恢复码',
                suffixIcon: IconButton(
                  tooltip: _obscure ? '显示密码' : '遮挡密码',
                  onPressed: () => setState(() => _obscure = !_obscure),
                  icon: Icon(
                    _obscure ? Icons.visibility : Icons.visibility_off,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _generateSecret,
              icon: const Icon(Icons.casino_outlined),
              label: const Text('生成中文词组密码'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _website,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(labelText: '网址'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _notes,
              maxLines: 3,
              decoration: const InputDecoration(labelText: '备注'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _tags,
              decoration: const InputDecoration(labelText: '标签（逗号分隔）'),
            ),
            const SizedBox(height: 18),
            FilledButton(
              onPressed: _saving || widget.controller.isBusy ? null : _save,
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 13),
                child: Text('加密保存'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> showCredentialDetails(
  BuildContext context,
  AppController controller,
  CredentialEntry entry,
) async {
  final messenger = ScaffoldMessenger.of(context);
  await showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) => FractionallySizedBox(
      heightFactor: 0.9,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
        children: [
          Text(entry.title, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text(entry.username.isEmpty ? '未填写账号' : entry.username),
          if (entry.website.isNotEmpty) SelectableText(entry.website),
          if (entry.notes.isNotEmpty) SelectableText(entry.notes),
          if (!entry.isDeleted) ...[
            const SizedBox(height: 16),
            CredentialSecretActions(secret: entry.secret),
          ],
          const SizedBox(height: 16),
          if (entry.isDeleted)
            FilledButton.icon(
              icon: const Icon(Icons.restore),
              label: const Text('恢复密码条目'),
              onPressed: () => runUiAction(sheetContext, () async {
                await controller.restoreCredential(entry.id);
                if (sheetContext.mounted) Navigator.pop(sheetContext);
              }, success: '已恢复，原有授权仍保留'),
            )
          else ...[
            FilledButton.icon(
              icon: const Icon(Icons.edit_outlined),
              label: const Text('编辑'),
              onPressed: () async {
                Navigator.pop(sheetContext);
                await showCredentialEditor(context, controller, entry: entry);
              },
            ),
            OutlinedButton.icon(
              icon: const Icon(Icons.policy_outlined),
              label: const Text('设置并预览交接授权'),
              onPressed: () => showReleasePolicyDialog(
                sheetContext,
                controller,
                recordType: 'credential',
                recordId: entry.id,
                recordTitle: entry.title,
              ),
            ),
          ],
          OutlinedButton.icon(
            icon: const Icon(Icons.history),
            label: const Text('查看修订历史'),
            onPressed: () =>
                _showCredentialHistory(sheetContext, controller, entry),
          ),
          if (!entry.isDeleted)
            TextButton.icon(
              icon: const Icon(Icons.delete_outline),
              label: const Text('移入回收区（保留历史）'),
              onPressed: () => runUiAction(sheetContext, () async {
                await controller.trashCredential(entry.id);
                if (sheetContext.mounted) Navigator.pop(sheetContext);
                if (messenger.mounted) {
                  messenger.showSnackBar(
                    SnackBar(
                      content: const Text('密码已移入回收区'),
                      action: SnackBarAction(
                        label: '撤销',
                        onPressed: () async {
                          try {
                            await controller.restoreCredential(entry.id);
                          } on Object catch (e) {
                            if (messenger.mounted) {
                              messenger.showSnackBar(
                                SnackBar(content: Text('恢复失败：$e')),
                              );
                            }
                          }
                        },
                      ),
                    ),
                  );
                }
              }),
            ),
          TextButton.icon(
            icon: const Icon(Icons.delete_forever),
            label: const Text('永久清除条目与历史密码'),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () async {
              final confirmed = await showDialog<bool>(
                context: sheetContext,
                builder: (c) => AlertDialog(
                  title: const Text('永久清除？'),
                  content: const Text('清除当前资料库中的条目和所有历史密码，无法恢复。已经导出的独立备份不受影响。'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(c, false),
                      child: const Text('取消'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(c, true),
                      child: const Text('永久清除'),
                    ),
                  ],
                ),
              );
              if (confirmed == true && sheetContext.mounted) {
                await runUiAction(sheetContext, () async {
                  await controller.purgeCredential(entry.id);
                  if (sheetContext.mounted) Navigator.pop(sheetContext);
                }, success: '条目与历史密码已清除');
              }
            },
          ),
        ],
      ),
    ),
  );
}

Future<void> _showCredentialHistory(
  BuildContext context,
  AppController controller,
  CredentialEntry entry,
) async {
  final history = await controller.credentialHistory(entry.id);
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text('${entry.title} · 加密历史'),
      content: SizedBox(
        width: 480,
        child: ListView.separated(
          shrinkWrap: true,
          itemCount: history.length,
          separatorBuilder: (_, _) => const Divider(),
          itemBuilder: (context, index) {
            final revision = history[index];
            return ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: Text('第 ${revision.number} 版 · ${revision.changeNote}'),
              children: [
                Text(revision.title),
                Text(revision.website),
                SelectableText(revision.notes),
                ReleasePreviewPanel(
                  preview: ReleasePreview(
                    level: VisibilityLevel.secret,
                    explanation: '历史密码默认遮挡',
                    title: revision.title,
                    body: revision.username,
                    secret: revision.secret,
                  ),
                ),
              ],
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('关闭'),
        ),
      ],
    ),
  );
}
