import 'package:flutter/foundation.dart';

/// Internal layout state. Stored inside the unlocked encrypted vault.
enum DockPlacement { center, left, right, top, bottom, floating }

sealed class DockNode {
  Map<String, Object?> toJson();
}

class DockGroup extends DockNode {
  DockGroup(this.id, this.tabs, [String? selected])
    : selected = selected ?? tabs.firstOrNull;
  final String id;
  final List<String> tabs;
  String? selected;
  @override
  Map<String, Object?> toJson() => {
    'type': 'group',
    'id': id,
    'tabs': tabs,
    'selected': selected,
  };
}

class DockSplit extends DockNode {
  DockSplit(this.vertical, this.first, this.second, [this.fraction = .5]);
  final bool vertical;
  DockNode first;
  DockNode second;
  double fraction;
  @override
  Map<String, Object?> toJson() => {
    'type': 'split',
    'vertical': vertical,
    'fraction': fraction,
    'first': first.toJson(),
    'second': second.toJson(),
  };
}

class FloatingDock {
  FloatingDock(
    this.group, {
    this.x = 100,
    this.y = 80,
    this.width = 560,
    this.height = 460,
  });
  final DockGroup group;
  double x, y, width, height;
  Map<String, Object?> toJson() => {
    'group': group.toJson(),
    'x': x,
    'y': y,
    'width': width,
    'height': height,
  };
}

class WorkbenchLayout extends ChangeNotifier {
  WorkbenchLayout({bool assistant = false}) {
    reset(assistant: assistant);
  }
  late DockNode root;
  final floating = <FloatingDock>[];
  int _serial = 0;
  bool assistant = false;
  String _id() => 'group-${DateTime.now().microsecondsSinceEpoch}-${_serial++}';
  DockGroup group(List<String> tabs) => DockGroup(_id(), tabs);
  void reset({required bool assistant}) {
    this.assistant = assistant;
    floating.clear();
    root = DockSplit(
      false,
      group([assistant ? 'agent' : 'cards']),
      group([
        assistant ? 'cards' : 'agent',
        'relations',
        'originals',
        'changes',
      ]),
      .65,
    );
    notifyListeners();
  }

  Iterable<DockGroup> _walk(DockNode node) sync* {
    if (node is DockGroup) {
      yield node;
    }
    if (node is DockSplit) {
      yield* _walk(node.first);
      yield* _walk(node.second);
    }
  }

  Iterable<DockGroup> get groups sync* {
    yield* _walk(root);
    for (final item in floating) {
      yield item.group;
    }
  }

  DockGroup? find(String id) => groups.where((g) => g.id == id).firstOrNull;
  DockGroup? containing(String view) =>
      groups.where((g) => g.tabs.contains(view)).firstOrNull;
  void open(String view, {String? groupId}) {
    final existing = containing(view);
    if (existing != null) {
      existing.selected = view;
    } else {
      final target = find(groupId ?? '') ?? _walk(root).first;
      target.tabs.add(view);
      target.selected = view;
    }
    notifyListeners();
  }

  void select(DockGroup group, String view) {
    group.selected = view;
    notifyListeners();
  }

  DockNode _prune(DockNode node) {
    if (node is! DockSplit) return node;
    node.first = _prune(node.first);
    node.second = _prune(node.second);
    if (node.first is DockGroup && (node.first as DockGroup).tabs.isEmpty) {
      return node.second;
    }
    if (node.second is DockGroup && (node.second as DockGroup).tabs.isEmpty) {
      return node.first;
    }
    return node;
  }

  void _remove(String view) {
    for (final g in groups) {
      g.tabs.remove(view);
      if (!g.tabs.contains(g.selected)) g.selected = g.tabs.firstOrNull;
    }
  }

  void close(String view) {
    _remove(view);
    root = _prune(root);
    floating.removeWhere((f) => f.group.tabs.isEmpty);
    notifyListeners();
  }

