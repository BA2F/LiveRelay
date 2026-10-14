import 'package:flutter/material.dart';

import '../controllers/app_controller.dart';
import '../../core/domain/entities.dart';
import '../model_labels.dart';

class ReferencePanel extends StatelessWidget {
  const ReferencePanel({
    super.key,
    required this.controller,
    required this.cardId,
    required this.onOpen,
  });
  final AppController controller;
  final String cardId;
  final ValueChanged<String> onOpen;
  Future<void> _replace(BuildContext context, List<String> ids) async {
    try {
      await controller.setCardReferences(cardId, ids);
    } on Object {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(controller.lastError ?? '引用保存失败')),
        );
      }
    }
  }

  Future<void> _add(
    BuildContext context,
    List<LifeCard> available,
    List<String> outgoing,
  ) async {
    final id = await showDialog<String>(
      context: context,
      builder: (_) => _ReferencePickerDialog(cards: available),
    );
    if (id != null && context.mounted) {
      await _replace(context, [...outgoing, id]);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cards = {for (final c in controller.cards) c.id: c};
    final outgoing = controller.cardReferences
        .where((r) => r.from == cardId && cards.containsKey(r.to))
        .map((r) => r.to)
        .toList();
    final incoming = controller.cardReferences
        .where((r) => r.to == cardId && cards.containsKey(r.from))
        .map((r) => r.from)
        .toList();
    final available = cards.values
        .where((c) => c.id != cardId && !outgoing.contains(c.id))
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(child: Text('卡片引用')),
            IconButton(
              tooltip: '添加卡片引用',
              onPressed: controller.isBusy || available.isEmpty
                  ? null
                  : () => _add(context, available, outgoing),
              icon: const Icon(Icons.add_link),
            ),
          ],
        ),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final id in outgoing)
              InputChip(
                label: Text(cards[id]!.title),
                onPressed: () => onOpen(id),
                onDeleted: controller.isBusy
                    ? null
                    : () => _replace(
                        context,
                        outgoing.where((v) => v != id).toList(),
                      ),
              ),
          ],
        ),
        if (incoming.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text('反向引用 · ${incoming.length}'),
          Wrap(
            spacing: 6,
            children: [
              for (final id in incoming)
                ActionChip(
                  label: Text(cards[id]!.title),
                  onPressed: () => onOpen(id),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

/// 搜索式选择器：卡片多时也能快速找到要引用的卡片。
class _ReferencePickerDialog extends StatefulWidget {
  const _ReferencePickerDialog({required this.cards});
  final List<LifeCard> cards;
  @override
  State<_ReferencePickerDialog> createState() => _ReferencePickerDialogState();
}

class _ReferencePickerDialogState extends State<_ReferencePickerDialog> {
  final _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  List<LifeCard> get _matches {
    final needle = _query.text.trim().toLowerCase();
    return widget.cards
        .where(
          (c) =>
              needle.isEmpty ||
              '${c.title} ${c.content} ${c.tags.join(' ')}'
                  .toLowerCase()
                  .contains(needle),
        )
        .take(50)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final matches = _matches;
    return Dialog(
      child: SizedBox(
        width: 480,
        height: 420,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: TextField(
                controller: _query,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: '搜索要引用的卡片',
                  prefixIcon: Icon(Icons.search),
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => Navigator.pop(
                  context,
                  matches.isEmpty ? null : matches.first.id,
                ),
              ),
            ),
            Expanded(
              child: matches.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('没有匹配的卡片'),
                    )
                  : ListView(
                      children: [
                        for (final card in matches)
                          ListTile(
                            dense: true,
                            leading: Icon(card.kind.icon, size: 18),
                            title: Text(card.title),
                            subtitle: Text(card.kind.label),
                            onTap: () => Navigator.pop(context, card.id),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
