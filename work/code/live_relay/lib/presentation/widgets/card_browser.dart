import 'package:flutter/material.dart';

import '../../application/card_summary.dart';
import '../design_system/appearance_tokens.dart';
import '../design_system/atoms.dart';
import '../model_labels.dart';

/// Internal presentation seam for a future alternative archive renderer.
typedef CardBrowserBuilder = Widget Function(
  BuildContext context,
  List<CardSummary> cards,
  ValueChanged<CardSummary> onOpen,
);

Widget defaultCardBrowser(
  BuildContext context,
  List<CardSummary> cards,
  ValueChanged<CardSummary> onOpen,
) => Column(
  children: [
    for (final card in cards)
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Card(
          child: InkWell(
            borderRadius: BorderRadius.circular(
              AppearanceTokens.of(context).cardRadius,
            ),
            onTap: () => onOpen(card),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Icon(
                        card.isPassword ? Icons.key_outlined : card.kind!.icon,
                        size: 20,
                      ),
                      Text(
                        card.title,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      StatusPill(
                        label: card.isPassword ? '密码' : card.kind!.label,
                      ),
                      if (card.status != null)
                        StatusPill(label: card.status!.label),
                    ],
                  ),
                  if (card.preview.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      card.preview,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  if (card.isPassword)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text('••••••••', semanticsLabel: '密码已遮盖'),
                    ),
                  if (card.tags.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: [for (final tag in card.tags) Text('#$tag')],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
  ],
);
