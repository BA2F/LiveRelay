import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../card_summary.dart';

class ExtensionView {
  const ExtensionView({
    required this.id,
    required this.title,
    required this.filter,
    this.setting,
  });
  final String id, title;
  final Map<String, String> filter;
  final String? setting;
}

class ExtensionCommand {
  const ExtensionCommand(this.id, this.title, this.view);
  final String id, title, view;
}

class ExtensionSetting {
  const ExtensionSetting(this.id, this.title, this.defaultValue);
  final String id, title;
  final bool defaultValue;
}

class ExtensionManifest {
  ExtensionManifest._(
    this.raw,
    this.id,
    this.name,
    this.version,
    this.description,
    this.views,
    this.commands,
    this.settings,
  );
  final Map<String, dynamic> raw;
  final String id, name, version, description;
  final List<ExtensionView> views;
  final List<ExtensionCommand> commands;
  final List<ExtensionSetting> settings;
  static const allowedCapabilities = {
    'cards.summary',
    'workbench.views',
    'workbench.commands',
    'workbench.settings',
  };
  static ExtensionManifest parse(Map<String, dynamic> raw) {
    try {
      return _parse(raw);
    } on FormatException {
      rethrow;
    } on Object {
      throw const FormatException('扩展描述结构无效');
    }
  }

  static ExtensionManifest _parse(Map<String, dynamic> raw) {
    if (jsonEncode(raw).length > 65536) throw const FormatException('扩展描述过大');
    void keys(Map value, Set<String> allowed) {
      if (value.keys.any((k) => !allowed.contains(k))) {
        throw const FormatException('扩展包含不支持的字段或可执行能力');
      }
    }

    keys(raw, {
      'apiVersion',
      'id',
      'name',
      'version',
      'description',
      'capabilities',
      'views',
      'commands',
      'settings',
    });
    if (raw['apiVersion'] != 1) throw const FormatException('扩展 API 版本不兼容');
    String str(Map value, String key, {int max = 120}) {
      final v = value[key];
      if (v is! String || v.trim().isEmpty || v.length > max) {
        throw FormatException('扩展 $key 无效');
      }
      return v;
    }

    String identifier(Map value) {
      final id = str(value, 'id', max: 80);
      if (!RegExp(r'^[a-z][a-z0-9.-]*$').hasMatch(id)) {
        throw const FormatException('扩展标识只能使用小写字母、数字、点和短横线');
      }
      return id;
    }

    final id = identifier(raw), name = str(raw, 'name');
    final version = str(raw, 'version');
    if (!RegExp(r'^\d+\.\d+\.\d+$').hasMatch(version)) {
      throw const FormatException('扩展版本必须为三段数字');
    }
    final capabilities = (raw['capabilities'] as List?)?.cast<String>() ?? [];
    if (capabilities.any((c) => !allowedCapabilities.contains(c)) ||
        !capabilities.contains('cards.summary')) {
      throw const FormatException('扩展请求了不支持的权限');
    }
    List<Map<String, dynamic>> rows(String key) {
      final value = raw[key];
      if (value is! List || value.length > 20) {
        throw FormatException('扩展 $key 无效');
      }
      return value.map((v) => Map<String, dynamic>.from(v as Map)).toList();
    }

    final settings = <ExtensionSetting>[];
    for (final row in rows('settings')) {
      keys(row, {'id', 'title', 'type', 'default'});
      if (row['type'] != 'boolean' || row['default'] is! bool) {
        throw const FormatException('仅支持布尔扩展设置');
      }
      settings.add(
        ExtensionSetting(
          identifier(row),
          str(row, 'title'),
          row['default'] as bool,
        ),
      );
    }
    final views = <ExtensionView>[];
    for (final row in rows('views')) {
      keys(row, {'id', 'title', 'filter', 'setting'});
      final filter = Map<String, dynamic>.from(row['filter'] as Map);
      keys(filter, {'status', 'kind', 'tag', 'query'});
      if (filter.values.any((v) => v is! String || v.length > 200)) {
        throw const FormatException('扩展筛选无效');
      }
      if (filter['status'] != null &&
          !{
            'draft',
            'confirmed',
            'split',
            'archived',
          }.contains(filter['status'])) {
        throw const FormatException('卡片状态无效');
      }
      final setting = row['setting'] as String?;
      if (setting != null && !settings.any((s) => s.id == setting)) {
        throw const FormatException('扩展引用了未知设置');
      }
      views.add(
        ExtensionView(
          id: identifier(row),
          title: str(row, 'title'),
          filter: filter.cast<String, String>(),
          setting: setting,
        ),
      );
    }
    final commands = <ExtensionCommand>[];
    for (final row in rows('commands')) {
      keys(row, {'id', 'title', 'view'});
      final view = str(row, 'view');
      if (!views.any((v) => v.id == view)) {
        throw const FormatException('扩展命令引用了未知视图');
      }
      commands.add(ExtensionCommand(identifier(row), str(row, 'title'), view));
    }
    for (final ids in [
      views.map((v) => v.id),
      commands.map((v) => v.id),
      settings.map((v) => v.id),
    ]) {
      if (ids.toSet().length != ids.length) {
        throw const FormatException('扩展贡献标识重复');
      }
    }
    if (views.isEmpty ||
        !capabilities.contains('workbench.views') ||
        commands.isNotEmpty && !capabilities.contains('workbench.commands') ||
        settings.isNotEmpty && !capabilities.contains('workbench.settings')) {
      throw const FormatException('扩展贡献缺少对应能力');
    }
    return ExtensionManifest._(
      Map.unmodifiable(raw),
      id,
      name,
      version,
      raw['description'] as String? ?? '',
      views,
      commands,
      settings,
    );
  }
}

class InstalledExtension {
  InstalledExtension(
    this.manifest, {
    this.enabled = true,
    Map<String, bool>? settings,
  }) : settings = settings ?? {};
  final ExtensionManifest manifest;
  bool enabled;
  final Map<String, bool> settings;
  bool setting(String id) =>
      settings[id] ??
      manifest.settings.firstWhere((s) => s.id == id).defaultValue;
}

/// Descriptors are data interpreted by trusted core widgets. No eval, process,
/// network, filesystem or vault handle is passed to an extension contribution.
class ExtensionRegistry extends ChangeNotifier {
  ExtensionRegistry({required this.read, required this.write});
  final Future<String?> Function() read;
  final Future<void> Function(String) write;
  final installed = <String, InstalledExtension>{};
  Future<void> _pending = Future.value();
  Future<void> load() async {
    final raw = await read();
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
    installed
      ..clear()
      ..addAll(result);
    notifyListeners();
  }

  Future<void> _change(void Function() mutate) {
    final next = _pending.then((_) async {
      final previous = _encode();
      mutate();
      try {
        await write(_encode());
      } on Object {
        _restore(previous);
        rethrow;
      }
      notifyListeners();
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
    installed.clear();
    for (final row in (jsonDecode(value)['extensions'] as List)) {
      final manifest = ExtensionManifest.parse(
        Map<String, dynamic>.from(row['manifest'] as Map),
      );
      installed[manifest.id] = InstalledExtension(
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
    installed[manifest.id] = InstalledExtension(manifest);
  });
  Future<void> setEnabled(String id, bool enabled) =>
      _change(() => installed[id]!.enabled = enabled);
  Future<void> remove(String id) => _change(() => installed.remove(id));
  Future<void> setSetting(String id, String key, bool value) => _change(() {
    if (!installed[id]!.manifest.settings.any((s) => s.id == key)) {
      throw const FormatException('设置不存在');
    }
    installed[id]!.settings[key] = value;
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
