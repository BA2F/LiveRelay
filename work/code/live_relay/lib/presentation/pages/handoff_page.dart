import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../controllers/app_controller.dart';
import '../../application/local_handoff_service.dart';
import '../../application/release_preview.dart';
import '../../core/domain/entities.dart';
import '../design_system/atoms.dart';
import '../model_labels.dart';
import '../widgets/release_preview_panel.dart';

ReleasePolicy _policy(AppController c, String type, String id) =>
    c.releasePolicies
        .where((p) => p.recordType == type && p.recordId == id)
        .firstOrNull ??
    ReleasePolicy(recordType: type, recordId: id);

class HandoffPage extends StatefulWidget {
  const HandoffPage({super.key});
  @override
  State<HandoffPage> createState() => _HandoffPageState();
}

class _HandoffPageState extends State<HandoffPage> {
  final selected = <String>{};
  String? _password, _error;
  DateTime? _updatedAt;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final view = context.read<AppController>().handoffView;
    if (view == null) return;
    final updated = await view.updatedAt();
    if (mounted) setState(() => _updatedAt = updated);
  }

  Future<String?> _askPassword({required bool confirm}) async {
    var first = '', second = '';
    return showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, refresh) {
          final ready = first.length >= 6 && (!confirm || first == second);
          return AlertDialog(
            title: Text(confirm ? '设置交接密码' : '输入交接密码'),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('接收者在这台设备上用它查看交接内容。知道密码的人都能看到，请当面告知。'),
                  const SizedBox(height: 12),
                  TextField(
                    obscureText: true,
                    onChanged: (value) => refresh(() => first = value),
                    decoration: const InputDecoration(
                      labelText: '交接密码（至少 6 位）',
                    ),
                  ),
                  if (confirm) ...[
                    const SizedBox(height: 12),
                    TextField(
                      obscureText: true,
                      onChanged: (value) => refresh(() => second = value),
                      decoration: const InputDecoration(labelText: '再次输入交接密码'),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: ready ? () => Navigator.pop(context, first) : null,
                child: const Text('确定'),
              ),
            ],
          );
        },
      ),
    );
  }

  List<ScopedRecord> get _selections => [
    for (final key in selected)
      ScopedRecord(
        key.startsWith('card/') ? 'card' : 'credential',
        key.substring(key.indexOf('/') + 1),
        key.startsWith('card/') ? VisibilityLevel.full : VisibilityLevel.secret,
      ),
  ];

  Future<void> _save() async {
    final controller = context.read<AppController>();
    final view = controller.handoffView;
    if (view == null) {
      setState(() => _error = '当前构建没有本地交接视图');
      return;
    }
    final selections = _selections;
    if (selections.isEmpty) {
      setState(() => _error = '先选择至少一条要交付的内容');
      return;
    }
    var password = _password;
    if (password == null) {
      final exists = await view.exists();
      final entered = await _askPassword(confirm: !exists);
      if (entered == null || !mounted) return;
      if (exists && !await view.accepts(entered)) {
        if (mounted) setState(() => _error = '交接密码不正确');
        return;
      }
      password = entered;
    }
    if (!mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final snapshot = await controller.handoff!.snapshotFor(selections);
      await view.save(
        password: password,
        snapshot: {
          ...snapshot,
          'ownerName': controller.ownerProfile['name'] ?? '本人',
        },
      );
      if (!mounted) return;
      setState(() {
        _password = password;
        _updatedAt = DateTime.now();
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('交接内容已保存')));
    } on Object catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _changePassword() async {
    final next = await _askPassword(confirm: true);
    if (next == null || !mounted) return;
    setState(() {
      _password = next;
      _error = null;
    });
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('新密码会在下次保存交接内容时生效')));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<AppController>();
    if (!c.isUnlocked) return const Center(child: Text('资料库已锁定'));
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        const Text('接收者在这台设备上打开程序，输入交接密码就能查看下面选定的内容；没有选择的记录不会出现在交接里。'),
        const SizedBox(height: 16),
        Card(
          child: ListTile(
            leading: const Icon(Icons.password_outlined),
            title: Text(_updatedAt == null ? '还没有交接密码' : '交接密码已设置'),
            subtitle: Text(
              _updatedAt == null
                  ? '保存交接内容时设置，之后长期有效。'
                  : '上次更新：'
                        '${DateFormat('yyyy-MM-dd HH:mm').format(_updatedAt!.toLocal())}',
            ),
            trailing: TextButton(
              onPressed: _busy ? null : _changePassword,
              child: Text(_updatedAt == null ? '设置密码' : '更改密码'),
            ),
          ),
        ),
        const SizedBox(height: 20),
        Text('交接内容', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 4),
        const Text('勾选要交给接收者的内容；没勾的不会出现。'),
        const SizedBox(height: 8),
        Builder(
          builder: (context) {
            final all = <String>[
              for (final record in <InformationCard>[
                ...c.cards,
                ...c.credentials,
              ])
                '${record is LifeCard ? 'card' : 'credential'}/${record.id}',
            ];
            final checked = all.where(selected.contains).length;
            return CheckboxListTile(
              value: all.isEmpty
                  ? false
                  : checked == all.length
                  ? true
                  : checked == 0
                  ? false
                  : null,
              tristate: true,
              title: const Text('全选'),
              subtitle: Text('已选 $checked / ${all.length} 条'),
              onChanged: _busy
                  ? null
                  : (value) => setState(() {
                      if (value == true) {
                        selected.addAll(all);
                      } else {
                        selected.removeAll(all);
                      }
                    }),
            );
          },
        ),
        const Divider(),
        for (final record in <InformationCard>[...c.cards, ...c.credentials])
          Builder(
            builder: (context) {
              final key =
                  '${record is LifeCard ? 'card' : 'credential'}/${record.id}';
              return CheckboxListTile(
                value: selected.contains(key),
                title: Text(record.title),
                subtitle: Text(
                  record is LifeCard ? '卡片 · 交付完整正文' : '密码条目 · 交付当前密码',
                ),
                onChanged: _busy
                    ? null
                    : (value) => setState(() {
                        if (value == true) {
                          selected.add(key);
                        } else {
                          selected.remove(key);
                        }
                      }),
              );
            },
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        if (_busy) const LinearProgressIndicator(),
        const SizedBox(height: 8),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: const Text('保存交接内容'),
        ),
      ],
    );
  }
}

