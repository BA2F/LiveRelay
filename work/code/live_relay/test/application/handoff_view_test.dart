import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:live_relay/application/handoff_view_service.dart';

void main() {
  test('local handoff view opens only with the shared password', () async {
    final root = await Directory.systemTemp.createTemp('handoff-view-');
    addTearDown(() => root.delete(recursive: true));
    final file = File('${root.path}/view.json');
    final service = HandoffViewService(() async => file);

    expect(await service.exists(), isFalse);
    expect(await service.updatedAt(), isNull);
    await service.save(
      password: 'family-2026',
      snapshot: {
        'version': 1,
        'ownerName': '本人',
        'records': [
          {
            'title': '卡片',
            'body': '只有密码能看到',
            'level': 'full',
            'history': <Object?>[],
            'originalIds': <Object?>[],
          },
        ],
        'originals': <String, Object?>{},
      },
    );

    expect(await service.exists(), isTrue);
    expect(await service.updatedAt(), isNotNull);
    final raw = await file.readAsString();
    expect(raw, isNot(contains('只有密码能看到')));
    expect(raw, isNot(contains('本人')));

    expect(await service.accepts('wrong-password'), isFalse);
    await expectLater(service.open('wrong-password'), throwsFormatException);

    final snapshot = await service.open('family-2026');
    expect(snapshot['ownerName'], '本人');
    expect((snapshot['records'] as List).single['body'], '只有密码能看到');
    expect(DateTime.tryParse(snapshot['date'] as String), isNotNull);

    await service.save(
      password: 'new-family-2026',
      snapshot: {
        'version': 1,
        'ownerName': '本人',
        'records': <Object?>[],
        'originals': <String, Object?>{},
      },
    );
    expect(await service.accepts('family-2026'), isFalse);
    expect(await service.accepts('new-family-2026'), isTrue);
    expect((await service.open('new-family-2026'))['records'], isEmpty);
  });

  test(
    'package bytes open with the pickup code without a local file',
    () async {
      final service = HandoffViewService(
        () async => File('unused-in-bytes-test.json'),
      );
      final bytes = await service.encode(
        password: 'ABCDEFGHJKLM',
        snapshot: {
          'version': 1,
          'ownerName': '本人',
          'records': [
            {'title': '卡片', 'body': '只有取件码能看到', 'level': 'full'},
          ],
          'originals': <String, Object?>{},
        },
      );
      expect(utf8.decode(bytes), isNot(contains('只有取件码能看到')));
      final snapshot = await service.openBytes(bytes, 'ABCDEFGHJKLM');
      expect((snapshot['records'] as List).single['body'], '只有取件码能看到');
      await expectLater(
        service.openBytes(bytes, 'WRONGCODE123'),
        throwsFormatException,
      );
    },
  );

  test('a missing handoff view reports it instead of opening', () async {
    final root = await Directory.systemTemp.createTemp('handoff-view-');
    addTearDown(() => root.delete(recursive: true));
    final service = HandoffViewService(
      () async => File('${root.path}/missing.json'),
    );
    await expectLater(service.open('family-2026'), throwsStateError);
    expect(await service.accepts('family-2026'), isFalse);
  });
}
