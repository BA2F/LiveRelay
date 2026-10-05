import 'dart:convert';

import '../domain/entities.dart';

class AiTokenizedPayload {
  const AiTokenizedPayload({
    required this.redactedText,
    required this.tokenMap,
  });

  final String redactedText;
  final Map<String, String> tokenMap;
}

class AiCardSuggestion {
  const AiCardSuggestion({
    required this.title,
    required this.content,
    required this.kind,
    required this.isInference,
    this.tags = const [],
  });

  final String title;
  final String content;
  final CardKind kind;
  final bool isInference;
  final List<String> tags;

  CardDraft toDraft() => CardDraft(
    title: title,
    content: content,
    kind: kind,
    status: CardStatus.draft,
    tags: ['AI', '待确认', if (isInference) '推断', ...tags],
  );
}

class AiPrivacyProcessor {
  const AiPrivacyProcessor();

  static final _tokenPattern = RegExp(r'\[\[[A-Z][A-Z0-9_]*_\d{2}\]\]');

  AiTokenizedPayload tokenize({
    required List<OcrLine> lines,
    required List<SensitiveMark> marks,
  }) {
    if (lines.isEmpty) throw const FormatException('OCR 没有可整理的文本行');
    final byOrder = <int, SensitiveFieldKind>{};
    for (final mark in marks) {
      if (byOrder.containsKey(mark.lineOrder)) {
        throw const FormatException('同一 OCR 文本行只能标记一种敏感类型');
      }
      byOrder[mark.lineOrder] = mark.kind;
    }

    final counters = <SensitiveFieldKind, int>{};
    final tokenMap = <String, String>{};
    final output = <String>[];
    for (final line in [...lines]..sort((a, b) => a.order.compareTo(b.order))) {
      final kind = byOrder[line.order];
      if (kind == null) {
        output.add(line.text);
        continue;
      }
      final next = (counters[kind] ?? 0) + 1;
      if (next > 99) throw const FormatException('单次同类敏感字段不能超过 99 个');
      counters[kind] = next;
      final token =
          '[[${kind.name.toUpperCase()}_${next.toString().padLeft(2, '0')}]]';
      tokenMap[token] = line.text;
      output.add(token);
    }
    return AiTokenizedPayload(
      redactedText: output.join('\n'),
      tokenMap: Map.unmodifiable(tokenMap),
    );
  }

  List<AiCardSuggestion> validateAndRehydrate(
    String response,
    AiTokenizedPayload payload,
  ) {
    final decoded = _decodeResponse(response);
    if (decoded.keys.toSet().difference(const {'cards'}).isNotEmpty ||
        decoded['cards'] is! List) {
      throw const FormatException('AI 返回结构不符合 cards Schema');
    }

    final seenTokens = _tokenPattern
        .allMatches(response)
        .map((match) => match.group(0)!)
        .toList(growable: false);
    final expected = payload.tokenMap.keys.toSet();
    final unknown = seenTokens.where((token) => !expected.contains(token));
    if (unknown.isNotEmpty) throw const FormatException('AI 返回了未知敏感 Token');
    for (final token in expected) {
      if (seenTokens.where((seen) => seen == token).length != 1) {
        throw const FormatException('AI 遗漏或重复了敏感 Token');
      }
    }

    final suggestions = <AiCardSuggestion>[];
    for (final raw in decoded['cards']! as List) {
      if (raw is! Map) throw const FormatException('AI 卡片结构错误');
      final item = Map<String, Object?>.from(raw);
      const allowed = {'title', 'content', 'kind', 'inference'};
      if (item.keys.toSet().difference(allowed).isNotEmpty ||
          item['title'] is! String ||
          item['content'] is! String ||
          item['kind'] is! String ||
          item['inference'] is! bool) {
        throw const FormatException('AI 卡片字段不符合 Schema');
      }
      final kind = _allowedKind(item['kind']! as String);
      final title = _rehydrate(
        item['title']! as String,
        payload.tokenMap,
      ).trim();
      final content = _rehydrate(
        item['content']! as String,
        payload.tokenMap,
      ).trim();
      if (title.isEmpty || content.isEmpty || title.length > 200) {
        throw const FormatException('AI 卡片标题或内容无效');
      }
      suggestions.add(
        AiCardSuggestion(
          title: title,
          content: content,
          kind: kind,
          isInference: item['inference']! as bool,
        ),
      );
    }
    if (suggestions.isEmpty || suggestions.length > 20) {
      throw const FormatException('AI 返回卡片数量异常');
    }
    return suggestions;
  }

  Map<String, Object?> _decodeResponse(String response) {
    try {
      var value = response.trim();
      if (value.startsWith('```')) {
        value = value.replaceFirst(RegExp(r'^```(?:json)?\s*'), '');
        value = value.replaceFirst(RegExp(r'\s*```$'), '');
      }
      final decoded = jsonDecode(value);
      if (decoded is Map) return Map<String, Object?>.from(decoded);
    } on Object {
      // Stable format error below avoids reflecting provider content to the UI.
    }
    throw const FormatException('AI 未返回有效 JSON');
  }

  CardKind _allowedKind(String value) {
    const allowed = <CardKind>{
      CardKind.note,
      CardKind.account,
      CardKind.asset,
      CardKind.debt,
      CardKind.location,
      CardKind.relationship,
      CardKind.document,
      CardKind.wish,
      CardKind.familyOperation,
    };
    final kind = CardKind.values
        .where((item) => item.name == value)
        .firstOrNull;
    if (kind == null || !allowed.contains(kind)) {
      throw const FormatException('AI 返回了不允许的卡片类型');
    }
    return kind;
  }

  String _rehydrate(String value, Map<String, String> tokenMap) {
    var result = value;
    for (final entry in tokenMap.entries) {
      result = result.replaceAll(entry.key, entry.value);
    }
    return result;
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
