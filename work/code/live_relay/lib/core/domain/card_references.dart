import 'entities.dart';

class CardReference {
  const CardReference(this.from, this.to);
  final String from, to;
}

class CardReferenceRules {
  static List<String> targets(String from, List<String> input) {
    final unique = input.toSet();
    if (unique.contains(from) || unique.length > 200) {
      throw const FormatException('不能引用自身，单卡最多 200 个引用');
    }
    return List.unmodifiable(unique);
  }

  static void validate(
    String from,
    List<String> targets,
    Map<String, LifeCard?> facts,
  ) {
    final owner = facts[from];
    if (owner == null || owner.isDeleted) throw const FormatException('卡片不存在');
    for (final id in targets) {
      final target = facts[id];
      if (target == null || target.isDeleted) {
        throw const FormatException('引用目标不存在');
      }
    }
  }

  static List<CardReference> replace(
    List<CardReference> prior,
    String from,
    List<String> targets,
  ) => List.unmodifiable([
    ...prior.where((r) => r.from != from),
    ...targets.map((to) => CardReference(from, to)),
  ]);
}
