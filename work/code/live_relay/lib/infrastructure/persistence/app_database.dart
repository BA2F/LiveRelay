import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';

part 'app_database.g.dart';

@DataClassName('SourceRow')
class Sources extends Table {
  TextColumn get id => text()();
  TextColumn get kind => text()();
  TextColumn get label => text()();
  TextColumn get textExcerpt => text().withDefault(const Constant(''))();
  TextColumn get blobId => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('EncryptedBlobRow')
class EncryptedBlobs extends Table {
  TextColumn get id => text()();
  TextColumn get originalName => text()();
  TextColumn get mediaKind => text()();
  TextColumn get mimeType => text()();
  TextColumn get relativePath => text()();
  IntColumn get byteLength => integer()();
  TextColumn get sha256 => text()();
  TextColumn get ocrText => text().nullable()();
  TextColumn get ocrJson => text().nullable()();
  TextColumn get sensitiveJson => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('CardRow')
class Cards extends Table {
  @override
  String get tableName => 'life_cards';

  TextColumn get id => text()();
  TextColumn get title => text()();
  TextColumn get content => text()();
  TextColumn get kind => text()();
  TextColumn get status => text()();
  TextColumn get tagsJson => text().withDefault(const Constant('[]'))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get confirmedAt => dateTime().nullable()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  TextColumn get parentCardId => text().nullable()();
  IntColumn get revisionNumber => integer().withDefault(const Constant(1))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('CardRevisionRow')
class CardRevisions extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get cardId => text().customConstraint(
    'NOT NULL REFERENCES life_cards(id) ON DELETE CASCADE',
  )();
  IntColumn get number => integer()();
  TextColumn get title => text()();
  TextColumn get content => text()();
  TextColumn get tagsJson => text().withDefault(const Constant('[]'))();
  TextColumn get status => text()();
  TextColumn get sourceKind => text()();
  TextColumn get sourceLabel => text()();
  TextColumn get sourceId => text().nullable()();
  TextColumn get changeNote => text()();
  DateTimeColumn get createdAt => dateTime()();
}

@DataClassName('CardRelationRow')
class CardRelations extends Table {
  IntColumn get id => integer().autoIncrement()();
  @ReferenceName('relationsFromCard')
  TextColumn get fromCardId => text().customConstraint(
    'NOT NULL REFERENCES life_cards(id) ON DELETE CASCADE',
  )();
  @ReferenceName('relationsToCard')
  TextColumn get toCardId => text().customConstraint(
    'NOT NULL REFERENCES life_cards(id) ON DELETE CASCADE',
  )();
  TextColumn get kind => text()();
  DateTimeColumn get createdAt => dateTime()();
}

@DataClassName('CredentialRow')
class Credentials extends Table {
  TextColumn get id => text()();
  TextColumn get title => text()();
  TextColumn get username => text()();
  TextColumn get secret => text()();
  TextColumn get website => text().withDefault(const Constant(''))();
  TextColumn get notes => text().withDefault(const Constant(''))();
  TextColumn get tagsJson => text().withDefault(const Constant('[]'))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  IntColumn get revisionNumber => integer().withDefault(const Constant(1))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('CredentialRevisionRow')
class CredentialRevisions extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get credentialId => text().customConstraint(
    'NOT NULL REFERENCES credentials(id) ON DELETE CASCADE',
  )();
  IntColumn get number => integer()();
  TextColumn get title => text()();
  TextColumn get username => text()();
  TextColumn get secret => text()();
  TextColumn get website => text()();
  TextColumn get notes => text()();
  TextColumn get changeNote => text()();
  DateTimeColumn get createdAt => dateTime()();
}

@DataClassName('ReleasePolicyRow')
class ReleasePolicies extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get recordType => text()();
  TextColumn get recordId => text()();
  TextColumn get recipientName => text()();
  TextColumn get incapacitatedLevel => text()();
  TextColumn get deceasedLevel => text()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {recordType, recordId},
  ];
}

@DataClassName('LifeStateEventRow')
class LifeStateEvents extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get fromState => text()();
  TextColumn get toState => text()();
  TextColumn get reason => text()();
  BoolColumn get isSimulation => boolean().withDefault(const Constant(true))();
  DateTimeColumn get occurredAt => dateTime()();
}

@DataClassName('AuditEventRow')
class AuditEvents extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get action => text()();
  TextColumn get entityType => text()();
  TextColumn get entityId => text()();
  TextColumn get description => text()();
  DateTimeColumn get occurredAt => dateTime()();
}

class VaultLocalState extends Table {
  TextColumn get name => text()();
  TextColumn get value => text()();
  @override
  Set<Column<Object>> get primaryKey => {name};
}

@DriftDatabase(
  tables: [
    VaultLocalState,
    Sources,
    EncryptedBlobs,
    Cards,
    CardRevisions,
    CardRelations,
    Credentials,
    CredentialRevisions,
    ReleasePolicies,
    LifeStateEvents,
    AuditEvents,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase._(super.executor);

  AppDatabase.inMemory() : super(NativeDatabase.memory());

  static Future<AppDatabase> openEncrypted({
    required Directory vaultDirectory,
    required Uint8List masterKey,
  }) async {
    await vaultDirectory.create(recursive: true);
    final databaseFile = File('${vaultDirectory.path}/vault.sqlite');
    final keyHex = masterKey
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
    final executor = NativeDatabase.createInBackground(
      databaseFile,
      setup: (database) {
        final cipherVersion = database.select('PRAGMA cipher_version;');
        if (cipherVersion.isEmpty) {
          throw StateError('SQLCipher 不可用，拒绝以明文打开 Vault');
        }
        database.execute('PRAGMA key = "x\'$keyHex\'";');
        database.execute('PRAGMA foreign_keys = ON;');
        // This authenticated read fails immediately for a wrong master key.
        database.select('SELECT count(*) FROM sqlite_master;');
      },
    );
    final result = AppDatabase._(executor);
    try {
      await result.customSelect('SELECT 1').getSingle();
      return result;
    } on Object {
      await result.close();
      rethrow;
    }
  }

  @override
  int get schemaVersion => 5;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (migrator) async {
      await migrator.createAll();
      await customStatement(
        'CREATE INDEX life_cards_updated_idx '
        'ON life_cards(deleted_at, updated_at DESC)',
      );
      await customStatement(
        'CREATE INDEX card_revisions_card_idx '
        'ON card_revisions(card_id, number DESC)',
      );
      await customStatement(
        'CREATE INDEX credentials_updated_idx '
        'ON credentials(deleted_at, updated_at DESC)',
      );
    },
    onUpgrade: (migrator, from, to) async {
      if (from < 5) await migrator.createTable(vaultLocalState);
      if (from < 2) {
        await migrator.createTable(encryptedBlobs);
      }
      if (from >= 2 && from < 3) {
        await migrator.addColumn(encryptedBlobs, encryptedBlobs.ocrJson);
      }
      if (from >= 2 && from < 4) {
        await migrator.addColumn(encryptedBlobs, encryptedBlobs.sensitiveJson);
      }
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );
}
