import '../../core/domain/entities.dart';
import 'card_edit_sessions.dart';

const windowSourcePreviewMaxBytes = 8 * 1024 * 1024;
const ownerWorkbenchTools = {
  'settings': '资料库与服务设置',
  'passwords': '密码库',
  'handoff': '身份与交接',
  'recycle': '回收站',
};

/// Explicit, bounded presentation projection. Never contains keys or credentials.
Map<String, Object?> projectWindowCard(LifeCard card, CardEditSession edit) => {
  'id': card.id,
  'title': edit.title,
  'content': edit.content,
  'tags': edit.tags,
  'kind': card.kind.name,
  'status': card.status.name,
  'revision': card.revisionNumber,
  'saveState': edit.state.name,
};

bool detachableView(String view) =>
    {
      'cards',
      'agent',
      'relations',
      'changes',
      'originals',
      'extensions',
      'speech',
    }.contains(view) ||
    RegExp(r'^(card|history|source|review)/[a-zA-Z0-9-]+(?:/[0-9]+)?$')
        .hasMatch(view) ||
    RegExp(r'^extension/[a-z][a-z0-9.-]*/[a-z][a-z0-9.-]*$').hasMatch(view);

Map<String, double>? windowBounds(dynamic value) {
  if (value is! Map) return null;
  final result = <String, double>{};
  for (final k in ['x', 'y', 'width', 'height']) {
    final v = value[k];
    if (v is! num || !v.isFinite || v.abs() > 100000) return null;
    result[k] = v.toDouble();
  }
  if (result['width']! < 400 || result['height']! < 280) return null;
  return result;
}
