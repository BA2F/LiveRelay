import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../application/workbench/workbench_layout_state.dart';
export '../../../application/workbench/workbench_layout_state.dart'
    show DockPlacement, DockNode, DockGroup, DockSplit, FloatingDock;

class WorkbenchLayout extends ChangeNotifier {
  WorkbenchLayout({bool assistant = false})
    : state = WorkbenchLayoutState(assistant: assistant) {
    _subscription = state.changes.listen((_) => notifyListeners());
  }
  final WorkbenchLayoutState state;
  late final StreamSubscription<void> _subscription;
  DockNode get root => state.root;
  List<FloatingDock> get floating => state.floating;
  bool get assistant => state.assistant;
  Iterable<DockGroup> get groups => state.groups;
  DockGroup group(List<String> tabs) => state.group(tabs);
  void reset({required bool assistant}) => state.reset(assistant: assistant);
  DockGroup? find(String id) => state.find(id);
  DockGroup? containing(String view) => state.containing(view);
  void open(String view, {String? groupId}) =>
      state.open(view, groupId: groupId);
  void select(DockGroup group, String view) => state.select(group, view);
  void close(String view) => state.close(view);
  void move(String view, String targetId, DockPlacement placement) =>
      state.move(view, targetId, placement);
  void resize(DockSplit split, double value) => state.resize(split, value);
  void changed() => state.changed();
  Map<String, Object?> toJson() => state.toJson();
  void restore(Map<String, dynamic> data) => state.restore(data);
  @override
  void dispose() {
    unawaited(_subscription.cancel());
    state.dispose();
    super.dispose();
  }
}
