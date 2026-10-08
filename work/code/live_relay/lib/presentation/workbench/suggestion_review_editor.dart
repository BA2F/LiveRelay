import 'package:flutter/material.dart';

import '../controllers/agent_conversation.dart';
import '../../core/ai/ai_privacy.dart';
import '../../core/ai/review_actions.dart';
import '../../core/domain/entities.dart';
import '../model_labels.dart';
import 'review_actions_editor.dart';

/// Main and detached renderers share the same owner review controls. Commands
/// are supplied by their respective bindings; this widget never owns a vault.
class SuggestionReviewEditor extends StatelessWidget {
  const SuggestionReviewEditor({
    super.key,
    required this.message,
    required this.index,
    required this.cards,
    required this.working,
    required this.onSuggestion,
    required this.onActions,
    required this.onAdopt,
  });
  final ConversationMessage message;
  final int index;
  final List<LifeCard> cards;
  final bool working;
  final ValueChanged<AiCardSuggestion> onSuggestion;
  final ValueChanged<ReviewActions> onActions;
  final VoidCallback onAdopt;

  @override
  Widget build(BuildContext context) {
    final suggestion = message.suggestions[index];
    final enabled = !message.accepted && !working;
    void edit({
      String? title,
      String? content,
      CardKind? kind,
      bool? inference,
      List<String>? tags,
    }) => onSuggestion(
      AiCardSuggestion(
        title: title ?? suggestion.title,
        content: content ?? suggestion.content,
        kind: kind ?? suggestion.kind,
        isInference: inference ?? suggestion.isInference,
        tags: tags ?? suggestion.tags,
      ),
    );
    Widget field(
      String name,
      String label,
      String value,
      ValueChanged<String> onChanged, {
      int maxLines = 1,
    }) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: ReviewTextField(
        key: ValueKey('${message.reviewId}/$index/$name'),
        label: label,
        value: value,
        enabled: enabled,
        maxLines: maxLines,
        onChanged: onChanged,
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        children: [
          DropdownButtonFormField<CardKind>(
            key: ValueKey('${message.reviewId}/$index/${suggestion.kind.name}'),
            initialValue: suggestion.kind,
            decoration: const InputDecoration(labelText: '建议类型'),
            items: [
              for (final kind in CardKind.values.where(
                (k) => k != CardKind.bundle,
              ))
                DropdownMenuItem(value: kind, child: Text(kind.label)),
            ],
            onChanged: enabled ? (kind) => edit(kind: kind) : null,
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('内容包含推断'),
            value: suggestion.isInference,
            onChanged: enabled ? (value) => edit(inference: value) : null,
          ),
          if (suggestion.isInference) const Text('包含推断，请核对'),
          field('title', '建议标题', suggestion.title, (text) => edit(title: text)),
          field(
            'content',
            '建议总结',
            suggestion.content,
            (text) => edit(content: text),
            maxLines: 6,
          ),
          field(
            'tags',
            '建议标签',
            suggestion.tags.join('，'),
            (text) => edit(
              tags: text
                  .split(RegExp('[，,]'))
                  .map((t) => t.trim())
                  .where((t) => t.isNotEmpty)
                  .toSet()
                  .toList(),
            ),
          ),
          ReviewActionsEditor(
            key: ValueKey('${message.reviewId}/$index/actions'),
            cards: cards,
            working: working,
            message: message,
            index: index,
            onChanged: onActions,
            onAdopt: onAdopt,
          ),
        ],
      ),
    );
  }
}

class ReviewTextField extends StatefulWidget {
  const ReviewTextField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.maxLines = 1,
    this.enabled = true,
  });
  final String label, value;
  final ValueChanged<String> onChanged;
  final int maxLines;
  final bool enabled;
  @override
  State<ReviewTextField> createState() => _ReviewTextFieldState();
}

class _ReviewTextFieldState extends State<ReviewTextField> {
  late final _text = TextEditingController(text: widget.value);
  @override
  void didUpdateWidget(covariant ReviewTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_text.text != widget.value) {
      final offset = _text.selection.baseOffset.clamp(0, widget.value.length);
      _text.value = TextEditingValue(
        text: widget.value,
        selection: TextSelection.collapsed(offset: offset),
      );
    }
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(
    controller: _text,
    enabled: widget.enabled,
    maxLines: widget.maxLines,
    decoration: InputDecoration(labelText: widget.label),
    onChanged: widget.onChanged,
  );
}
