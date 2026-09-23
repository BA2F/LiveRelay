// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $SourcesTable extends Sources with TableInfo<$SourcesTable, SourceRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SourcesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
    'kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _labelMeta = const VerificationMeta('label');
  @override
  late final GeneratedColumn<String> label = GeneratedColumn<String>(
    'label',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _textExcerptMeta = const VerificationMeta(
    'textExcerpt',
  );
  @override
  late final GeneratedColumn<String> textExcerpt = GeneratedColumn<String>(
    'text_excerpt',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _blobIdMeta = const VerificationMeta('blobId');
  @override
  late final GeneratedColumn<String> blobId = GeneratedColumn<String>(
    'blob_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    kind,
    label,
    textExcerpt,
    blobId,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sources';
  @override
  VerificationContext validateIntegrity(
    Insertable<SourceRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    if (data.containsKey('label')) {
      context.handle(
        _labelMeta,
        label.isAcceptableOrUnknown(data['label']!, _labelMeta),
      );
    } else if (isInserting) {
      context.missing(_labelMeta);
    }
    if (data.containsKey('text_excerpt')) {
      context.handle(
        _textExcerptMeta,
        textExcerpt.isAcceptableOrUnknown(
          data['text_excerpt']!,
          _textExcerptMeta,
        ),
      );
    }
    if (data.containsKey('blob_id')) {
      context.handle(
        _blobIdMeta,
        blobId.isAcceptableOrUnknown(data['blob_id']!, _blobIdMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SourceRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SourceRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      )!,
      label: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}label'],
      )!,
      textExcerpt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}text_excerpt'],
      )!,
      blobId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}blob_id'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $SourcesTable createAlias(String alias) {
    return $SourcesTable(attachedDatabase, alias);
  }
}

