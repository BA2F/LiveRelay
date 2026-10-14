import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../application/workbench/workbench_tabs_state.dart';
export '../../../application/workbench/workbench_tabs_state.dart'
    show WorkbenchTabsState;

class WorkbenchTabs extends ChangeNotifier {
  WorkbenchTabs() : state = WorkbenchTabsState() {
    _subscription = state.changes.listen((_) => notifyListeners());
  }
  final WorkbenchTabsState state;
  late final StreamSubscription<void> _subscription;
  List<String> get tabs => state.tabs;
  String? get active => state.active;
  String get section => state.section;
  bool get collapsed => state.collapsed;
  bool get rightCollapsed => state.rightCollapsed;
  void reset() => state.reset();
  void open(String view) => state.open(view);
  void activate(String view) => state.activate(view);
  void close(String view) => state.close(view);
  void closeOthers(String view) => state.closeOthers(view);
  void closeAll() => state.closeAll();
  void move(String view, int index) => state.move(view, index);
  void selectSection(String value) => state.selectSection(value);
  void setCollapsed(bool value) => state.setCollapsed(value);
  void setRightCollapsed(bool value) => state.setRightCollapsed(value);
  Map<String, Object?> toJson() => state.toJson();
  void restore(Map<String, dynamic> data) => state.restore(data);
  @override
  void dispose() {
    unawaited(_subscription.cancel());
    state.dispose();
    super.dispose();
  }
}
