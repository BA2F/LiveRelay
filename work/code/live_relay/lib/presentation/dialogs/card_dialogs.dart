import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../controllers/app_controller.dart';
import '../../core/domain/entities.dart';
import '../design_system/atoms.dart';
import '../model_labels.dart';
import '../../application/release_preview.dart';
import '../widgets/release_preview_panel.dart';
import '../pages/originals_page.dart';

Future<void> showCardEditor(
  BuildContext context,
  AppController controller, {
  LifeCard? card,
  String? sourceBlobId,
  String? initialContent,
}) async {
  await Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (_) => _CardEditorSheet(
        controller: controller,
        card: card,
        sourceBlobId: sourceBlobId,
        initialContent: initialContent,
      ),
    ),
  );
}

class _CardEditorSheet extends StatefulWidget {
  const _CardEditorSheet({
    required this.controller,
    required this.card,
    this.sourceBlobId,
    this.initialContent,
  });
  final AppController controller;
  final LifeCard? card;
  final String? sourceBlobId;
  final String? initialContent;
  @override
  State<_CardEditorSheet> createState() => _CardEditorSheetState();
}

class _CardEditorSheetState extends State<_CardEditorSheet> {
  late final _title = TextEditingController(text: widget.card?.title);
  late final _content = TextEditingController(
    text: widget.card?.content ?? widget.initialContent,
  );
  late final _tags = TextEditingController(text: widget.card?.tags.join(', '));
  late CardKind _kind = widget.card?.kind ?? CardKind.note;
  bool _dirty = false;
  bool _allowExit = false;
  bool _saving = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    for (final c in [_title, _content, _tags]) {
      c.addListener(_changed);
    }
    _dirty = widget.initialContent?.isNotEmpty ?? false;
  }

  void _changed() {
    if (mounted) setState(() => _dirty = true);
  }

  @override
  void dispose() {
    for (final c in [_title, _content, _tags]) {
      c.dispose();
    }
    super.dispose();
  }

  /// 采集只有这一个保存动作：新内容存为待整理；编辑已有卡片保留它
  /// 原来的确认状态（与桌面自动保存一致），确认动作在卡片详情里单独进行。
  Future<void> _save() async {
    if (_saving) return;
    final content = _content.text.trim();
    if (content.isEmpty) {
      setState(() => _error = '先写下一点内容。');
      return;
    }
    final firstLine = content.split('\n').first;
    final title = _title.text.trim().isNotEmpty
        ? _title.text.trim()
        : String.fromCharCodes(firstLine.runes.take(28));
    final status = widget.card?.status ?? CardStatus.draft;
    final draft = CardDraft(
      title: title,
      content: content,
      kind: _kind,
      status: status,
      tags: _tags.text.split(RegExp(r'[,，]')),
    );
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      if (widget.card != null) {
        await widget.controller.updateCard(
          widget.card!.id,
          draft,
          changeNote: status == CardStatus.confirmed
              ? '本人修改并保存，卡片保持已确认'
              : '本人修改，保存待整理',
        );
      } else if (widget.sourceBlobId != null) {
        await widget.controller.createCardFromOriginal(
          widget.sourceBlobId!,
          draft,
        );
      } else {
        await widget.controller.createCard(draft);
      }
      if (mounted) {
        setState(() {
          _allowExit = true;
          _saving = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              status == CardStatus.confirmed ? '已加密保存，卡片保持已确认' : '已加密保存在本机，进入待整理',
            ),
          ),
        );
        // PopScope must rebuild before programmatic pop.
        await Future<void>.delayed(Duration.zero);
        if (mounted) Navigator.pop(context);
      }
    } on Object {
      if (mounted) {
        setState(() => _error = widget.controller.lastError ?? '保存失败，输入仍保留');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _leave() async {
    if (_saving) return;
    final action = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('保留还没保存的内容？'),
        content: const Text('保留会加密保存为待整理内容，之后可以继续编辑。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('继续编辑'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, 'discard'),
            child: const Text('放弃修改'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, 'save'),
            child: const Text('加密保留'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (action == 'save') {
      await _save();
    }
    if (action == 'discard') {
      setState(() {
        _allowExit = true;
        _saving = false;
      });
      await Future<void>.delayed(Duration.zero);
      if (mounted) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope<void>(
    canPop: (!_dirty || _allowExit) && !_saving,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) _leave();
    },
    child: Scaffold(
      appBar: AppBar(title: Text(widget.card == null ? '记一条' : '编辑这条信息')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            TextField(
              controller: _content,
              autofocus: true,
              minLines: 4,
              maxLines: 10,
              decoration: const InputDecoration(
                labelText: '想记下什么？',
                hintText: '例如：备用钥匙在鞋柜第二层。',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              widget.card == null
                  ? '保存为待整理内容，默认仅本人可见；核对后可在卡片详情里确认。'
                  : '保存会生成同一卡片的新修订，旧内容和来源保留。',
            ),
            const SizedBox(height: 16),
            ExpansionTile(
              title: const Text('补充信息（可选）'),
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(bottom: 16),
              children: [
                TextField(
                  controller: _title,
                  decoration: const InputDecoration(
                    labelText: '标题',
                    hintText: '留空时使用内容首行',
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<CardKind>(
                  initialValue: _kind,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: '类型'),
                  items: CardKind.values
                      .where(
                        (v) => v != CardKind.bundle || _kind == CardKind.bundle,
                      )
                      .map(
                        (v) => DropdownMenuItem(value: v, child: Text(v.label)),
                      )
                      .toList(),
                  onChanged: _saving
                      ? null
                      : (v) => setState(() {
                          _kind = v ?? _kind;
                          _dirty = true;
                        }),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _tags,
                  decoration: const InputDecoration(labelText: '标签（逗号分隔）'),
                ),
              ],
            ),
            if (_error != null) ...[
              ErrorBanner(_error!),
              const SizedBox(height: 12),
            ],
            FilledButton(
              onPressed: _saving ? null : _save,
              child: Text(_saving ? '加密保存中…' : '保存'),
            ),
          ],
        ),
      ),
    ),
  );
}

Future<void> showCardDetails(
  BuildContext context,
  AppController controller,
  LifeCard card,
) async {
  await Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (_) =>
          _CardDetailPage(controller: controller, initialCard: card),
    ),
  );
}

class _CardDetailPage extends StatefulWidget {
  const _CardDetailPage({required this.controller, required this.initialCard});
  final AppController controller;
  final LifeCard initialCard;
  @override
  State<_CardDetailPage> createState() => _CardDetailPageState();
}

class _CardDetailPageState extends State<_CardDetailPage> {
  late Future<List<CardSource>> _sources = widget.controller.cardSources(
    widget.initialCard.id,
  );
  late Future<List<CardRelation>> _relations = widget.controller.cardRelations(
    widget.initialCard.id,
  );
  String _time(DateTime value) =>
      DateFormat('yyyy-MM-dd HH:mm').format(value.toLocal());
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      final controller = widget.controller;
      final card =
          [
            ...controller.cards,
            ...controller.recycledCards,
          ].where((c) => c.id == widget.initialCard.id).firstOrNull ??
          widget.initialCard;
      return Scaffold(
        appBar: AppBar(
          title: const Text('卡片详情'),
          actions: [
            PopupMenuButton<String>(
              tooltip: '更多操作',
              onSelected: (value) async {
                if (value == 'history') {
                  await showCardHistory(context, controller, card);
                  return;
                }
                if (value == 'split') {
                  if (context.mounted) {
                    await showSplitCardDialog(context, controller, card);
                  }
                  return;
                }
                if (value == 'combine') {
                  if (context.mounted) {
                    await showCombineCardsDialog(context, controller);
                  }
                  return;
                }
                if (value == 'trash' && context.mounted) {
                  final messenger = ScaffoldMessenger.of(context);
                  await runUiAction(context, () async {
                    await controller.trashCard(card.id);
                    if (!context.mounted) return;
                    Navigator.pop(context);
                    messenger.showSnackBar(
                      SnackBar(
                        content: const Text('已移入回收区，来源和历史保留'),
                        action: SnackBarAction(
                          label: '撤销',
                          onPressed: () async {
                            try {
                              await controller.restoreCard(card.id);
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
                  });
                }
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'history', child: Text('修订历史')),
                if (!card.isDeleted) ...[
                  const PopupMenuItem(value: 'split', child: Text('拆分卡片')),
                  const PopupMenuItem(value: 'combine', child: Text('创建组合卡片')),
                  const PopupMenuItem(value: 'trash', child: Text('移入回收区')),
                ],
              ],
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(card.title, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                StatusPill(label: card.isDeleted ? '在回收区' : card.status.label),
                StatusPill(label: card.kind.label),
              ],
            ),
            const SizedBox(height: 20),
            SelectableText(card.content),
            if (card.tags.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: card.tags.map((t) => Chip(label: Text(t))).toList(),
              ),
            ],
            const SizedBox(height: 20),
            Text('第 ${card.revisionNumber} 版 · 更新于 ${_time(card.updatedAt)}'),
            Text(
              card.confirmedAt == null
                  ? '尚待本人核对'
                  : '本人确认于 ${_time(card.confirmedAt!)}',
            ),
            const SizedBox(height: 16),
            if (card.isDeleted)
              FilledButton.icon(
                icon: const Icon(Icons.restore),
                label: const Text('恢复这张卡片'),
                onPressed: controller.isBusy
                    ? null
                    : () => runUiAction(
                        context,
                        () => controller.restoreCard(card.id),
                        success: '已恢复，已有授权仍保留',
                      ),
              )
            else ...[
              FilledButton.icon(
                icon: const Icon(Icons.edit_outlined),
                label: const Text('编辑这条信息'),
                onPressed: controller.isBusy
                    ? null
                    : () async {
                        await showCardEditor(context, controller, card: card);
                        if (mounted) {
                          setState(() {
                            _sources = controller.cardSources(card.id);
                            _relations = controller.cardRelations(card.id);
                          });
                        }
                      },
              ),
              if (card.isDraft)
                OutlinedButton.icon(
                  icon: const Icon(Icons.verified_outlined),
                  label: const Text('本人确认这条内容'),
                  onPressed: controller.isBusy
                      ? null
                      : () => runUiAction(context, () async {
                          await controller.confirmCard(card.id);
                          if (mounted) {
                            setState(() {
                              _sources = controller.cardSources(card.id);
                            });
                          }
                        }, success: '已确认，历史仍保留'),
                ),
              OutlinedButton.icon(
                icon: const Icon(Icons.policy_outlined),
                label: const Text('设置并预览交接授权'),
                onPressed: controller.isBusy
                    ? null
                    : () => showReleasePolicyDialog(
                        context,
                        controller,
                        recordType: 'card',
                        recordId: card.id,
                        recordTitle: card.title,
                      ),
              ),
            ],
            const SizedBox(height: 24),
            Text('这条信息从哪里来', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            FutureBuilder<List<CardSource>>(
              future: _sources,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return ErrorBanner('来源读取失败：${snapshot.error}');
                }
                if (!snapshot.hasData) return const LinearProgressIndicator();
                return Column(
                  children: snapshot.data!
                      .map(
                        (source) => ExpansionTile(
                          tilePadding: EdgeInsets.zero,
                          title: Text(source.label),
                          subtitle: Text(_time(source.createdAt)),
                          children: [
                            Align(
                              alignment: Alignment.centerLeft,
                              child: SelectableText(source.excerpt),
                            ),
                            if (source.blobId != null)
                              ...controller.blobs
                                  .where((b) => b.id == source.blobId)
                                  .map(
                                    (blob) => ListTile(
                                      contentPadding: EdgeInsets.zero,
                                      leading: const Icon(Icons.attach_file),
                                      title: Text(blob.originalName),
                                      subtitle: const Text('查看原件 / 整理内容'),
                                      onTap: () => openOriginalWorkspace(
                                        context,
                                        controller,
                                        blob,
                                      ),
                                    ),
                                  ),
                          ],
                        ),
                      )
                      .toList(),
                );
              },
            ),
            FutureBuilder<List<CardRelation>>(
              future: _relations,
              builder: (context, snapshot) => Column(
                children: (snapshot.data ?? []).map((relation) {
                  final relatedId = relation.fromCardId == card.id
                      ? relation.toCardId
                      : relation.fromCardId;
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.link),
                    title: Text(
                      relation.kind == RelationKind.splitFrom
                          ? '查看拆分前身 / 后续卡片'
                          : '查看组合 / 成员卡片',
                    ),
                    onTap: () => runUiAction(context, () async {
                      final related = await controller.getCard(relatedId);
                      if (related == null) throw StateError('关联卡片不存在');
                      if (context.mounted) {
                        await showCardDetails(context, controller, related);
                      }
                    }),
                  );
                }).toList(),
              ),
            ),
            OutlinedButton.icon(
              onPressed: () => showCardHistory(context, controller, card),
              icon: const Icon(Icons.history),
              label: const Text('查看完整修订历史'),
            ),
          ],
        ),
      );
    },
  );
}

