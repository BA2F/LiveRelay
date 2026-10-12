import 'dart:async';

/// 桌面标签状态：打开的对象、顺序、当前标签与左栏选择。
/// 只保存对象引用（view id），内容仍由各自的数据源提供。
class WorkbenchTabsState {
  WorkbenchTabsState() {
    reset();
  }
  static const sections = [
    'inbox',
    'cards',
    'originals',
    'passwords',
    'recycle',
  ];
  final _changes = StreamController<void>.broadcast();
  Stream<void> get changes => _changes.stream;
  void _changed() {
    if (!_changes.isClosed) _changes.add(null);
  }

  final tabs = <String>[];
  String? active;
  String section = 'inbox';
  bool collapsed = false;

  void reset() {
    tabs.clear();
    active = null;
    section = 'inbox';
    collapsed = false;
    _changed();
  }

  /// 打开对象：已在标签中则切到该标签，否则追加为新标签。
  void open(String view) {
    if (view.isEmpty) return;
    if (!tabs.contains(view)) tabs.add(view);
    active = view;
    _changed();
  }

  void activate(String view) {
    if (active == view || !tabs.contains(view)) return;
    active = view;
    _changed();
  }

  /// 关闭标签：关掉当前标签后选它右侧的标签，没有则选左侧。
  void close(String view) {
    final index = tabs.indexOf(view);
    if (index < 0) return;
    tabs.removeAt(index);
    if (active == view) {
      active = tabs.isEmpty ? null : tabs[index.clamp(0, tabs.length - 1)];
    }
    _changed();
  }

  void closeOthers(String view) {
    if (!tabs.contains(view)) return;
    tabs
      ..clear()
      ..add(view);
    active = view;
    _changed();
  }

  void closeAll() {
    if (tabs.isEmpty && active == null) return;
    tabs.clear();
    active = null;
    _changed();
  }

  /// 拖动排序：把 [view] 移到列表的 [index] 位置。
  void move(String view, int index) {
    final from = tabs.indexOf(view);
    if (from < 0) return;
    final target = index.clamp(0, tabs.length - 1);
    if (from == target) return;
    tabs.removeAt(from);
    tabs.insert(target, view);
    _changed();
  }

  void selectSection(String value) {
    if (section == value || !sections.contains(value)) return;
    section = value;
    _changed();
  }

  void setCollapsed(bool value) {
    if (collapsed == value) return;
    collapsed = value;
    _changed();
  }

  Map<String, Object?> toJson() => {
    'version': 2,
    'tabs': List.of(tabs),
    'active': active,
    'section': section,
    'collapsed': collapsed,
  };

  /// 解析失败时抛 FormatException，且不改动当前状态；
  /// 由调用方决定回落到默认值还是保留现状。
  void restore(Map<String, dynamic> data) {
    if (data['version'] != 2) throw const FormatException('标签记录版本不支持');
    final raw = data['tabs'];
    if (raw is! List || raw.length > 50) {
      throw const FormatException('标签记录无效');
    }
    final parsed = <String>[];
    final seen = <String>{};
    for (final value in raw) {
      if (value is! String ||
          value.isEmpty ||
          value.length > 250 ||
          !seen.add(value)) {
        throw const FormatException('标签无效或重复');
      }
      parsed.add(value);
    }
    final activeValue = data['active'];
    final sectionValue = data['section'];
    tabs
      ..clear()
      ..addAll(parsed);
    active = activeValue is String && parsed.contains(activeValue)
        ? activeValue
        : parsed.firstOrNull;
    section = sectionValue is String && sections.contains(sectionValue)
        ? sectionValue
        : 'inbox';
    collapsed = data['collapsed'] == true;
    _changed();
  }

  void dispose() {
    unawaited(_changes.close());
  }
}
