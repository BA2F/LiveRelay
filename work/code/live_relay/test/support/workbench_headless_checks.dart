// Ordinary Dart verification of workbench state; no widgets/window channels.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:live_relay/application/workbench/card_edit_runtime.dart';
import 'package:live_relay/application/workbench/extension_runtime.dart';
import 'package:live_relay/application/workbench/workbench_layout_state.dart';
import 'package:live_relay/application/card_summary.dart';
import 'package:live_relay/core/domain/entities.dart';
import 'package:live_relay/core/extensions/extension_manifest.dart';

void check(bool v, String message) {
  if (!v) throw StateError(message);
}

Future<void> reject(Future<Object?> f, String message) async {
  Object? error;
  try {
    await f;
  } on Object catch (e) {
    error = e;
  }
  check(
    error != null && '$error'.contains(message),
    'Expected $message; got $error',
  );
}

LifeCard card() => LifeCard(
  id: 'public-card',
  title: 'public title',
  content: 'public body',
  kind: CardKind.note,
  status: CardStatus.draft,
  tags: const [],
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
  revisionNumber: 1,
);
Map<String, dynamic> manifest() => {
  'apiVersion': 1,
  'id': 'fixture.plugin',
  'name': 'Public fixture',
  'version': '1.0.0',
  'capabilities': [
    'cards.summary',
    'workbench.views',
    'workbench.commands',
    'workbench.settings',
  ],
  'views': [
    {
      'id': 'drafts',
      'title': 'Drafts',
      'filter': {'status': 'draft'},
      'setting': 'sourced',
    },
  ],
  'commands': [
    {'id': 'show', 'title': 'Show', 'view': 'drafts'},
  ],
  'settings': [
    {
      'id': 'sourced',
      'title': 'Sourced only',
      'type': 'boolean',
      'default': false,
    },
  ],
};
Map<String, Future<void> Function()> workbenchChecks() => {
  'headless dock move/float/restore preserves one view and rejects invalid state atomically':
      () async {
        final layout = WorkbenchLayoutState();
        final restored = WorkbenchLayoutState();
        try {
          final target = layout.groups.last.id;
          layout.move('cards', target, DockPlacement.floating);
          layout.floating.single.x = 320;
          restored.restore(
            Map<String, dynamic>.from(
              jsonDecode(jsonEncode(layout.toJson())) as Map,
            ),
          );
          check(
            restored.floating.single.x == 320 &&
                restored.containing('cards')?.tabs.single == 'cards',
            'Float round trip failed',
          );
          restored.move('cards', restored.groups.first.id, DockPlacement.left);
          check(
            restored.floating.isEmpty &&
                restored.groups
                        .expand((g) => g.tabs)
                        .where((v) => v == 'cards')
                        .length ==
                    1,
            'View duplicated/lost',
          );
          final before = jsonEncode(restored.toJson());
          final invalid = Map<String, dynamic>.from(jsonDecode(before) as Map);
          invalid['root']['fraction'] = double.nan;
          await reject(Future.sync(() => restored.restore(invalid)), '尺寸无效');
          check(
            before == jsonEncode(restored.toJson()),
            'Invalid restore changed active layout',
          );
        } finally {
          layout.dispose();
          restored.dispose();
        }
      },
  'headless edit while saving drains latest buffer and retries a real failed save':
      () async {
        final entered = Completer<void>(), release = Completer<void>();
        final titles = <String>[];
        var fail = false;
        final edits = CardEditRuntime(
          canSave: () => true,
          debounce: const Duration(days: 1),
          save: (id, draft) async {
            titles.add(draft.title);
            if (titles.length == 1) {
              entered.complete();
              await release.future;
            }
            if (fail) throw const FormatException('fixture save denied');
          },
        );
        try {
          final s = edits.session(card());
          edits.edit(s, title: 'first');
          final first = edits.flush();
          await entered.future;
          edits.edit(s, title: 'second');
          final second = edits.flush();
          release.complete();
          await first;
          await second;
          check(
            titles.join(',') == 'first,second' && !edits.hasUnsaved,
            'New edit lost behind running save',
          );
          fail = true;
          edits.edit(s, title: 'retry');
          await edits.flush();
          check(
            s.state == CardSaveState.failed && s.error == 'fixture save denied',
            'Failure disappeared',
          );
          fail = false;
          await edits.flush();
          check(
            s.state == CardSaveState.saved && titles.last == 'retry',
            'Retry did not save same buffer',
          );
        } finally {
          edits.dispose();
        }
      },
  'headless clearing editors blanks held buffers and ignores a late saved object':
      () async {
        final entered = Completer<void>(), release = Completer<void>();
        final edits = CardEditRuntime(
          canSave: () => true,
          debounce: const Duration(days: 1),
          save: (id, draft) async {
            entered.complete();
            await release.future;
          },
        );
        try {
          final old = edits.session(card());
          edits.edit(old, content: 'public changed');
          final pending = edits.flush();
          await entered.future;
          edits.clear();
          check(
            old.title.isEmpty &&
                old.content.isEmpty &&
                old.tags.isEmpty &&
                edits.values.isEmpty,
            'Held editor plaintext retained',
          );
          release.complete();
          await pending;
          check(
            edits.values.isEmpty && !edits.hasUnsaved && old.content.isEmpty,
            'Late save resurrected buffer',
          );
        } finally {
          edits.dispose();
        }
      },
  'headless extension descriptor freezes caller inputs and filters credentials out':
      () async {
        final raw = manifest();
        final parsed = ExtensionManifest.parse(raw);
        (raw['views'] as List).single['filter']['status'] = 'confirmed';
        check(
          parsed.views.single.filter['status'] == 'draft' &&
              (parsed.raw['views'] as List).single['filter']['status'] ==
                  'draft',
          'Mutable caller changed reviewed descriptor',
        );
        String? saved;
        final runtime = ExtensionRuntime(
          read: () async => saved,
          write: (value) async {
            saved = value;
          },
        );
        try {
          await runtime.install(parsed);
          final summaries = [
            CardSummary.fromRecord(card()),
            CardSummary(
              recordType: 'credential',
              recordId: 'fixture-credential',
              title: 'public username',
              preview: 'public',
              tags: const [],
              updatedAt: DateTime.utc(2026),
            ),
          ];
          check(
            runtime
                    .filter('extension/fixture.plugin/drafts', summaries, {})
                    .length ==
                1,
            'Extension received credential projection',
          );
          await runtime.setSetting('fixture.plugin', 'sourced', true);
          check(
            runtime
                .filter('extension/fixture.plugin/drafts', summaries, {})
                .isEmpty,
            'Setting ignored',
          );
          check(
            runtime.filter('extension/fixture.plugin/drafts', summaries, {
                  'public-card',
                }).length ==
                1,
            'Source filter rejected valid original',
          );
          await reject(
            Future.sync(
              () => ExtensionManifest.parse({
                ...manifest(),
                'capabilities': ['cards.summary', 'filesystem'],
              }),
            ),
            '不支持的权限',
          );
        } finally {
          runtime.dispose();
        }
      },
  'headless extension persistence rollback retains installed state and serializes commands':
      () async {
        String? saved;
        var fail = false;
        final runtime = ExtensionRuntime(
          read: () async => saved,
          write: (value) async {
            if (fail) throw StateError('fixture write denied');
            saved = value;
          },
        );
        final reloaded = ExtensionRuntime(
          read: () async => saved,
          write: (value) async {
            saved = value;
          },
        );
        try {
          await runtime.install(ExtensionManifest.parse(manifest()));
          fail = true;
          await reject(runtime.remove('fixture.plugin'), 'write denied');
          check(
            runtime.installed.containsKey('fixture.plugin'),
            'Failed write lost installed state',
          );
          fail = false;
          await Future.wait([
            runtime.setEnabled('fixture.plugin', false),
            runtime.setSetting('fixture.plugin', 'sourced', true),
          ]);
          await reloaded.load();
          check(
            reloaded.views.isEmpty &&
                reloaded.installed['fixture.plugin']!.setting('sourced'),
            'Queued choices lost',
          );
        } finally {
          runtime.dispose();
          reloaded.dispose();
        }
      },
};
Future<void> main() async {
  for (final entry in workbenchChecks().entries) {
    await entry.value();
    stdout.writeln('PASS ${entry.key}');
  }
}
