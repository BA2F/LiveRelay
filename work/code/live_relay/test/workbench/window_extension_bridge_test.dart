import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_relay/application/workbench/extension_registry.dart';
import 'package:live_relay/application/workbench/window_extension_bridge.dart';

void main() {
  test('detached extension mutations reject revoked/unknown capabilities and preserve owner registry on storage failure', () async {
    String? stored;
    var blocked = false, active = true;
    final registry = ExtensionRegistry(
      read: () async => stored,
      write: (value) async {
        if (blocked) throw const FileSystemException('fixture blocked');
        stored = value;
      },
    );
    final bridge = WindowExtensionBridge(registry, active: () => active);
    final raw = jsonDecode(
      File('assets/extensions/draft-review.lrext.json').readAsStringSync(),
    ) as Map;
    late final RemoteExtensionAccess remote;
    remote = RemoteExtensionAccess((method, args) async {
      await bridge.invoke(MethodCall(method, args));
      remote.update(windowExtensions(registry));
    });
    try {
      await expectLater(
        bridge.invoke(
          MethodCall('installExtension', {
            'manifest': {
              ...raw,
              'capabilities': [...raw['capabilities'] as List, 'vault.full'],
            },
          }),
        ),
        throwsFormatException,
      );
      expect(registry.installed, isEmpty);
      await remote.install(
        ExtensionManifest.parse(Map<String, dynamic>.from(raw)),
      );
      expect(remote.installed.keys, ['liverelay.draft-review']);
      final before = stored;
      blocked = true;
      await expectLater(
        remote.setEnabled('liverelay.draft-review', false),
        throwsA(isA<FileSystemException>()),
      );
      expect(registry.installed.values.single.enabled, true);
      expect(remote.installed.values.single.enabled, true);
      expect(stored, before);
      blocked = false;
      await remote.setSetting('liverelay.draft-review', 'only-sourced', true);
      expect(remote.installed.values.single.setting('only-sourced'), true);
      await remote.setEnabled('liverelay.draft-review', false);
      expect(registry.commands, isEmpty);
      await expectLater(
        remote.setSetting('liverelay.draft-review', 'only-sourced', false),
        throwsFormatException,
      );
      active = false;
      await expectLater(
        remote.remove('liverelay.draft-review'),
        throwsFormatException,
      );
      expect(registry.installed, hasLength(1));
      active = true;
      await remote.remove('liverelay.draft-review');
      expect(remote.installed, isEmpty);
      await expectLater(
        remote.setEnabled('removed', true),
        throwsFormatException,
      );
    } finally {
      remote.dispose();
      registry.dispose();
    }
  });
}