  DockNode _replace(DockNode node, String id, DockNode replacement) {
    if (node is DockGroup && node.id == id) return replacement;
    if (node is DockSplit) {
      node.first = _replace(node.first, id, replacement);
      node.second = _replace(node.second, id, replacement);
    }
    return node;
  }

  void move(String view, String targetId, DockPlacement placement) {
    final target = find(targetId);
    if (target == null && placement != DockPlacement.floating) return;
    _remove(view);
    if (placement == DockPlacement.floating) {
      floating.add(FloatingDock(group([view])));
    } else if (placement == DockPlacement.center) {
      target!.tabs.add(view);
      target.selected = view;
    } else {
      final added = group([view]);
      final before =
          placement == DockPlacement.left || placement == DockPlacement.top;
      final split = DockSplit(
        placement == DockPlacement.top || placement == DockPlacement.bottom,
        before ? added : target!,
        before ? target! : added,
      );
      // A floating group can be docked back via a main group's drop targets.
      // Splits within a floating panel are kept as tabs to avoid nested windows.
      if (floating.any((f) => f.group.id == targetId)) {
        target!.tabs.add(view);
        target.selected = view;
      } else {
        root = _replace(root, targetId, split);
      }
    }
    root = _prune(root);
    floating.removeWhere((f) => f.group.tabs.isEmpty);
    notifyListeners();
  }

  void resize(DockSplit split, double value) {
    split.fraction = value.clamp(.15, .85);
    notifyListeners();
  }

  void changed() => notifyListeners();
  Map<String, Object?> toJson() => {
    'version': 1,
    'assistant': assistant,
    'root': root.toJson(),
    'floating': floating.map((f) => f.toJson()).toList(),
  };
  void restore(Map<String, dynamic> data) {
    if (data['version'] != 1) throw const FormatException('布局版本不支持');
    final seen = <String>{};
    final groupIds = <String>{};
    DockNode parse(Map<String, dynamic> value, int depth) {
      if (depth > 12) throw const FormatException('布局层数过多');
      if (value['type'] == 'split') {
        final fraction = (value['fraction'] as num).toDouble();
        if (!fraction.isFinite) throw const FormatException('布局尺寸无效');
        return DockSplit(
          value['vertical'] == true,
          parse(Map<String, dynamic>.from(value['first'] as Map), depth + 1),
          parse(Map<String, dynamic>.from(value['second'] as Map), depth + 1),
          fraction.clamp(.15, .85),
        );
      }
      if (value['type'] != 'group') throw const FormatException('布局节点无效');
      final id = value['id'] as String;
      if (!groupIds.add(id)) throw const FormatException('布局组重复');
      final tabs = (value['tabs'] as List).cast<String>();
      if (tabs.length > 50 || tabs.any((t) => t.length > 250 || !seen.add(t))) {
        throw const FormatException('标签无效或重复');
      }
      final result = DockGroup(id, List.of(tabs));
      if (tabs.contains(value['selected'])) {
        result.selected = value['selected'] as String;
      }
      return result;
    }

    final parsed = parse(Map<String, dynamic>.from(data['root'] as Map), 0);
    final windows = <FloatingDock>[];
    for (final raw in (data['floating'] as List? ?? [])) {
      if (windows.length >= 12) throw const FormatException('浮动窗口过多');
      final f = Map<String, dynamic>.from(raw as Map);
      final g = parse(Map<String, dynamic>.from(f['group'] as Map), 0);
      if (g is! DockGroup) throw const FormatException('浮动组无效');
      double number(String key, double fallback) {
        final n = (f[key] as num?)?.toDouble() ?? fallback;
        if (!n.isFinite) throw const FormatException('浮动尺寸无效');
        return n;
      }

      windows.add(
        FloatingDock(
          g,
          x: number('x', 100),
          y: number('y', 80),
          width: number('width', 560).clamp(260, 2000),
          height: number('height', 460).clamp(180, 1600),
        ),
      );
    }
    root = _prune(parsed);
    floating
      ..clear()
      ..addAll(windows);
    assistant = data['assistant'] == true;
    notifyListeners();
  }
}