Future<void> showCardHistory(
  BuildContext context,
  AppController controller,
  LifeCard card,
) async {
  await runUiAction(context, () async {
    final history = await controller.cardHistory(card.id);
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('${card.title} · 修订历史'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              children: history
                  .map(
                    (revision) => ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      title: Text(
                        '第 ${revision.number} 版 · ${revision.changeNote}',
                      ),
                      subtitle: Text(
                        '${revision.sourceLabel} · ${DateFormat('yyyy-MM-dd HH:mm').format(revision.createdAt.toLocal())}',
                      ),
                      children: [
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(revision.title),
                              Text(revision.status.label),
                              SelectableText(revision.content),
                              if (revision.tags.isNotEmpty)
                                Text('标签：${revision.tags.join('、')}'),
                            ],
                          ),
                        ),
                      ],
                    ),
                  )
                  .toList(),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  });
}

Future<void> showSplitCardDialog(
  BuildContext context,
  AppController controller,
  LifeCard card,
) async {
  final firstTitle = TextEditingController();
  final firstContent = TextEditingController();
  final secondTitle = TextEditingController();
  final secondContent = TextEditingController();
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('拆成两张独立卡片'),
      content: SingleChildScrollView(
        child: SizedBox(
          width: 520,
          child: Column(
            children: [
              TextField(
                controller: firstTitle,
                decoration: const InputDecoration(labelText: '卡片一标题'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: firstContent,
                maxLines: 3,
                decoration: const InputDecoration(labelText: '卡片一内容'),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: secondTitle,
                decoration: const InputDecoration(labelText: '卡片二标题'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: secondContent,
                maxLines: 3,
                decoration: const InputDecoration(labelText: '卡片二内容'),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () async {
            try {
              await controller.splitCard(card.id, [
                CardDraft(title: firstTitle.text, content: firstContent.text),
                CardDraft(title: secondTitle.text, content: secondContent.text),
              ]);
              if (dialogContext.mounted) Navigator.pop(dialogContext);
            } on Object {
              if (dialogContext.mounted) {
                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  SnackBar(content: Text(controller.lastError ?? '拆分失败')),
                );
              }
            }
          },
          child: const Text('拆分并保留前身'),
        ),
      ],
    ),
  );
  await Future<void>.delayed(const Duration(milliseconds: 350));
  firstTitle.dispose();
  firstContent.dispose();
  secondTitle.dispose();
  secondContent.dispose();
}

Future<void> showReleasePolicyDialog(
  BuildContext context,
  AppController controller, {
  required String recordType,
  required String recordId,
  required String recordTitle,
}) async {
  final existing = await controller.releasePolicy(recordType, recordId);
  if (!context.mounted) return;
  var incapacitated = existing.incapacitated;
  var deceased = existing.deceased;
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text('交接授权 · $recordTitle'),
        content: SingleChildScrollView(
          child: SizedBox(
            width: 480,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('仅本机模拟 · 演示执行人。默认仅本人可见。选择后可核对实际输出，不会发送给他人。'),
                const SizedBox(height: 18),
                DropdownButtonFormField<VisibilityLevel>(
                  initialValue: incapacitated,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: '临时失能时'),
                  items: VisibilityLevel.values
                      .map(
                        (level) => DropdownMenuItem(
                          value: level,
                          child: Text(level.label),
                        ),
                      )
                      .toList(),
                  onChanged: (value) =>
                      setState(() => incapacitated = value ?? incapacitated),
                ),
                const SizedBox(height: 8),
                ReleasePreviewPanel(
                  preview: _policyPreview(
                    controller,
                    recordType,
                    recordId,
                    incapacitated,
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<VisibilityLevel>(
                  initialValue: deceased,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: '身故时'),
                  items: VisibilityLevel.values
                      .map(
                        (level) => DropdownMenuItem(
                          value: level,
                          child: Text(level.label),
                        ),
                      )
                      .toList(),
                  onChanged: (value) =>
                      setState(() => deceased = value ?? deceased),
                ),
                const SizedBox(height: 8),
                ReleasePreviewPanel(
                  preview: _policyPreview(
                    controller,
                    recordType,
                    recordId,
                    deceased,
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              await runUiAction(dialogContext, () async {
                await controller.saveReleasePolicy(
                  ReleasePolicy(
                    recordType: recordType,
                    recordId: recordId,
                    incapacitated: incapacitated,
                    deceased: deceased,
                  ),
                );
                if (dialogContext.mounted) Navigator.pop(dialogContext);
              }, success: '授权已加密保存');
            },
            child: const Text('保存授权'),
          ),
        ],
      ),
    ),
  );
}

