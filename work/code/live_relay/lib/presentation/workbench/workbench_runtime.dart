import 'dart:async';
import 'dart:convert';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/foundation.dart';

import '../controllers/app_controller.dart';
import '../../application/workbench/workspace_state_store.dart';
import '../controllers/agent_conversation.dart';
import 'state/card_edit_sessions.dart';
import 'state/extension_registry.dart';
import 'state/workbench_layout.dart';

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
    layout.addListener(_layoutChanged);
  }

  final AppController controller;
  final layout = WorkbenchLayout();
  late final CardEditSessions edits;
  late final ExtensionRegistry extensions;
  late final AgentConversation conversation;
  bool loaded = false;
  String? layoutError, exitError;
  bool _disposed = false, _restoring = true, _exiting = false;
  Timer? _layoutTimer;
  Future<void> _layoutWrite = Future.value();
  bool get _active => !_disposed && controller.isUnlocked;

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  Future<void> load({String? preset}) async {
    try {
      await conversation.load();
    } on Object {
      layoutError = '会话读取失败，原有加密记录保留';
    }
    if (!_active) return;
    try {
      await extensions.load();
    } on Object {
      layoutError = '扩展配置读取失败，原有配置保留';
    }
    if (!_active) return;
    try {
      final saved = await controller.readWorkbenchState();
      if (!_active) return;
      if (saved != null) {
        layout.restore(Map<String, dynamic>.from(jsonDecode(saved) as Map));
      } else {
        layout.reset(assistant: preset == 'assistant');
      }
    } on Object {
      layoutError = '已恢复默认布局；原有资料保留';
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
    final obsolete = layout.groups
        .expand((g) => g.tabs)
        .where((v) => v.startsWith('extension/') && !active.contains(v))
        .toList();
    for (final view in obsolete) {
      layout.close(view);
    }
    _changed();
  }

  void _layoutChanged() {
    if (_restoring || _disposed) return;
    _layoutTimer?.cancel();
    _layoutTimer = Timer(
      const Duration(milliseconds: 400),
      () => unawaited(persistLayout()),
    );
  }

  Future<void> persistLayout() {
    _layoutTimer?.cancel();
    final json = jsonEncode(layout.toJson());
    final next = _layoutWrite.then((_) async {
      if (!_active) return;
      try {
        await controller.writeWorkbenchState(json);
        if (_active) layoutError = null;
      } on Object {
        if (_active) layoutError = '布局保存失败，点击重试';
      }
      _changed();
    });
    _layoutWrite = next;
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
    await persistLayout();
    if (!_active) throw const FormatException('资料库已锁定');
    if (layoutError != null) throw const FormatException('布局未保存，请重试');
  }

  Future<void> saveAndLock() async {
    await flush();
    await controller.lock();
  }

  Future<void> resetLayout(
    String preset,
    Future<void> Function() savePreset,
  ) async {
    await flush();
    if (!_active) return;
    await savePreset();
    if (!_active) return;
    layout.reset(assistant: preset == 'assistant');
    await persistLayout();
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
    layout.removeListener(_layoutChanged);
    _layoutTimer?.cancel();
    edits.dispose();
    conversation.dispose();
    extensions.dispose();
    layout.dispose();
    super.dispose();
  }
}
