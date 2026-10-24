import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../controllers/app_controller.dart';
import '../../application/handoff_delivery_service.dart';
import '../../application/local_handoff_service.dart';
import '../../application/release_preview.dart';
import '../../core/domain/entities.dart';
import '../../core/security/pickup_code.dart';
import '../design_system/atoms.dart';
import '../model_labels.dart';
import '../widgets/release_preview_panel.dart';
import 'recipient_delivery_page.dart';

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
  // Card id -> original blob ids included with that card.
  final originals = <String, List<String>>{};
  String? _password, _error, _deliveryError;
  DateTime? _updatedAt;
  bool _busy = false, _deliveryBusy = false;
  List<HandoffDelivery> _deliveries = const [];

  @override
  void initState() {
    super.initState();
    _load();
    _loadDeliveries();
  }

  Future<void> _load() async {
    final view = context.read<AppController>().handoffView;
    if (view == null) return;
    final updated = await view.updatedAt();
    if (mounted) setState(() => _updatedAt = updated);
  }

  Future<void> _loadDeliveries() async {
    if (!mounted) return;
    final service = context.read<AppController>().delivery;
    if (service == null) return;
    try {
      final deliveries = await service.list();
      if (mounted) setState(() => _deliveries = deliveries);
    } on Object catch (error) {
      if (mounted) setState(() => _deliveryError = '$error');
    }
  }

  String _deliveryStatus(DeliveryStatus status) => switch (status) {
    DeliveryStatus.draft => '草稿',
    DeliveryStatus.uploaded => '已上传',
    DeliveryStatus.needsUpdate => '待更新',
    DeliveryStatus.disabled => '已停用',
  };

  Future<void> _addRecipient() async {
    final controller = context.read<AppController>();
    final service = controller.delivery;
    if (service == null) return;
    final connection = await controller.webDavConnection();
    if (!mounted) return;
    if (connection == null) {
      setState(() => _deliveryError = '先到「设备间搬运」配置云端连接，再添加接收者');
      return;
    }
    try {
      final input = await showAddRecipientDialog(context);
      if (input == null || !mounted) return;
      final scope = <ScopedRecord>[
        for (final card in controller.cards)
          ScopedRecord('card', card.id, VisibilityLevel.full),
        for (final entry in controller.credentials)
          ScopedRecord('credential', entry.id, VisibilityLevel.secret),
      ];
      setState(() {
        _deliveryBusy = true;
        _deliveryError = null;
      });
      final delivery = await service.add(
        label: input.$1,
        email: input.$2,
        scope: scope,
        connection: connection,
      );
      if (!mounted) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => RecipientDeliveryPage(deliveryId: delivery.id),
        ),
      );
      await _loadDeliveries();
    } on Object catch (error) {
      if (mounted) setState(() => _deliveryError = '$error');
    } finally {
      if (mounted) setState(() => _deliveryBusy = false);
    }
  }

  Future<void> _openDelivery(HandoffDelivery delivery) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => RecipientDeliveryPage(deliveryId: delivery.id),
      ),
    );
    await _loadDeliveries();
  }

  Future<void> _showCodes() async {
    final revealed = <String>{};
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, refresh) => AlertDialog(
          title: const Text('取件码总览'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('这些码能打开对应的交接包，请只交给本人。'),
                  const SizedBox(height: 12),
                  for (final delivery in _deliveries)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '${delivery.label} · ${delivery.email}',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              IconButton(
                                tooltip: revealed.contains(delivery.id)
                                    ? '遮住'
                                    : '显示',
                                onPressed: () => refresh(() {
                                  if (!revealed.add(delivery.id)) {
                                    revealed.remove(delivery.id);
                                  }
                                }),
                                icon: Icon(
                                  revealed.contains(delivery.id)
                                      ? Icons.visibility_off_outlined
                                      : Icons.visibility_outlined,
                                ),
                              ),
                              IconButton(
                                tooltip: '复制',
                                onPressed: () async {
                                  await Clipboard.setData(
                                    ClipboardData(
                                      text: PickupCode.format(
                                        delivery.pickupCode,
                                      ),
                                    ),
                                  );
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          '已复制 ${delivery.label} 的取件码',
                                        ),
                                      ),
                                    );
                                  }
                                },
                                icon: const Icon(Icons.copy_outlined),
                              ),
                            ],
                          ),
                          Text(
                            revealed.contains(delivery.id)
                                ? PickupCode.format(delivery.pickupCode)
                                : '••••-••••-••••',
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (_deliveries.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Text('还没有接收者'),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('关闭'),
            ),
          ],
        ),
      ),
    );
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
      if (key.startsWith('card/'))
        ScopedRecord(
          'card',
          key.substring(key.indexOf('/') + 1),
          (originals[key.substring(key.indexOf('/') + 1)]?.isNotEmpty ?? false)
              ? VisibilityLevel.original
              : VisibilityLevel.full,
          originalIds:
              originals[key.substring(key.indexOf('/') + 1)] ?? const [],
        )
      else
        ScopedRecord(
          'credential',
          key.substring(key.indexOf('/') + 1),
          VisibilityLevel.secret,
        ),
  ];

  Future<List<VaultBlob>> _availableOriginals(
    AppController controller,
    String cardId,
  ) async {
    final sources = await controller.cardSources(cardId);
    return controller.blobs
        .where((blob) => sources.any((source) => source.blobId == blob.id))
        .toList();
  }

  Future<void> _toggleOriginals(String cardId, bool value) async {
    if (!value) {
      setState(() => originals.remove(cardId));
      return;
    }
    final available = await _availableOriginals(
      context.read<AppController>(),
      cardId,
    );
    if (!mounted) return;
    if (available.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('这张卡片没有关联原件')));
      return;
    }
    setState(() => originals[cardId] = [for (final blob in available) blob.id]);
  }

  Future<void> _chooseOriginals(String cardId) async {
    final available = await _availableOriginals(
      context.read<AppController>(),
      cardId,
    );
    if (!mounted) return;
    final ids = <String>{...?originals[cardId]};
    final result = await showDialog<List<String>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, refresh) => AlertDialog(
          title: const Text('交付哪些原件'),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('勾选的文件会完整交付，包括图片、录音等原始内容。'),
                  for (final blob in available)
                    CheckboxListTile(
                      value: ids.contains(blob.id),
                      title: Text(blob.originalName),
                      onChanged: (value) => refresh(() {
                        if (value == true) {
                          ids.add(blob.id);
                        } else {
                          ids.remove(blob.id);
                        }
                      }),
                    ),
                  if (available.isEmpty) const Text('此卡片没有关联原件'),
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
              onPressed: () => Navigator.pop(context, ids.toList()),
              child: const Text('确认原件范围'),
            ),
          ],
        ),
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      if (result.isEmpty) {
        originals.remove(cardId);
      } else {
        originals[cardId] = result;
      }
    });
  }

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
        const Text('给不在身边的人：每位接收者一份交接包和一个取件码；到点后由云端摇篮按草稿发邮件。'),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Text(
                '交给他人',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            TextButton(
              onPressed: _deliveries.isEmpty ? null : _showCodes,
              child: const Text('取件码总览'),
            ),
          ],
        ),
        for (final delivery in _deliveries)
          ListTile(
            contentPadding: EdgeInsets.zero,
            isThreeLine: true,
            leading: const Icon(Icons.person_outline),
            title: Text(delivery.label),
            subtitle: Text(
              '${delivery.email}\n'
              '${_deliveryStatus(delivery.status)} · ${delivery.scope.length} 条 · '
              '取件码 ••••••',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: _deliveryBusy ? null : () => _openDelivery(delivery),
          ),
        if (_deliveries.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('还没有接收者。添加后按人设范围和取件码。'),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: _deliveryBusy ? null : _addRecipient,
            icon: const Icon(Icons.person_add_alt_1_outlined),
            label: const Text('添加接收者'),
          ),
        ),
        if (_deliveryBusy) const LinearProgressIndicator(),
        if (_deliveryError != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              _deliveryError!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        const SizedBox(height: 24),
        const Divider(),
        Text('本机取件（同一台设备）', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
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
                        originals.clear();
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
              final card = record is LifeCard;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  CheckboxListTile(
                    value: selected.contains(key),
                    title: Text(record.title),
                    subtitle: Text(
                      card ? '卡片 · 交付完整正文' : '密码条目 · 交付账号、网址、备注和当前密码',
                    ),
                    onChanged: _busy
                        ? null
                        : (value) => setState(() {
                            if (value == true) {
                              selected.add(key);
                            } else {
                              selected.remove(key);
                              if (card) originals.remove(record.id);
                            }
                          }),
                  ),
                  if (card && selected.contains(key)) ...[
                    CheckboxListTile(
                      contentPadding: const EdgeInsets.only(
                        left: 32,
                        right: 16,
                      ),
                      value: originals.containsKey(record.id),
                      title: const Text('附带原件'),
                      subtitle: Text(
                        originals[record.id] == null
                            ? '不交付原件'
                            : '${originals[record.id]!.length} 个原件',
                      ),
                      onChanged: _busy
                          ? null
                          : (value) =>
                                _toggleOriginals(record.id, value ?? false),
                    ),
                    if (originals[record.id]?.isNotEmpty ?? false)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Padding(
                          padding: const EdgeInsets.only(left: 32, bottom: 8),
                          child: TextButton(
                            onPressed: _busy
                                ? null
                                : () => _chooseOriginals(record.id),
                            child: const Text('选择具体原件'),
                          ),
                        ),
                      ),
                  ],
                ],
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

@visibleForTesting
Future<(String, String)?> showAddRecipientDialog(BuildContext context) =>
    showDialog<(String, String)>(
      context: context,
      builder: (_) => const _AddRecipientDialog(),
    );

class _AddRecipientDialog extends StatefulWidget {
  const _AddRecipientDialog();

  @override
  State<_AddRecipientDialog> createState() => _AddRecipientDialogState();
}

class _AddRecipientDialogState extends State<_AddRecipientDialog> {
  final _label = TextEditingController();
  final _email = TextEditingController();

  bool get _ready =>
      _label.text.trim().isNotEmpty &&
      _email.text.contains('@') &&
      _email.text.length >= 3;

  @override
  void dispose() {
    _label.dispose();
    _email.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('添加接收者'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _label,
              autofocus: true,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(labelText: '称呼'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(labelText: '邮箱'),
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
          onPressed: _ready
              ? () => Navigator.pop(context, (
                  _label.text.trim(),
                  _email.text.trim(),
                ))
              : null,
          child: const Text('添加'),
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