Future<void> showCombineCardsDialog(
  BuildContext context,
  AppController controller,
) async {
  final title = TextEditingController();
  final selected = <String>{};
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('创建组合卡片'),
        content: SizedBox(
          width: 520,
          height: 480,
          child: Column(
            children: [
              TextField(
                controller: title,
                decoration: const InputDecoration(labelText: '组合名称'),
              ),
              const SizedBox(height: 12),
              const Text('组合只建立引用，不复制内容，也不扩大成员权限。'),
              const SizedBox(height: 8),
              Expanded(
                child: ListView(
                  children: controller.cards
                      .where((card) => card.kind != CardKind.bundle)
                      .map(
                        (card) => CheckboxListTile(
                          value: selected.contains(card.id),
                          title: Text(card.title),
                          subtitle: Text(card.kind.label),
                          onChanged: (value) => setState(() {
                            if (value ?? false) {
                              selected.add(card.id);
                            } else {
                              selected.remove(card.id);
                            }
                          }),
                        ),
                      )
                      .toList(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: selected.length < 2
                ? null
                : () async {
                    try {
                      await controller.combineCards(
                        title.text,
                        selected.toList(),
                      );
                      if (dialogContext.mounted) Navigator.pop(dialogContext);
                    } on Object {
                      if (dialogContext.mounted) {
                        ScaffoldMessenger.of(dialogContext).showSnackBar(
                          SnackBar(
                            content: Text(controller.lastError ?? '组合失败'),
                          ),
                        );
                      }
                    }
                  },
            child: const Text('组合'),
          ),
        ],
      ),
    ),
  );
  await Future<void>.delayed(const Duration(milliseconds: 350));
  title.dispose();
}

ReleasePreview _policyPreview(
  AppController controller,
  String type,
  String id,
  VisibilityLevel level,
) {
  if (type == 'card') {
    final card = controller.cards.firstWhere((c) => c.id == id);
    return ReleasePreview.card(card, level);
  }
  return ReleasePreview.credential(
    controller.credentials.firstWhere((c) => c.id == id),
    level,
  );
}
