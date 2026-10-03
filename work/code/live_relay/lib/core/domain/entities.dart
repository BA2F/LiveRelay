import 'dart:math' as math;

enum CardKind {
  note,
  account,
  asset,
  debt,
  location,
  relationship,
  document,
  wish,
  familyOperation,
  bundle,
}

enum CardStatus { draft, confirmed, split, archived }

enum SourceKind {
  ownerInput,
  imported,
  ocrDerived,
  aiGenerated,
  photo,
  audio,
  video,
}

enum RelationKind { splitFrom, bundleMember }

enum LifeState { active, incapacitated, deceased }

enum VisibilityLevel { hidden, existence, summary, full, secret, original }

enum BlobMediaKind { image, audio, video, document, other }

enum SensitiveFieldKind { account, secret, money, note }

class SensitiveMark {
  const SensitiveMark({required this.lineOrder, required this.kind});

  final int lineOrder;
  final SensitiveFieldKind kind;
}

class OcrLine {
  const OcrLine({
    required this.text,
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
    required this.order,
    this.confidence,
  });

  final String text;
  final double left;
  final double top;
  final double right;
  final double bottom;
  final int order;
  final double? confidence;
}

class OcrResult {
  const OcrResult({required this.text, required this.lines});

  final String text;
  final List<OcrLine> lines;
}

class VaultBlob {
  const VaultBlob({
    required this.id,
    required this.originalName,
    required this.mediaKind,
    required this.mimeType,
    required this.relativePath,
    required this.byteLength,
    required this.sha256,
    required this.createdAt,
    this.ocrText,
    this.ocrLines = const [],
    this.sensitiveMarks = const [],
  });

  final String id;
  final String originalName;
  final BlobMediaKind mediaKind;
  final String mimeType;
  final String relativePath;
  final int byteLength;
  final String sha256;
  final DateTime createdAt;
  final String? ocrText;
  final List<OcrLine> ocrLines;
  final List<SensitiveMark> sensitiveMarks;
}

abstract interface class InformationCard {
  String get id;
  String get title;
  List<String> get tags;
  DateTime get createdAt;
  DateTime get updatedAt;
  int get revisionNumber;
  bool get isDeleted;
}

class LifeCard implements InformationCard {
  const LifeCard({
    required this.id,
    required this.title,
    required this.content,
    required this.kind,
    required this.status,
    required this.tags,
    required this.createdAt,
    required this.updatedAt,
    required this.revisionNumber,
    this.confirmedAt,
    this.deletedAt,
    this.parentCardId,
  });

  @override
  final String id;
  @override
  final String title;
  final String content;
  final CardKind kind;
  final CardStatus status;
  @override
  final List<String> tags;
  @override
  final DateTime createdAt;
  @override
  final DateTime updatedAt;
  final DateTime? confirmedAt;
  final DateTime? deletedAt;
  final String? parentCardId;
  @override
  final int revisionNumber;

  bool get isDraft => status == CardStatus.draft;
  @override
  bool get isDeleted => deletedAt != null;
}

class CardDraft {
  const CardDraft({
    required this.title,
    required this.content,
    this.kind = CardKind.note,
    this.status = CardStatus.confirmed,
    this.tags = const [],
  });

  final String title;
  final String content;
  final CardKind kind;
  final CardStatus status;
  final List<String> tags;
}

class CardRevision {
  const CardRevision({
    required this.id,
    required this.cardId,
    required this.number,
    required this.title,
    required this.content,
    required this.tags,
    required this.status,
    required this.sourceKind,
    required this.sourceLabel,
    required this.changeNote,
    required this.createdAt,
  });

  final int id;
  final String cardId;
  final int number;
  final String title;
  final String content;
  final List<String> tags;
  final CardStatus status;
  final SourceKind sourceKind;
  final String sourceLabel;
  final String changeNote;
  final DateTime createdAt;
}

