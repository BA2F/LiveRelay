import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../application/workbench/extension_runtime.dart';
import '../../../application/card_summary.dart';
import '../../../core/extensions/extension_manifest.dart';
export '../../../core/extensions/extension_manifest.dart';

abstract interface class ExtensionAccess implements Listenable {
  Map<String, InstalledExtension> get installed;
  Future<void> install(ExtensionManifest manifest);
  Future<void> setEnabled(String id, bool enabled);
  Future<void> remove(String id);
  Future<void> setSetting(String id, String key, bool value);
}

class ExtensionRegistry extends ChangeNotifier implements ExtensionAccess {
  ExtensionRegistry({
    required Future<String?> Function() read,
    required Future<void> Function(String) write,
  }) : runtime = ExtensionRuntime(read: read, write: write) {
    _subscription = runtime.changes.listen((_) => notifyListeners());
  }
  final ExtensionRuntime runtime;
  late final StreamSubscription<void> _subscription;
  @override
  Map<String, InstalledExtension> get installed => runtime.installed;
  Map<String, ExtensionView> get views => runtime.views;
  List<({String id, String title, String view})> get commands =>
      runtime.commands;
  Future<void> load() => runtime.load();
  @override
  Future<void> install(ExtensionManifest manifest) => runtime.install(manifest);
  @override
  Future<void> setEnabled(String id, bool enabled) =>
      runtime.setEnabled(id, enabled);
  @override
  Future<void> remove(String id) => runtime.remove(id);
  @override
  Future<void> setSetting(String id, String key, bool value) =>
      runtime.setSetting(id, key, value);
  List<CardSummary> filter(
    String viewId,
    List<CardSummary> cards,
    Set<String> sourced,
  ) => runtime.filter(viewId, cards, sourced);
  @override
  void dispose() {
    unawaited(_subscription.cancel());
    runtime.dispose();
    super.dispose();
  }
}