class RecipientPreviewPage extends StatefulWidget {
  const RecipientPreviewPage({super.key});
  @override
  State<RecipientPreviewPage> createState() => _RecipientPreviewPageState();
}

class _RecipientPreviewPageState extends State<RecipientPreviewPage> {
  LifeState _scene = LifeState.incapacitated;
  @override
  Widget build(BuildContext context) {
    final c = context.watch<AppController>();
    return Scaffold(
      appBar: AppBar(title: const Text('接收者预览')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('切换情境只用于核对各状态下对方能看到的内容。'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final scene in LifeState.values)
                ChoiceChip(
                  label: Text(scene.label),
                  selected: _scene == scene,
                  onSelected: (_) => setState(() => _scene = scene),
                ),
            ],
          ),
          const SizedBox(height: 16),
          ReleasedContents(controller: c, scene: _scene),
        ],
      ),
    );
  }
}

/// 按情境列出会被释放的内容；交接预览与独立演示共用。
class ReleasedContents extends StatelessWidget {
  const ReleasedContents({
    super.key,
    required this.controller,
    required this.scene,
  });
  final AppController controller;
  final LifeState scene;
  @override
  Widget build(BuildContext context) {
    final cards = controller.cards
        .where(
          (v) =>
              _policy(controller, 'card', v.id).visibleAt(scene) !=
              VisibilityLevel.hidden,
        )
        .toList();
    final credentials = controller.credentials
        .where(
          (v) =>
              _policy(controller, 'credential', v.id).visibleAt(scene) !=
              VisibilityLevel.hidden,
        )
        .toList();
    if (cards.isEmpty && credentials.isEmpty) {
      return const EmptyState(
        icon: Icons.visibility_off_outlined,
        title: '此情境下没有被授权的信息',
        message: '未设置的条目保持私密；健康状态不释放任何信息。',
      );
    }
    return Column(
      children: [
        for (final card in cards) ...[
          ReleasePreviewPanel(
            preview: ReleasePreview.card(
              card,
              _policy(controller, 'card', card.id).visibleAt(scene),
            ),
          ),
          const SizedBox(height: 12),
        ],
        for (final entry in credentials) ...[
          ReleasePreviewPanel(
            preview: ReleasePreview.credential(
              entry,
              _policy(controller, 'credential', entry.id).visibleAt(scene),
            ),
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}
