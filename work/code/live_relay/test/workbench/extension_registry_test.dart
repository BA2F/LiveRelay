import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:live_relay/application/workbench/extension_registry.dart';
import 'package:live_relay/application/card_summary.dart';
import 'package:live_relay/core/domain/entities.dart';

void main() {
  Map<String, dynamic> sample() => jsonDecode(
    File('assets/extensions/draft-review.lrext.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  test('install, settings, enable, remove and reload contribute actual filtered views and commands', () async {
    String? persisted;
    final registry = ExtensionRegistry(
      read: () async => persisted,
      write: (v) async => persisted = v,
    );
    final manifest = ExtensionManifest.parse(sample());
    await registry.install(manifest);
    final now = DateTime.utc(2026);
    CardSummary card(String id, CardStatus status) => CardSummary.fromRecord(
      LifeCard(
        id: id,
        title: id,
        content: '摘要',
        kind: CardKind.note,
        status: status,
        tags: [],
        createdAt: now,
        updatedAt: now,
        revisionNumber: 1,
      ),
    );
    final cards = [
      card('draft', CardStatus.draft),
      card('confirmed', CardStatus.confirmed),
      CardSummary.fromRecord(
        CredentialEntry(
          id: 'password',
          title: '密码',
          username: 'owner',
          secret: 'never-provide',
          website: '',
          notes: '',
          tags: [],
          createdAt: now,
          updatedAt: now,
          revisionNumber: 1,
        ),
      ),
    ];
    final viewId = registry.views.keys.single;
    expect(registry.filter(viewId, cards, {}).map((c) => c.recordId), [
      'draft',
    ]);
    expect(registry.commands.single.view, viewId);
    await registry.setSetting(manifest.id, 'only-sourced', true);
    expect(registry.filter(viewId, cards, {}), isEmpty);
    expect(registry.filter(viewId, cards, {'draft'}), hasLength(1));
    await registry.setEnabled(manifest.id, false);
    expect(registry.views, isEmpty);
    expect(registry.commands, isEmpty);
    final reloaded = ExtensionRegistry(
      read: () async => persisted,
      write: (v) async => persisted = v,
    );
    await reloaded.load();
    expect(reloaded.installed[manifest.id]!.enabled, isFalse);
    await reloaded.setEnabled(manifest.id, true);
    expect(reloaded.views, hasLength(1));
    await reloaded.remove(manifest.id);
    expect(reloaded.views, isEmpty);
    expect((jsonDecode(persisted!)['extensions'] as List), isEmpty);
    registry.dispose();
    reloaded.dispose();
  });
  test('untrusted manifests cannot contribute executable, filesystem or vault capability', () {
    for (final extra in [
      {'executable': '/bin/sh'},
      {
        'capabilities': ['vault.key'],
      },
      {'apiVersion': 2},
      {'views': 'invalid'},
    ]) {
      expect(
        () => ExtensionManifest.parse({...sample(), ...extra}),
        throwsFormatException,
      );
    }
  });
  test(
    'failed persistence rolls back enabled state and registrations',
    () async {
      var failed = false;
      final registry = ExtensionRegistry(
        read: () async => null,
        write: (_) async {
          if (failed) throw const FileSystemException('disk');
        },
      );
      final manifest = ExtensionManifest.parse(sample());
      await registry.install(manifest);
      failed = true;
      await expectLater(
        registry.setEnabled(manifest.id, false),
        throwsA(isA<FileSystemException>()),
      );
      expect(registry.views, hasLength(1));
      expect(registry.installed[manifest.id]!.enabled, isTrue);
      registry.dispose();
    },
  );
}
