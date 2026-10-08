import 'entities.dart';

class DraftRules {
  static void validateCard(CardDraft draft) {
    if (draft.title.trim().isEmpty) throw const FormatException('标题不能为空');
    if (draft.content.trim().isEmpty) throw const FormatException('内容不能为空');
  }

  static void validateCredential(CredentialDraft draft) {
    if (draft.title.trim().isEmpty) throw const FormatException('条目名称不能为空');
    if (draft.secret.isEmpty) throw const FormatException('密码不能为空');
  }

  static List<String> normalizedTags(Iterable<String> tags) =>
      List.unmodifiable(
        tags.map((tag) => tag.trim()).where((tag) => tag.isNotEmpty).toSet(),
      );
  static CardDraft freeze(CardDraft draft) => CardDraft(
    title: draft.title,
    content: draft.content,
    kind: draft.kind,
    status: draft.status,
    tags: List.unmodifiable(draft.tags),
  );
}

/// Uses facts read by the repository inside its mutation transaction.
class SplitCardPlan {
  SplitCardPlan(LifeCard? original, List<CardDraft> input)
    : parts = List.unmodifiable(input.map(DraftRules.freeze)) {
    if (parts.length < 2) throw const FormatException('拆分至少需要两张卡片');
    if (original == null || original.isDeleted) throw StateError('卡片不存在');
    for (final part in parts) {
      DraftRules.validateCard(part);
    }
    parent = CardDraft(
      title: original.title,
      content: original.content,
      kind: original.kind,
      status: CardStatus.split,
      tags: List.unmodifiable(original.tags),
    );
    parentId = original.id;
    revision = original.revisionNumber + 1;
  }
  final List<CardDraft> parts;
  late final CardDraft parent;
  late final String parentId;
  late final int revision;
  String get revisionNote => '拆分为 ${parts.length} 张独立卡片';
  String get childSourceLabel => '由「${parent.title}」拆分';
}

class BundleCardPlan {
  BundleCardPlan(String title, List<String> ids)
    : memberIds = List.unmodifiable(ids) {
    if (memberIds.length < 2) throw const FormatException('组合至少需要两张卡片');
    if (memberIds.toSet().length != memberIds.length) {
      throw const FormatException('组合卡片不能包含重复成员');
    }
    draft = CardDraft(
      title: title.trim(),
      content: '组合展示 ${memberIds.length} 张独立卡片',
      kind: CardKind.bundle,
      tags: const ['组合'],
    );
    DraftRules.validateCard(draft);
  }
  final List<String> memberIds;
  late final CardDraft draft;
  void validateMembers(Map<String, LifeCard?> facts) {
    for (final id in memberIds) {
      final card = facts[id];
      if (card == null || card.isDeleted) throw StateError('组合成员不存在');
    }
  }
}
