import '../core/domain/entities.dart';

/// A renderer receives a projection, never the credential carrying its secret.
class CardSummary {
  const CardSummary({
    required this.recordType,
    required this.recordId,
    required this.title,
    required this.preview,
    required this.tags,
    required this.updatedAt,
    this.kind,
    this.status,
  });

  factory CardSummary.fromRecord(InformationCard record) => switch (record) {
    LifeCard c => CardSummary(
      recordType: 'card',
      recordId: c.id,
      title: c.title,
      preview: c.content,
      tags: List.unmodifiable(c.tags),
      updatedAt: c.updatedAt,
      kind: c.kind,
      status: c.status,
    ),
    CredentialEntry c => CardSummary(
      recordType: 'credential',
      recordId: c.id,
      title: c.title,
      preview: c.username,
      tags: List.unmodifiable(c.tags),
      updatedAt: c.updatedAt,
    ),
    _ => throw UnsupportedError('未注册的卡片类型'),
  };

  final String recordType;
  final String recordId;
  final String title;
  final String preview;
  final List<String> tags;
  final DateTime updatedAt;
  final CardKind? kind;
  final CardStatus? status;
  bool get isPassword => recordType == 'credential';
}
