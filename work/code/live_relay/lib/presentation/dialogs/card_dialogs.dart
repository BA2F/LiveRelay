import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../application/app_controller.dart';
import '../../core/domain/entities.dart';
import '../design_system/atoms.dart';
import '../model_labels.dart';

Future<void> showCardEditor(
  BuildContext context,
  AppController controller, {
  LifeCard? card,
  CardStatus initialStatus = CardStatus.confirmed,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _CardEditorSheet(
      controller: controller,
      card: card,
      initialStatus: initialStatus,
    ),
  );
}

class _CardEditorSheet extends StatefulWidget {
  const _CardEditorSheet({
    required this.controller,
    required this.card,
    required this.initialStatus,
  });

  final AppController controller;
  final LifeCard? card;
  final CardStatus initialStatus;

  @override
  State<_CardEditorSheet> createState() => _CardEditorSheetState();
}

class _CardEditorSheetState extends State<_CardEditorSheet> {
  late final TextEditingController _title;
  late final TextEditingController _content;
  late final TextEditingController _tags;
  late CardKind _kind;
  late CardStatus _status;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.card?.title);
    _content = TextEditingController(text: widget.card?.content);
    _tags = TextEditingController(text: widget.card?.tags.join(', '));
    _kind = widget.card?.kind ?? CardKind.note;
    _status = widget.card?.status ?? widget.initialStatus;
  }

  @override
  void dispose() {
    _title.dispose();
    _content.dispose();
    _tags.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final draft = CardDraft(
      title: _title.text,
      content: _content.text,
      kind: _kind,
      status: _status,
      tags: _tags.text.split(RegExp(r'[,，]')),
    );
    try {
      if (widget.card == null) {
        await widget.controller.createCard(draft);
      } else {
        await widget.controller.updateCard(widget.card!.id, draft);
      }
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
              widget.card == null ? '新建信息卡片' : '编辑卡片',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 18),
            TextField(
              controller: _title,
              autofocus: true,
              decoration: const InputDecoration(labelText: '标题'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _content,
              minLines: 4,
              maxLines: 9,
              decoration: const InputDecoration(
                labelText: '内容',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<CardKind>(
              initialValue: _kind,
              decoration: const InputDecoration(labelText: '类别'),
              items: CardKind.values
                  .where((value) => value != CardKind.bundle)
                  .map(
                    (value) => DropdownMenuItem(
                      value: value,
                      child: Text(value.label),
                    ),
                  )
                  .toList(),
              onChanged: (value) => setState(() => _kind = value ?? _kind),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _tags,
              decoration: const InputDecoration(
                labelText: '标签',
                hintText: '用逗号分隔',
              ),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('暂存为待确认草稿'),
              subtitle: const Text('AI 或未整理完成的内容不自动成为事实'),
              value: _status == CardStatus.draft,
              onChanged: (value) => setState(
                () => _status = value ? CardStatus.draft : CardStatus.confirmed,
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: widget.controller.isBusy ? null : _save,
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 13),
                child: Text('保存'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> showCardDetails(
  BuildContext context,
  AppController controller,
  LifeCard card,
) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (sheetContext) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.76,
      minChildSize: 0.5,
      maxChildSize: 0.96,
      builder: (context, scrollController) => ListView(
        controller: scrollController,
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Icon(card.kind.icon),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  card.title,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ),
              StatusPill(label: card.status.label),
            ],
          ),
          const SizedBox(height: 18),
          SelectableText(card.content),
          if (card.tags.isNotEmpty) ...[
            const SizedBox(height: 18),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: card.tags.map((tag) => Chip(label: Text(tag))).toList(),
            ),
          ],
          const SizedBox(height: 18),
          Text(
            '第 ${card.revisionNumber} 版 · 更新于 ${DateFormat('yyyy-MM-dd HH:mm').format(card.updatedAt.toLocal())}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.tonalIcon(
                onPressed: () async {
                  Navigator.pop(sheetContext);
                  await showCardEditor(context, controller, card: card);
                },
                icon: const Icon(Icons.edit_outlined),
                label: const Text('编辑'),
              ),
              if (card.status == CardStatus.draft)
                FilledButton.tonalIcon(
                  onPressed: () async {
                    await controller.confirmCard(card.id);
                    if (sheetContext.mounted) Navigator.pop(sheetContext);
                  },
                  icon: const Icon(Icons.verified_outlined),
                  label: const Text('本人确认'),
                ),
              OutlinedButton.icon(
                onPressed: () => showCardHistory(context, controller, card),
                icon: const Icon(Icons.history),
                label: const Text('历史'),
              ),
              OutlinedButton.icon(
                onPressed: () => showSplitCardDialog(context, controller, card),
                icon: const Icon(Icons.call_split),
                label: const Text('拆分'),
              ),
              OutlinedButton.icon(
                onPressed: () => showReleasePolicyDialog(
                  context,
                  controller,
                  recordType: 'card',
                  recordId: card.id,
                  recordTitle: card.title,
                ),
                icon: const Icon(Icons.policy_outlined),
                label: const Text('交接策略'),
              ),
            ],
          ),
          const SizedBox(height: 24),
          TextButton.icon(
            onPressed: () async {
              await controller.trashCard(card.id);
              if (sheetContext.mounted) Navigator.pop(sheetContext);
            },
            icon: const Icon(Icons.delete_outline),
            label: const Text('移入回收区（保留历史）'),
          ),
        ],
      ),
    ),
  );
}

Future<void> showCardHistory(
  BuildContext context,
  AppController controller,
  LifeCard card,
) async {
  final history = await controller.cardHistory(card.id);
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('${card.title} · 修订历史'),
      content: SizedBox(
        width: 520,
        child: ListView.separated(
          shrinkWrap: true,
          itemCount: history.length,
          separatorBuilder: (_, _) => const Divider(),
          itemBuilder: (context, index) {
            final revision = history[index];
            return ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('v${revision.number} · ${revision.changeNote}'),
              subtitle: Text(
                '${revision.content}\n${revision.sourceLabel} · ${DateFormat('yyyy-MM-dd HH:mm').format(revision.createdAt.toLocal())}',
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
              ),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
      ],
    ),
  );
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
        title: Text('交接策略 · $recordTitle'),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('默认仅本人可见。下面是对“演示执行人”的明确授权，不代表法律处置权。'),
              const SizedBox(height: 18),
              DropdownButtonFormField<VisibilityLevel>(
                initialValue: incapacitated,
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
              const SizedBox(height: 12),
              DropdownButtonFormField<VisibilityLevel>(
                initialValue: deceased,
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
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              await controller.saveReleasePolicy(
                ReleasePolicy(
                  recordType: recordType,
                  recordId: recordId,
                  incapacitated: incapacitated,
                  deceased: deceased,
                ),
              );
              if (dialogContext.mounted) Navigator.pop(dialogContext);
            },
            child: const Text('保存策略'),
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
