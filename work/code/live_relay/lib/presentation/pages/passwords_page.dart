import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../application/app_controller.dart';
import '../../core/domain/entities.dart';
import '../design_system/atoms.dart';
import '../dialogs/card_dialogs.dart';

class PasswordsPage extends StatefulWidget {
  const PasswordsPage({super.key});

  @override
  State<PasswordsPage> createState() => _PasswordsPageState();
}

class _PasswordsPageState extends State<PasswordsPage> {
  final _search = TextEditingController();
  final _revealed = <String>{};
  final _hideTimers = <String, Timer>{};

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
          'Edge 导出的 CSV 是明文。留灯只读取并写入当前加密 Vault，不保存原 CSV；'
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
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '与人生卡片共用同一个加密 Vault',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  IconButton.filledTonal(
                    tooltip: '导入 Edge CSV',
                    onPressed: controller.isBusy
                        ? null
                        : () => _importEdgeCsv(controller),
                    icon: const Icon(Icons.upload_file_outlined),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: () => _showCredentialEditor(context, controller),
                    icon: const Icon(Icons.add),
                    label: const Text('新建'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SearchBar(
                controller: _search,
                hintText: '搜索名称、账号、网址或备注',
                leading: const Icon(Icons.search),
                onSubmitted: (_) =>
                    controller.refresh(credentialQuery: _search.text),
              ),
            ],
          ),
        ),
        Expanded(
          child: controller.credentials.isEmpty
              ? EmptyState(
                  icon: Icons.key_off_outlined,
                  title: '密码库还是空的',
                  message: '条目只在 Vault 解锁后按需显示，Secret 默认遮挡。',
                  action: FilledButton.tonal(
                    onPressed: () => _showCredentialEditor(context, controller),
                    child: const Text('添加第一个条目'),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: () =>
                      controller.refresh(credentialQuery: _search.text),
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
                    itemCount: controller.credentials.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final entry = controller.credentials[index];
                      final visible = _revealed.contains(entry.id);
                      return Card(
                        child: InkWell(
                          borderRadius: BorderRadius.circular(20),
                          onTap: () => _showCredentialDetails(
                            context,
                            controller,
                            entry,
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              children: [
                                const CircleAvatar(child: Icon(Icons.key)),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        entry.title,
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium,
                                      ),
                                      if (entry.username.isNotEmpty)
                                        Text(
                                          entry.username,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      const SizedBox(height: 6),
                                      Text(
                                        visible ? entry.secret : '••••••••••••',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontFamily: 'monospace',
                                          letterSpacing: 1.2,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  tooltip: visible ? '遮挡' : '显示 30 秒',
                                  onPressed: () => _toggleReveal(entry),
                                  icon: Icon(
                                    visible
                                        ? Icons.visibility_off
                                        : Icons.visibility,
                                  ),
                                ),
                                IconButton(
                                  tooltip: '复制密码',
                                  onPressed: () => _copySecret(entry),
                                  icon: const Icon(Icons.copy),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }
}

Future<void> _showCredentialEditor(
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
              onPressed: widget.controller.isBusy ? null : _save,
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

Future<void> _showCredentialDetails(
  BuildContext context,
  AppController controller,
  CredentialEntry entry,
) async {
  await showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    showDragHandle: true,
    builder: (sheetContext) => Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(entry.title, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text(entry.username.isEmpty ? '未填写账号' : entry.username),
          if (entry.website.isNotEmpty) Text(entry.website),
          if (entry.notes.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(entry.notes),
          ],
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.tonalIcon(
                onPressed: () async {
                  Navigator.pop(sheetContext);
                  await _showCredentialEditor(
                    context,
                    controller,
                    entry: entry,
                  );
                },
                icon: const Icon(Icons.edit_outlined),
                label: const Text('编辑'),
              ),
              OutlinedButton.icon(
                onPressed: () =>
                    _showCredentialHistory(context, controller, entry),
                icon: const Icon(Icons.history),
                label: const Text('历史'),
              ),
              OutlinedButton.icon(
                onPressed: () => showReleasePolicyDialog(
                  context,
                  controller,
                  recordType: 'credential',
                  recordId: entry.id,
                  recordTitle: entry.title,
                ),
                icon: const Icon(Icons.policy_outlined),
                label: const Text('交接策略'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextButton.icon(
            onPressed: () async {
              await controller.trashCredential(entry.id);
              if (sheetContext.mounted) Navigator.pop(sheetContext);
            },
            icon: const Icon(Icons.delete_outline),
            label: const Text('普通删除（保留加密历史）'),
          ),
          TextButton.icon(
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () async {
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (dialogContext) => AlertDialog(
                  title: const Text('永久清除？'),
                  content: const Text(
                    '将清除此 Vault 中的当前条目和所有历史 Secret。已经导出的独立备份不受影响。',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(dialogContext, false),
                      child: const Text('取消'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(dialogContext, true),
                      child: const Text('永久清除'),
                    ),
                  ],
                ),
              );
              if (confirmed ?? false) {
                await controller.purgeCredential(entry.id);
                if (sheetContext.mounted) Navigator.pop(sheetContext);
              }
            },
            icon: const Icon(Icons.delete_forever),
            label: const Text('永久清除条目与历史 Secret'),
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
            return ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('v${revision.number} · ${revision.changeNote}'),
              subtitle: Text('${revision.username}\n旧 Secret 默认不显示'),
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
