import 'dart:convert';

import '../ports/vault_repository.dart';

class CardReference {
  const CardReference(this.from, this.to);
  final String from, to;
}

/// Versioned internal state in SQLCipher. Older clients preserve and ignore it;
/// existing split/bundle enum and schema remain readable without migration.
class CardReferenceStore {
  const CardReferenceStore(this.repository);
  final VaultRepository repository;
  static const key = 'workbench.references.v1';
  Future<List<CardReference>> read() async {
    final raw = await repository.readLocalValue(key);
    if (raw == null) return [];
    final data = jsonDecode(raw) as Map<String, dynamic>;
    if (data['version'] != 1) throw const FormatException('引用版本不支持');
    return [
      for (final r in (data['references'] as List))
        CardReference(r['from'] as String, r['to'] as String),
    ];
  }

  Future<void> replace(String from, List<String> targets) async {
    final owner = await repository.getCard(from);
    if (owner == null || owner.isDeleted) throw const FormatException('卡片不存在');
    final unique = targets.toSet();
    if (unique.contains(from) || unique.length > 200) {
      throw const FormatException('不能引用自身，单卡最多 200 个引用');
    }
    for (final id in unique) {
      final target = await repository.getCard(id);
      if (target == null || target.isDeleted) {
        throw const FormatException('引用目标不存在');
      }
    }
    final links = (await read()).where((r) => r.from != from).toList();
    links.addAll(unique.map((to) => CardReference(from, to)));
    await repository.writeLocalValue(
      key,
      jsonEncode({
        'version': 1,
        'references': [
          for (final r in links) {'from': r.from, 'to': r.to},
        ],
      }),
    );
  }
}
