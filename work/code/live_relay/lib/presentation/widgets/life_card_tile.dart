import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/domain/entities.dart';
import '../design_system/atoms.dart';
import '../model_labels.dart';

class LifeCardTile extends StatelessWidget {
  const LifeCardTile({
    super.key,
    required this.card,
    required this.onTap,
    this.selected = false,
    this.onSelected,
  });

  final LifeCard card;
  final VoidCallback onTap;
  final bool selected;
  final ValueChanged<bool>? onSelected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: selected ? scheme.secondaryContainer : null,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        onLongPress: onSelected == null ? null : () => onSelected!(!selected),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(11),
                  child: Icon(card.kind.icon, color: scheme.onPrimaryContainer),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            card.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        if (selected) const Icon(Icons.check_circle),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      card.content,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        StatusPill(
                          label: card.status.label,
                          icon: card.status == CardStatus.confirmed
                              ? Icons.verified_outlined
                              : Icons.edit_note,
                        ),
                        Text(
                          '${card.kind.label} · ${DateFormat('MM-dd HH:mm').format(card.updatedAt.toLocal())}',
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
