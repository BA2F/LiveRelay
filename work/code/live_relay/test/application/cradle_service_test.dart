import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:live_relay/application/cradle_service.dart';
import 'package:live_relay/application/local_handoff_service.dart';
import 'package:live_relay/core/cradle/cradle_records.dart';
import 'package:live_relay/core/ports/transfer_medium.dart';
import 'package:live_relay/infrastructure/persistence/app_database.dart';
import 'package:live_relay/infrastructure/persistence/sqlite_vault_repository.dart';

import '../support/session_fakes.dart';

class MemoryMedium implements TransferMedium {
  final files = <String, Uint8List>{};
  @override
  String get label => '内存介质';
  @override
  Future<List<MediumEntry>> list() async => [
    for (final entry in files.entries)
      MediumEntry(name: entry.key, length: entry.value.length),
  ];
  @override
  Future<Uint8List> read(String name) async =>
      files[name] ??
      (throw const TransferMediumException('云端没有这个文件', notFound: true));
  @override
  Future<Uint8List> readPrefix(String name, int maxBytes) async {
    final bytes = await read(name);
    return bytes.length > maxBytes
        ? Uint8List.sublistView(bytes, 0, maxBytes)
        : bytes;
  }

  @override
  Future<void> writeAtomic(String name, Uint8List bytes) async {
    files[name] = Uint8List.fromList(bytes);
  }

  @override
  Future<void> delete(String name) async {
    files.remove(name);
  }
}

Future<CradleService> _unlockedCradle(Directory root) async {
  final repository = SqliteVaultRepository(AppDatabase.inMemory());
  final session = fixtureSession(
    directory: Directory('${root.path}/owner'),
    openRepository: (_, _) async => repository,
  );
  await session.prepare();
  await session.openWithKey(Uint8List(32));
  session.markUnlocked();
  addTearDown(session.close);
  return CradleService(LocalHandoffService(session, originals: session));
}

