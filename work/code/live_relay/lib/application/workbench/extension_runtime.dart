import 'dart:async';
import 'dart:convert';

import '../../core/extensions/extension_manifest.dart';
import '../card_summary.dart';

class ExtensionRuntime {
  ExtensionRuntime({required this.read, required this.write});
  final Future<String?> Function() read;
  final Future<void> Function(String) write;
  final _installed = <String, InstalledExtension>{};
  Map<String, InstalledExtension> get installed => Map.unmodifiable(_installed);
  bool _disposed = false;
  final _changes = StreamController<void>.broadcast();
  Stream<void> get changes => _changes.stream;
  void _changed() {
    if (!_disposed) _changes.add(null);
  }

  void dispose() {
    _disposed = true;
    _installed.clear();
    unawaited(_changes.close());
  }

  Future<void> _pending = Future.value();
  Future<void> load() async {
    final raw = await read();
    if (_disposed) throw StateError('扩展运行态已销毁');
    if (raw == null) return;
    final data = jsonDecode(raw) as Map<String, dynamic>;
    if (data['version'] != 1) throw const FormatException('扩展配置版本不支持');
    final result = <String, InstalledExtension>{};
    for (final row in data['extensions'] as List) {
      final manifest = ExtensionManifest.parse(
        Map<String, dynamic>.from(row['manifest'] as Map),
      );
      if (result.containsKey(manifest.id)) {
        throw const FormatException('安装扩展重复');
      }
      result[manifest.id] = InstalledExtension(
        manifest,
        enabled: row['enabled'] == true,
        settings: Map<String, bool>.from(row['settings'] as Map),
      );
    }
    _installed
      ..clear()
      ..addAll(result);
    _changed();
  }

  Future<void> _change(void Function() mutate) {
    final next = _pending.then((_) async {
      if (_disposed) throw StateError('扩展运行态已销毁');
      final previous = _encode();
      mutate();
      try {
        await write(_encode());
      } on Object {
        if (!_disposed) _restore(previous);
        rethrow;
      }
      _changed();
    });
    _pending = next.then<void>((_) {}, onError: (Object _) {});
    return next;
  }

  String _encode() => jsonEncode({
    'version': 1,
    'extensions': [
      for (final item in installed.values)
        {
          'manifest': item.manifest.raw,
          'enabled': item.enabled,
          'settings': item.settings,
        },
    ],
  });
  void _restore(String value) {
    _installed.clear();
    for (final row in (jsonDecode(value)['extensions'] as List)) {
      final manifest = ExtensionManifest.parse(
        Map<String, dynamic>.from(row['manifest'] as Map),
      );
      _installed[manifest.id] = InstalledExtension(
        manifest,
        enabled: row['enabled'] == true,
        settings: Map<String, bool>.from(row['settings'] as Map),
      );
    }
  }

  Future<void> install(ExtensionManifest manifest) => _change(() {
    if (installed.containsKey(manifest.id)) {
      throw const FormatException('此扩展已安装，请移除后安装新版本');
    }
    if (installed.length >= 50) throw const FormatException('最多安装 50 个扩展');
    _installed[manifest.id] = InstalledExtension(manifest);
  });
  Future<void> setEnabled(String id, bool enabled) =>
      _change(() => _installed[id] = installed[id]!.copyWith(enabled: enabled));
  Future<void> remove(String id) => _change(() => _installed.remove(id));
  Future<void> setSetting(String id, String key, bool value) => _change(() {
    if (!installed[id]!.manifest.settings.any((s) => s.id == key)) {
      throw const FormatException('设置不存在');
    }
    _installed[id] = installed[id]!.copyWith(
      settings: {...installed[id]!.settings, key: value},
    );
  });
  Map<String, ExtensionView> get views => {
    for (final item in installed.values.where((e) => e.enabled))
      for (final view in item.manifest.views)
        'extension/${item.manifest.id}/${view.id}': view,
  };
  List<({String id, String title, String view})> get commands => [
    for (final item in installed.values.where((e) => e.enabled))
      for (final c in item.manifest.commands)
        (
          id: '${item.manifest.id}.${c.id}',
          title: c.title,
          view: 'extension/${item.manifest.id}/${c.view}',
        ),
  ];
  List<CardSummary> filter(
    String viewId,
    List<CardSummary> cards,
    Set<String> sourced,
  ) {
    final view = views[viewId];
    if (view == null) return [];
    final extension = installed[viewId.split('/')[1]]!;
    return cards
        .where(
          (c) =>
              !c.isPassword &&
              (view.filter['status'] == null ||
                  c.status?.name == view.filter['status']) &&
              (view.filter['kind'] == null ||
                  c.kind?.name == view.filter['kind']) &&
              (view.filter['tag'] == null ||
                  c.tags.contains(view.filter['tag'])) &&
              (view.filter['query'] == null ||
                  '${c.title} ${c.preview}'.toLowerCase().contains(
                    view.filter['query']!.toLowerCase(),
                  )) &&
              (view.setting == null ||
                  !extension.setting(view.setting!) ||
                  sourced.contains(c.recordId)),
        )
        .toList();
  }
}
