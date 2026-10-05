import 'dart:convert';

import 'conversation_attachment.dart';
import 'review_actions.dart';

/// Owner-only confirmation evidence, independent of the current conversation.
/// No credentials, provider wire history or release authority belong here.
class ReviewSourceInput {
  const ReviewSourceInput(this.text, this.attachments);
  final String text;
  final List<ConversationAttachment> attachments;
}

class ReviewSource {
  const ReviewSource({
    required this.reviewId,
    required this.providerLabel,
    required this.confirmedAt,
    required this.inputs,
    required this.reply,
    this.actions = const [],
  });
  final String reviewId, providerLabel, reply;
  final DateTime confirmedAt;
  final List<ReviewSourceInput> inputs;
  final List<ReviewActions> actions;
  static const maxLength = 32 * 1024 * 1024;
  String get storageKey => 'ars.$reviewId';
  static String cardKey(String id) => 'card.agent-source.$id';
  ReviewSource withActions(List<ReviewActions> plans) => ReviewSource(
    reviewId: reviewId,
    providerLabel: providerLabel,
    confirmedAt: confirmedAt,
    inputs: inputs,
    reply: reply,
    actions: plans,
  );

  String encode() {
    if (!RegExp(r'^[a-zA-Z0-9-]{1,64}$').hasMatch(reviewId) ||
        providerLabel.length > 1000 ||
        reply.length > 128 * 1024 ||
        inputs.length > 1000 ||
        actions.length > 20 ||
        inputs.any((i) => i.text.length > 32000 || i.attachments.length > 6)) {
      throw const FormatException('确认来源记录无效或过大');
    }
    for (final action in actions) {
      action.validate();
    }
    final encoded = jsonEncode({
      'version': 1,
      'review': reviewId,
      'provider': providerLabel,
      'confirmedAt': confirmedAt.toUtc().toIso8601String(),
      'reply': reply,
      'actions': [for (final action in actions) action.toJson()],
      'inputs': [
        for (final input in inputs)
          {
            'text': input.text,
            'attachments': [for (final a in input.attachments) a.toJson()],
          },
      ],
    });
    if (encoded.length > maxLength) {
      throw const FormatException('确认来源超过32 MB，请缩小会话后确认');
    }
    return encoded;
  }

  factory ReviewSource.decode(String value) {
    if (value.length > maxLength) {
      throw const FormatException('确认来源过大');
    }
    final allocated = <ConversationAttachment>[];
    try {
      final raw = jsonDecode(value) as Map;
      if (raw['version'] != 1) {
        throw const FormatException('确认来源版本不支持');
      }
      final inputs = <ReviewSourceInput>[];
      final entries = raw['inputs'] as List;
      if (entries.length > 1000) throw const FormatException('确认来源过大');
      for (final entry in entries) {
        final items = entry['attachments'] as List;
        if (items.length > 6) throw const FormatException('确认附件过多');
        final attachments = <ConversationAttachment>[];
        for (final item in items) {
          final a = ConversationAttachment.fromJson(item as Map);
          allocated.add(a);
          attachments.add(a);
        }
        inputs.add(ReviewSourceInput(entry['text'] as String, attachments));
      }
      final result = ReviewSource(
        reviewId: raw['review'] as String,
        providerLabel: raw['provider'] as String,
        confirmedAt: DateTime.parse(raw['confirmedAt'] as String),
        inputs: inputs,
        reply: raw['reply'] as String,
        actions: [
          for (final a in raw['actions'] as List? ?? [])
            ReviewActions.fromJson(a as Map),
        ],
      );
      result.encode();
      return result;
    } on Object {
      for (final a in allocated) {
        a.wipe();
      }
      throw const FormatException('确认来源记录无法读取');
    }
  }

  void wipe() {
    for (final input in inputs) {
      for (final a in input.attachments) {
        a.wipe();
      }
    }
  }
}
