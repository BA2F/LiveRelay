import 'package:flutter/material.dart';

import '../../application/app_controller.dart';

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
            PopupMenuButton<String>(
              tooltip: '添加卡片引用',
              enabled: !controller.isBusy && available.isNotEmpty,
              icon: const Icon(Icons.add_link),
              onSelected: (id) => _replace(context, [...outgoing, id]),
              itemBuilder: (_) => [
                for (final c in available)
                  PopupMenuItem(value: c.id, child: Text(c.title)),
              ],
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