class CardRelation {
  const CardRelation({
    required this.fromCardId,
    required this.toCardId,
    required this.kind,
  });

  final String fromCardId;
  final String toCardId;
  final RelationKind kind;
}

class CredentialEntry implements InformationCard {
  const CredentialEntry({
    required this.id,
    required this.title,
    required this.username,
    required this.secret,
    required this.website,
    required this.notes,
    required this.tags,
    required this.createdAt,
    required this.updatedAt,
    required this.revisionNumber,
    this.deletedAt,
  });

  @override
  final String id;
  @override
  final String title;
  final String username;
  final String secret;
  final String website;
  final String notes;
  @override
  final List<String> tags;
  @override
  final DateTime createdAt;
  @override
  final DateTime updatedAt;
  final DateTime? deletedAt;
  @override
  final int revisionNumber;

  @override
  bool get isDeleted => deletedAt != null;
}

class CredentialDraft {
  const CredentialDraft({
    required this.title,
    required this.username,
    required this.secret,
    this.website = '',
    this.notes = '',
    this.tags = const [],
  });

  final String title;
  final String username;
  final String secret;
  final String website;
  final String notes;
  final List<String> tags;
}

class CredentialRevision {
  const CredentialRevision({
    required this.id,
    required this.credentialId,
    required this.number,
    required this.title,
    required this.username,
    required this.secret,
    required this.website,
    required this.notes,
    required this.createdAt,
    required this.changeNote,
  });

  final int id;
  final String credentialId;
  final int number;
  final String title;
  final String username;
  final String secret;
  final String website;
  final String notes;
  final DateTime createdAt;
  final String changeNote;
}

class ReleasePolicy {
  const ReleasePolicy({
    required this.recordType,
    required this.recordId,
    this.recipientName = '演示执行人',
    this.incapacitated = VisibilityLevel.hidden,
    this.deceased = VisibilityLevel.hidden,
  });

  final String recordType;
  final String recordId;
  final String recipientName;
  final VisibilityLevel incapacitated;
  final VisibilityLevel deceased;

  VisibilityLevel visibleAt(LifeState state) => switch (state) {
    LifeState.active => VisibilityLevel.hidden,
    LifeState.incapacitated => incapacitated,
    LifeState.deceased => deceased,
  };
}

class LifeStateEvent {
  const LifeStateEvent({
    required this.id,
    required this.from,
    required this.to,
    required this.reason,
    required this.occurredAt,
    required this.isSimulation,
  });

  final int id;
  final LifeState from;
  final LifeState to;
  final String reason;
  final DateTime occurredAt;
  final bool isSimulation;
}

class VaultInsights {
  const VaultInsights({
    required this.totalCards,
    required this.drafts,
    required this.confirmed,
    required this.stale,
    required this.credentials,
    required this.byKind,
  });

  final int totalCards;
  final int drafts;
  final int confirmed;
  final int stale;
  final int credentials;
  final Map<CardKind, int> byKind;

  double get organizationProgress {
    if (totalCards == 0) return 0;
    return math.min(1, confirmed / totalCards);
  }
}

/// A persisted source excerpt; revisions without a source row are represented
/// by their retained revision text. Blob references never expose file paths.
class CardSource {
  const CardSource({
    required this.label,
    required this.kind,
    required this.excerpt,
    required this.createdAt,
    this.blobId,
  });
  final String label;
  final SourceKind kind;
  final String excerpt;
  final DateTime createdAt;
  final String? blobId;
}

class BackupPreview {
  const BackupPreview({
    required this.createdAt,
    required this.cards,
    required this.credentials,
    required this.originals,
    required this.recycledCards,
    required this.recycledCredentials,
    this.missingOriginals = 0,
    this.requiresReset = false,
  });
  final DateTime? createdAt;
  final int cards;
  final int credentials;
  final int originals;
  final int recycledCards;
  final int recycledCredentials;
  final int missingOriginals;
  final bool requiresReset;
}
