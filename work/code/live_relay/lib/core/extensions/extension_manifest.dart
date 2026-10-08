import 'dart:convert';

class ExtensionView {
  ExtensionView({
    required this.id,
    required this.title,
    required Map<String, String> filter,
    this.setting,
  }) : filter = Map.unmodifiable(filter);
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
  static Map<String, dynamic> _freezeMap(Map<String, dynamic> value) {
    Object? freeze(Object? v) => v is Map
        ? Map<String, dynamic>.unmodifiable({
            for (final e in v.entries) e.key as String: freeze(e.value),
          })
        : v is List
        ? List<Object?>.unmodifiable(v.map(freeze))
        : v;
    return freeze(value) as Map<String, dynamic>;
  }

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
      _freezeMap(raw),
      id,
      name,
      version,
      raw['description'] as String? ?? '',
      List.unmodifiable(views),
      List.unmodifiable(commands),
      List.unmodifiable(settings),
    );
  }
}

class InstalledExtension {
  InstalledExtension(
    this.manifest, {
    this.enabled = true,
    Map<String, bool>? settings,
  }) : settings = Map.unmodifiable(settings ?? {});
  final ExtensionManifest manifest;
  final bool enabled;
  final Map<String, bool> settings;
  InstalledExtension copyWith({bool? enabled, Map<String, bool>? settings}) =>
      InstalledExtension(
        manifest,
        enabled: enabled ?? this.enabled,
        settings: settings ?? this.settings,
      );
  bool setting(String id) =>
      settings[id] ??
      manifest.settings.firstWhere((s) => s.id == id).defaultValue;
}
