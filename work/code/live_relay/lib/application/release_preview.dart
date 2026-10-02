import '../core/domain/entities.dart';

/// The existing MVP release rules, shared by policy inspection and simulation.
/// Deliberately preserves the legacy 80 UTF-16-unit excerpt and credential
/// notes/username fallback; changing these rules requires domain design.
class ReleasePreview {
  const ReleasePreview({
    required this.level,
    required this.explanation,
    this.title,
    this.body = '',
    this.secret,
  });
  final VisibilityLevel level;
  final String explanation;
  final String? title;
  final String body;
  final String? secret;

  factory ReleasePreview.card(LifeCard card, VisibilityLevel level) {
    if (level == VisibilityLevel.hidden) {
      return ReleasePreview(level: level, explanation: '对方看不到这条信息。');
    }
    return ReleasePreview(
      level: level,
      title: card.title,
      explanation: switch (level) {
        VisibilityLevel.existence => '仅显示标题及存在提示，正文不可见。',
        VisibilityLevel.summary => '显示标题和正文前 80 个字符；短正文会全部显示。这不是本人选择的摘要。',
        VisibilityLevel.original => '当前卡片规则显示完整正文；此本机预览不提供原件文件。',
        VisibilityLevel.secret => '当前卡片规则显示完整正文；没有额外的密码字段。',
        _ => '显示标题和完整正文。',
      },
      body: switch (level) {
        VisibilityLevel.existence => '存在一条此类信息，内容未授权。',
        VisibilityLevel.summary =>
          card.content.length > 80
              ? '${card.content.substring(0, 80)}…'
              : card.content,
        _ => card.content,
      },
    );
  }

  factory ReleasePreview.credential(
    CredentialEntry entry,
    VisibilityLevel level,
  ) {
    if (level == VisibilityLevel.hidden) {
      return ReleasePreview(level: level, explanation: '对方看不到这条信息。');
    }
    return ReleasePreview(
      level: level,
      title: entry.title,
      explanation: switch (level) {
        VisibilityLevel.existence => '仅显示名称及存在提示，账号和密码不可见。',
        VisibilityLevel.summary => '显示名称、账号和网址；备注和密码不可见。',
        VisibilityLevel.full => '显示名称及备注；备注为空时显示账号。密码和网址不可见。',
        VisibilityLevel.original => '当前密码条目规则显示名称、账号和密码；不提供原件文件。密码默认遮挡。',
        _ => '显示名称、账号和密码，密码默认遮挡。',
      },
      body: switch (level) {
        VisibilityLevel.existence => '存在此账户，具体信息未授权。',
        VisibilityLevel.summary => '${entry.username} ${entry.website}'.trim(),
        VisibilityLevel.full =>
          entry.notes.isEmpty ? entry.username : entry.notes,
        _ => entry.username,
      },
      secret: level.index >= VisibilityLevel.secret.index ? entry.secret : null,
    );
  }
}