class SourceRow extends DataClass implements Insertable<SourceRow> {
  final String id;
  final String kind;
  final String label;
  final String textExcerpt;
  final String? blobId;
  final DateTime createdAt;
  const SourceRow({
    required this.id,
    required this.kind,
    required this.label,
    required this.textExcerpt,
    this.blobId,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['kind'] = Variable<String>(kind);
    map['label'] = Variable<String>(label);
    map['text_excerpt'] = Variable<String>(textExcerpt);
    if (!nullToAbsent || blobId != null) {
      map['blob_id'] = Variable<String>(blobId);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  SourcesCompanion toCompanion(bool nullToAbsent) {
    return SourcesCompanion(
      id: Value(id),
      kind: Value(kind),
      label: Value(label),
      textExcerpt: Value(textExcerpt),
      blobId: blobId == null && nullToAbsent
          ? const Value.absent()
          : Value(blobId),
      createdAt: Value(createdAt),
    );
  }

  factory SourceRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SourceRow(
      id: serializer.fromJson<String>(json['id']),
      kind: serializer.fromJson<String>(json['kind']),
      label: serializer.fromJson<String>(json['label']),
      textExcerpt: serializer.fromJson<String>(json['textExcerpt']),
      blobId: serializer.fromJson<String?>(json['blobId']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'kind': serializer.toJson<String>(kind),
      'label': serializer.toJson<String>(label),
      'textExcerpt': serializer.toJson<String>(textExcerpt),
      'blobId': serializer.toJson<String?>(blobId),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  SourceRow copyWith({
    String? id,
    String? kind,
    String? label,
    String? textExcerpt,
    Value<String?> blobId = const Value.absent(),
    DateTime? createdAt,
  }) => SourceRow(
    id: id ?? this.id,
    kind: kind ?? this.kind,
    label: label ?? this.label,
    textExcerpt: textExcerpt ?? this.textExcerpt,
    blobId: blobId.present ? blobId.value : this.blobId,
    createdAt: createdAt ?? this.createdAt,
  );
  SourceRow copyWithCompanion(SourcesCompanion data) {
    return SourceRow(
      id: data.id.present ? data.id.value : this.id,
      kind: data.kind.present ? data.kind.value : this.kind,
      label: data.label.present ? data.label.value : this.label,
      textExcerpt: data.textExcerpt.present
          ? data.textExcerpt.value
          : this.textExcerpt,
      blobId: data.blobId.present ? data.blobId.value : this.blobId,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SourceRow(')
          ..write('id: $id, ')
          ..write('kind: $kind, ')
          ..write('label: $label, ')
          ..write('textExcerpt: $textExcerpt, ')
          ..write('blobId: $blobId, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, kind, label, textExcerpt, blobId, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SourceRow &&
          other.id == this.id &&
          other.kind == this.kind &&
          other.label == this.label &&
          other.textExcerpt == this.textExcerpt &&
          other.blobId == this.blobId &&
          other.createdAt == this.createdAt);
}

class SourcesCompanion extends UpdateCompanion<SourceRow> {
  final Value<String> id;
  final Value<String> kind;
  final Value<String> label;
  final Value<String> textExcerpt;
  final Value<String?> blobId;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const SourcesCompanion({
    this.id = const Value.absent(),
    this.kind = const Value.absent(),
    this.label = const Value.absent(),
    this.textExcerpt = const Value.absent(),
    this.blobId = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SourcesCompanion.insert({
    required String id,
    required String kind,
    required String label,
    this.textExcerpt = const Value.absent(),
    this.blobId = const Value.absent(),
    required DateTime createdAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       kind = Value(kind),
       label = Value(label),
       createdAt = Value(createdAt);
  static Insertable<SourceRow> custom({
    Expression<String>? id,
    Expression<String>? kind,
    Expression<String>? label,
    Expression<String>? textExcerpt,
    Expression<String>? blobId,
    Expression<DateTime>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (kind != null) 'kind': kind,
      if (label != null) 'label': label,
      if (textExcerpt != null) 'text_excerpt': textExcerpt,
      if (blobId != null) 'blob_id': blobId,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SourcesCompanion copyWith({
    Value<String>? id,
    Value<String>? kind,
    Value<String>? label,
    Value<String>? textExcerpt,
    Value<String?>? blobId,
    Value<DateTime>? createdAt,
    Value<int>? rowid,
  }) {
    return SourcesCompanion(
      id: id ?? this.id,
      kind: kind ?? this.kind,
      label: label ?? this.label,
      textExcerpt: textExcerpt ?? this.textExcerpt,
      blobId: blobId ?? this.blobId,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (label.present) {
      map['label'] = Variable<String>(label.value);
    }
    if (textExcerpt.present) {
      map['text_excerpt'] = Variable<String>(textExcerpt.value);
    }
    if (blobId.present) {
      map['blob_id'] = Variable<String>(blobId.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SourcesCompanion(')
          ..write('id: $id, ')
          ..write('kind: $kind, ')
          ..write('label: $label, ')
          ..write('textExcerpt: $textExcerpt, ')
          ..write('blobId: $blobId, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $EncryptedBlobsTable extends EncryptedBlobs
    with TableInfo<$EncryptedBlobsTable, EncryptedBlobRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $EncryptedBlobsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _originalNameMeta = const VerificationMeta(
    'originalName',
  );
  @override
  late final GeneratedColumn<String> originalName = GeneratedColumn<String>(
    'original_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _mediaKindMeta = const VerificationMeta(
    'mediaKind',
  );
  @override
  late final GeneratedColumn<String> mediaKind = GeneratedColumn<String>(
    'media_kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _mimeTypeMeta = const VerificationMeta(
    'mimeType',
  );
  @override
  late final GeneratedColumn<String> mimeType = GeneratedColumn<String>(
    'mime_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _relativePathMeta = const VerificationMeta(
    'relativePath',
  );
  @override
  late final GeneratedColumn<String> relativePath = GeneratedColumn<String>(
    'relative_path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _byteLengthMeta = const VerificationMeta(
    'byteLength',
  );
  @override
  late final GeneratedColumn<int> byteLength = GeneratedColumn<int>(
    'byte_length',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sha256Meta = const VerificationMeta('sha256');
  @override
  late final GeneratedColumn<String> sha256 = GeneratedColumn<String>(
    'sha256',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _ocrTextMeta = const VerificationMeta(
    'ocrText',
  );
  @override
  late final GeneratedColumn<String> ocrText = GeneratedColumn<String>(
    'ocr_text',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _ocrJsonMeta = const VerificationMeta(
    'ocrJson',
  );
  @override
  late final GeneratedColumn<String> ocrJson = GeneratedColumn<String>(
    'ocr_json',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _sensitiveJsonMeta = const VerificationMeta(
    'sensitiveJson',
  );
  @override
  late final GeneratedColumn<String> sensitiveJson = GeneratedColumn<String>(
    'sensitive_json',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    originalName,
    mediaKind,
    mimeType,
    relativePath,
    byteLength,
    sha256,
    ocrText,
    ocrJson,
    sensitiveJson,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'encrypted_blobs';
  @override
  VerificationContext validateIntegrity(
    Insertable<EncryptedBlobRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('original_name')) {
      context.handle(
        _originalNameMeta,
        originalName.isAcceptableOrUnknown(
          data['original_name']!,
          _originalNameMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_originalNameMeta);
    }
    if (data.containsKey('media_kind')) {
      context.handle(
        _mediaKindMeta,
        mediaKind.isAcceptableOrUnknown(data['media_kind']!, _mediaKindMeta),
      );
    } else if (isInserting) {
      context.missing(_mediaKindMeta);
    }
    if (data.containsKey('mime_type')) {
      context.handle(
        _mimeTypeMeta,
        mimeType.isAcceptableOrUnknown(data['mime_type']!, _mimeTypeMeta),
      );
    } else if (isInserting) {
      context.missing(_mimeTypeMeta);
    }
    if (data.containsKey('relative_path')) {
      context.handle(
        _relativePathMeta,
        relativePath.isAcceptableOrUnknown(
          data['relative_path']!,
          _relativePathMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_relativePathMeta);
    }
    if (data.containsKey('byte_length')) {
      context.handle(
        _byteLengthMeta,
        byteLength.isAcceptableOrUnknown(data['byte_length']!, _byteLengthMeta),
      );
    } else if (isInserting) {
      context.missing(_byteLengthMeta);
    }
    if (data.containsKey('sha256')) {
      context.handle(
        _sha256Meta,
        sha256.isAcceptableOrUnknown(data['sha256']!, _sha256Meta),
      );
    } else if (isInserting) {
      context.missing(_sha256Meta);
    }
    if (data.containsKey('ocr_text')) {
      context.handle(
        _ocrTextMeta,
        ocrText.isAcceptableOrUnknown(data['ocr_text']!, _ocrTextMeta),
      );
    }
    if (data.containsKey('ocr_json')) {
      context.handle(
        _ocrJsonMeta,
        ocrJson.isAcceptableOrUnknown(data['ocr_json']!, _ocrJsonMeta),
      );
    }
    if (data.containsKey('sensitive_json')) {
      context.handle(
        _sensitiveJsonMeta,
        sensitiveJson.isAcceptableOrUnknown(
          data['sensitive_json']!,
          _sensitiveJsonMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  EncryptedBlobRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return EncryptedBlobRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      originalName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}original_name'],
      )!,
      mediaKind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}media_kind'],
      )!,
      mimeType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}mime_type'],
      )!,
      relativePath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}relative_path'],
      )!,
      byteLength: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}byte_length'],
      )!,
      sha256: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sha256'],
      )!,
      ocrText: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}ocr_text'],
      ),
      ocrJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}ocr_json'],
      ),
      sensitiveJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sensitive_json'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $EncryptedBlobsTable createAlias(String alias) {
    return $EncryptedBlobsTable(attachedDatabase, alias);
  }
}

class EncryptedBlobRow extends DataClass
    implements Insertable<EncryptedBlobRow> {
  final String id;
  final String originalName;
  final String mediaKind;
  final String mimeType;
  final String relativePath;
  final int byteLength;
  final String sha256;
  final String? ocrText;
  final String? ocrJson;
  final String? sensitiveJson;
  final DateTime createdAt;
  const EncryptedBlobRow({
    required this.id,
    required this.originalName,
    required this.mediaKind,
    required this.mimeType,
    required this.relativePath,
    required this.byteLength,
    required this.sha256,
    this.ocrText,
    this.ocrJson,
    this.sensitiveJson,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['original_name'] = Variable<String>(originalName);
    map['media_kind'] = Variable<String>(mediaKind);
    map['mime_type'] = Variable<String>(mimeType);
    map['relative_path'] = Variable<String>(relativePath);
    map['byte_length'] = Variable<int>(byteLength);
    map['sha256'] = Variable<String>(sha256);
    if (!nullToAbsent || ocrText != null) {
      map['ocr_text'] = Variable<String>(ocrText);
    }
    if (!nullToAbsent || ocrJson != null) {
      map['ocr_json'] = Variable<String>(ocrJson);
    }
    if (!nullToAbsent || sensitiveJson != null) {
      map['sensitive_json'] = Variable<String>(sensitiveJson);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  EncryptedBlobsCompanion toCompanion(bool nullToAbsent) {
    return EncryptedBlobsCompanion(
      id: Value(id),
      originalName: Value(originalName),
      mediaKind: Value(mediaKind),
      mimeType: Value(mimeType),
      relativePath: Value(relativePath),
      byteLength: Value(byteLength),
      sha256: Value(sha256),
      ocrText: ocrText == null && nullToAbsent
          ? const Value.absent()
          : Value(ocrText),
      ocrJson: ocrJson == null && nullToAbsent
          ? const Value.absent()
          : Value(ocrJson),
      sensitiveJson: sensitiveJson == null && nullToAbsent
          ? const Value.absent()
          : Value(sensitiveJson),
      createdAt: Value(createdAt),
    );
  }

  factory EncryptedBlobRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return EncryptedBlobRow(
      id: serializer.fromJson<String>(json['id']),
      originalName: serializer.fromJson<String>(json['originalName']),
      mediaKind: serializer.fromJson<String>(json['mediaKind']),
      mimeType: serializer.fromJson<String>(json['mimeType']),
      relativePath: serializer.fromJson<String>(json['relativePath']),
      byteLength: serializer.fromJson<int>(json['byteLength']),
      sha256: serializer.fromJson<String>(json['sha256']),
      ocrText: serializer.fromJson<String?>(json['ocrText']),
      ocrJson: serializer.fromJson<String?>(json['ocrJson']),
      sensitiveJson: serializer.fromJson<String?>(json['sensitiveJson']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'originalName': serializer.toJson<String>(originalName),
      'mediaKind': serializer.toJson<String>(mediaKind),
      'mimeType': serializer.toJson<String>(mimeType),
      'relativePath': serializer.toJson<String>(relativePath),
      'byteLength': serializer.toJson<int>(byteLength),
      'sha256': serializer.toJson<String>(sha256),
      'ocrText': serializer.toJson<String?>(ocrText),
      'ocrJson': serializer.toJson<String?>(ocrJson),
      'sensitiveJson': serializer.toJson<String?>(sensitiveJson),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  EncryptedBlobRow copyWith({
    String? id,
    String? originalName,
    String? mediaKind,
    String? mimeType,
    String? relativePath,
    int? byteLength,
    String? sha256,
    Value<String?> ocrText = const Value.absent(),
    Value<String?> ocrJson = const Value.absent(),
    Value<String?> sensitiveJson = const Value.absent(),
    DateTime? createdAt,
  }) => EncryptedBlobRow(
    id: id ?? this.id,
    originalName: originalName ?? this.originalName,
    mediaKind: mediaKind ?? this.mediaKind,
    mimeType: mimeType ?? this.mimeType,
    relativePath: relativePath ?? this.relativePath,
    byteLength: byteLength ?? this.byteLength,
    sha256: sha256 ?? this.sha256,
    ocrText: ocrText.present ? ocrText.value : this.ocrText,
    ocrJson: ocrJson.present ? ocrJson.value : this.ocrJson,
    sensitiveJson: sensitiveJson.present
        ? sensitiveJson.value
        : this.sensitiveJson,
    createdAt: createdAt ?? this.createdAt,
  );
  EncryptedBlobRow copyWithCompanion(EncryptedBlobsCompanion data) {
    return EncryptedBlobRow(
      id: data.id.present ? data.id.value : this.id,
      originalName: data.originalName.present
          ? data.originalName.value
          : this.originalName,
      mediaKind: data.mediaKind.present ? data.mediaKind.value : this.mediaKind,
      mimeType: data.mimeType.present ? data.mimeType.value : this.mimeType,
      relativePath: data.relativePath.present
          ? data.relativePath.value
          : this.relativePath,
      byteLength: data.byteLength.present
          ? data.byteLength.value
          : this.byteLength,
      sha256: data.sha256.present ? data.sha256.value : this.sha256,
      ocrText: data.ocrText.present ? data.ocrText.value : this.ocrText,
      ocrJson: data.ocrJson.present ? data.ocrJson.value : this.ocrJson,
      sensitiveJson: data.sensitiveJson.present
          ? data.sensitiveJson.value
          : this.sensitiveJson,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('EncryptedBlobRow(')
          ..write('id: $id, ')
          ..write('originalName: $originalName, ')
          ..write('mediaKind: $mediaKind, ')
          ..write('mimeType: $mimeType, ')
          ..write('relativePath: $relativePath, ')
          ..write('byteLength: $byteLength, ')
          ..write('sha256: $sha256, ')
          ..write('ocrText: $ocrText, ')
          ..write('ocrJson: $ocrJson, ')
          ..write('sensitiveJson: $sensitiveJson, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    originalName,
    mediaKind,
    mimeType,
    relativePath,
    byteLength,
    sha256,
    ocrText,
    ocrJson,
    sensitiveJson,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is EncryptedBlobRow &&
          other.id == this.id &&
          other.originalName == this.originalName &&
          other.mediaKind == this.mediaKind &&
          other.mimeType == this.mimeType &&
          other.relativePath == this.relativePath &&
          other.byteLength == this.byteLength &&
          other.sha256 == this.sha256 &&
          other.ocrText == this.ocrText &&
          other.ocrJson == this.ocrJson &&
          other.sensitiveJson == this.sensitiveJson &&
          other.createdAt == this.createdAt);
}

class EncryptedBlobsCompanion extends UpdateCompanion<EncryptedBlobRow> {
  final Value<String> id;
  final Value<String> originalName;
  final Value<String> mediaKind;
  final Value<String> mimeType;
  final Value<String> relativePath;
  final Value<int> byteLength;
  final Value<String> sha256;
  final Value<String?> ocrText;
  final Value<String?> ocrJson;
  final Value<String?> sensitiveJson;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const EncryptedBlobsCompanion({
    this.id = const Value.absent(),
    this.originalName = const Value.absent(),
    this.mediaKind = const Value.absent(),
    this.mimeType = const Value.absent(),
    this.relativePath = const Value.absent(),
    this.byteLength = const Value.absent(),
    this.sha256 = const Value.absent(),
    this.ocrText = const Value.absent(),
    this.ocrJson = const Value.absent(),
    this.sensitiveJson = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  EncryptedBlobsCompanion.insert({
    required String id,
    required String originalName,
    required String mediaKind,
    required String mimeType,
    required String relativePath,
    required int byteLength,
    required String sha256,
    this.ocrText = const Value.absent(),
    this.ocrJson = const Value.absent(),
    this.sensitiveJson = const Value.absent(),
    required DateTime createdAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       originalName = Value(originalName),
       mediaKind = Value(mediaKind),
       mimeType = Value(mimeType),
       relativePath = Value(relativePath),
       byteLength = Value(byteLength),
       sha256 = Value(sha256),
       createdAt = Value(createdAt);
  static Insertable<EncryptedBlobRow> custom({
    Expression<String>? id,
    Expression<String>? originalName,
    Expression<String>? mediaKind,
    Expression<String>? mimeType,
    Expression<String>? relativePath,
    Expression<int>? byteLength,
    Expression<String>? sha256,
    Expression<String>? ocrText,
    Expression<String>? ocrJson,
    Expression<String>? sensitiveJson,
    Expression<DateTime>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (originalName != null) 'original_name': originalName,
      if (mediaKind != null) 'media_kind': mediaKind,
      if (mimeType != null) 'mime_type': mimeType,
      if (relativePath != null) 'relative_path': relativePath,
      if (byteLength != null) 'byte_length': byteLength,
      if (sha256 != null) 'sha256': sha256,
      if (ocrText != null) 'ocr_text': ocrText,
      if (ocrJson != null) 'ocr_json': ocrJson,
      if (sensitiveJson != null) 'sensitive_json': sensitiveJson,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  EncryptedBlobsCompanion copyWith({
    Value<String>? id,
    Value<String>? originalName,
    Value<String>? mediaKind,
    Value<String>? mimeType,
    Value<String>? relativePath,
    Value<int>? byteLength,
    Value<String>? sha256,
    Value<String?>? ocrText,
    Value<String?>? ocrJson,
    Value<String?>? sensitiveJson,
    Value<DateTime>? createdAt,
    Value<int>? rowid,
  }) {
    return EncryptedBlobsCompanion(
      id: id ?? this.id,
      originalName: originalName ?? this.originalName,
      mediaKind: mediaKind ?? this.mediaKind,
      mimeType: mimeType ?? this.mimeType,
      relativePath: relativePath ?? this.relativePath,
      byteLength: byteLength ?? this.byteLength,
      sha256: sha256 ?? this.sha256,
      ocrText: ocrText ?? this.ocrText,
      ocrJson: ocrJson ?? this.ocrJson,
      sensitiveJson: sensitiveJson ?? this.sensitiveJson,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (originalName.present) {
      map['original_name'] = Variable<String>(originalName.value);
    }
    if (mediaKind.present) {
      map['media_kind'] = Variable<String>(mediaKind.value);
    }
    if (mimeType.present) {
      map['mime_type'] = Variable<String>(mimeType.value);
    }
    if (relativePath.present) {
      map['relative_path'] = Variable<String>(relativePath.value);
    }
    if (byteLength.present) {
      map['byte_length'] = Variable<int>(byteLength.value);
    }
    if (sha256.present) {
      map['sha256'] = Variable<String>(sha256.value);
    }
    if (ocrText.present) {
      map['ocr_text'] = Variable<String>(ocrText.value);
    }
    if (ocrJson.present) {
      map['ocr_json'] = Variable<String>(ocrJson.value);
    }
    if (sensitiveJson.present) {
      map['sensitive_json'] = Variable<String>(sensitiveJson.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('EncryptedBlobsCompanion(')
          ..write('id: $id, ')
          ..write('originalName: $originalName, ')
          ..write('mediaKind: $mediaKind, ')
          ..write('mimeType: $mimeType, ')
          ..write('relativePath: $relativePath, ')
          ..write('byteLength: $byteLength, ')
          ..write('sha256: $sha256, ')
          ..write('ocrText: $ocrText, ')
          ..write('ocrJson: $ocrJson, ')
          ..write('sensitiveJson: $sensitiveJson, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CardsTable extends Cards with TableInfo<$CardsTable, CardRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CardsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _contentMeta = const VerificationMeta(
    'content',
  );
  @override
  late final GeneratedColumn<String> content = GeneratedColumn<String>(
    'content',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
    'kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _tagsJsonMeta = const VerificationMeta(
    'tagsJson',
  );
  @override
  late final GeneratedColumn<String> tagsJson = GeneratedColumn<String>(
    'tags_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('[]'),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _confirmedAtMeta = const VerificationMeta(
    'confirmedAt',
  );
  @override
  late final GeneratedColumn<DateTime> confirmedAt = GeneratedColumn<DateTime>(
    'confirmed_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<DateTime> deletedAt = GeneratedColumn<DateTime>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _parentCardIdMeta = const VerificationMeta(
    'parentCardId',
  );
  @override
  late final GeneratedColumn<String> parentCardId = GeneratedColumn<String>(
    'parent_card_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _revisionNumberMeta = const VerificationMeta(
    'revisionNumber',
  );
  @override
  late final GeneratedColumn<int> revisionNumber = GeneratedColumn<int>(
    'revision_number',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    title,
    content,
    kind,
    status,
    tagsJson,
    createdAt,
    updatedAt,
    confirmedAt,
    deletedAt,
    parentCardId,
    revisionNumber,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'life_cards';
  @override
  VerificationContext validateIntegrity(
    Insertable<CardRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('content')) {
      context.handle(
        _contentMeta,
        content.isAcceptableOrUnknown(data['content']!, _contentMeta),
      );
    } else if (isInserting) {
      context.missing(_contentMeta);
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    } else if (isInserting) {
      context.missing(_statusMeta);
    }
    if (data.containsKey('tags_json')) {
      context.handle(
        _tagsJsonMeta,
        tagsJson.isAcceptableOrUnknown(data['tags_json']!, _tagsJsonMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('confirmed_at')) {
      context.handle(
        _confirmedAtMeta,
        confirmedAt.isAcceptableOrUnknown(
          data['confirmed_at']!,
          _confirmedAtMeta,
        ),
      );
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    if (data.containsKey('parent_card_id')) {
      context.handle(
        _parentCardIdMeta,
        parentCardId.isAcceptableOrUnknown(
          data['parent_card_id']!,
          _parentCardIdMeta,
        ),
      );
    }
    if (data.containsKey('revision_number')) {
      context.handle(
        _revisionNumberMeta,
        revisionNumber.isAcceptableOrUnknown(
          data['revision_number']!,
          _revisionNumberMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  CardRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CardRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      content: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}content'],
      )!,
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      )!,
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      tagsJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}tags_json'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      confirmedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}confirmed_at'],
      ),
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}deleted_at'],
      ),
      parentCardId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}parent_card_id'],
      ),
      revisionNumber: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}revision_number'],
      )!,
    );
  }

  @override
  $CardsTable createAlias(String alias) {
    return $CardsTable(attachedDatabase, alias);
  }
}

class CardRow extends DataClass implements Insertable<CardRow> {
  final String id;
  final String title;
  final String content;
  final String kind;
  final String status;
  final String tagsJson;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? confirmedAt;
  final DateTime? deletedAt;
  final String? parentCardId;
  final int revisionNumber;
  const CardRow({
    required this.id,
    required this.title,
    required this.content,
    required this.kind,
    required this.status,
    required this.tagsJson,
    required this.createdAt,
    required this.updatedAt,
    this.confirmedAt,
    this.deletedAt,
    this.parentCardId,
    required this.revisionNumber,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['title'] = Variable<String>(title);
    map['content'] = Variable<String>(content);
    map['kind'] = Variable<String>(kind);
    map['status'] = Variable<String>(status);
    map['tags_json'] = Variable<String>(tagsJson);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    if (!nullToAbsent || confirmedAt != null) {
      map['confirmed_at'] = Variable<DateTime>(confirmedAt);
    }
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<DateTime>(deletedAt);
    }
    if (!nullToAbsent || parentCardId != null) {
      map['parent_card_id'] = Variable<String>(parentCardId);
    }
    map['revision_number'] = Variable<int>(revisionNumber);
    return map;
  }

  CardsCompanion toCompanion(bool nullToAbsent) {
    return CardsCompanion(
      id: Value(id),
      title: Value(title),
      content: Value(content),
      kind: Value(kind),
      status: Value(status),
      tagsJson: Value(tagsJson),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      confirmedAt: confirmedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(confirmedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
      parentCardId: parentCardId == null && nullToAbsent
          ? const Value.absent()
          : Value(parentCardId),
      revisionNumber: Value(revisionNumber),
    );
  }

  factory CardRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CardRow(
      id: serializer.fromJson<String>(json['id']),
      title: serializer.fromJson<String>(json['title']),
      content: serializer.fromJson<String>(json['content']),
      kind: serializer.fromJson<String>(json['kind']),
      status: serializer.fromJson<String>(json['status']),
      tagsJson: serializer.fromJson<String>(json['tagsJson']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      confirmedAt: serializer.fromJson<DateTime?>(json['confirmedAt']),
      deletedAt: serializer.fromJson<DateTime?>(json['deletedAt']),
      parentCardId: serializer.fromJson<String?>(json['parentCardId']),
      revisionNumber: serializer.fromJson<int>(json['revisionNumber']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'title': serializer.toJson<String>(title),
      'content': serializer.toJson<String>(content),
      'kind': serializer.toJson<String>(kind),
      'status': serializer.toJson<String>(status),
      'tagsJson': serializer.toJson<String>(tagsJson),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'confirmedAt': serializer.toJson<DateTime?>(confirmedAt),
      'deletedAt': serializer.toJson<DateTime?>(deletedAt),
      'parentCardId': serializer.toJson<String?>(parentCardId),
      'revisionNumber': serializer.toJson<int>(revisionNumber),
    };
  }

  CardRow copyWith({
    String? id,
    String? title,
    String? content,
    String? kind,
    String? status,
    String? tagsJson,
    DateTime? createdAt,
    DateTime? updatedAt,
    Value<DateTime?> confirmedAt = const Value.absent(),
    Value<DateTime?> deletedAt = const Value.absent(),
    Value<String?> parentCardId = const Value.absent(),
    int? revisionNumber,
  }) => CardRow(
    id: id ?? this.id,
    title: title ?? this.title,
    content: content ?? this.content,
    kind: kind ?? this.kind,
    status: status ?? this.status,
    tagsJson: tagsJson ?? this.tagsJson,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    confirmedAt: confirmedAt.present ? confirmedAt.value : this.confirmedAt,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
    parentCardId: parentCardId.present ? parentCardId.value : this.parentCardId,
    revisionNumber: revisionNumber ?? this.revisionNumber,
  );
  CardRow copyWithCompanion(CardsCompanion data) {
    return CardRow(
      id: data.id.present ? data.id.value : this.id,
      title: data.title.present ? data.title.value : this.title,
      content: data.content.present ? data.content.value : this.content,
      kind: data.kind.present ? data.kind.value : this.kind,
      status: data.status.present ? data.status.value : this.status,
      tagsJson: data.tagsJson.present ? data.tagsJson.value : this.tagsJson,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      confirmedAt: data.confirmedAt.present
          ? data.confirmedAt.value
          : this.confirmedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
      parentCardId: data.parentCardId.present
          ? data.parentCardId.value
          : this.parentCardId,
      revisionNumber: data.revisionNumber.present
          ? data.revisionNumber.value
          : this.revisionNumber,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CardRow(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('content: $content, ')
          ..write('kind: $kind, ')
          ..write('status: $status, ')
          ..write('tagsJson: $tagsJson, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('confirmedAt: $confirmedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('parentCardId: $parentCardId, ')
          ..write('revisionNumber: $revisionNumber')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    title,
    content,
    kind,
    status,
    tagsJson,
    createdAt,
    updatedAt,
    confirmedAt,
    deletedAt,
    parentCardId,
    revisionNumber,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CardRow &&
          other.id == this.id &&
          other.title == this.title &&
          other.content == this.content &&
          other.kind == this.kind &&
          other.status == this.status &&
          other.tagsJson == this.tagsJson &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.confirmedAt == this.confirmedAt &&
          other.deletedAt == this.deletedAt &&
          other.parentCardId == this.parentCardId &&
          other.revisionNumber == this.revisionNumber);
}

class CardsCompanion extends UpdateCompanion<CardRow> {
  final Value<String> id;
  final Value<String> title;
  final Value<String> content;
  final Value<String> kind;
  final Value<String> status;
  final Value<String> tagsJson;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<DateTime?> confirmedAt;
  final Value<DateTime?> deletedAt;
  final Value<String?> parentCardId;
  final Value<int> revisionNumber;
  final Value<int> rowid;
  const CardsCompanion({
    this.id = const Value.absent(),
    this.title = const Value.absent(),
    this.content = const Value.absent(),
    this.kind = const Value.absent(),
    this.status = const Value.absent(),
    this.tagsJson = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.confirmedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.parentCardId = const Value.absent(),
    this.revisionNumber = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CardsCompanion.insert({
    required String id,
    required String title,
    required String content,
    required String kind,
    required String status,
    this.tagsJson = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
    this.confirmedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.parentCardId = const Value.absent(),
    this.revisionNumber = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       title = Value(title),
       content = Value(content),
       kind = Value(kind),
       status = Value(status),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<CardRow> custom({
    Expression<String>? id,
    Expression<String>? title,
    Expression<String>? content,
    Expression<String>? kind,
    Expression<String>? status,
    Expression<String>? tagsJson,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<DateTime>? confirmedAt,
    Expression<DateTime>? deletedAt,
    Expression<String>? parentCardId,
    Expression<int>? revisionNumber,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (title != null) 'title': title,
      if (content != null) 'content': content,
      if (kind != null) 'kind': kind,
      if (status != null) 'status': status,
      if (tagsJson != null) 'tags_json': tagsJson,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (confirmedAt != null) 'confirmed_at': confirmedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (parentCardId != null) 'parent_card_id': parentCardId,
      if (revisionNumber != null) 'revision_number': revisionNumber,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CardsCompanion copyWith({
    Value<String>? id,
    Value<String>? title,
    Value<String>? content,
    Value<String>? kind,
    Value<String>? status,
    Value<String>? tagsJson,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<DateTime?>? confirmedAt,
    Value<DateTime?>? deletedAt,
    Value<String?>? parentCardId,
    Value<int>? revisionNumber,
    Value<int>? rowid,
  }) {
    return CardsCompanion(
      id: id ?? this.id,
      title: title ?? this.title,
      content: content ?? this.content,
      kind: kind ?? this.kind,
      status: status ?? this.status,
      tagsJson: tagsJson ?? this.tagsJson,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      confirmedAt: confirmedAt ?? this.confirmedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      parentCardId: parentCardId ?? this.parentCardId,
      revisionNumber: revisionNumber ?? this.revisionNumber,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (content.present) {
      map['content'] = Variable<String>(content.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (tagsJson.present) {
      map['tags_json'] = Variable<String>(tagsJson.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (confirmedAt.present) {
      map['confirmed_at'] = Variable<DateTime>(confirmedAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<DateTime>(deletedAt.value);
    }
    if (parentCardId.present) {
      map['parent_card_id'] = Variable<String>(parentCardId.value);
    }
    if (revisionNumber.present) {
      map['revision_number'] = Variable<int>(revisionNumber.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CardsCompanion(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('content: $content, ')
          ..write('kind: $kind, ')
          ..write('status: $status, ')
          ..write('tagsJson: $tagsJson, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('confirmedAt: $confirmedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('parentCardId: $parentCardId, ')
          ..write('revisionNumber: $revisionNumber, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CardRevisionsTable extends CardRevisions
    with TableInfo<$CardRevisionsTable, CardRevisionRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CardRevisionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _cardIdMeta = const VerificationMeta('cardId');
  @override
  late final GeneratedColumn<String> cardId = GeneratedColumn<String>(
    'card_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL REFERENCES life_cards(id) ON DELETE CASCADE',
  );
  static const VerificationMeta _numberMeta = const VerificationMeta('number');
  @override
  late final GeneratedColumn<int> number = GeneratedColumn<int>(
    'number',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _contentMeta = const VerificationMeta(
    'content',
  );
  @override
  late final GeneratedColumn<String> content = GeneratedColumn<String>(
    'content',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _tagsJsonMeta = const VerificationMeta(
    'tagsJson',
  );
  @override
  late final GeneratedColumn<String> tagsJson = GeneratedColumn<String>(
    'tags_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('[]'),
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sourceKindMeta = const VerificationMeta(
    'sourceKind',
  );
  @override
  late final GeneratedColumn<String> sourceKind = GeneratedColumn<String>(
    'source_kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sourceLabelMeta = const VerificationMeta(
    'sourceLabel',
  );
  @override
  late final GeneratedColumn<String> sourceLabel = GeneratedColumn<String>(
    'source_label',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sourceIdMeta = const VerificationMeta(
    'sourceId',
  );
  @override
  late final GeneratedColumn<String> sourceId = GeneratedColumn<String>(
    'source_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _changeNoteMeta = const VerificationMeta(
    'changeNote',
  );
  @override
  late final GeneratedColumn<String> changeNote = GeneratedColumn<String>(
    'change_note',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    cardId,
    number,
    title,
    content,
    tagsJson,
    status,
    sourceKind,
    sourceLabel,
    sourceId,
    changeNote,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'card_revisions';
  @override
  VerificationContext validateIntegrity(
    Insertable<CardRevisionRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('card_id')) {
      context.handle(
        _cardIdMeta,
        cardId.isAcceptableOrUnknown(data['card_id']!, _cardIdMeta),
      );
    } else if (isInserting) {
      context.missing(_cardIdMeta);
    }
    if (data.containsKey('number')) {
      context.handle(
        _numberMeta,
        number.isAcceptableOrUnknown(data['number']!, _numberMeta),
      );
    } else if (isInserting) {
      context.missing(_numberMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('content')) {
      context.handle(
        _contentMeta,
        content.isAcceptableOrUnknown(data['content']!, _contentMeta),
      );
    } else if (isInserting) {
      context.missing(_contentMeta);
    }
    if (data.containsKey('tags_json')) {
      context.handle(
        _tagsJsonMeta,
        tagsJson.isAcceptableOrUnknown(data['tags_json']!, _tagsJsonMeta),
      );
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    } else if (isInserting) {
      context.missing(_statusMeta);
    }
    if (data.containsKey('source_kind')) {
      context.handle(
        _sourceKindMeta,
        sourceKind.isAcceptableOrUnknown(data['source_kind']!, _sourceKindMeta),
      );
    } else if (isInserting) {
      context.missing(_sourceKindMeta);
    }
    if (data.containsKey('source_label')) {
      context.handle(
        _sourceLabelMeta,
        sourceLabel.isAcceptableOrUnknown(
          data['source_label']!,
          _sourceLabelMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_sourceLabelMeta);
    }
    if (data.containsKey('source_id')) {
      context.handle(
        _sourceIdMeta,
        sourceId.isAcceptableOrUnknown(data['source_id']!, _sourceIdMeta),
      );
    }
    if (data.containsKey('change_note')) {
      context.handle(
        _changeNoteMeta,
        changeNote.isAcceptableOrUnknown(data['change_note']!, _changeNoteMeta),
      );
    } else if (isInserting) {
      context.missing(_changeNoteMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  CardRevisionRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CardRevisionRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      cardId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}card_id'],
      )!,
      number: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}number'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      content: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}content'],
      )!,
      tagsJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}tags_json'],
      )!,
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      sourceKind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_kind'],
      )!,
      sourceLabel: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_label'],
      )!,
      sourceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_id'],
      ),
      changeNote: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}change_note'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $CardRevisionsTable createAlias(String alias) {
    return $CardRevisionsTable(attachedDatabase, alias);
  }
}

class CardRevisionRow extends DataClass implements Insertable<CardRevisionRow> {
  final int id;
  final String cardId;
  final int number;
  final String title;
  final String content;
  final String tagsJson;
  final String status;
  final String sourceKind;
  final String sourceLabel;
  final String? sourceId;
  final String changeNote;
  final DateTime createdAt;
  const CardRevisionRow({
    required this.id,
    required this.cardId,
    required this.number,
    required this.title,
    required this.content,
    required this.tagsJson,
    required this.status,
    required this.sourceKind,
    required this.sourceLabel,
    this.sourceId,
    required this.changeNote,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['card_id'] = Variable<String>(cardId);
    map['number'] = Variable<int>(number);
    map['title'] = Variable<String>(title);
    map['content'] = Variable<String>(content);
    map['tags_json'] = Variable<String>(tagsJson);
    map['status'] = Variable<String>(status);
    map['source_kind'] = Variable<String>(sourceKind);
    map['source_label'] = Variable<String>(sourceLabel);
    if (!nullToAbsent || sourceId != null) {
      map['source_id'] = Variable<String>(sourceId);
    }
    map['change_note'] = Variable<String>(changeNote);
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  CardRevisionsCompanion toCompanion(bool nullToAbsent) {
    return CardRevisionsCompanion(
      id: Value(id),
      cardId: Value(cardId),
      number: Value(number),
      title: Value(title),
      content: Value(content),
      tagsJson: Value(tagsJson),
      status: Value(status),
      sourceKind: Value(sourceKind),
      sourceLabel: Value(sourceLabel),
      sourceId: sourceId == null && nullToAbsent
          ? const Value.absent()
          : Value(sourceId),
      changeNote: Value(changeNote),
      createdAt: Value(createdAt),
    );
  }

  factory CardRevisionRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CardRevisionRow(
      id: serializer.fromJson<int>(json['id']),
      cardId: serializer.fromJson<String>(json['cardId']),
      number: serializer.fromJson<int>(json['number']),
      title: serializer.fromJson<String>(json['title']),
      content: serializer.fromJson<String>(json['content']),
      tagsJson: serializer.fromJson<String>(json['tagsJson']),
      status: serializer.fromJson<String>(json['status']),
      sourceKind: serializer.fromJson<String>(json['sourceKind']),
      sourceLabel: serializer.fromJson<String>(json['sourceLabel']),
      sourceId: serializer.fromJson<String?>(json['sourceId']),
      changeNote: serializer.fromJson<String>(json['changeNote']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'cardId': serializer.toJson<String>(cardId),
      'number': serializer.toJson<int>(number),
      'title': serializer.toJson<String>(title),
      'content': serializer.toJson<String>(content),
      'tagsJson': serializer.toJson<String>(tagsJson),
      'status': serializer.toJson<String>(status),
      'sourceKind': serializer.toJson<String>(sourceKind),
      'sourceLabel': serializer.toJson<String>(sourceLabel),
      'sourceId': serializer.toJson<String?>(sourceId),
      'changeNote': serializer.toJson<String>(changeNote),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  CardRevisionRow copyWith({
    int? id,
    String? cardId,
    int? number,
    String? title,
    String? content,
    String? tagsJson,
    String? status,
    String? sourceKind,
    String? sourceLabel,
    Value<String?> sourceId = const Value.absent(),
    String? changeNote,
    DateTime? createdAt,
  }) => CardRevisionRow(
    id: id ?? this.id,
    cardId: cardId ?? this.cardId,
    number: number ?? this.number,
    title: title ?? this.title,
    content: content ?? this.content,
    tagsJson: tagsJson ?? this.tagsJson,
    status: status ?? this.status,
    sourceKind: sourceKind ?? this.sourceKind,
    sourceLabel: sourceLabel ?? this.sourceLabel,
    sourceId: sourceId.present ? sourceId.value : this.sourceId,
    changeNote: changeNote ?? this.changeNote,
    createdAt: createdAt ?? this.createdAt,
  );
  CardRevisionRow copyWithCompanion(CardRevisionsCompanion data) {
    return CardRevisionRow(
      id: data.id.present ? data.id.value : this.id,
      cardId: data.cardId.present ? data.cardId.value : this.cardId,
      number: data.number.present ? data.number.value : this.number,
      title: data.title.present ? data.title.value : this.title,
      content: data.content.present ? data.content.value : this.content,
      tagsJson: data.tagsJson.present ? data.tagsJson.value : this.tagsJson,
      status: data.status.present ? data.status.value : this.status,
      sourceKind: data.sourceKind.present
          ? data.sourceKind.value
          : this.sourceKind,
      sourceLabel: data.sourceLabel.present
          ? data.sourceLabel.value
          : this.sourceLabel,
      sourceId: data.sourceId.present ? data.sourceId.value : this.sourceId,
      changeNote: data.changeNote.present
          ? data.changeNote.value
          : this.changeNote,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CardRevisionRow(')
          ..write('id: $id, ')
          ..write('cardId: $cardId, ')
          ..write('number: $number, ')
          ..write('title: $title, ')
          ..write('content: $content, ')
          ..write('tagsJson: $tagsJson, ')
          ..write('status: $status, ')
          ..write('sourceKind: $sourceKind, ')
          ..write('sourceLabel: $sourceLabel, ')
          ..write('sourceId: $sourceId, ')
          ..write('changeNote: $changeNote, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    cardId,
    number,
    title,
    content,
    tagsJson,
    status,
    sourceKind,
    sourceLabel,
    sourceId,
    changeNote,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CardRevisionRow &&
          other.id == this.id &&
          other.cardId == this.cardId &&
          other.number == this.number &&
          other.title == this.title &&
          other.content == this.content &&
          other.tagsJson == this.tagsJson &&
          other.status == this.status &&
          other.sourceKind == this.sourceKind &&
          other.sourceLabel == this.sourceLabel &&
          other.sourceId == this.sourceId &&
          other.changeNote == this.changeNote &&
          other.createdAt == this.createdAt);
}

class CardRevisionsCompanion extends UpdateCompanion<CardRevisionRow> {
  final Value<int> id;
  final Value<String> cardId;
  final Value<int> number;
  final Value<String> title;
  final Value<String> content;
  final Value<String> tagsJson;
  final Value<String> status;
  final Value<String> sourceKind;
  final Value<String> sourceLabel;
  final Value<String?> sourceId;
  final Value<String> changeNote;
  final Value<DateTime> createdAt;
  const CardRevisionsCompanion({
    this.id = const Value.absent(),
    this.cardId = const Value.absent(),
    this.number = const Value.absent(),
    this.title = const Value.absent(),
    this.content = const Value.absent(),
    this.tagsJson = const Value.absent(),
    this.status = const Value.absent(),
    this.sourceKind = const Value.absent(),
    this.sourceLabel = const Value.absent(),
    this.sourceId = const Value.absent(),
    this.changeNote = const Value.absent(),
    this.createdAt = const Value.absent(),
  });
  CardRevisionsCompanion.insert({
    this.id = const Value.absent(),
    required String cardId,
    required int number,
    required String title,
    required String content,
    this.tagsJson = const Value.absent(),
    required String status,
    required String sourceKind,
    required String sourceLabel,
    this.sourceId = const Value.absent(),
    required String changeNote,
    required DateTime createdAt,
  }) : cardId = Value(cardId),
       number = Value(number),
       title = Value(title),
       content = Value(content),
       status = Value(status),
       sourceKind = Value(sourceKind),
       sourceLabel = Value(sourceLabel),
       changeNote = Value(changeNote),
       createdAt = Value(createdAt);
  static Insertable<CardRevisionRow> custom({
    Expression<int>? id,
    Expression<String>? cardId,
    Expression<int>? number,
    Expression<String>? title,
    Expression<String>? content,
    Expression<String>? tagsJson,
    Expression<String>? status,
    Expression<String>? sourceKind,
    Expression<String>? sourceLabel,
    Expression<String>? sourceId,
    Expression<String>? changeNote,
    Expression<DateTime>? createdAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (cardId != null) 'card_id': cardId,
      if (number != null) 'number': number,
      if (title != null) 'title': title,
      if (content != null) 'content': content,
      if (tagsJson != null) 'tags_json': tagsJson,
      if (status != null) 'status': status,
      if (sourceKind != null) 'source_kind': sourceKind,
      if (sourceLabel != null) 'source_label': sourceLabel,
      if (sourceId != null) 'source_id': sourceId,
      if (changeNote != null) 'change_note': changeNote,
      if (createdAt != null) 'created_at': createdAt,
    });
  }

  CardRevisionsCompanion copyWith({
    Value<int>? id,
    Value<String>? cardId,
    Value<int>? number,
    Value<String>? title,
    Value<String>? content,
    Value<String>? tagsJson,
    Value<String>? status,
    Value<String>? sourceKind,
    Value<String>? sourceLabel,
    Value<String?>? sourceId,
    Value<String>? changeNote,
    Value<DateTime>? createdAt,
  }) {
    return CardRevisionsCompanion(
      id: id ?? this.id,
      cardId: cardId ?? this.cardId,
      number: number ?? this.number,
      title: title ?? this.title,
      content: content ?? this.content,
      tagsJson: tagsJson ?? this.tagsJson,
      status: status ?? this.status,
      sourceKind: sourceKind ?? this.sourceKind,
      sourceLabel: sourceLabel ?? this.sourceLabel,
      sourceId: sourceId ?? this.sourceId,
      changeNote: changeNote ?? this.changeNote,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (cardId.present) {
      map['card_id'] = Variable<String>(cardId.value);
    }
    if (number.present) {
      map['number'] = Variable<int>(number.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (content.present) {
      map['content'] = Variable<String>(content.value);
    }
    if (tagsJson.present) {
      map['tags_json'] = Variable<String>(tagsJson.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (sourceKind.present) {
      map['source_kind'] = Variable<String>(sourceKind.value);
    }
    if (sourceLabel.present) {
      map['source_label'] = Variable<String>(sourceLabel.value);
    }
    if (sourceId.present) {
      map['source_id'] = Variable<String>(sourceId.value);
    }
    if (changeNote.present) {
      map['change_note'] = Variable<String>(changeNote.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CardRevisionsCompanion(')
          ..write('id: $id, ')
          ..write('cardId: $cardId, ')
          ..write('number: $number, ')
          ..write('title: $title, ')
          ..write('content: $content, ')
          ..write('tagsJson: $tagsJson, ')
          ..write('status: $status, ')
          ..write('sourceKind: $sourceKind, ')
          ..write('sourceLabel: $sourceLabel, ')
          ..write('sourceId: $sourceId, ')
          ..write('changeNote: $changeNote, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }
}

class $CardRelationsTable extends CardRelations
    with TableInfo<$CardRelationsTable, CardRelationRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CardRelationsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _fromCardIdMeta = const VerificationMeta(
    'fromCardId',
  );
  @override
  late final GeneratedColumn<String> fromCardId = GeneratedColumn<String>(
    'from_card_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL REFERENCES life_cards(id) ON DELETE CASCADE',
  );
  static const VerificationMeta _toCardIdMeta = const VerificationMeta(
    'toCardId',
  );
  @override
  late final GeneratedColumn<String> toCardId = GeneratedColumn<String>(
    'to_card_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL REFERENCES life_cards(id) ON DELETE CASCADE',
  );
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
    'kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    fromCardId,
    toCardId,
    kind,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'card_relations';
  @override
  VerificationContext validateIntegrity(
    Insertable<CardRelationRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('from_card_id')) {
      context.handle(
        _fromCardIdMeta,
        fromCardId.isAcceptableOrUnknown(
          data['from_card_id']!,
          _fromCardIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_fromCardIdMeta);
    }
    if (data.containsKey('to_card_id')) {
      context.handle(
        _toCardIdMeta,
        toCardId.isAcceptableOrUnknown(data['to_card_id']!, _toCardIdMeta),
      );
    } else if (isInserting) {
      context.missing(_toCardIdMeta);
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  CardRelationRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CardRelationRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      fromCardId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}from_card_id'],
      )!,
      toCardId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}to_card_id'],
      )!,
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $CardRelationsTable createAlias(String alias) {
    return $CardRelationsTable(attachedDatabase, alias);
  }
}

class CardRelationRow extends DataClass implements Insertable<CardRelationRow> {
  final int id;
  final String fromCardId;
  final String toCardId;
  final String kind;
  final DateTime createdAt;
  const CardRelationRow({
    required this.id,
    required this.fromCardId,
    required this.toCardId,
    required this.kind,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['from_card_id'] = Variable<String>(fromCardId);
    map['to_card_id'] = Variable<String>(toCardId);
    map['kind'] = Variable<String>(kind);
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  CardRelationsCompanion toCompanion(bool nullToAbsent) {
    return CardRelationsCompanion(
      id: Value(id),
      fromCardId: Value(fromCardId),
      toCardId: Value(toCardId),
      kind: Value(kind),
      createdAt: Value(createdAt),
    );
  }

  factory CardRelationRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CardRelationRow(
      id: serializer.fromJson<int>(json['id']),
      fromCardId: serializer.fromJson<String>(json['fromCardId']),
      toCardId: serializer.fromJson<String>(json['toCardId']),
      kind: serializer.fromJson<String>(json['kind']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'fromCardId': serializer.toJson<String>(fromCardId),
      'toCardId': serializer.toJson<String>(toCardId),
      'kind': serializer.toJson<String>(kind),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  CardRelationRow copyWith({
    int? id,
    String? fromCardId,
    String? toCardId,
    String? kind,
    DateTime? createdAt,
  }) => CardRelationRow(
    id: id ?? this.id,
    fromCardId: fromCardId ?? this.fromCardId,
    toCardId: toCardId ?? this.toCardId,
    kind: kind ?? this.kind,
    createdAt: createdAt ?? this.createdAt,
  );
  CardRelationRow copyWithCompanion(CardRelationsCompanion data) {
    return CardRelationRow(
      id: data.id.present ? data.id.value : this.id,
      fromCardId: data.fromCardId.present
          ? data.fromCardId.value
          : this.fromCardId,
      toCardId: data.toCardId.present ? data.toCardId.value : this.toCardId,
      kind: data.kind.present ? data.kind.value : this.kind,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CardRelationRow(')
          ..write('id: $id, ')
          ..write('fromCardId: $fromCardId, ')
          ..write('toCardId: $toCardId, ')
          ..write('kind: $kind, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, fromCardId, toCardId, kind, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CardRelationRow &&
          other.id == this.id &&
          other.fromCardId == this.fromCardId &&
          other.toCardId == this.toCardId &&
          other.kind == this.kind &&
          other.createdAt == this.createdAt);
}

class CardRelationsCompanion extends UpdateCompanion<CardRelationRow> {
  final Value<int> id;
  final Value<String> fromCardId;
  final Value<String> toCardId;
  final Value<String> kind;
  final Value<DateTime> createdAt;
  const CardRelationsCompanion({
    this.id = const Value.absent(),
    this.fromCardId = const Value.absent(),
    this.toCardId = const Value.absent(),
    this.kind = const Value.absent(),
    this.createdAt = const Value.absent(),
  });
  CardRelationsCompanion.insert({
    this.id = const Value.absent(),
    required String fromCardId,
    required String toCardId,
    required String kind,
    required DateTime createdAt,
  }) : fromCardId = Value(fromCardId),
       toCardId = Value(toCardId),
       kind = Value(kind),
       createdAt = Value(createdAt);
  static Insertable<CardRelationRow> custom({
    Expression<int>? id,
    Expression<String>? fromCardId,
    Expression<String>? toCardId,
    Expression<String>? kind,
    Expression<DateTime>? createdAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (fromCardId != null) 'from_card_id': fromCardId,
      if (toCardId != null) 'to_card_id': toCardId,
      if (kind != null) 'kind': kind,
      if (createdAt != null) 'created_at': createdAt,
    });
  }

  CardRelationsCompanion copyWith({
    Value<int>? id,
    Value<String>? fromCardId,
    Value<String>? toCardId,
    Value<String>? kind,
    Value<DateTime>? createdAt,
  }) {
    return CardRelationsCompanion(
      id: id ?? this.id,
      fromCardId: fromCardId ?? this.fromCardId,
      toCardId: toCardId ?? this.toCardId,
      kind: kind ?? this.kind,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (fromCardId.present) {
      map['from_card_id'] = Variable<String>(fromCardId.value);
    }
    if (toCardId.present) {
      map['to_card_id'] = Variable<String>(toCardId.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CardRelationsCompanion(')
          ..write('id: $id, ')
          ..write('fromCardId: $fromCardId, ')
          ..write('toCardId: $toCardId, ')
          ..write('kind: $kind, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }
}

class $CredentialsTable extends Credentials
    with TableInfo<$CredentialsTable, CredentialRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CredentialsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _usernameMeta = const VerificationMeta(
    'username',
  );
  @override
  late final GeneratedColumn<String> username = GeneratedColumn<String>(
    'username',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _secretMeta = const VerificationMeta('secret');
  @override
  late final GeneratedColumn<String> secret = GeneratedColumn<String>(
    'secret',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _websiteMeta = const VerificationMeta(
    'website',
  );
  @override
  late final GeneratedColumn<String> website = GeneratedColumn<String>(
    'website',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _notesMeta = const VerificationMeta('notes');
  @override
  late final GeneratedColumn<String> notes = GeneratedColumn<String>(
    'notes',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _tagsJsonMeta = const VerificationMeta(
    'tagsJson',
  );
  @override
  late final GeneratedColumn<String> tagsJson = GeneratedColumn<String>(
    'tags_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('[]'),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<DateTime> deletedAt = GeneratedColumn<DateTime>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _revisionNumberMeta = const VerificationMeta(
    'revisionNumber',
  );
  @override
  late final GeneratedColumn<int> revisionNumber = GeneratedColumn<int>(
    'revision_number',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    title,
    username,
    secret,
    website,
    notes,
    tagsJson,
    createdAt,
    updatedAt,
    deletedAt,
    revisionNumber,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'credentials';
  @override
  VerificationContext validateIntegrity(
    Insertable<CredentialRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('username')) {
      context.handle(
        _usernameMeta,
        username.isAcceptableOrUnknown(data['username']!, _usernameMeta),
      );
    } else if (isInserting) {
      context.missing(_usernameMeta);
    }
    if (data.containsKey('secret')) {
      context.handle(
        _secretMeta,
        secret.isAcceptableOrUnknown(data['secret']!, _secretMeta),
      );
    } else if (isInserting) {
      context.missing(_secretMeta);
    }
    if (data.containsKey('website')) {
      context.handle(
        _websiteMeta,
        website.isAcceptableOrUnknown(data['website']!, _websiteMeta),
      );
    }
    if (data.containsKey('notes')) {
      context.handle(
        _notesMeta,
        notes.isAcceptableOrUnknown(data['notes']!, _notesMeta),
      );
    }
    if (data.containsKey('tags_json')) {
      context.handle(
        _tagsJsonMeta,
        tagsJson.isAcceptableOrUnknown(data['tags_json']!, _tagsJsonMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    if (data.containsKey('revision_number')) {
      context.handle(
        _revisionNumberMeta,
        revisionNumber.isAcceptableOrUnknown(
          data['revision_number']!,
          _revisionNumberMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  CredentialRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CredentialRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      username: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}username'],
      )!,
      secret: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}secret'],
      )!,
      website: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}website'],
      )!,
      notes: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}notes'],
      )!,
      tagsJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}tags_json'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}deleted_at'],
      ),
      revisionNumber: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}revision_number'],
      )!,
    );
  }

  @override
  $CredentialsTable createAlias(String alias) {
    return $CredentialsTable(attachedDatabase, alias);
  }
}

class CredentialRow extends DataClass implements Insertable<CredentialRow> {
  final String id;
  final String title;
  final String username;
  final String secret;
  final String website;
  final String notes;
  final String tagsJson;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final int revisionNumber;
  const CredentialRow({
    required this.id,
    required this.title,
    required this.username,
    required this.secret,
    required this.website,
    required this.notes,
    required this.tagsJson,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    required this.revisionNumber,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['title'] = Variable<String>(title);
    map['username'] = Variable<String>(username);
    map['secret'] = Variable<String>(secret);
    map['website'] = Variable<String>(website);
    map['notes'] = Variable<String>(notes);
    map['tags_json'] = Variable<String>(tagsJson);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<DateTime>(deletedAt);
    }
    map['revision_number'] = Variable<int>(revisionNumber);
    return map;
  }

  CredentialsCompanion toCompanion(bool nullToAbsent) {
    return CredentialsCompanion(
      id: Value(id),
      title: Value(title),
      username: Value(username),
      secret: Value(secret),
      website: Value(website),
      notes: Value(notes),
      tagsJson: Value(tagsJson),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
      revisionNumber: Value(revisionNumber),
    );
  }

  factory CredentialRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CredentialRow(
      id: serializer.fromJson<String>(json['id']),
      title: serializer.fromJson<String>(json['title']),
      username: serializer.fromJson<String>(json['username']),
      secret: serializer.fromJson<String>(json['secret']),
      website: serializer.fromJson<String>(json['website']),
      notes: serializer.fromJson<String>(json['notes']),
      tagsJson: serializer.fromJson<String>(json['tagsJson']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      deletedAt: serializer.fromJson<DateTime?>(json['deletedAt']),
      revisionNumber: serializer.fromJson<int>(json['revisionNumber']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'title': serializer.toJson<String>(title),
      'username': serializer.toJson<String>(username),
      'secret': serializer.toJson<String>(secret),
      'website': serializer.toJson<String>(website),
      'notes': serializer.toJson<String>(notes),
      'tagsJson': serializer.toJson<String>(tagsJson),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'deletedAt': serializer.toJson<DateTime?>(deletedAt),
      'revisionNumber': serializer.toJson<int>(revisionNumber),
    };
  }

  CredentialRow copyWith({
    String? id,
    String? title,
    String? username,
    String? secret,
    String? website,
    String? notes,
    String? tagsJson,
    DateTime? createdAt,
    DateTime? updatedAt,
    Value<DateTime?> deletedAt = const Value.absent(),
    int? revisionNumber,
  }) => CredentialRow(
    id: id ?? this.id,
    title: title ?? this.title,
    username: username ?? this.username,
    secret: secret ?? this.secret,
    website: website ?? this.website,
    notes: notes ?? this.notes,
    tagsJson: tagsJson ?? this.tagsJson,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
    revisionNumber: revisionNumber ?? this.revisionNumber,
  );
  CredentialRow copyWithCompanion(CredentialsCompanion data) {
    return CredentialRow(
      id: data.id.present ? data.id.value : this.id,
      title: data.title.present ? data.title.value : this.title,
      username: data.username.present ? data.username.value : this.username,
      secret: data.secret.present ? data.secret.value : this.secret,
      website: data.website.present ? data.website.value : this.website,
      notes: data.notes.present ? data.notes.value : this.notes,
      tagsJson: data.tagsJson.present ? data.tagsJson.value : this.tagsJson,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
      revisionNumber: data.revisionNumber.present
          ? data.revisionNumber.value
          : this.revisionNumber,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CredentialRow(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('username: $username, ')
          ..write('secret: $secret, ')
          ..write('website: $website, ')
          ..write('notes: $notes, ')
          ..write('tagsJson: $tagsJson, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('revisionNumber: $revisionNumber')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    title,
    username,
    secret,
    website,
    notes,
    tagsJson,
    createdAt,
    updatedAt,
    deletedAt,
    revisionNumber,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CredentialRow &&
          other.id == this.id &&
          other.title == this.title &&
          other.username == this.username &&
          other.secret == this.secret &&
          other.website == this.website &&
          other.notes == this.notes &&
          other.tagsJson == this.tagsJson &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.deletedAt == this.deletedAt &&
          other.revisionNumber == this.revisionNumber);
}

class CredentialsCompanion extends UpdateCompanion<CredentialRow> {
  final Value<String> id;
  final Value<String> title;
  final Value<String> username;
  final Value<String> secret;
  final Value<String> website;
  final Value<String> notes;
  final Value<String> tagsJson;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<DateTime?> deletedAt;
  final Value<int> revisionNumber;
  final Value<int> rowid;
  const CredentialsCompanion({
    this.id = const Value.absent(),
    this.title = const Value.absent(),
    this.username = const Value.absent(),
    this.secret = const Value.absent(),
    this.website = const Value.absent(),
    this.notes = const Value.absent(),
    this.tagsJson = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.revisionNumber = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CredentialsCompanion.insert({
    required String id,
    required String title,
    required String username,
    required String secret,
    this.website = const Value.absent(),
    this.notes = const Value.absent(),
    this.tagsJson = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
    this.deletedAt = const Value.absent(),
    this.revisionNumber = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       title = Value(title),
       username = Value(username),
       secret = Value(secret),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<CredentialRow> custom({
    Expression<String>? id,
    Expression<String>? title,
    Expression<String>? username,
    Expression<String>? secret,
    Expression<String>? website,
    Expression<String>? notes,
    Expression<String>? tagsJson,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<DateTime>? deletedAt,
    Expression<int>? revisionNumber,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (title != null) 'title': title,
      if (username != null) 'username': username,
      if (secret != null) 'secret': secret,
      if (website != null) 'website': website,
      if (notes != null) 'notes': notes,
      if (tagsJson != null) 'tags_json': tagsJson,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (revisionNumber != null) 'revision_number': revisionNumber,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CredentialsCompanion copyWith({
    Value<String>? id,
    Value<String>? title,
    Value<String>? username,
    Value<String>? secret,
    Value<String>? website,
    Value<String>? notes,
    Value<String>? tagsJson,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<DateTime?>? deletedAt,
    Value<int>? revisionNumber,
    Value<int>? rowid,
  }) {
    return CredentialsCompanion(
      id: id ?? this.id,
      title: title ?? this.title,
      username: username ?? this.username,
      secret: secret ?? this.secret,
      website: website ?? this.website,
      notes: notes ?? this.notes,
      tagsJson: tagsJson ?? this.tagsJson,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      revisionNumber: revisionNumber ?? this.revisionNumber,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (username.present) {
      map['username'] = Variable<String>(username.value);
    }
    if (secret.present) {
      map['secret'] = Variable<String>(secret.value);
    }
    if (website.present) {
      map['website'] = Variable<String>(website.value);
    }
    if (notes.present) {
      map['notes'] = Variable<String>(notes.value);
    }
    if (tagsJson.present) {
      map['tags_json'] = Variable<String>(tagsJson.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<DateTime>(deletedAt.value);
    }
    if (revisionNumber.present) {
      map['revision_number'] = Variable<int>(revisionNumber.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CredentialsCompanion(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('username: $username, ')
          ..write('secret: $secret, ')
          ..write('website: $website, ')
          ..write('notes: $notes, ')
          ..write('tagsJson: $tagsJson, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('revisionNumber: $revisionNumber, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CredentialRevisionsTable extends CredentialRevisions
    with TableInfo<$CredentialRevisionsTable, CredentialRevisionRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CredentialRevisionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _credentialIdMeta = const VerificationMeta(
    'credentialId',
  );
  @override
  late final GeneratedColumn<String> credentialId = GeneratedColumn<String>(
    'credential_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL REFERENCES credentials(id) ON DELETE CASCADE',
  );
  static const VerificationMeta _numberMeta = const VerificationMeta('number');
  @override
  late final GeneratedColumn<int> number = GeneratedColumn<int>(
    'number',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _usernameMeta = const VerificationMeta(
    'username',
  );
  @override
  late final GeneratedColumn<String> username = GeneratedColumn<String>(
    'username',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _secretMeta = const VerificationMeta('secret');
  @override
  late final GeneratedColumn<String> secret = GeneratedColumn<String>(
    'secret',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _websiteMeta = const VerificationMeta(
    'website',
  );
  @override
  late final GeneratedColumn<String> website = GeneratedColumn<String>(
    'website',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _notesMeta = const VerificationMeta('notes');
  @override
  late final GeneratedColumn<String> notes = GeneratedColumn<String>(
    'notes',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _changeNoteMeta = const VerificationMeta(
    'changeNote',
  );
  @override
  late final GeneratedColumn<String> changeNote = GeneratedColumn<String>(
    'change_note',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    credentialId,
    number,
    title,
    username,
    secret,
    website,
    notes,
    changeNote,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'credential_revisions';
  @override
  VerificationContext validateIntegrity(
    Insertable<CredentialRevisionRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('credential_id')) {
      context.handle(
        _credentialIdMeta,
        credentialId.isAcceptableOrUnknown(
          data['credential_id']!,
          _credentialIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_credentialIdMeta);
    }
    if (data.containsKey('number')) {
      context.handle(
        _numberMeta,
        number.isAcceptableOrUnknown(data['number']!, _numberMeta),
      );
    } else if (isInserting) {
      context.missing(_numberMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('username')) {
      context.handle(
        _usernameMeta,
        username.isAcceptableOrUnknown(data['username']!, _usernameMeta),
      );
    } else if (isInserting) {
      context.missing(_usernameMeta);
    }
    if (data.containsKey('secret')) {
      context.handle(
        _secretMeta,
        secret.isAcceptableOrUnknown(data['secret']!, _secretMeta),
      );
    } else if (isInserting) {
      context.missing(_secretMeta);
    }
    if (data.containsKey('website')) {
      context.handle(
        _websiteMeta,
        website.isAcceptableOrUnknown(data['website']!, _websiteMeta),
      );
    } else if (isInserting) {
      context.missing(_websiteMeta);
    }
    if (data.containsKey('notes')) {
      context.handle(
        _notesMeta,
        notes.isAcceptableOrUnknown(data['notes']!, _notesMeta),
      );
    } else if (isInserting) {
      context.missing(_notesMeta);
    }
    if (data.containsKey('change_note')) {
      context.handle(
        _changeNoteMeta,
        changeNote.isAcceptableOrUnknown(data['change_note']!, _changeNoteMeta),
      );
    } else if (isInserting) {
      context.missing(_changeNoteMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  CredentialRevisionRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CredentialRevisionRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      credentialId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}credential_id'],
      )!,
      number: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}number'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      username: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}username'],
      )!,
      secret: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}secret'],
      )!,
      website: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}website'],
      )!,
      notes: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}notes'],
      )!,
      changeNote: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}change_note'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $CredentialRevisionsTable createAlias(String alias) {
    return $CredentialRevisionsTable(attachedDatabase, alias);
  }
}

class CredentialRevisionRow extends DataClass
    implements Insertable<CredentialRevisionRow> {
  final int id;
  final String credentialId;
  final int number;
  final String title;
  final String username;
  final String secret;
  final String website;
  final String notes;
  final String changeNote;
  final DateTime createdAt;
  const CredentialRevisionRow({
    required this.id,
    required this.credentialId,
    required this.number,
    required this.title,
    required this.username,
    required this.secret,
    required this.website,
    required this.notes,
    required this.changeNote,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['credential_id'] = Variable<String>(credentialId);
    map['number'] = Variable<int>(number);
    map['title'] = Variable<String>(title);
    map['username'] = Variable<String>(username);
    map['secret'] = Variable<String>(secret);
    map['website'] = Variable<String>(website);
    map['notes'] = Variable<String>(notes);
    map['change_note'] = Variable<String>(changeNote);
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  CredentialRevisionsCompanion toCompanion(bool nullToAbsent) {
    return CredentialRevisionsCompanion(
      id: Value(id),
      credentialId: Value(credentialId),
      number: Value(number),
      title: Value(title),
      username: Value(username),
      secret: Value(secret),
      website: Value(website),
      notes: Value(notes),
      changeNote: Value(changeNote),
      createdAt: Value(createdAt),
    );
  }

  factory CredentialRevisionRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CredentialRevisionRow(
      id: serializer.fromJson<int>(json['id']),
      credentialId: serializer.fromJson<String>(json['credentialId']),
      number: serializer.fromJson<int>(json['number']),
      title: serializer.fromJson<String>(json['title']),
      username: serializer.fromJson<String>(json['username']),
      secret: serializer.fromJson<String>(json['secret']),
      website: serializer.fromJson<String>(json['website']),
      notes: serializer.fromJson<String>(json['notes']),
      changeNote: serializer.fromJson<String>(json['changeNote']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'credentialId': serializer.toJson<String>(credentialId),
      'number': serializer.toJson<int>(number),
      'title': serializer.toJson<String>(title),
      'username': serializer.toJson<String>(username),
      'secret': serializer.toJson<String>(secret),
      'website': serializer.toJson<String>(website),
      'notes': serializer.toJson<String>(notes),
      'changeNote': serializer.toJson<String>(changeNote),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  CredentialRevisionRow copyWith({
    int? id,
    String? credentialId,
    int? number,
    String? title,
    String? username,
    String? secret,
    String? website,
    String? notes,
    String? changeNote,
    DateTime? createdAt,
  }) => CredentialRevisionRow(
    id: id ?? this.id,
    credentialId: credentialId ?? this.credentialId,
    number: number ?? this.number,
    title: title ?? this.title,
    username: username ?? this.username,
    secret: secret ?? this.secret,
    website: website ?? this.website,
    notes: notes ?? this.notes,
    changeNote: changeNote ?? this.changeNote,
    createdAt: createdAt ?? this.createdAt,
  );
  CredentialRevisionRow copyWithCompanion(CredentialRevisionsCompanion data) {
    return CredentialRevisionRow(
      id: data.id.present ? data.id.value : this.id,
      credentialId: data.credentialId.present
          ? data.credentialId.value
          : this.credentialId,
      number: data.number.present ? data.number.value : this.number,
      title: data.title.present ? data.title.value : this.title,
      username: data.username.present ? data.username.value : this.username,
      secret: data.secret.present ? data.secret.value : this.secret,
      website: data.website.present ? data.website.value : this.website,
      notes: data.notes.present ? data.notes.value : this.notes,
      changeNote: data.changeNote.present
          ? data.changeNote.value
          : this.changeNote,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CredentialRevisionRow(')
          ..write('id: $id, ')
          ..write('credentialId: $credentialId, ')
          ..write('number: $number, ')
          ..write('title: $title, ')
          ..write('username: $username, ')
          ..write('secret: $secret, ')
          ..write('website: $website, ')
          ..write('notes: $notes, ')
          ..write('changeNote: $changeNote, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    credentialId,
    number,
    title,
    username,
    secret,
    website,
    notes,
    changeNote,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CredentialRevisionRow &&
          other.id == this.id &&
          other.credentialId == this.credentialId &&
          other.number == this.number &&
          other.title == this.title &&
          other.username == this.username &&
          other.secret == this.secret &&
          other.website == this.website &&
          other.notes == this.notes &&
          other.changeNote == this.changeNote &&
          other.createdAt == this.createdAt);
}

class CredentialRevisionsCompanion
    extends UpdateCompanion<CredentialRevisionRow> {
  final Value<int> id;
  final Value<String> credentialId;
  final Value<int> number;
  final Value<String> title;
  final Value<String> username;
  final Value<String> secret;
  final Value<String> website;
  final Value<String> notes;
  final Value<String> changeNote;
  final Value<DateTime> createdAt;
  const CredentialRevisionsCompanion({
    this.id = const Value.absent(),
    this.credentialId = const Value.absent(),
    this.number = const Value.absent(),
    this.title = const Value.absent(),
    this.username = const Value.absent(),
    this.secret = const Value.absent(),
    this.website = const Value.absent(),
    this.notes = const Value.absent(),
    this.changeNote = const Value.absent(),
    this.createdAt = const Value.absent(),
  });
  CredentialRevisionsCompanion.insert({
    this.id = const Value.absent(),
    required String credentialId,
    required int number,
    required String title,
    required String username,
    required String secret,
    required String website,
    required String notes,
    required String changeNote,
    required DateTime createdAt,
  }) : credentialId = Value(credentialId),
       number = Value(number),
       title = Value(title),
       username = Value(username),
       secret = Value(secret),
       website = Value(website),
       notes = Value(notes),
       changeNote = Value(changeNote),
       createdAt = Value(createdAt);
  static Insertable<CredentialRevisionRow> custom({
    Expression<int>? id,
    Expression<String>? credentialId,
    Expression<int>? number,
    Expression<String>? title,
    Expression<String>? username,
    Expression<String>? secret,
    Expression<String>? website,
    Expression<String>? notes,
    Expression<String>? changeNote,
    Expression<DateTime>? createdAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (credentialId != null) 'credential_id': credentialId,
      if (number != null) 'number': number,
      if (title != null) 'title': title,
      if (username != null) 'username': username,
      if (secret != null) 'secret': secret,
      if (website != null) 'website': website,
      if (notes != null) 'notes': notes,
      if (changeNote != null) 'change_note': changeNote,
      if (createdAt != null) 'created_at': createdAt,
    });
  }

  CredentialRevisionsCompanion copyWith({
    Value<int>? id,
    Value<String>? credentialId,
    Value<int>? number,
    Value<String>? title,
    Value<String>? username,
    Value<String>? secret,
    Value<String>? website,
    Value<String>? notes,
    Value<String>? changeNote,
    Value<DateTime>? createdAt,
  }) {
    return CredentialRevisionsCompanion(
      id: id ?? this.id,
      credentialId: credentialId ?? this.credentialId,
      number: number ?? this.number,
      title: title ?? this.title,
      username: username ?? this.username,
      secret: secret ?? this.secret,
      website: website ?? this.website,
      notes: notes ?? this.notes,
      changeNote: changeNote ?? this.changeNote,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (credentialId.present) {
      map['credential_id'] = Variable<String>(credentialId.value);
    }
    if (number.present) {
      map['number'] = Variable<int>(number.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (username.present) {
      map['username'] = Variable<String>(username.value);
    }
    if (secret.present) {
      map['secret'] = Variable<String>(secret.value);
    }
    if (website.present) {
      map['website'] = Variable<String>(website.value);
    }
    if (notes.present) {
      map['notes'] = Variable<String>(notes.value);
    }
    if (changeNote.present) {
      map['change_note'] = Variable<String>(changeNote.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CredentialRevisionsCompanion(')
          ..write('id: $id, ')
          ..write('credentialId: $credentialId, ')
          ..write('number: $number, ')
          ..write('title: $title, ')
          ..write('username: $username, ')
          ..write('secret: $secret, ')
          ..write('website: $website, ')
          ..write('notes: $notes, ')
          ..write('changeNote: $changeNote, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }
}

class $ReleasePoliciesTable extends ReleasePolicies
    with TableInfo<$ReleasePoliciesTable, ReleasePolicyRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ReleasePoliciesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _recordTypeMeta = const VerificationMeta(
    'recordType',
  );
  @override
  late final GeneratedColumn<String> recordType = GeneratedColumn<String>(
    'record_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _recordIdMeta = const VerificationMeta(
    'recordId',
  );
  @override
  late final GeneratedColumn<String> recordId = GeneratedColumn<String>(
    'record_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _recipientNameMeta = const VerificationMeta(
    'recipientName',
  );
  @override
  late final GeneratedColumn<String> recipientName = GeneratedColumn<String>(
    'recipient_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _incapacitatedLevelMeta =
      const VerificationMeta('incapacitatedLevel');
  @override
  late final GeneratedColumn<String> incapacitatedLevel =
      GeneratedColumn<String>(
        'incapacitated_level',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      );
  static const VerificationMeta _deceasedLevelMeta = const VerificationMeta(
    'deceasedLevel',
  );
  @override
  late final GeneratedColumn<String> deceasedLevel = GeneratedColumn<String>(
    'deceased_level',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    recordType,
    recordId,
    recipientName,
    incapacitatedLevel,
    deceasedLevel,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'release_policies';
  @override
  VerificationContext validateIntegrity(
    Insertable<ReleasePolicyRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('record_type')) {
      context.handle(
        _recordTypeMeta,
        recordType.isAcceptableOrUnknown(data['record_type']!, _recordTypeMeta),
      );
    } else if (isInserting) {
      context.missing(_recordTypeMeta);
    }
    if (data.containsKey('record_id')) {
      context.handle(
        _recordIdMeta,
        recordId.isAcceptableOrUnknown(data['record_id']!, _recordIdMeta),
      );
    } else if (isInserting) {
      context.missing(_recordIdMeta);
    }
    if (data.containsKey('recipient_name')) {
      context.handle(
        _recipientNameMeta,
        recipientName.isAcceptableOrUnknown(
          data['recipient_name']!,
          _recipientNameMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_recipientNameMeta);
    }
    if (data.containsKey('incapacitated_level')) {
      context.handle(
        _incapacitatedLevelMeta,
        incapacitatedLevel.isAcceptableOrUnknown(
          data['incapacitated_level']!,
          _incapacitatedLevelMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_incapacitatedLevelMeta);
    }
    if (data.containsKey('deceased_level')) {
      context.handle(
        _deceasedLevelMeta,
        deceasedLevel.isAcceptableOrUnknown(
          data['deceased_level']!,
          _deceasedLevelMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_deceasedLevelMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {recordType, recordId},
  ];
  @override
  ReleasePolicyRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ReleasePolicyRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      recordType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}record_type'],
      )!,
      recordId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}record_id'],
      )!,
      recipientName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}recipient_name'],
      )!,
      incapacitatedLevel: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}incapacitated_level'],
      )!,
      deceasedLevel: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}deceased_level'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $ReleasePoliciesTable createAlias(String alias) {
    return $ReleasePoliciesTable(attachedDatabase, alias);
  }
}

class ReleasePolicyRow extends DataClass
    implements Insertable<ReleasePolicyRow> {
  final int id;
  final String recordType;
  final String recordId;
  final String recipientName;
  final String incapacitatedLevel;
  final String deceasedLevel;
  final DateTime updatedAt;
  const ReleasePolicyRow({
    required this.id,
    required this.recordType,
    required this.recordId,
    required this.recipientName,
    required this.incapacitatedLevel,
    required this.deceasedLevel,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['record_type'] = Variable<String>(recordType);
    map['record_id'] = Variable<String>(recordId);
    map['recipient_name'] = Variable<String>(recipientName);
    map['incapacitated_level'] = Variable<String>(incapacitatedLevel);
    map['deceased_level'] = Variable<String>(deceasedLevel);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  ReleasePoliciesCompanion toCompanion(bool nullToAbsent) {
    return ReleasePoliciesCompanion(
      id: Value(id),
      recordType: Value(recordType),
      recordId: Value(recordId),
      recipientName: Value(recipientName),
      incapacitatedLevel: Value(incapacitatedLevel),
      deceasedLevel: Value(deceasedLevel),
      updatedAt: Value(updatedAt),
    );
  }

  factory ReleasePolicyRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ReleasePolicyRow(
      id: serializer.fromJson<int>(json['id']),
      recordType: serializer.fromJson<String>(json['recordType']),
      recordId: serializer.fromJson<String>(json['recordId']),
      recipientName: serializer.fromJson<String>(json['recipientName']),
      incapacitatedLevel: serializer.fromJson<String>(
        json['incapacitatedLevel'],
      ),
      deceasedLevel: serializer.fromJson<String>(json['deceasedLevel']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'recordType': serializer.toJson<String>(recordType),
      'recordId': serializer.toJson<String>(recordId),
      'recipientName': serializer.toJson<String>(recipientName),
      'incapacitatedLevel': serializer.toJson<String>(incapacitatedLevel),
      'deceasedLevel': serializer.toJson<String>(deceasedLevel),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  ReleasePolicyRow copyWith({
    int? id,
    String? recordType,
    String? recordId,
    String? recipientName,
    String? incapacitatedLevel,
    String? deceasedLevel,
    DateTime? updatedAt,
  }) => ReleasePolicyRow(
    id: id ?? this.id,
    recordType: recordType ?? this.recordType,
    recordId: recordId ?? this.recordId,
    recipientName: recipientName ?? this.recipientName,
    incapacitatedLevel: incapacitatedLevel ?? this.incapacitatedLevel,
    deceasedLevel: deceasedLevel ?? this.deceasedLevel,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  ReleasePolicyRow copyWithCompanion(ReleasePoliciesCompanion data) {
    return ReleasePolicyRow(
      id: data.id.present ? data.id.value : this.id,
      recordType: data.recordType.present
          ? data.recordType.value
          : this.recordType,
      recordId: data.recordId.present ? data.recordId.value : this.recordId,
      recipientName: data.recipientName.present
          ? data.recipientName.value
          : this.recipientName,
      incapacitatedLevel: data.incapacitatedLevel.present
          ? data.incapacitatedLevel.value
          : this.incapacitatedLevel,
      deceasedLevel: data.deceasedLevel.present
          ? data.deceasedLevel.value
          : this.deceasedLevel,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ReleasePolicyRow(')
          ..write('id: $id, ')
          ..write('recordType: $recordType, ')
          ..write('recordId: $recordId, ')
          ..write('recipientName: $recipientName, ')
          ..write('incapacitatedLevel: $incapacitatedLevel, ')
          ..write('deceasedLevel: $deceasedLevel, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    recordType,
    recordId,
    recipientName,
    incapacitatedLevel,
    deceasedLevel,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ReleasePolicyRow &&
          other.id == this.id &&
          other.recordType == this.recordType &&
          other.recordId == this.recordId &&
          other.recipientName == this.recipientName &&
          other.incapacitatedLevel == this.incapacitatedLevel &&
          other.deceasedLevel == this.deceasedLevel &&
          other.updatedAt == this.updatedAt);
}

class ReleasePoliciesCompanion extends UpdateCompanion<ReleasePolicyRow> {
  final Value<int> id;
  final Value<String> recordType;
  final Value<String> recordId;
  final Value<String> recipientName;
  final Value<String> incapacitatedLevel;
  final Value<String> deceasedLevel;
  final Value<DateTime> updatedAt;
  const ReleasePoliciesCompanion({
    this.id = const Value.absent(),
    this.recordType = const Value.absent(),
    this.recordId = const Value.absent(),
    this.recipientName = const Value.absent(),
    this.incapacitatedLevel = const Value.absent(),
    this.deceasedLevel = const Value.absent(),
    this.updatedAt = const Value.absent(),
  });
  ReleasePoliciesCompanion.insert({
    this.id = const Value.absent(),
    required String recordType,
    required String recordId,
    required String recipientName,
    required String incapacitatedLevel,
    required String deceasedLevel,
    required DateTime updatedAt,
  }) : recordType = Value(recordType),
       recordId = Value(recordId),
       recipientName = Value(recipientName),
       incapacitatedLevel = Value(incapacitatedLevel),
       deceasedLevel = Value(deceasedLevel),
       updatedAt = Value(updatedAt);
  static Insertable<ReleasePolicyRow> custom({
    Expression<int>? id,
    Expression<String>? recordType,
    Expression<String>? recordId,
    Expression<String>? recipientName,
    Expression<String>? incapacitatedLevel,
    Expression<String>? deceasedLevel,
    Expression<DateTime>? updatedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (recordType != null) 'record_type': recordType,
      if (recordId != null) 'record_id': recordId,
      if (recipientName != null) 'recipient_name': recipientName,
      if (incapacitatedLevel != null) 'incapacitated_level': incapacitatedLevel,
      if (deceasedLevel != null) 'deceased_level': deceasedLevel,
      if (updatedAt != null) 'updated_at': updatedAt,
    });
  }

  ReleasePoliciesCompanion copyWith({
    Value<int>? id,
    Value<String>? recordType,
    Value<String>? recordId,
    Value<String>? recipientName,
    Value<String>? incapacitatedLevel,
    Value<String>? deceasedLevel,
    Value<DateTime>? updatedAt,
  }) {
    return ReleasePoliciesCompanion(
      id: id ?? this.id,
      recordType: recordType ?? this.recordType,
      recordId: recordId ?? this.recordId,
      recipientName: recipientName ?? this.recipientName,
      incapacitatedLevel: incapacitatedLevel ?? this.incapacitatedLevel,
      deceasedLevel: deceasedLevel ?? this.deceasedLevel,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (recordType.present) {
      map['record_type'] = Variable<String>(recordType.value);
    }
    if (recordId.present) {
      map['record_id'] = Variable<String>(recordId.value);
    }
    if (recipientName.present) {
      map['recipient_name'] = Variable<String>(recipientName.value);
    }
    if (incapacitatedLevel.present) {
      map['incapacitated_level'] = Variable<String>(incapacitatedLevel.value);
    }
    if (deceasedLevel.present) {
      map['deceased_level'] = Variable<String>(deceasedLevel.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ReleasePoliciesCompanion(')
          ..write('id: $id, ')
          ..write('recordType: $recordType, ')
          ..write('recordId: $recordId, ')
          ..write('recipientName: $recipientName, ')
          ..write('incapacitatedLevel: $incapacitatedLevel, ')
          ..write('deceasedLevel: $deceasedLevel, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }
}

class $LifeStateEventsTable extends LifeStateEvents
    with TableInfo<$LifeStateEventsTable, LifeStateEventRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LifeStateEventsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _fromStateMeta = const VerificationMeta(
    'fromState',
  );
  @override
  late final GeneratedColumn<String> fromState = GeneratedColumn<String>(
    'from_state',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _toStateMeta = const VerificationMeta(
    'toState',
  );
  @override
  late final GeneratedColumn<String> toState = GeneratedColumn<String>(
    'to_state',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _reasonMeta = const VerificationMeta('reason');
  @override
  late final GeneratedColumn<String> reason = GeneratedColumn<String>(
    'reason',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _isSimulationMeta = const VerificationMeta(
    'isSimulation',
  );
  @override
  late final GeneratedColumn<bool> isSimulation = GeneratedColumn<bool>(
    'is_simulation',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_simulation" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _occurredAtMeta = const VerificationMeta(
    'occurredAt',
  );
  @override
  late final GeneratedColumn<DateTime> occurredAt = GeneratedColumn<DateTime>(
    'occurred_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    fromState,
    toState,
    reason,
    isSimulation,
    occurredAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'life_state_events';
  @override
  VerificationContext validateIntegrity(
    Insertable<LifeStateEventRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('from_state')) {
      context.handle(
        _fromStateMeta,
        fromState.isAcceptableOrUnknown(data['from_state']!, _fromStateMeta),
      );
    } else if (isInserting) {
      context.missing(_fromStateMeta);
    }
    if (data.containsKey('to_state')) {
      context.handle(
        _toStateMeta,
        toState.isAcceptableOrUnknown(data['to_state']!, _toStateMeta),
      );
    } else if (isInserting) {
      context.missing(_toStateMeta);
    }
    if (data.containsKey('reason')) {
      context.handle(
        _reasonMeta,
        reason.isAcceptableOrUnknown(data['reason']!, _reasonMeta),
      );
    } else if (isInserting) {
      context.missing(_reasonMeta);
    }
    if (data.containsKey('is_simulation')) {
      context.handle(
        _isSimulationMeta,
        isSimulation.isAcceptableOrUnknown(
          data['is_simulation']!,
          _isSimulationMeta,
        ),
      );
    }
    if (data.containsKey('occurred_at')) {
      context.handle(
        _occurredAtMeta,
        occurredAt.isAcceptableOrUnknown(data['occurred_at']!, _occurredAtMeta),
      );
    } else if (isInserting) {
      context.missing(_occurredAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  LifeStateEventRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LifeStateEventRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      fromState: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}from_state'],
      )!,
      toState: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}to_state'],
      )!,
      reason: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}reason'],
      )!,
      isSimulation: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_simulation'],
      )!,
      occurredAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}occurred_at'],
      )!,
    );
  }

  @override
  $LifeStateEventsTable createAlias(String alias) {
    return $LifeStateEventsTable(attachedDatabase, alias);
  }
}

class LifeStateEventRow extends DataClass
    implements Insertable<LifeStateEventRow> {
  final int id;
  final String fromState;
  final String toState;
  final String reason;
  final bool isSimulation;
  final DateTime occurredAt;
  const LifeStateEventRow({
    required this.id,
    required this.fromState,
    required this.toState,
    required this.reason,
    required this.isSimulation,
    required this.occurredAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['from_state'] = Variable<String>(fromState);
    map['to_state'] = Variable<String>(toState);
    map['reason'] = Variable<String>(reason);
    map['is_simulation'] = Variable<bool>(isSimulation);
    map['occurred_at'] = Variable<DateTime>(occurredAt);
    return map;
  }

  LifeStateEventsCompanion toCompanion(bool nullToAbsent) {
    return LifeStateEventsCompanion(
      id: Value(id),
      fromState: Value(fromState),
      toState: Value(toState),
      reason: Value(reason),
      isSimulation: Value(isSimulation),
      occurredAt: Value(occurredAt),
    );
  }

  factory LifeStateEventRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LifeStateEventRow(
      id: serializer.fromJson<int>(json['id']),
      fromState: serializer.fromJson<String>(json['fromState']),
      toState: serializer.fromJson<String>(json['toState']),
      reason: serializer.fromJson<String>(json['reason']),
      isSimulation: serializer.fromJson<bool>(json['isSimulation']),
      occurredAt: serializer.fromJson<DateTime>(json['occurredAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'fromState': serializer.toJson<String>(fromState),
      'toState': serializer.toJson<String>(toState),
      'reason': serializer.toJson<String>(reason),
      'isSimulation': serializer.toJson<bool>(isSimulation),
      'occurredAt': serializer.toJson<DateTime>(occurredAt),
    };
  }

  LifeStateEventRow copyWith({
    int? id,
    String? fromState,
    String? toState,
    String? reason,
    bool? isSimulation,
    DateTime? occurredAt,
  }) => LifeStateEventRow(
    id: id ?? this.id,
    fromState: fromState ?? this.fromState,
    toState: toState ?? this.toState,
    reason: reason ?? this.reason,
    isSimulation: isSimulation ?? this.isSimulation,
    occurredAt: occurredAt ?? this.occurredAt,
  );
  LifeStateEventRow copyWithCompanion(LifeStateEventsCompanion data) {
    return LifeStateEventRow(
      id: data.id.present ? data.id.value : this.id,
      fromState: data.fromState.present ? data.fromState.value : this.fromState,
      toState: data.toState.present ? data.toState.value : this.toState,
      reason: data.reason.present ? data.reason.value : this.reason,
      isSimulation: data.isSimulation.present
          ? data.isSimulation.value
          : this.isSimulation,
      occurredAt: data.occurredAt.present
          ? data.occurredAt.value
          : this.occurredAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LifeStateEventRow(')
          ..write('id: $id, ')
          ..write('fromState: $fromState, ')
          ..write('toState: $toState, ')
          ..write('reason: $reason, ')
          ..write('isSimulation: $isSimulation, ')
          ..write('occurredAt: $occurredAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, fromState, toState, reason, isSimulation, occurredAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LifeStateEventRow &&
          other.id == this.id &&
          other.fromState == this.fromState &&
          other.toState == this.toState &&
          other.reason == this.reason &&
          other.isSimulation == this.isSimulation &&
          other.occurredAt == this.occurredAt);
}

class LifeStateEventsCompanion extends UpdateCompanion<LifeStateEventRow> {
  final Value<int> id;
  final Value<String> fromState;
  final Value<String> toState;
  final Value<String> reason;
  final Value<bool> isSimulation;
  final Value<DateTime> occurredAt;
  const LifeStateEventsCompanion({
    this.id = const Value.absent(),
    this.fromState = const Value.absent(),
    this.toState = const Value.absent(),
    this.reason = const Value.absent(),
    this.isSimulation = const Value.absent(),
    this.occurredAt = const Value.absent(),
  });
  LifeStateEventsCompanion.insert({
    this.id = const Value.absent(),
    required String fromState,
    required String toState,
    required String reason,
    this.isSimulation = const Value.absent(),
    required DateTime occurredAt,
  }) : fromState = Value(fromState),
       toState = Value(toState),
       reason = Value(reason),
       occurredAt = Value(occurredAt);
  static Insertable<LifeStateEventRow> custom({
    Expression<int>? id,
    Expression<String>? fromState,
    Expression<String>? toState,
    Expression<String>? reason,
    Expression<bool>? isSimulation,
    Expression<DateTime>? occurredAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (fromState != null) 'from_state': fromState,
      if (toState != null) 'to_state': toState,
      if (reason != null) 'reason': reason,
      if (isSimulation != null) 'is_simulation': isSimulation,
      if (occurredAt != null) 'occurred_at': occurredAt,
    });
  }

  LifeStateEventsCompanion copyWith({
    Value<int>? id,
    Value<String>? fromState,
    Value<String>? toState,
    Value<String>? reason,
    Value<bool>? isSimulation,
    Value<DateTime>? occurredAt,
  }) {
    return LifeStateEventsCompanion(
      id: id ?? this.id,
      fromState: fromState ?? this.fromState,
      toState: toState ?? this.toState,
      reason: reason ?? this.reason,
      isSimulation: isSimulation ?? this.isSimulation,
      occurredAt: occurredAt ?? this.occurredAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (fromState.present) {
      map['from_state'] = Variable<String>(fromState.value);
    }
    if (toState.present) {
      map['to_state'] = Variable<String>(toState.value);
    }
    if (reason.present) {
      map['reason'] = Variable<String>(reason.value);
    }
    if (isSimulation.present) {
      map['is_simulation'] = Variable<bool>(isSimulation.value);
    }
    if (occurredAt.present) {
      map['occurred_at'] = Variable<DateTime>(occurredAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LifeStateEventsCompanion(')
          ..write('id: $id, ')
          ..write('fromState: $fromState, ')
          ..write('toState: $toState, ')
          ..write('reason: $reason, ')
          ..write('isSimulation: $isSimulation, ')
          ..write('occurredAt: $occurredAt')
          ..write(')'))
        .toString();
  }
}

class $AuditEventsTable extends AuditEvents
    with TableInfo<$AuditEventsTable, AuditEventRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AuditEventsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _actionMeta = const VerificationMeta('action');
  @override
  late final GeneratedColumn<String> action = GeneratedColumn<String>(
    'action',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _entityTypeMeta = const VerificationMeta(
    'entityType',
  );
  @override
  late final GeneratedColumn<String> entityType = GeneratedColumn<String>(
    'entity_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _entityIdMeta = const VerificationMeta(
    'entityId',
  );
  @override
  late final GeneratedColumn<String> entityId = GeneratedColumn<String>(
    'entity_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _descriptionMeta = const VerificationMeta(
    'description',
  );
  @override
  late final GeneratedColumn<String> description = GeneratedColumn<String>(
    'description',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _occurredAtMeta = const VerificationMeta(
    'occurredAt',
  );
  @override
  late final GeneratedColumn<DateTime> occurredAt = GeneratedColumn<DateTime>(
    'occurred_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    action,
    entityType,
    entityId,
    description,
    occurredAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'audit_events';
  @override
  VerificationContext validateIntegrity(
    Insertable<AuditEventRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('action')) {
      context.handle(
        _actionMeta,
        action.isAcceptableOrUnknown(data['action']!, _actionMeta),
      );
    } else if (isInserting) {
      context.missing(_actionMeta);
    }
    if (data.containsKey('entity_type')) {
      context.handle(
        _entityTypeMeta,
        entityType.isAcceptableOrUnknown(data['entity_type']!, _entityTypeMeta),
      );
    } else if (isInserting) {
      context.missing(_entityTypeMeta);
    }
    if (data.containsKey('entity_id')) {
      context.handle(
        _entityIdMeta,
        entityId.isAcceptableOrUnknown(data['entity_id']!, _entityIdMeta),
      );
    } else if (isInserting) {
      context.missing(_entityIdMeta);
    }
    if (data.containsKey('description')) {
      context.handle(
        _descriptionMeta,
        description.isAcceptableOrUnknown(
          data['description']!,
          _descriptionMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_descriptionMeta);
    }
    if (data.containsKey('occurred_at')) {
      context.handle(
        _occurredAtMeta,
        occurredAt.isAcceptableOrUnknown(data['occurred_at']!, _occurredAtMeta),
      );
    } else if (isInserting) {
      context.missing(_occurredAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  AuditEventRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AuditEventRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      action: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}action'],
      )!,
      entityType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}entity_type'],
      )!,
      entityId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}entity_id'],
      )!,
      description: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}description'],
      )!,
      occurredAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}occurred_at'],
      )!,
    );
  }

  @override
  $AuditEventsTable createAlias(String alias) {
    return $AuditEventsTable(attachedDatabase, alias);
  }
}

class AuditEventRow extends DataClass implements Insertable<AuditEventRow> {
  final int id;
  final String action;
  final String entityType;
  final String entityId;
  final String description;
  final DateTime occurredAt;
  const AuditEventRow({
    required this.id,
    required this.action,
    required this.entityType,
    required this.entityId,
    required this.description,
    required this.occurredAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['action'] = Variable<String>(action);
    map['entity_type'] = Variable<String>(entityType);
    map['entity_id'] = Variable<String>(entityId);
    map['description'] = Variable<String>(description);
    map['occurred_at'] = Variable<DateTime>(occurredAt);
    return map;
  }

  AuditEventsCompanion toCompanion(bool nullToAbsent) {
    return AuditEventsCompanion(
      id: Value(id),
      action: Value(action),
      entityType: Value(entityType),
      entityId: Value(entityId),
      description: Value(description),
      occurredAt: Value(occurredAt),
    );
  }

  factory AuditEventRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AuditEventRow(
      id: serializer.fromJson<int>(json['id']),
      action: serializer.fromJson<String>(json['action']),
      entityType: serializer.fromJson<String>(json['entityType']),
      entityId: serializer.fromJson<String>(json['entityId']),
      description: serializer.fromJson<String>(json['description']),
      occurredAt: serializer.fromJson<DateTime>(json['occurredAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'action': serializer.toJson<String>(action),
      'entityType': serializer.toJson<String>(entityType),
      'entityId': serializer.toJson<String>(entityId),
      'description': serializer.toJson<String>(description),
      'occurredAt': serializer.toJson<DateTime>(occurredAt),
    };
  }

  AuditEventRow copyWith({
    int? id,
    String? action,
    String? entityType,
    String? entityId,
    String? description,
    DateTime? occurredAt,
  }) => AuditEventRow(
    id: id ?? this.id,
    action: action ?? this.action,
    entityType: entityType ?? this.entityType,
    entityId: entityId ?? this.entityId,
    description: description ?? this.description,
    occurredAt: occurredAt ?? this.occurredAt,
  );
  AuditEventRow copyWithCompanion(AuditEventsCompanion data) {
    return AuditEventRow(
      id: data.id.present ? data.id.value : this.id,
      action: data.action.present ? data.action.value : this.action,
      entityType: data.entityType.present
          ? data.entityType.value
          : this.entityType,
      entityId: data.entityId.present ? data.entityId.value : this.entityId,
      description: data.description.present
          ? data.description.value
          : this.description,
      occurredAt: data.occurredAt.present
          ? data.occurredAt.value
          : this.occurredAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AuditEventRow(')
          ..write('id: $id, ')
          ..write('action: $action, ')
          ..write('entityType: $entityType, ')
          ..write('entityId: $entityId, ')
          ..write('description: $description, ')
          ..write('occurredAt: $occurredAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, action, entityType, entityId, description, occurredAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AuditEventRow &&
          other.id == this.id &&
          other.action == this.action &&
          other.entityType == this.entityType &&
          other.entityId == this.entityId &&
          other.description == this.description &&
          other.occurredAt == this.occurredAt);
}

class AuditEventsCompanion extends UpdateCompanion<AuditEventRow> {
  final Value<int> id;
  final Value<String> action;
  final Value<String> entityType;
  final Value<String> entityId;
  final Value<String> description;
  final Value<DateTime> occurredAt;
  const AuditEventsCompanion({
    this.id = const Value.absent(),
    this.action = const Value.absent(),
    this.entityType = const Value.absent(),
    this.entityId = const Value.absent(),
    this.description = const Value.absent(),
    this.occurredAt = const Value.absent(),
  });
  AuditEventsCompanion.insert({
    this.id = const Value.absent(),
    required String action,
    required String entityType,
    required String entityId,
    required String description,
    required DateTime occurredAt,
  }) : action = Value(action),
       entityType = Value(entityType),
       entityId = Value(entityId),
       description = Value(description),
       occurredAt = Value(occurredAt);
  static Insertable<AuditEventRow> custom({
    Expression<int>? id,
    Expression<String>? action,
    Expression<String>? entityType,
    Expression<String>? entityId,
    Expression<String>? description,
    Expression<DateTime>? occurredAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (action != null) 'action': action,
      if (entityType != null) 'entity_type': entityType,
      if (entityId != null) 'entity_id': entityId,
      if (description != null) 'description': description,
      if (occurredAt != null) 'occurred_at': occurredAt,
    });
  }

  AuditEventsCompanion copyWith({
    Value<int>? id,
    Value<String>? action,
    Value<String>? entityType,
    Value<String>? entityId,
    Value<String>? description,
    Value<DateTime>? occurredAt,
  }) {
    return AuditEventsCompanion(
      id: id ?? this.id,
      action: action ?? this.action,
      entityType: entityType ?? this.entityType,
      entityId: entityId ?? this.entityId,
      description: description ?? this.description,
      occurredAt: occurredAt ?? this.occurredAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (action.present) {
      map['action'] = Variable<String>(action.value);
    }
    if (entityType.present) {
      map['entity_type'] = Variable<String>(entityType.value);
    }
    if (entityId.present) {
      map['entity_id'] = Variable<String>(entityId.value);
    }
    if (description.present) {
      map['description'] = Variable<String>(description.value);
    }
    if (occurredAt.present) {
      map['occurred_at'] = Variable<DateTime>(occurredAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AuditEventsCompanion(')
          ..write('id: $id, ')
          ..write('action: $action, ')
          ..write('entityType: $entityType, ')
          ..write('entityId: $entityId, ')
          ..write('description: $description, ')
          ..write('occurredAt: $occurredAt')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $SourcesTable sources = $SourcesTable(this);
  late final $EncryptedBlobsTable encryptedBlobs = $EncryptedBlobsTable(this);
  late final $CardsTable cards = $CardsTable(this);
  late final $CardRevisionsTable cardRevisions = $CardRevisionsTable(this);
  late final $CardRelationsTable cardRelations = $CardRelationsTable(this);
  late final $CredentialsTable credentials = $CredentialsTable(this);
  late final $CredentialRevisionsTable credentialRevisions =
      $CredentialRevisionsTable(this);
  late final $ReleasePoliciesTable releasePolicies = $ReleasePoliciesTable(
    this,
  );
  late final $LifeStateEventsTable lifeStateEvents = $LifeStateEventsTable(
    this,
  );
  late final $AuditEventsTable auditEvents = $AuditEventsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    sources,
    encryptedBlobs,
    cards,
    cardRevisions,
    cardRelations,
    credentials,
    credentialRevisions,
    releasePolicies,
    lifeStateEvents,
    auditEvents,
  ];
  @override
  StreamQueryUpdateRules get streamUpdateRules => const StreamQueryUpdateRules([
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'life_cards',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('card_revisions', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'life_cards',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('card_relations', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'life_cards',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('card_relations', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'credentials',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('credential_revisions', kind: UpdateKind.delete)],
    ),
  ]);
}

typedef $$SourcesTableCreateCompanionBuilder = SourcesCompanion Function({
  required String id,
  required String kind,
  required String label,
  Value<String> textExcerpt,
  Value<String?> blobId,
  required DateTime createdAt,
  Value<int> rowid,
});
typedef $$SourcesTableUpdateCompanionBuilder = SourcesCompanion Function({
  Value<String> id,
  Value<String> kind,
  Value<String> label,
  Value<String> textExcerpt,
  Value<String?> blobId,
  Value<DateTime> createdAt,
  Value<int> rowid,
});

class $$SourcesTableFilterComposer
    extends Composer<_$AppDatabase, $SourcesTable> {
  $$SourcesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get label => $composableBuilder(
    column: $table.label,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get textExcerpt => $composableBuilder(
    column: $table.textExcerpt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get blobId => $composableBuilder(
    column: $table.blobId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SourcesTableOrderingComposer
    extends Composer<_$AppDatabase, $SourcesTable> {
  $$SourcesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get label => $composableBuilder(
    column: $table.label,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get textExcerpt => $composableBuilder(
    column: $table.textExcerpt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get blobId => $composableBuilder(
    column: $table.blobId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SourcesTableAnnotationComposer
    extends Composer<_$AppDatabase, $SourcesTable> {
  $$SourcesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<String> get label =>
      $composableBuilder(column: $table.label, builder: (column) => column);

  GeneratedColumn<String> get textExcerpt => $composableBuilder(
    column: $table.textExcerpt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get blobId =>
      $composableBuilder(column: $table.blobId, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$SourcesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SourcesTable,
          SourceRow,
          $$SourcesTableFilterComposer,
          $$SourcesTableOrderingComposer,
          $$SourcesTableAnnotationComposer,
          $$SourcesTableCreateCompanionBuilder,
          $$SourcesTableUpdateCompanionBuilder,
          (SourceRow, BaseReferences<_$AppDatabase, $SourcesTable, SourceRow>),
          SourceRow,
          PrefetchHooks Function()
        > {
  $$SourcesTableTableManager(_$AppDatabase db, $SourcesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SourcesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SourcesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SourcesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> kind = const Value.absent(),
                Value<String> label = const Value.absent(),
                Value<String> textExcerpt = const Value.absent(),
                Value<String?> blobId = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SourcesCompanion(
                id: id,
                kind: kind,
                label: label,
                textExcerpt: textExcerpt,
                blobId: blobId,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String kind,
                required String label,
                Value<String> textExcerpt = const Value.absent(),
                Value<String?> blobId = const Value.absent(),
                required DateTime createdAt,
                Value<int> rowid = const Value.absent(),
              }) => SourcesCompanion.insert(
                id: id,
                kind: kind,
                label: label,
                textExcerpt: textExcerpt,
                blobId: blobId,
                createdAt: createdAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$SourcesTable, SourceRow>(table),
                  BaseReferences<_$AppDatabase, $SourcesTable, SourceRow>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SourcesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SourcesTable,
      SourceRow,
      $$SourcesTableFilterComposer,
      $$SourcesTableOrderingComposer,
      $$SourcesTableAnnotationComposer,
      $$SourcesTableCreateCompanionBuilder,
      $$SourcesTableUpdateCompanionBuilder,
      (SourceRow, BaseReferences<_$AppDatabase, $SourcesTable, SourceRow>),
      SourceRow,
      PrefetchHooks Function()
    >;
typedef $$EncryptedBlobsTableCreateCompanionBuilder =
    EncryptedBlobsCompanion Function({
      required String id,
      required String originalName,
      required String mediaKind,
      required String mimeType,
      required String relativePath,
      required int byteLength,
      required String sha256,
      Value<String?> ocrText,
      Value<String?> ocrJson,
      Value<String?> sensitiveJson,
      required DateTime createdAt,
      Value<int> rowid,
    });
typedef $$EncryptedBlobsTableUpdateCompanionBuilder =
    EncryptedBlobsCompanion Function({
      Value<String> id,
      Value<String> originalName,
      Value<String> mediaKind,
      Value<String> mimeType,
      Value<String> relativePath,
      Value<int> byteLength,
      Value<String> sha256,
      Value<String?> ocrText,
      Value<String?> ocrJson,
      Value<String?> sensitiveJson,
      Value<DateTime> createdAt,
      Value<int> rowid,
    });

class $$EncryptedBlobsTableFilterComposer
    extends Composer<_$AppDatabase, $EncryptedBlobsTable> {
  $$EncryptedBlobsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get originalName => $composableBuilder(
    column: $table.originalName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get mediaKind => $composableBuilder(
    column: $table.mediaKind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get mimeType => $composableBuilder(
    column: $table.mimeType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get relativePath => $composableBuilder(
    column: $table.relativePath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get byteLength => $composableBuilder(
    column: $table.byteLength,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sha256 => $composableBuilder(
    column: $table.sha256,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get ocrText => $composableBuilder(
    column: $table.ocrText,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get ocrJson => $composableBuilder(
    column: $table.ocrJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sensitiveJson => $composableBuilder(
    column: $table.sensitiveJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$EncryptedBlobsTableOrderingComposer
    extends Composer<_$AppDatabase, $EncryptedBlobsTable> {
  $$EncryptedBlobsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get originalName => $composableBuilder(
    column: $table.originalName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mediaKind => $composableBuilder(
    column: $table.mediaKind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mimeType => $composableBuilder(
    column: $table.mimeType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get relativePath => $composableBuilder(
    column: $table.relativePath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get byteLength => $composableBuilder(
    column: $table.byteLength,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sha256 => $composableBuilder(
    column: $table.sha256,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get ocrText => $composableBuilder(
    column: $table.ocrText,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get ocrJson => $composableBuilder(
    column: $table.ocrJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sensitiveJson => $composableBuilder(
    column: $table.sensitiveJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$EncryptedBlobsTableAnnotationComposer
    extends Composer<_$AppDatabase, $EncryptedBlobsTable> {
  $$EncryptedBlobsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get originalName => $composableBuilder(
    column: $table.originalName,
    builder: (column) => column,
  );

  GeneratedColumn<String> get mediaKind =>
      $composableBuilder(column: $table.mediaKind, builder: (column) => column);

  GeneratedColumn<String> get mimeType =>
      $composableBuilder(column: $table.mimeType, builder: (column) => column);

  GeneratedColumn<String> get relativePath => $composableBuilder(
    column: $table.relativePath,
    builder: (column) => column,
  );

  GeneratedColumn<int> get byteLength => $composableBuilder(
    column: $table.byteLength,
    builder: (column) => column,
  );

  GeneratedColumn<String> get sha256 =>
      $composableBuilder(column: $table.sha256, builder: (column) => column);

  GeneratedColumn<String> get ocrText =>
      $composableBuilder(column: $table.ocrText, builder: (column) => column);

  GeneratedColumn<String> get ocrJson =>
      $composableBuilder(column: $table.ocrJson, builder: (column) => column);

  GeneratedColumn<String> get sensitiveJson => $composableBuilder(
    column: $table.sensitiveJson,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$EncryptedBlobsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $EncryptedBlobsTable,
          EncryptedBlobRow,
          $$EncryptedBlobsTableFilterComposer,
          $$EncryptedBlobsTableOrderingComposer,
          $$EncryptedBlobsTableAnnotationComposer,
          $$EncryptedBlobsTableCreateCompanionBuilder,
          $$EncryptedBlobsTableUpdateCompanionBuilder,
          (
            EncryptedBlobRow,
            BaseReferences<
              _$AppDatabase,
              $EncryptedBlobsTable,
              EncryptedBlobRow
            >,
          ),
          EncryptedBlobRow,
          PrefetchHooks Function()
        > {
  $$EncryptedBlobsTableTableManager(
    _$AppDatabase db,
    $EncryptedBlobsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$EncryptedBlobsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$EncryptedBlobsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$EncryptedBlobsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> originalName = const Value.absent(),
                Value<String> mediaKind = const Value.absent(),
                Value<String> mimeType = const Value.absent(),
                Value<String> relativePath = const Value.absent(),
                Value<int> byteLength = const Value.absent(),
                Value<String> sha256 = const Value.absent(),
                Value<String?> ocrText = const Value.absent(),
                Value<String?> ocrJson = const Value.absent(),
                Value<String?> sensitiveJson = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => EncryptedBlobsCompanion(
                id: id,
                originalName: originalName,
                mediaKind: mediaKind,
                mimeType: mimeType,
                relativePath: relativePath,
                byteLength: byteLength,
                sha256: sha256,
                ocrText: ocrText,
                ocrJson: ocrJson,
                sensitiveJson: sensitiveJson,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String originalName,
                required String mediaKind,
                required String mimeType,
                required String relativePath,
                required int byteLength,
                required String sha256,
                Value<String?> ocrText = const Value.absent(),
                Value<String?> ocrJson = const Value.absent(),
                Value<String?> sensitiveJson = const Value.absent(),
                required DateTime createdAt,
                Value<int> rowid = const Value.absent(),
              }) => EncryptedBlobsCompanion.insert(
                id: id,
                originalName: originalName,
                mediaKind: mediaKind,
                mimeType: mimeType,
                relativePath: relativePath,
                byteLength: byteLength,
                sha256: sha256,
                ocrText: ocrText,
                ocrJson: ocrJson,
                sensitiveJson: sensitiveJson,
                createdAt: createdAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$EncryptedBlobsTable, EncryptedBlobRow>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $EncryptedBlobsTable,
                    EncryptedBlobRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$EncryptedBlobsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $EncryptedBlobsTable,
      EncryptedBlobRow,
      $$EncryptedBlobsTableFilterComposer,
      $$EncryptedBlobsTableOrderingComposer,
      $$EncryptedBlobsTableAnnotationComposer,
      $$EncryptedBlobsTableCreateCompanionBuilder,
      $$EncryptedBlobsTableUpdateCompanionBuilder,
      (
        EncryptedBlobRow,
        BaseReferences<_$AppDatabase, $EncryptedBlobsTable, EncryptedBlobRow>,
      ),
      EncryptedBlobRow,
      PrefetchHooks Function()
    >;
typedef $$CardsTableCreateCompanionBuilder = CardsCompanion Function({
  required String id,
  required String title,
  required String content,
  required String kind,
  required String status,
  Value<String> tagsJson,
  required DateTime createdAt,
  required DateTime updatedAt,
  Value<DateTime?> confirmedAt,
  Value<DateTime?> deletedAt,
  Value<String?> parentCardId,
  Value<int> revisionNumber,
  Value<int> rowid,
});
typedef $$CardsTableUpdateCompanionBuilder = CardsCompanion Function({
  Value<String> id,
  Value<String> title,
  Value<String> content,
  Value<String> kind,
  Value<String> status,
  Value<String> tagsJson,
  Value<DateTime> createdAt,
  Value<DateTime> updatedAt,
  Value<DateTime?> confirmedAt,
  Value<DateTime?> deletedAt,
  Value<String?> parentCardId,
  Value<int> revisionNumber,
  Value<int> rowid,
});

final class $$CardsTableReferences
    extends BaseReferences<_$AppDatabase, $CardsTable, CardRow> {
  $$CardsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$CardRevisionsTable, List<CardRevisionRow>>
  _cardRevisionsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.cardRevisions,
    aliasName: 'life_cards__id__card_revisions__card_id',
  );

  $$CardRevisionsTableProcessedTableManager get cardRevisionsRefs {
    final manager = $$CardRevisionsTableTableManager(
      $_db,
      $_db.cardRevisions,
    ).filter((f) => f.cardId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_cardRevisionsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$CardRelationsTable, List<CardRelationRow>>
  _relationsFromCardTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.cardRelations,
    aliasName: 'life_cards__id__card_relations__from_card_id',
  );

  $$CardRelationsTableProcessedTableManager get relationsFromCard {
    final manager = $$CardRelationsTableTableManager(
      $_db,
      $_db.cardRelations,
    ).filter((f) => f.fromCardId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_relationsFromCardTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$CardRelationsTable, List<CardRelationRow>>
  _relationsToCardTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.cardRelations,
    aliasName: 'life_cards__id__card_relations__to_card_id',
  );

  $$CardRelationsTableProcessedTableManager get relationsToCard {
    final manager = $$CardRelationsTableTableManager(
      $_db,
      $_db.cardRelations,
    ).filter((f) => f.toCardId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_relationsToCardTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$CardsTableFilterComposer extends Composer<_$AppDatabase, $CardsTable> {
  $$CardsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get content => $composableBuilder(
    column: $table.content,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get tagsJson => $composableBuilder(
    column: $table.tagsJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get confirmedAt => $composableBuilder(
    column: $table.confirmedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get parentCardId => $composableBuilder(
    column: $table.parentCardId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get revisionNumber => $composableBuilder(
    column: $table.revisionNumber,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> cardRevisionsRefs(
    Expression<bool> Function($$CardRevisionsTableFilterComposer f) f,
  ) {
    final $$CardRevisionsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.cardRevisions,
      getReferencedColumn: (t) => t.cardId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CardRevisionsTableFilterComposer(
            $db: $db,
            $table: $db.cardRevisions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> relationsFromCard(
    Expression<bool> Function($$CardRelationsTableFilterComposer f) f,
  ) {
    final $$CardRelationsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.cardRelations,
      getReferencedColumn: (t) => t.fromCardId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CardRelationsTableFilterComposer(
            $db: $db,
            $table: $db.cardRelations,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> relationsToCard(
    Expression<bool> Function($$CardRelationsTableFilterComposer f) f,
  ) {
    final $$CardRelationsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.cardRelations,
      getReferencedColumn: (t) => t.toCardId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CardRelationsTableFilterComposer(
            $db: $db,
            $table: $db.cardRelations,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$CardsTableOrderingComposer
    extends Composer<_$AppDatabase, $CardsTable> {
  $$CardsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get content => $composableBuilder(
    column: $table.content,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get tagsJson => $composableBuilder(
    column: $table.tagsJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get confirmedAt => $composableBuilder(
    column: $table.confirmedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get parentCardId => $composableBuilder(
    column: $table.parentCardId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get revisionNumber => $composableBuilder(
    column: $table.revisionNumber,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CardsTableAnnotationComposer
    extends Composer<_$AppDatabase, $CardsTable> {
  $$CardsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get content =>
      $composableBuilder(column: $table.content, builder: (column) => column);

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<String> get tagsJson =>
      $composableBuilder(column: $table.tagsJson, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get confirmedAt => $composableBuilder(
    column: $table.confirmedAt,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);

  GeneratedColumn<String> get parentCardId => $composableBuilder(
    column: $table.parentCardId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get revisionNumber => $composableBuilder(
    column: $table.revisionNumber,
    builder: (column) => column,
  );

  Expression<T> cardRevisionsRefs<T extends Object>(
    Expression<T> Function($$CardRevisionsTableAnnotationComposer a) f,
  ) {
    final $$CardRevisionsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.cardRevisions,
      getReferencedColumn: (t) => t.cardId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CardRevisionsTableAnnotationComposer(
            $db: $db,
            $table: $db.cardRevisions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> relationsFromCard<T extends Object>(
    Expression<T> Function($$CardRelationsTableAnnotationComposer a) f,
  ) {
    final $$CardRelationsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.cardRelations,
      getReferencedColumn: (t) => t.fromCardId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CardRelationsTableAnnotationComposer(
            $db: $db,
            $table: $db.cardRelations,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> relationsToCard<T extends Object>(
    Expression<T> Function($$CardRelationsTableAnnotationComposer a) f,
  ) {
    final $$CardRelationsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.cardRelations,
      getReferencedColumn: (t) => t.toCardId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CardRelationsTableAnnotationComposer(
            $db: $db,
            $table: $db.cardRelations,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$CardsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CardsTable,
          CardRow,
          $$CardsTableFilterComposer,
          $$CardsTableOrderingComposer,
          $$CardsTableAnnotationComposer,
          $$CardsTableCreateCompanionBuilder,
          $$CardsTableUpdateCompanionBuilder,
          (CardRow, $$CardsTableReferences),
          CardRow,
          PrefetchHooks Function({
            bool cardRevisionsRefs,
            bool relationsFromCard,
            bool relationsToCard,
          })
        > {
  $$CardsTableTableManager(_$AppDatabase db, $CardsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CardsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CardsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CardsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String> content = const Value.absent(),
                Value<String> kind = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<String> tagsJson = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<DateTime?> confirmedAt = const Value.absent(),
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<String?> parentCardId = const Value.absent(),
                Value<int> revisionNumber = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CardsCompanion(
                id: id,
                title: title,
                content: content,
                kind: kind,
                status: status,
                tagsJson: tagsJson,
                createdAt: createdAt,
                updatedAt: updatedAt,
                confirmedAt: confirmedAt,
                deletedAt: deletedAt,
                parentCardId: parentCardId,
                revisionNumber: revisionNumber,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String title,
                required String content,
                required String kind,
                required String status,
                Value<String> tagsJson = const Value.absent(),
                required DateTime createdAt,
                required DateTime updatedAt,
                Value<DateTime?> confirmedAt = const Value.absent(),
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<String?> parentCardId = const Value.absent(),
                Value<int> revisionNumber = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CardsCompanion.insert(
                id: id,
                title: title,
                content: content,
                kind: kind,
                status: status,
                tagsJson: tagsJson,
                createdAt: createdAt,
                updatedAt: updatedAt,
                confirmedAt: confirmedAt,
                deletedAt: deletedAt,
                parentCardId: parentCardId,
                revisionNumber: revisionNumber,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$CardsTable, CardRow>(table),
                  $$CardsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({
                cardRevisionsRefs = false,
                relationsFromCard = false,
                relationsToCard = false,
              }) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (cardRevisionsRefs) db.cardRevisions,
                    if (relationsFromCard) db.cardRelations,
                    if (relationsToCard) db.cardRelations,
                  ],
                  addJoins: null,
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (cardRevisionsRefs)
                        await $_getPrefetchedData<
                          CardRow,
                          $CardsTable,
                          CardRevisionRow
                        >(
                          currentTable: table,
                          referencedTable: $$CardsTableReferences
                              ._cardRevisionsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$CardsTableReferences(
                                db,
                                table,
                                p0,
                              ).cardRevisionsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.cardId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (relationsFromCard)
                        await $_getPrefetchedData<
                          CardRow,
                          $CardsTable,
                          CardRelationRow
                        >(
                          currentTable: table,
                          referencedTable: $$CardsTableReferences
                              ._relationsFromCardTable(db),
                          managerFromTypedResult: (p0) =>
                              $$CardsTableReferences(
                                db,
                                table,
                                p0,
                              ).relationsFromCard,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.fromCardId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (relationsToCard)
                        await $_getPrefetchedData<
                          CardRow,
                          $CardsTable,
                          CardRelationRow
                        >(
                          currentTable: table,
                          referencedTable: $$CardsTableReferences
                              ._relationsToCardTable(db),
                          managerFromTypedResult: (p0) =>
                              $$CardsTableReferences(
                                db,
                                table,
                                p0,
                              ).relationsToCard,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.toCardId == item.id,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$CardsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CardsTable,
      CardRow,
      $$CardsTableFilterComposer,
      $$CardsTableOrderingComposer,
      $$CardsTableAnnotationComposer,
      $$CardsTableCreateCompanionBuilder,
      $$CardsTableUpdateCompanionBuilder,
      (CardRow, $$CardsTableReferences),
      CardRow,
      PrefetchHooks Function({
        bool cardRevisionsRefs,
        bool relationsFromCard,
        bool relationsToCard,
      })
    >;
typedef $$CardRevisionsTableCreateCompanionBuilder =
    CardRevisionsCompanion Function({
      Value<int> id,
      required String cardId,
      required int number,
      required String title,
      required String content,
      Value<String> tagsJson,
      required String status,
      required String sourceKind,
      required String sourceLabel,
      Value<String?> sourceId,
      required String changeNote,
      required DateTime createdAt,
    });
typedef $$CardRevisionsTableUpdateCompanionBuilder =
    CardRevisionsCompanion Function({
      Value<int> id,
      Value<String> cardId,
      Value<int> number,
      Value<String> title,
      Value<String> content,
      Value<String> tagsJson,
      Value<String> status,
      Value<String> sourceKind,
      Value<String> sourceLabel,
      Value<String?> sourceId,
      Value<String> changeNote,
      Value<DateTime> createdAt,
    });

final class $$CardRevisionsTableReferences
    extends
        BaseReferences<_$AppDatabase, $CardRevisionsTable, CardRevisionRow> {
  $$CardRevisionsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $CardsTable _cardIdTable(_$AppDatabase db) =>
      db.cards.createAlias('card_revisions__card_id__life_cards__id');

  $$CardsTableProcessedTableManager get cardId {
    final $_column = $_itemColumn<String>('card_id')!;

    final manager = $$CardsTableTableManager(
      $_db,
      $_db.cards,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_cardIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$CardRevisionsTableFilterComposer
    extends Composer<_$AppDatabase, $CardRevisionsTable> {
  $$CardRevisionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get number => $composableBuilder(
    column: $table.number,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get content => $composableBuilder(
    column: $table.content,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get tagsJson => $composableBuilder(
    column: $table.tagsJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sourceKind => $composableBuilder(
    column: $table.sourceKind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sourceLabel => $composableBuilder(
    column: $table.sourceLabel,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sourceId => $composableBuilder(
    column: $table.sourceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get changeNote => $composableBuilder(
    column: $table.changeNote,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  $$CardsTableFilterComposer get cardId {
    final $$CardsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.cardId,
      referencedTable: $db.cards,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CardsTableFilterComposer(
            $db: $db,
            $table: $db.cards,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$CardRevisionsTableOrderingComposer
    extends Composer<_$AppDatabase, $CardRevisionsTable> {
  $$CardRevisionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get number => $composableBuilder(
    column: $table.number,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get content => $composableBuilder(
    column: $table.content,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get tagsJson => $composableBuilder(
    column: $table.tagsJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sourceKind => $composableBuilder(
    column: $table.sourceKind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sourceLabel => $composableBuilder(
    column: $table.sourceLabel,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sourceId => $composableBuilder(
    column: $table.sourceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get changeNote => $composableBuilder(
    column: $table.changeNote,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$CardsTableOrderingComposer get cardId {
    final $$CardsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.cardId,
      referencedTable: $db.cards,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CardsTableOrderingComposer(
            $db: $db,
            $table: $db.cards,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$CardRevisionsTableAnnotationComposer
    extends Composer<_$AppDatabase, $CardRevisionsTable> {
  $$CardRevisionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get number =>
      $composableBuilder(column: $table.number, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get content =>
      $composableBuilder(column: $table.content, builder: (column) => column);

  GeneratedColumn<String> get tagsJson =>
      $composableBuilder(column: $table.tagsJson, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<String> get sourceKind => $composableBuilder(
    column: $table.sourceKind,
    builder: (column) => column,
  );

  GeneratedColumn<String> get sourceLabel => $composableBuilder(
    column: $table.sourceLabel,
    builder: (column) => column,
  );

  GeneratedColumn<String> get sourceId =>
      $composableBuilder(column: $table.sourceId, builder: (column) => column);

  GeneratedColumn<String> get changeNote => $composableBuilder(
    column: $table.changeNote,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  $$CardsTableAnnotationComposer get cardId {
    final $$CardsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.cardId,
      referencedTable: $db.cards,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CardsTableAnnotationComposer(
            $db: $db,
            $table: $db.cards,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$CardRevisionsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CardRevisionsTable,
          CardRevisionRow,
          $$CardRevisionsTableFilterComposer,
          $$CardRevisionsTableOrderingComposer,
          $$CardRevisionsTableAnnotationComposer,
          $$CardRevisionsTableCreateCompanionBuilder,
          $$CardRevisionsTableUpdateCompanionBuilder,
          (CardRevisionRow, $$CardRevisionsTableReferences),
          CardRevisionRow,
          PrefetchHooks Function({bool cardId})
        > {
  $$CardRevisionsTableTableManager(_$AppDatabase db, $CardRevisionsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CardRevisionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CardRevisionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CardRevisionsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> cardId = const Value.absent(),
                Value<int> number = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String> content = const Value.absent(),
                Value<String> tagsJson = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<String> sourceKind = const Value.absent(),
                Value<String> sourceLabel = const Value.absent(),
                Value<String?> sourceId = const Value.absent(),
                Value<String> changeNote = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
              }) => CardRevisionsCompanion(
                id: id,
                cardId: cardId,
                number: number,
                title: title,
                content: content,
                tagsJson: tagsJson,
                status: status,
                sourceKind: sourceKind,
                sourceLabel: sourceLabel,
                sourceId: sourceId,
                changeNote: changeNote,
                createdAt: createdAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String cardId,
                required int number,
                required String title,
                required String content,
                Value<String> tagsJson = const Value.absent(),
                required String status,
                required String sourceKind,
                required String sourceLabel,
                Value<String?> sourceId = const Value.absent(),
                required String changeNote,
                required DateTime createdAt,
              }) => CardRevisionsCompanion.insert(
                id: id,
                cardId: cardId,
                number: number,
                title: title,
                content: content,
                tagsJson: tagsJson,
                status: status,
                sourceKind: sourceKind,
                sourceLabel: sourceLabel,
                sourceId: sourceId,
                changeNote: changeNote,
                createdAt: createdAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$CardRevisionsTable, CardRevisionRow>(table),
                  $$CardRevisionsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({cardId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (cardId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.cardId,
                        referencedTable: $$CardRevisionsTableReferences
                            ._cardIdTable(db),
                        referencedColumn: $$CardRevisionsTableReferences
                            ._cardIdTable(db)
                            .id,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$CardRevisionsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CardRevisionsTable,
      CardRevisionRow,
      $$CardRevisionsTableFilterComposer,
      $$CardRevisionsTableOrderingComposer,
      $$CardRevisionsTableAnnotationComposer,
      $$CardRevisionsTableCreateCompanionBuilder,
      $$CardRevisionsTableUpdateCompanionBuilder,
      (CardRevisionRow, $$CardRevisionsTableReferences),
      CardRevisionRow,
      PrefetchHooks Function({bool cardId})
    >;
typedef $$CardRelationsTableCreateCompanionBuilder =
    CardRelationsCompanion Function({
      Value<int> id,
      required String fromCardId,
      required String toCardId,
      required String kind,
      required DateTime createdAt,
    });
typedef $$CardRelationsTableUpdateCompanionBuilder =
    CardRelationsCompanion Function({
      Value<int> id,
      Value<String> fromCardId,
      Value<String> toCardId,
      Value<String> kind,
      Value<DateTime> createdAt,
    });

final class $$CardRelationsTableReferences
    extends
        BaseReferences<_$AppDatabase, $CardRelationsTable, CardRelationRow> {
  $$CardRelationsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $CardsTable _fromCardIdTable(_$AppDatabase db) =>
      db.cards.createAlias('card_relations__from_card_id__life_cards__id');

  $$CardsTableProcessedTableManager get fromCardId {
    final $_column = $_itemColumn<String>('from_card_id')!;

    final manager = $$CardsTableTableManager(
      $_db,
      $_db.cards,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_fromCardIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $CardsTable _toCardIdTable(_$AppDatabase db) =>
      db.cards.createAlias('card_relations__to_card_id__life_cards__id');

  $$CardsTableProcessedTableManager get toCardId {
    final $_column = $_itemColumn<String>('to_card_id')!;

    final manager = $$CardsTableTableManager(
      $_db,
      $_db.cards,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_toCardIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$CardRelationsTableFilterComposer
    extends Composer<_$AppDatabase, $CardRelationsTable> {
  $$CardRelationsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  $$CardsTableFilterComposer get fromCardId {
    final $$CardsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.fromCardId,
      referencedTable: $db.cards,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CardsTableFilterComposer(
            $db: $db,
            $table: $db.cards,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$CardsTableFilterComposer get toCardId {
    final $$CardsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.toCardId,
      referencedTable: $db.cards,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CardsTableFilterComposer(
            $db: $db,
            $table: $db.cards,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$CardRelationsTableOrderingComposer
    extends Composer<_$AppDatabase, $CardRelationsTable> {
  $$CardRelationsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$CardsTableOrderingComposer get fromCardId {
    final $$CardsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.fromCardId,
      referencedTable: $db.cards,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CardsTableOrderingComposer(
            $db: $db,
            $table: $db.cards,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$CardsTableOrderingComposer get toCardId {
    final $$CardsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.toCardId,
      referencedTable: $db.cards,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CardsTableOrderingComposer(
            $db: $db,
            $table: $db.cards,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$CardRelationsTableAnnotationComposer
    extends Composer<_$AppDatabase, $CardRelationsTable> {
  $$CardRelationsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  $$CardsTableAnnotationComposer get fromCardId {
    final $$CardsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.fromCardId,
      referencedTable: $db.cards,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CardsTableAnnotationComposer(
            $db: $db,
            $table: $db.cards,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$CardsTableAnnotationComposer get toCardId {
    final $$CardsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.toCardId,
      referencedTable: $db.cards,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CardsTableAnnotationComposer(
            $db: $db,
            $table: $db.cards,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$CardRelationsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CardRelationsTable,
          CardRelationRow,
          $$CardRelationsTableFilterComposer,
          $$CardRelationsTableOrderingComposer,
          $$CardRelationsTableAnnotationComposer,
          $$CardRelationsTableCreateCompanionBuilder,
          $$CardRelationsTableUpdateCompanionBuilder,
          (CardRelationRow, $$CardRelationsTableReferences),
          CardRelationRow,
          PrefetchHooks Function({bool fromCardId, bool toCardId})
        > {
  $$CardRelationsTableTableManager(_$AppDatabase db, $CardRelationsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CardRelationsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CardRelationsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CardRelationsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> fromCardId = const Value.absent(),
                Value<String> toCardId = const Value.absent(),
                Value<String> kind = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
              }) => CardRelationsCompanion(
                id: id,
                fromCardId: fromCardId,
                toCardId: toCardId,
                kind: kind,
                createdAt: createdAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String fromCardId,
                required String toCardId,
                required String kind,
                required DateTime createdAt,
              }) => CardRelationsCompanion.insert(
                id: id,
                fromCardId: fromCardId,
                toCardId: toCardId,
                kind: kind,
                createdAt: createdAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$CardRelationsTable, CardRelationRow>(table),
                  $$CardRelationsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({fromCardId = false, toCardId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (fromCardId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.fromCardId,
                        referencedTable: $$CardRelationsTableReferences
                            ._fromCardIdTable(db),
                        referencedColumn: $$CardRelationsTableReferences
                            ._fromCardIdTable(db)
                            .id,
                      ) as T;
                    }
                    if (toCardId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.toCardId,
                        referencedTable: $$CardRelationsTableReferences
                            ._toCardIdTable(db),
                        referencedColumn: $$CardRelationsTableReferences
                            ._toCardIdTable(db)
                            .id,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$CardRelationsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CardRelationsTable,
      CardRelationRow,
      $$CardRelationsTableFilterComposer,
      $$CardRelationsTableOrderingComposer,
      $$CardRelationsTableAnnotationComposer,
      $$CardRelationsTableCreateCompanionBuilder,
      $$CardRelationsTableUpdateCompanionBuilder,
      (CardRelationRow, $$CardRelationsTableReferences),
      CardRelationRow,
      PrefetchHooks Function({bool fromCardId, bool toCardId})
    >;
typedef $$CredentialsTableCreateCompanionBuilder =
    CredentialsCompanion Function({
      required String id,
      required String title,
      required String username,
      required String secret,
      Value<String> website,
      Value<String> notes,
      Value<String> tagsJson,
      required DateTime createdAt,
      required DateTime updatedAt,
      Value<DateTime?> deletedAt,
      Value<int> revisionNumber,
      Value<int> rowid,
    });
typedef $$CredentialsTableUpdateCompanionBuilder =
    CredentialsCompanion Function({
      Value<String> id,
      Value<String> title,
      Value<String> username,
      Value<String> secret,
      Value<String> website,
      Value<String> notes,
      Value<String> tagsJson,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<DateTime?> deletedAt,
      Value<int> revisionNumber,
      Value<int> rowid,
    });

final class $$CredentialsTableReferences
    extends BaseReferences<_$AppDatabase, $CredentialsTable, CredentialRow> {
  $$CredentialsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<
    $CredentialRevisionsTable,
    List<CredentialRevisionRow>
  >
  _credentialRevisionsRefsTable(_$AppDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.credentialRevisions,
        aliasName: 'credentials__id__credential_revisions__credential_id',
      );

  $$CredentialRevisionsTableProcessedTableManager get credentialRevisionsRefs {
    final manager = $$CredentialRevisionsTableTableManager(
      $_db,
      $_db.credentialRevisions,
    ).filter((f) => f.credentialId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _credentialRevisionsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$CredentialsTableFilterComposer
    extends Composer<_$AppDatabase, $CredentialsTable> {
  $$CredentialsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get username => $composableBuilder(
    column: $table.username,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get secret => $composableBuilder(
    column: $table.secret,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get website => $composableBuilder(
    column: $table.website,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get tagsJson => $composableBuilder(
    column: $table.tagsJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get revisionNumber => $composableBuilder(
    column: $table.revisionNumber,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> credentialRevisionsRefs(
    Expression<bool> Function($$CredentialRevisionsTableFilterComposer f) f,
  ) {
    final $$CredentialRevisionsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.credentialRevisions,
      getReferencedColumn: (t) => t.credentialId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CredentialRevisionsTableFilterComposer(
            $db: $db,
            $table: $db.credentialRevisions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$CredentialsTableOrderingComposer
    extends Composer<_$AppDatabase, $CredentialsTable> {
  $$CredentialsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get username => $composableBuilder(
    column: $table.username,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get secret => $composableBuilder(
    column: $table.secret,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get website => $composableBuilder(
    column: $table.website,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get tagsJson => $composableBuilder(
    column: $table.tagsJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get revisionNumber => $composableBuilder(
    column: $table.revisionNumber,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CredentialsTableAnnotationComposer
    extends Composer<_$AppDatabase, $CredentialsTable> {
  $$CredentialsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get username =>
      $composableBuilder(column: $table.username, builder: (column) => column);

  GeneratedColumn<String> get secret =>
      $composableBuilder(column: $table.secret, builder: (column) => column);

  GeneratedColumn<String> get website =>
      $composableBuilder(column: $table.website, builder: (column) => column);

  GeneratedColumn<String> get notes =>
      $composableBuilder(column: $table.notes, builder: (column) => column);

  GeneratedColumn<String> get tagsJson =>
      $composableBuilder(column: $table.tagsJson, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);

  GeneratedColumn<int> get revisionNumber => $composableBuilder(
    column: $table.revisionNumber,
    builder: (column) => column,
  );

  Expression<T> credentialRevisionsRefs<T extends Object>(
    Expression<T> Function($$CredentialRevisionsTableAnnotationComposer a) f,
  ) {
    final $$CredentialRevisionsTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.credentialRevisions,
          getReferencedColumn: (t) => t.credentialId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$CredentialRevisionsTableAnnotationComposer(
                $db: $db,
                $table: $db.credentialRevisions,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }
}

class $$CredentialsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CredentialsTable,
          CredentialRow,
          $$CredentialsTableFilterComposer,
          $$CredentialsTableOrderingComposer,
          $$CredentialsTableAnnotationComposer,
          $$CredentialsTableCreateCompanionBuilder,
          $$CredentialsTableUpdateCompanionBuilder,
          (CredentialRow, $$CredentialsTableReferences),
          CredentialRow,
          PrefetchHooks Function({bool credentialRevisionsRefs})
        > {
  $$CredentialsTableTableManager(_$AppDatabase db, $CredentialsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CredentialsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CredentialsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CredentialsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String> username = const Value.absent(),
                Value<String> secret = const Value.absent(),
                Value<String> website = const Value.absent(),
                Value<String> notes = const Value.absent(),
                Value<String> tagsJson = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<int> revisionNumber = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CredentialsCompanion(
                id: id,
                title: title,
                username: username,
                secret: secret,
                website: website,
                notes: notes,
                tagsJson: tagsJson,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                revisionNumber: revisionNumber,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String title,
                required String username,
                required String secret,
                Value<String> website = const Value.absent(),
                Value<String> notes = const Value.absent(),
                Value<String> tagsJson = const Value.absent(),
                required DateTime createdAt,
                required DateTime updatedAt,
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<int> revisionNumber = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CredentialsCompanion.insert(
                id: id,
                title: title,
                username: username,
                secret: secret,
                website: website,
                notes: notes,
                tagsJson: tagsJson,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                revisionNumber: revisionNumber,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$CredentialsTable, CredentialRow>(table),
                  $$CredentialsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({credentialRevisionsRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [
                if (credentialRevisionsRefs) db.credentialRevisions,
              ],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (credentialRevisionsRefs)
                    await $_getPrefetchedData<
                      CredentialRow,
                      $CredentialsTable,
                      CredentialRevisionRow
                    >(
                      currentTable: table,
                      referencedTable: $$CredentialsTableReferences
                          ._credentialRevisionsRefsTable(db),
                      managerFromTypedResult: (p0) =>
                          $$CredentialsTableReferences(
                            db,
                            table,
                            p0,
                          ).credentialRevisionsRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where(
                            (e) => e.credentialId == item.id,
                          ),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$CredentialsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CredentialsTable,
      CredentialRow,
      $$CredentialsTableFilterComposer,
      $$CredentialsTableOrderingComposer,
      $$CredentialsTableAnnotationComposer,
      $$CredentialsTableCreateCompanionBuilder,
      $$CredentialsTableUpdateCompanionBuilder,
      (CredentialRow, $$CredentialsTableReferences),
      CredentialRow,
      PrefetchHooks Function({bool credentialRevisionsRefs})
    >;
typedef $$CredentialRevisionsTableCreateCompanionBuilder =
    CredentialRevisionsCompanion Function({
      Value<int> id,
      required String credentialId,
      required int number,
      required String title,
      required String username,
      required String secret,
      required String website,
      required String notes,
      required String changeNote,
      required DateTime createdAt,
    });
typedef $$CredentialRevisionsTableUpdateCompanionBuilder =
    CredentialRevisionsCompanion Function({
      Value<int> id,
      Value<String> credentialId,
      Value<int> number,
      Value<String> title,
      Value<String> username,
      Value<String> secret,
      Value<String> website,
      Value<String> notes,
      Value<String> changeNote,
      Value<DateTime> createdAt,
    });

final class $$CredentialRevisionsTableReferences
    extends
        BaseReferences<
          _$AppDatabase,
          $CredentialRevisionsTable,
          CredentialRevisionRow
        > {
  $$CredentialRevisionsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $CredentialsTable _credentialIdTable(_$AppDatabase db) => db
      .credentials
      .createAlias('credential_revisions__credential_id__credentials__id');

  $$CredentialsTableProcessedTableManager get credentialId {
    final $_column = $_itemColumn<String>('credential_id')!;

    final manager = $$CredentialsTableTableManager(
      $_db,
      $_db.credentials,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_credentialIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$CredentialRevisionsTableFilterComposer
    extends Composer<_$AppDatabase, $CredentialRevisionsTable> {
  $$CredentialRevisionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get number => $composableBuilder(
    column: $table.number,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get username => $composableBuilder(
    column: $table.username,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get secret => $composableBuilder(
    column: $table.secret,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get website => $composableBuilder(
    column: $table.website,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get changeNote => $composableBuilder(
    column: $table.changeNote,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  $$CredentialsTableFilterComposer get credentialId {
    final $$CredentialsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.credentialId,
      referencedTable: $db.credentials,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CredentialsTableFilterComposer(
            $db: $db,
            $table: $db.credentials,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$CredentialRevisionsTableOrderingComposer
    extends Composer<_$AppDatabase, $CredentialRevisionsTable> {
  $$CredentialRevisionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get number => $composableBuilder(
    column: $table.number,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get username => $composableBuilder(
    column: $table.username,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get secret => $composableBuilder(
    column: $table.secret,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get website => $composableBuilder(
    column: $table.website,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get changeNote => $composableBuilder(
    column: $table.changeNote,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$CredentialsTableOrderingComposer get credentialId {
    final $$CredentialsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.credentialId,
      referencedTable: $db.credentials,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CredentialsTableOrderingComposer(
            $db: $db,
            $table: $db.credentials,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$CredentialRevisionsTableAnnotationComposer
    extends Composer<_$AppDatabase, $CredentialRevisionsTable> {
  $$CredentialRevisionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get number =>
      $composableBuilder(column: $table.number, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get username =>
      $composableBuilder(column: $table.username, builder: (column) => column);

  GeneratedColumn<String> get secret =>
      $composableBuilder(column: $table.secret, builder: (column) => column);

  GeneratedColumn<String> get website =>
      $composableBuilder(column: $table.website, builder: (column) => column);

  GeneratedColumn<String> get notes =>
      $composableBuilder(column: $table.notes, builder: (column) => column);

  GeneratedColumn<String> get changeNote => $composableBuilder(
    column: $table.changeNote,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  $$CredentialsTableAnnotationComposer get credentialId {
    final $$CredentialsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.credentialId,
      referencedTable: $db.credentials,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CredentialsTableAnnotationComposer(
            $db: $db,
            $table: $db.credentials,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$CredentialRevisionsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CredentialRevisionsTable,
          CredentialRevisionRow,
          $$CredentialRevisionsTableFilterComposer,
          $$CredentialRevisionsTableOrderingComposer,
          $$CredentialRevisionsTableAnnotationComposer,
          $$CredentialRevisionsTableCreateCompanionBuilder,
          $$CredentialRevisionsTableUpdateCompanionBuilder,
          (CredentialRevisionRow, $$CredentialRevisionsTableReferences),
          CredentialRevisionRow,
          PrefetchHooks Function({bool credentialId})
        > {
  $$CredentialRevisionsTableTableManager(
    _$AppDatabase db,
    $CredentialRevisionsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CredentialRevisionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CredentialRevisionsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$CredentialRevisionsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> credentialId = const Value.absent(),
                Value<int> number = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String> username = const Value.absent(),
                Value<String> secret = const Value.absent(),
                Value<String> website = const Value.absent(),
                Value<String> notes = const Value.absent(),
                Value<String> changeNote = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
              }) => CredentialRevisionsCompanion(
                id: id,
                credentialId: credentialId,
                number: number,
                title: title,
                username: username,
                secret: secret,
                website: website,
                notes: notes,
                changeNote: changeNote,
                createdAt: createdAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String credentialId,
                required int number,
                required String title,
                required String username,
                required String secret,
                required String website,
                required String notes,
                required String changeNote,
                required DateTime createdAt,
              }) => CredentialRevisionsCompanion.insert(
                id: id,
                credentialId: credentialId,
                number: number,
                title: title,
                username: username,
                secret: secret,
                website: website,
                notes: notes,
                changeNote: changeNote,
                createdAt: createdAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$CredentialRevisionsTable, CredentialRevisionRow>(
                    table,
                  ),
                  $$CredentialRevisionsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({credentialId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (credentialId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.credentialId,
                        referencedTable: $$CredentialRevisionsTableReferences
                            ._credentialIdTable(db),
                        referencedColumn: $$CredentialRevisionsTableReferences
                            ._credentialIdTable(db)
                            .id,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$CredentialRevisionsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CredentialRevisionsTable,
      CredentialRevisionRow,
      $$CredentialRevisionsTableFilterComposer,
      $$CredentialRevisionsTableOrderingComposer,
      $$CredentialRevisionsTableAnnotationComposer,
      $$CredentialRevisionsTableCreateCompanionBuilder,
      $$CredentialRevisionsTableUpdateCompanionBuilder,
      (CredentialRevisionRow, $$CredentialRevisionsTableReferences),
      CredentialRevisionRow,
      PrefetchHooks Function({bool credentialId})
    >;
typedef $$ReleasePoliciesTableCreateCompanionBuilder =
    ReleasePoliciesCompanion Function({
      Value<int> id,
      required String recordType,
      required String recordId,
      required String recipientName,
      required String incapacitatedLevel,
      required String deceasedLevel,
      required DateTime updatedAt,
    });
typedef $$ReleasePoliciesTableUpdateCompanionBuilder =
    ReleasePoliciesCompanion Function({
      Value<int> id,
      Value<String> recordType,
      Value<String> recordId,
      Value<String> recipientName,
      Value<String> incapacitatedLevel,
      Value<String> deceasedLevel,
      Value<DateTime> updatedAt,
    });

class $$ReleasePoliciesTableFilterComposer
    extends Composer<_$AppDatabase, $ReleasePoliciesTable> {
  $$ReleasePoliciesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get recordType => $composableBuilder(
    column: $table.recordType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get recordId => $composableBuilder(
    column: $table.recordId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get recipientName => $composableBuilder(
    column: $table.recipientName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get incapacitatedLevel => $composableBuilder(
    column: $table.incapacitatedLevel,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get deceasedLevel => $composableBuilder(
    column: $table.deceasedLevel,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ReleasePoliciesTableOrderingComposer
    extends Composer<_$AppDatabase, $ReleasePoliciesTable> {
  $$ReleasePoliciesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get recordType => $composableBuilder(
    column: $table.recordType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get recordId => $composableBuilder(
    column: $table.recordId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get recipientName => $composableBuilder(
    column: $table.recipientName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get incapacitatedLevel => $composableBuilder(
    column: $table.incapacitatedLevel,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get deceasedLevel => $composableBuilder(
    column: $table.deceasedLevel,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ReleasePoliciesTableAnnotationComposer
    extends Composer<_$AppDatabase, $ReleasePoliciesTable> {
  $$ReleasePoliciesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get recordType => $composableBuilder(
    column: $table.recordType,
    builder: (column) => column,
  );

  GeneratedColumn<String> get recordId =>
      $composableBuilder(column: $table.recordId, builder: (column) => column);

  GeneratedColumn<String> get recipientName => $composableBuilder(
    column: $table.recipientName,
    builder: (column) => column,
  );

  GeneratedColumn<String> get incapacitatedLevel => $composableBuilder(
    column: $table.incapacitatedLevel,
    builder: (column) => column,
  );

  GeneratedColumn<String> get deceasedLevel => $composableBuilder(
    column: $table.deceasedLevel,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$ReleasePoliciesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ReleasePoliciesTable,
          ReleasePolicyRow,
          $$ReleasePoliciesTableFilterComposer,
          $$ReleasePoliciesTableOrderingComposer,
          $$ReleasePoliciesTableAnnotationComposer,
          $$ReleasePoliciesTableCreateCompanionBuilder,
          $$ReleasePoliciesTableUpdateCompanionBuilder,
          (
            ReleasePolicyRow,
            BaseReferences<
              _$AppDatabase,
              $ReleasePoliciesTable,
              ReleasePolicyRow
            >,
          ),
          ReleasePolicyRow,
          PrefetchHooks Function()
        > {
  $$ReleasePoliciesTableTableManager(
    _$AppDatabase db,
    $ReleasePoliciesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ReleasePoliciesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ReleasePoliciesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ReleasePoliciesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> recordType = const Value.absent(),
                Value<String> recordId = const Value.absent(),
                Value<String> recipientName = const Value.absent(),
                Value<String> incapacitatedLevel = const Value.absent(),
                Value<String> deceasedLevel = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
              }) => ReleasePoliciesCompanion(
                id: id,
                recordType: recordType,
                recordId: recordId,
                recipientName: recipientName,
                incapacitatedLevel: incapacitatedLevel,
                deceasedLevel: deceasedLevel,
                updatedAt: updatedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String recordType,
                required String recordId,
                required String recipientName,
                required String incapacitatedLevel,
                required String deceasedLevel,
                required DateTime updatedAt,
              }) => ReleasePoliciesCompanion.insert(
                id: id,
                recordType: recordType,
                recordId: recordId,
                recipientName: recipientName,
                incapacitatedLevel: incapacitatedLevel,
                deceasedLevel: deceasedLevel,
                updatedAt: updatedAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$ReleasePoliciesTable, ReleasePolicyRow>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $ReleasePoliciesTable,
                    ReleasePolicyRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ReleasePoliciesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ReleasePoliciesTable,
      ReleasePolicyRow,
      $$ReleasePoliciesTableFilterComposer,
      $$ReleasePoliciesTableOrderingComposer,
      $$ReleasePoliciesTableAnnotationComposer,
      $$ReleasePoliciesTableCreateCompanionBuilder,
      $$ReleasePoliciesTableUpdateCompanionBuilder,
      (
        ReleasePolicyRow,
        BaseReferences<_$AppDatabase, $ReleasePoliciesTable, ReleasePolicyRow>,
      ),
      ReleasePolicyRow,
      PrefetchHooks Function()
    >;
typedef $$LifeStateEventsTableCreateCompanionBuilder =
    LifeStateEventsCompanion Function({
      Value<int> id,
      required String fromState,
      required String toState,
      required String reason,
      Value<bool> isSimulation,
      required DateTime occurredAt,
    });
typedef $$LifeStateEventsTableUpdateCompanionBuilder =
    LifeStateEventsCompanion Function({
      Value<int> id,
      Value<String> fromState,
      Value<String> toState,
      Value<String> reason,
      Value<bool> isSimulation,
      Value<DateTime> occurredAt,
    });

class $$LifeStateEventsTableFilterComposer
    extends Composer<_$AppDatabase, $LifeStateEventsTable> {
  $$LifeStateEventsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get fromState => $composableBuilder(
    column: $table.fromState,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get toState => $composableBuilder(
    column: $table.toState,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get reason => $composableBuilder(
    column: $table.reason,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isSimulation => $composableBuilder(
    column: $table.isSimulation,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get occurredAt => $composableBuilder(
    column: $table.occurredAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$LifeStateEventsTableOrderingComposer
    extends Composer<_$AppDatabase, $LifeStateEventsTable> {
  $$LifeStateEventsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get fromState => $composableBuilder(
    column: $table.fromState,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get toState => $composableBuilder(
    column: $table.toState,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get reason => $composableBuilder(
    column: $table.reason,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isSimulation => $composableBuilder(
    column: $table.isSimulation,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get occurredAt => $composableBuilder(
    column: $table.occurredAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$LifeStateEventsTableAnnotationComposer
    extends Composer<_$AppDatabase, $LifeStateEventsTable> {
  $$LifeStateEventsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get fromState =>
      $composableBuilder(column: $table.fromState, builder: (column) => column);

  GeneratedColumn<String> get toState =>
      $composableBuilder(column: $table.toState, builder: (column) => column);

  GeneratedColumn<String> get reason =>
      $composableBuilder(column: $table.reason, builder: (column) => column);

  GeneratedColumn<bool> get isSimulation => $composableBuilder(
    column: $table.isSimulation,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get occurredAt => $composableBuilder(
    column: $table.occurredAt,
    builder: (column) => column,
  );
}

class $$LifeStateEventsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $LifeStateEventsTable,
          LifeStateEventRow,
          $$LifeStateEventsTableFilterComposer,
          $$LifeStateEventsTableOrderingComposer,
          $$LifeStateEventsTableAnnotationComposer,
          $$LifeStateEventsTableCreateCompanionBuilder,
          $$LifeStateEventsTableUpdateCompanionBuilder,
          (
            LifeStateEventRow,
            BaseReferences<
              _$AppDatabase,
              $LifeStateEventsTable,
              LifeStateEventRow
            >,
          ),
          LifeStateEventRow,
          PrefetchHooks Function()
        > {
  $$LifeStateEventsTableTableManager(
    _$AppDatabase db,
    $LifeStateEventsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LifeStateEventsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LifeStateEventsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LifeStateEventsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> fromState = const Value.absent(),
                Value<String> toState = const Value.absent(),
                Value<String> reason = const Value.absent(),
                Value<bool> isSimulation = const Value.absent(),
                Value<DateTime> occurredAt = const Value.absent(),
              }) => LifeStateEventsCompanion(
                id: id,
                fromState: fromState,
                toState: toState,
                reason: reason,
                isSimulation: isSimulation,
                occurredAt: occurredAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String fromState,
                required String toState,
                required String reason,
                Value<bool> isSimulation = const Value.absent(),
                required DateTime occurredAt,
              }) => LifeStateEventsCompanion.insert(
                id: id,
                fromState: fromState,
                toState: toState,
                reason: reason,
                isSimulation: isSimulation,
                occurredAt: occurredAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$LifeStateEventsTable, LifeStateEventRow>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $LifeStateEventsTable,
                    LifeStateEventRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$LifeStateEventsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $LifeStateEventsTable,
      LifeStateEventRow,
      $$LifeStateEventsTableFilterComposer,
      $$LifeStateEventsTableOrderingComposer,
      $$LifeStateEventsTableAnnotationComposer,
      $$LifeStateEventsTableCreateCompanionBuilder,
      $$LifeStateEventsTableUpdateCompanionBuilder,
      (
        LifeStateEventRow,
        BaseReferences<_$AppDatabase, $LifeStateEventsTable, LifeStateEventRow>,
      ),
      LifeStateEventRow,
      PrefetchHooks Function()
    >;
typedef $$AuditEventsTableCreateCompanionBuilder =
    AuditEventsCompanion Function({
      Value<int> id,
      required String action,
      required String entityType,
      required String entityId,
      required String description,
      required DateTime occurredAt,
    });
typedef $$AuditEventsTableUpdateCompanionBuilder =
    AuditEventsCompanion Function({
      Value<int> id,
      Value<String> action,
      Value<String> entityType,
      Value<String> entityId,
      Value<String> description,
      Value<DateTime> occurredAt,
    });

class $$AuditEventsTableFilterComposer
    extends Composer<_$AppDatabase, $AuditEventsTable> {
  $$AuditEventsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get action => $composableBuilder(
    column: $table.action,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get entityType => $composableBuilder(
    column: $table.entityType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get entityId => $composableBuilder(
    column: $table.entityId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get occurredAt => $composableBuilder(
    column: $table.occurredAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$AuditEventsTableOrderingComposer
    extends Composer<_$AppDatabase, $AuditEventsTable> {
  $$AuditEventsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get action => $composableBuilder(
    column: $table.action,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get entityType => $composableBuilder(
    column: $table.entityType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get entityId => $composableBuilder(
    column: $table.entityId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get occurredAt => $composableBuilder(
    column: $table.occurredAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$AuditEventsTableAnnotationComposer
    extends Composer<_$AppDatabase, $AuditEventsTable> {
  $$AuditEventsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get action =>
      $composableBuilder(column: $table.action, builder: (column) => column);

  GeneratedColumn<String> get entityType => $composableBuilder(
    column: $table.entityType,
    builder: (column) => column,
  );

  GeneratedColumn<String> get entityId =>
      $composableBuilder(column: $table.entityId, builder: (column) => column);

  GeneratedColumn<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get occurredAt => $composableBuilder(
    column: $table.occurredAt,
    builder: (column) => column,
  );
}

class $$AuditEventsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $AuditEventsTable,
          AuditEventRow,
          $$AuditEventsTableFilterComposer,
          $$AuditEventsTableOrderingComposer,
          $$AuditEventsTableAnnotationComposer,
          $$AuditEventsTableCreateCompanionBuilder,
          $$AuditEventsTableUpdateCompanionBuilder,
          (
            AuditEventRow,
            BaseReferences<_$AppDatabase, $AuditEventsTable, AuditEventRow>,
          ),
          AuditEventRow,
          PrefetchHooks Function()
        > {
  $$AuditEventsTableTableManager(_$AppDatabase db, $AuditEventsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AuditEventsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AuditEventsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AuditEventsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> action = const Value.absent(),
                Value<String> entityType = const Value.absent(),
                Value<String> entityId = const Value.absent(),
                Value<String> description = const Value.absent(),
                Value<DateTime> occurredAt = const Value.absent(),
              }) => AuditEventsCompanion(
                id: id,
                action: action,
                entityType: entityType,
                entityId: entityId,
                description: description,
                occurredAt: occurredAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String action,
                required String entityType,
                required String entityId,
                required String description,
                required DateTime occurredAt,
              }) => AuditEventsCompanion.insert(
                id: id,
                action: action,
                entityType: entityType,
                entityId: entityId,
                description: description,
                occurredAt: occurredAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$AuditEventsTable, AuditEventRow>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $AuditEventsTable,
                    AuditEventRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$AuditEventsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $AuditEventsTable,
      AuditEventRow,
      $$AuditEventsTableFilterComposer,
      $$AuditEventsTableOrderingComposer,
      $$AuditEventsTableAnnotationComposer,
      $$AuditEventsTableCreateCompanionBuilder,
      $$AuditEventsTableUpdateCompanionBuilder,
      (
        AuditEventRow,
        BaseReferences<_$AppDatabase, $AuditEventsTable, AuditEventRow>,
      ),
      AuditEventRow,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$SourcesTableTableManager get sources =>
      $$SourcesTableTableManager(_db, _db.sources);
  $$EncryptedBlobsTableTableManager get encryptedBlobs =>
      $$EncryptedBlobsTableTableManager(_db, _db.encryptedBlobs);
  $$CardsTableTableManager get cards =>
      $$CardsTableTableManager(_db, _db.cards);
  $$CardRevisionsTableTableManager get cardRevisions =>
      $$CardRevisionsTableTableManager(_db, _db.cardRevisions);
  $$CardRelationsTableTableManager get cardRelations =>
      $$CardRelationsTableTableManager(_db, _db.cardRelations);
  $$CredentialsTableTableManager get credentials =>
      $$CredentialsTableTableManager(_db, _db.credentials);
  $$CredentialRevisionsTableTableManager get credentialRevisions =>
      $$CredentialRevisionsTableTableManager(_db, _db.credentialRevisions);
  $$ReleasePoliciesTableTableManager get releasePolicies =>
      $$ReleasePoliciesTableTableManager(_db, _db.releasePolicies);
  $$LifeStateEventsTableTableManager get lifeStateEvents =>
      $$LifeStateEventsTableTableManager(_db, _db.lifeStateEvents);
  $$AuditEventsTableTableManager get auditEvents =>
      $$AuditEventsTableTableManager(_db, _db.auditEvents);
}
