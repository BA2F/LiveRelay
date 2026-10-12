import 'dart:async';
import 'dart:convert';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/foundation.dart';

import '../controllers/app_controller.dart';
import '../../application/workbench/workspace_state_store.dart';
import '../controllers/agent_conversation.dart';
import 'state/card_edit_sessions.dart';
import 'state/extension_registry.dart';
import 'state/workbench_tabs.dart';

/// One owner for desktop sessions and persistence, independent of the view tree.
class WorkbenchRuntime extends ChangeNotifier {
  WorkbenchRuntime(this.controller) {
    conversation = AgentConversation(controller);
    extensions = ExtensionRegistry(
      read: () => controller.workspaceState.read(WorkspaceRecord.extensions),
      write: (value) =>
          controller.workspaceState.write(WorkspaceRecord.extensions, value),
    );
    edits = CardEditSessions(
      save: (id, draft) => controller.records
          .updateCard(id, draft, changeNote: '工作台自动保存')
          .then((_) {}),
      canSave: () => controller.isUnlocked && !controller.isBusy,
    );
    controller.addListener(_controllerChanged);
    extensions.addListener(_extensionsChanged);
    tabs.addListener(_tabsChanged);
  }

  final AppController controller;
  final tabs = WorkbenchTabs();
  late final CardEditSessions edits;
  late final ExtensionRegistry extensions;
  late final AgentConversation conversation;
  bool loaded = false;
  String? notice, persistError, exitError;
  bool _disposed = false, _restoring = true, _exiting = false;
  Timer? _tabsTimer;
  Future<void> _tabsWrite = Future.value();
  bool get _active => !_disposed && controller.isUnlocked;

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  Future<void> load() async {
    try {
      await conversation.load();
    } on Object {
      notice = '会话读取失败，原有加密记录保留';
    }
    if (!_active) return;
    try {
      await extensions.load();
    } on Object {
      notice = '扩展配置读取失败，原有配置保留';
    }
    if (!_active) return;
    try {
      final saved = await controller.readWorkbenchState();
      if (!_active) return;
      if (saved != null) {
        tabs.restore(Map<String, dynamic>.from(jsonDecode(saved) as Map));
      } else {
        tabs.reset();
      }
    } on Object {
      // 旧版停靠布局或损坏的标签记录：回到默认标签，资料不受影响。
      tabs.reset();
    }
    if (!_active) return;
    loaded = true;
    _restoring = false;
    _changed();
  }

  void _controllerChanged() {
    if (!controller.isUnlocked) {
      edits.clear();
    } else {
      edits.synchronize(controller.cards);
    }
  }

  void _extensionsChanged() {
    final active = extensions.views.keys.toSet();
    final obsolete = tabs.tabs
        .where((v) => v.startsWith('extension/') && !active.contains(v))
        .toList();
    for (final view in obsolete) {
      tabs.close(view);
    }
    _changed();
  }

  void _tabsChanged() {
    if (_restoring || _disposed) return;
    _tabsTimer?.cancel();
    _tabsTimer = Timer(
      const Duration(milliseconds: 400),
      () => unawaited(persistTabs()),
    );
  }

  Future<void> persistTabs() {
    _tabsTimer?.cancel();
    final json = jsonEncode(tabs.toJson());
    final next = _tabsWrite.then((_) async {
      if (!_active) return;
      try {
        await controller.writeWorkbenchState(json);
        if (_active) {
          persistError = null;
          notice = null;
        }
      } on Object {
        if (!_active) return;
        // 与卡片自动保存等写入并发时资料库可能正忙：稍后重试，不当作失败。
        if (controller.isBusy) {
          _tabsTimer?.cancel();
          _tabsTimer = Timer(
            const Duration(milliseconds: 500),
            () => unawaited(persistTabs()),
          );
        } else {
          persistError = '工作台状态保存失败，点击重试';
        }
      }
      _changed();
    });
    _tabsWrite = next;
    return next;
  }

  Future<void> flush() async {
    if (!_active) throw const FormatException('资料库已锁定');
    await _saveState();
  }

  Future<void> _saveState() async {
    if (!loaded) throw const FormatException('工作台正在恢复，请稍后重试');
    await edits.flush();
    if (edits.hasUnsaved) throw const FormatException('仍有修改未保存，请重试保存');
    await conversation.flush();
    await persistTabs();
    if (!_active) throw const FormatException('资料库已锁定');
    if (persistError != null) {
      throw const FormatException('工作台状态未保存，请重试');
    }
  }

  Future<void> saveAndLock() async {
    await flush();
    await controller.lock();
  }

  Future<AppExitResponse> requestExit() async {
    exitError = null;
    if (_exiting || controller.isBusy || (controller.speech?.busy ?? false)) {
      controller.cancelAgentTask();
      return AppExitResponse.cancel;
    }
    _exiting = true;
    try {
      controller.cancelAgentTask();
      for (final cleanup in List.of(controller.exitCleanups)) {
        await cleanup();
      }
      await _saveState();
      return AppExitResponse.exit;
    } on Object {
      exitError = '退出已取消，请重试保存后关闭窗口';
      _changed();
      return AppExitResponse.cancel;
    } finally {
      _exiting = false;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    controller.removeListener(_controllerChanged);
    extensions.removeListener(_extensionsChanged);
    tabs.removeListener(_tabsChanged);
    _tabsTimer?.cancel();
    edits.dispose();
    conversation.dispose();
    extensions.dispose();
    tabs.dispose();
    super.dispose();
  }
}
