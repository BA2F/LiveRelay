import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'extension_registry.dart';

List<Map<String, Object?>> windowExtensions(ExtensionRegistry registry) => [
  for (final item in registry.installed.values)
    {
      'manifest': item.manifest.raw,
      'enabled': item.enabled,
      'settings': Map.of(item.settings),
    },
];

class WindowExtensionBridge {
  WindowExtensionBridge(this.registry, {required this.active});
  final ExtensionRegistry registry;
  final bool Function() active;
  static const methods = {
    'installExtension',
    'enableExtension',
    'removeExtension',
    'extensionSetting',
  };
  Future<void> invoke(MethodCall call) async {
    if (!active()) throw const FormatException('扩展管理视图已关闭');
    final a = call.arguments is Map ? call.arguments as Map : const {};
    if (call.method != 'installExtension' &&
        !registry.installed.containsKey(a['id'])) {
      throw const FormatException('扩展已移除');
    }
    switch (call.method) {
      case 'installExtension':
        await registry.install(
          ExtensionManifest.parse(
            Map<String, dynamic>.from(a['manifest'] as Map),
          ),
        );
      case 'enableExtension':
        if (a['enabled'] is! bool) throw const FormatException('启停选择无效');
        await registry.setEnabled(a['id'] as String, a['enabled'] as bool);
      case 'removeExtension':
        await registry.remove(a['id'] as String);
      case 'extensionSetting':
        final item = registry.installed[a['id']]!;
        if (!item.enabled ||
            a['value'] is! bool ||
            !item.manifest.settings.any((s) => s.id == a['key'])) {
          throw const FormatException('扩展设置无效');
        }
        await registry.setSetting(
          a['id'] as String,
          a['key'] as String,
          a['value'] as bool,
        );
      default:
        throw const FormatException('扩展操作无效');
    }
  }
}

/// A projection for the shared catalog UI. All mutations run in the owner;
/// stale or unregistered IDs are checked there, never applied locally.
class RemoteExtensionAccess extends ChangeNotifier implements ExtensionAccess {
  RemoteExtensionAccess(this.request);
  final Future<void> Function(String, Map<String, Object?>) request;
  @override
  final installed = <String, InstalledExtension>{};
  void update(List rows) {
    final updated = <String, InstalledExtension>{};
    for (final row in rows) {
      final manifest = ExtensionManifest.parse(
        Map<String, dynamic>.from(row['manifest'] as Map),
      );
      updated[manifest.id] = InstalledExtension(
        manifest,
        enabled: row['enabled'] == true,
        settings: Map<String, bool>.from(row['settings'] as Map),
      );
    }
    installed
      ..clear()
      ..addAll(updated);
    notifyListeners();
  }

  void clear() {
    installed.clear();
    notifyListeners();
  }

  @override
  Future<void> install(ExtensionManifest manifest) =>
      request('installExtension', {'manifest': manifest.raw});
  @override
  Future<void> setEnabled(String id, bool enabled) =>
      request('enableExtension', {'id': id, 'enabled': enabled});
  @override
  Future<void> remove(String id) => request('removeExtension', {'id': id});
  @override
  Future<void> setSetting(String id, String key, bool value) =>
      request('extensionSetting', {'id': id, 'key': key, 'value': value});
}