void main() {
  test(
    'check-in records upload, read back, verify, and reject tampering',
    () async {
      final root = await Directory.systemTemp.createTemp('cradle-unit-');
      final cradle = await _unlockedCradle(root);
      final medium = MemoryMedium();

      expect(await cradle.readCheckin(medium), isNull);

      final uploaded = await cradle.uploadCheckin(medium, device: 'phone');
      final raw = jsonDecode(
        utf8.decode(medium.files[CheckinRecord.fileName]!),
      ) as Map<String, Object?>;
      expect(raw['kind'], CheckinRecord.kind);
      expect(raw['version'], CheckinRecord.version);
      expect(raw['device'], 'phone');

      final readBack = await cradle.readCheckin(medium);
      expect(readBack, isNotNull);
      expect(readBack!.checkedAt, uploaded.checkedAt);
      expect(readBack.device, 'phone');
      expect(await CradleService.verifyCheckin(readBack), isTrue);

      final tampered = CheckinRecord(
        checkedAt: readBack.checkedAt.add(const Duration(days: 30)),
        device: readBack.device,
        publicIdentity: readBack.publicIdentity,
        signature: readBack.signature,
      );
      expect(await CradleService.verifyCheckin(tampered), isFalse);

      expect(
        () => CheckinRecord.parse({'kind': 'other', 'version': 1}),
        throwsFormatException,
      );
    },
  );

  test(
    'pre-authorized packages upload under the canonical plan name',
    () async {
      final root = await Directory.systemTemp.createTemp('cradle-unit-');
      final cradle = await _unlockedCradle(root);
      final medium = MemoryMedium();

      expect(
        CradleRecipient.packageNameFor('家人'),
        'liverelay-handoff-家人.lrshare',
      );
      expect(
        CradleRecipient.packageNameFor(r'a/b\c'),
        'liverelay-handoff-a_b_c.lrshare',
      );

      final bytes = Uint8List.fromList(
        utf8.encode('fake scoped delivery wire'),
      );
      await cradle.uploadPackage(
        medium,
        packageName: CradleRecipient.packageNameFor('家人'),
        bytes: bytes,
      );
      expect(medium.files['liverelay-handoff-家人.lrshare'], bytes);

      expect(
        () =>
            cradle.uploadPackage(medium, packageName: 'bad/name', bytes: bytes),
        throwsFormatException,
      );
      expect(
        () => cradle.uploadPackage(medium, packageName: '', bytes: bytes),
        throwsFormatException,
      );
    },
  );

  test('cradle plans round-trip and validate parameter ranges', () async {
    final root = await Directory.systemTemp.createTemp('cradle-unit-');
    final cradle = await _unlockedCradle(root);
    final medium = MemoryMedium();

    expect(await cradle.readPlan(medium), isNull);

    const plan = CradlePlan(
      ownerEmail: 'owner@example.com',
      periodDays: 7,
      remindBeforeDays: 1,
      graceDays: 3,
      recipients: [
        CradleRecipient(
          label: '家人',
          email: 'someone@example.com',
          packageName: 'handoff/family.lrshare',
          cloudUrl: 'http://example.com:3923/owner/',
          cloudUser: 'owner',
          cloudPassword: 'password',
          subject: '【留灯】张三 给你留了内容',
          body: '取件链接：http://example.com/family.lrshare\n取件码：ABCD-EFGH-JKLM',
        ),
      ],
    );
    expect(plan.remindAfterDays, 6);
    expect(plan.triggerAfterDays, 10);

    await cradle.uploadPlan(medium, plan);
    final readBack = await cradle.readPlan(medium);
    expect(readBack, isNotNull);
    expect(readBack!.ownerEmail, 'owner@example.com');
    expect(readBack.periodDays, 7);
    expect(readBack.remindBeforeDays, 1);
    expect(readBack.graceDays, 3);
    expect(readBack.recipients.single.label, '家人');
    expect(readBack.recipients.single.email, 'someone@example.com');
    expect(
      readBack.recipients.single.cloudUrl,
      'http://example.com:3923/owner/',
    );
    expect(readBack.recipients.single.subject, '【留灯】张三 给你留了内容');
    expect(readBack.recipients.single.body, contains('取件码：ABCD-EFGH-JKLM'));

    final versionOne = CradlePlan.parse({
      'kind': CradlePlan.kind,
      'version': 1,
      'ownerEmail': 'owner@example.com',
      'periodDays': 7,
      'remindBeforeDays': 1,
      'graceDays': 3,
      'recipients': [
        {
          'label': '家人',
          'email': 'someone@example.com',
          'package': 'handoff/family.lrshare',
          'cloudUrl': 'http://example.com:3923/owner/',
          'cloudUser': 'owner',
          'cloudPassword': 'password',
        },
      ],
    });
    expect(versionOne.recipients.single.subject, isEmpty);
    expect(versionOne.recipients.single.body, isEmpty);

    expect(
      CradlePlan.validationError(
        periodDays: 7,
        remindBeforeDays: 7,
        graceDays: 3,
      ),
      isNotNull,
    );
    expect(
      CradlePlan.validationError(
        periodDays: 0,
        remindBeforeDays: 0,
        graceDays: 3,
      ),
      isNotNull,
    );
    expect(
      CradlePlan.validationError(
        periodDays: 7,
        remindBeforeDays: 1,
        graceDays: 91,
      ),
      isNotNull,
    );
    expect(
      () => CradlePlan.parse({
        'kind': CradlePlan.kind,
        'version': 1,
        'ownerEmail': 'owner@example.com',
        'periodDays': 'seven',
        'remindBeforeDays': 1,
        'graceDays': 3,
        'recipients': <Object?>[],
      }),
      throwsFormatException,
    );
    expect(
      () => CradlePlan.parse({
        'kind': CradlePlan.kind,
        'version': 1,
        'periodDays': 7,
        'remindBeforeDays': 1,
        'graceDays': 3,
        'recipients': <Object?>[],
      }),
      throwsFormatException,
    );
  });
}
