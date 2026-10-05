import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../infrastructure/desktop_window_channel.dart';

import 'package:flutter/services.dart';

import '../../application/app_controller.dart';
import '../../application/agent/agent_conversation.dart';
import '../../application/workbench/card_edit_sessions.dart';
import '../../application/workbench/window_projection.dart';
import '../../core/domain/entities.dart';

class DetachedWorkbenchSession {
  DetachedWorkbenchSession(this.view, this.channel, this.window, this.bounds);
  String view;
  final LocalWindowChannel channel;
  final PresentationWindow window;
  Map<String, double>? bounds;
  bool closed = false;
}

/// The only vault owner remains the main engine. Child engines exchange typed
/// projections and commands through a separate paired channel per window.
class NativeWindowHost {
  NativeWindowHost({
    required this.controller,
    required this.edits,
    required this.conversation,
    required this.onDock,
    required this.onSend,
    this.diagnostics = false,
  }) {
    controller.addListener(_changed);
    edits.addListener(_changed);
    conversation.addListener(_changed);
  }
  final AppController controller;
  final CardEditSessions edits;
  final AgentConversation conversation;
  final void Function(String) onDock;
  final Future<void> Function() onSend;
  final bool diagnostics;
  final sessions = <DetachedWorkbenchSession>[];
  bool _disposed = false, _unlocked = true;
  int _version = 0, _epoch = 0;
  int _opening = 0;
  Timer? _timer;
  Future<void> _writes = Future.value();
  Future<void>? _shutdown;

  Future<void> restore() async {
    if (!Platform.isLinux) return;
    final raw = await controller.readWorkbenchWindows();
    if (raw == null) return;
    final data = jsonDecode(raw) as Map;
    if (data['version'] != 1 ||
        data['windows'] is! List ||
        (data['windows'] as List).length > 8) {
      throw const FormatException('独立窗口布局记录无效');
    }
    for (final entry in data['windows'] as List) {
      if (!controller.isUnlocked || _disposed) return;
      final view = entry['view'] as String;
      if (!detachableView(view)) continue;
      await open(view, bounds: windowBounds(entry['bounds']));
    }
  }

  Future<DetachedWorkbenchSession> open(
    String view, {
    Map<String, double>? bounds,
  }) async {
    if (_disposed ||
        !controller.isUnlocked ||
        !Platform.isLinux ||
        !detachableView(view)) {
      throw const FormatException('此视图暂不能移到独立窗口');
    }
    if (sessions.length + _opening >= 8) {
      throw const FormatException('最多打开8个独立窗口');
    }
    _opening++;
    final epoch = _epoch;
    DetachedWorkbenchSession? session;
    PresentationWindow? window;
    try {
      window = await PresentationWindow.create(
        bounds: bounds,
        diagnostics: diagnostics,
        handler: (call) async {
          while (session == null && !_disposed && epoch == _epoch) {
            await Future<void>.delayed(const Duration(milliseconds: 10));
          }
          final s = session;
          if (s == null ||
              s.closed ||
              _disposed ||
              epoch != _epoch ||
              !controller.isUnlocked) {
            throw PlatformException(code: 'SESSION_REVOKED');
          }
          return _handle(s, call, epoch);
        },
      );
      session = DetachedWorkbenchSession(view, window.channel, window, bounds);
      sessions.add(session);
      final active = session;
      window.process.exitCode.then((_) {
        if (!active.closed && !_disposed && controller.isUnlocked) {
          active.closed = true;
          sessions.remove(active);
          onDock(active.view);
          unawaited(_persist().catchError((_) {}));
        }
      });
      if (epoch != _epoch || _disposed || !controller.isUnlocked) {
        await window.hide();
        throw const FormatException('窗口会话已撤销');
      }
      await window.show();
      await _persist();
      return session;
    } on Object {
      final s = session;
      if (s != null) {
        s.closed = true;
        sessions.remove(s);
        try {
          await s.window.hide();
        } on Object {
          /* startup failed */
        }
      }
      window?.channel.close();
      await window?.stop();
      rethrow;
    } finally {
      _opening--;
    }
  }

  void _changed() {
    if (_disposed) return;
    _version++;
    if (!controller.isUnlocked && _unlocked) {
      _unlocked = false;
      _epoch++;
      unawaited(shutdown(preserve: true));
      return;
    }
    if (controller.isUnlocked) _unlocked = true;
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 50), () {
      for (final s in List.of(sessions)) {
        if (!s.closed) {
          unawaited(
            s.channel.invokeMethod('invalidate').catchError((_) => null),
          );
        }
      }
    });
  }

  Future<dynamic> _handle(
    DetachedWorkbenchSession s,
    MethodCall call,
    int epoch,
  ) async {
    final a = call.arguments is Map ? call.arguments as Map : const {};
    final id = a['id'] as String?;
    LifeCard card() =>
        controller.cards.where((c) => c.id == id).firstOrNull ??
        (throw const FormatException('卡片已不存在'));
    switch (call.method) {
      case 'health':
        return {'epoch': epoch};
      case 'snapshot':
        return _snapshot(s, epoch);
      case 'navigate':
        final view = a['view'] as String;
        if (!detachableView(view)) throw const FormatException('不支持的视图');
        s.view = view;
        _version++;
        await _persist();
      case 'edit':
        if (!{'title', 'content', 'tags'}.contains(a['field']) ||
            a['text'] is! String ||
            (a['text'] as String).length > 32000) {
          throw const FormatException('编辑内容无效');
        }
        final edit = edits.session(card());
        final text = a['text'] as String;
        edits.edit(
          edit,
          title: a['field'] == 'title' ? text : null,
          content: a['field'] == 'content' ? text : null,
          tags: a['field'] == 'tags' ? text : null,
        );
      case 'flush':
        await edits.flush();
        await conversation.flush();
        if (edits.hasUnsaved) throw const FormatException('修改尚未保存，请重试');
      case 'confirm':
        card();
        await edits.flush();
        if (edits.hasUnsaved) throw const FormatException('请先保存修改');
        await controller.confirmCard(id!);
      case 'delete':
        card();
        await edits.flush();
        if (edits.hasUnsaved) throw const FormatException('请先保存修改');
        await controller.trashCard(id!);
      case 'restoreRevision':
        card();
        await edits.flush();
        if (edits.hasUnsaved) throw const FormatException('请先保存修改');
        await controller.restoreCardRevision(id!, a['number'] as int);
      case 'references':
        card();
        await controller.setCardReferences(
          id!,
          (a['targets'] as List).cast<String>(),
        );
      case 'draft':
        if (a['text'] is! String || (a['text'] as String).length > 32000) {
          throw const FormatException('输入过长');
        }
        conversation.updateDraft(a['text'] as String);
      case 'send':
        await onSend();
      case 'editSuggestion':
        final m = conversation.messages
            .where((m) => m.reviewId == a['reviewId'])
            .firstOrNull;
        if (m == null ||
            a['text'] is! String ||
            (a['text'] as String).length > 32000) {
          throw const FormatException('建议已失效');
        }
        final index = a['index'] as int;
        if (index < 0 ||
            index >= m.suggestions.length ||
            !{'title', 'content'}.contains(a['field'])) {
          throw const FormatException('建议字段无效');
        }
        conversation.editSuggestion(
          m,
          index,
          title: a['field'] == 'title' ? a['text'] as String : null,
          content: a['field'] == 'content' ? a['text'] as String : null,
        );
      case 'accept':
        final m = conversation.messages
            .where((m) => m.reviewId == a['reviewId'])
            .firstOrNull;
        if (m == null) throw const FormatException('建议已失效');
        if (m.actions.any((a) => a.hasChanges)) {
          throw const FormatException('此建议包含操作计划，请合并到主工作台核对并确认');
        }
        await conversation.accept(m);
      case 'geometry':
        final bounds = windowBounds(a);
        if (bounds == null) throw const FormatException('窗口位置无效');
        s.bounds = bounds;
        await _persist();
      case 'close':
        await edits.flush();
        await conversation.flush();
        if (edits.hasUnsaved) throw const FormatException('修改尚未保存');
        s.closed = true;
        sessions.remove(s);
        onDock(s.view);
        await _persist();
        // Keep the handler until the child's final response has been delivered.
        unawaited(
          Future<void>.delayed(
            const Duration(milliseconds: 200),
            () => s.channel.setMethodCallHandler(null),
          ),
        );
        return true;
      default:
        throw PlatformException(code: 'UNSUPPORTED_COMMAND');
    }
    if (_disposed || epoch != _epoch || !controller.isUnlocked) {
      throw PlatformException(code: 'SESSION_REVOKED');
    }
    return true;
  }

  Future<Map<String, Object?>> _snapshot(
    DetachedWorkbenchSession s,
    int epoch,
  ) async {
    final version = _version;
    final selectedId = s.view.split('/').elementAtOrNull(1);
    final cards = s.view.startsWith('card/') || s.view.startsWith('history/')
        ? controller.cards.where((c) => c.id == selectedId).toList()
        : {'cards', 'relations', 'changes'}.contains(s.view)
        ? controller.cards
        : <LifeCard>[];
    final projected = [
      for (final c in cards) projectWindowCard(c, edits.session(c)),
    ];
    final sources = <String, Object?>{};
    for (final c in cards) {
      final entries = await controller.currentCardSources(c.id);
      sources[c.id] = [
        for (final source in entries)
          {'id': source.blobId, 'text': source.excerpt, 'label': source.label},
      ];
    }
    final data = <String, Object?>{
      'version': version,
      'view': s.view,
      'cards': projected,
      'sources': sources,
      'references': [
        for (final r in controller.cardReferences)
          if (cards.any((c) => c.id == r.from || c.id == r.to))
            {'from': r.from, 'to': r.to},
      ],
      'titles': {for (final c in controller.cards) c.id: c.title},
    };
    if (s.view == 'originals') {
      data['originals'] = [
        for (final b in controller.blobs.where(
          (b) => !controller.recycledBlobIds.contains(b.id),
        ))
          {
            'id': b.id,
            'name': b.originalName,
            'kind': b.mediaKind.name,
            'size': b.byteLength,
          },
      ];
    }
    if (s.view.startsWith('source/')) {
      final b = controller.blobs
          .where(
            (b) =>
                b.id == selectedId &&
                !controller.recycledBlobIds.contains(b.id),
          )
          .firstOrNull;
      if (b != null) {
        data['source'] = {
          'id': b.id,
          'name': b.originalName,
          'kind': b.mediaKind.name,
          'mime': b.mimeType,
        };
        if ((b.mediaKind == BlobMediaKind.image ||
                b.mimeType.startsWith('text/')) &&
            b.byteLength <= 8 * 1024 * 1024) {
          final bytes = await controller.readOriginal(b.id);
          try {
            data['sourceBytes'] = Uint8List.fromList(bytes);
          } finally {
            bytes.fillRange(0, bytes.length, 0);
          }
        }
      }
    }
    if (s.view.startsWith('history/')) {
      data['history'] = [
        for (final r in await controller.cardHistory(selectedId!))
          {
            'number': r.number,
            'title': r.title,
            'content': r.content,
            'note': r.changeNote,
            'time': r.createdAt.toIso8601String(),
          },
      ];
    }
    if (s.view == 'agent') {
      data['draft'] = conversation.draft;
      data['working'] = conversation.working;
      data['model'] = controller.aiSettings.model;
      data['error'] = conversation.error;
      data['messages'] = [
        for (final m in conversation.messages)
          {
            'role': m.role,
            'text': m.text,
            'reviewId': m.reviewId,
            'accepted': m.accepted,
            'hasActions': m.actions.any((a) => a.hasChanges),
            'suggestions': [
              for (final c in m.suggestions)
                {'title': c.title, 'content': c.content},
            ],
          },
      ];
    }
    if (_disposed || epoch != _epoch || !controller.isUnlocked || s.closed) {
      final bytes = data['sourceBytes'];
      if (bytes is Uint8List) bytes.fillRange(0, bytes.length, 0);
      throw PlatformException(code: 'SESSION_REVOKED');
    }
    return data;
  }

  Future<void> _persist() {
    final json = jsonEncode({
      'version': 1,
      'windows': [
        for (final s in sessions.where((s) => !s.closed))
          {'view': s.view, 'bounds': s.bounds},
      ],
    });
    final next = _writes.then((_) async {
      if (controller.isUnlocked && !_disposed) {
        await controller.writeWorkbenchWindows(json);
      }
    });
    _writes = next.catchError((_) {});
    return next;
  }

  Future<void> shutdown({bool preserve = false}) {
    final existing = _shutdown;
    if (existing != null) return existing;
    final next = _shutdownWindows(preserve);
    _shutdown = next;
    return next.whenComplete(() => _shutdown = null);
  }

  Future<void> _shutdownWindows(bool preserve) async {
    _timer?.cancel();
    if (!preserve && controller.isUnlocked) await _persist();
    for (final s in List.of(sessions)) {
      s.closed = true;
      try {
        await s.channel
            .invokeMethod('revoke')
            .timeout(const Duration(seconds: 2));
      } on Object {
        try {
          await s.window.hide();
        } on Object {
          /* already closed */
        }
      }
      await s.window.stop();
      s.channel.close();
    }
    sessions.clear();
    if (!preserve && controller.isUnlocked && !_disposed) await _persist();
  }

  Future<void> flushChildren() async {
    for (final s in List.of(sessions)) {
      if (!s.closed) {
        await s.channel
            .invokeMethod('prepareClose')
            .timeout(const Duration(seconds: 5));
      }
    }
    await _writes;
  }

  void dispose() {
    controller.removeListener(_changed);
    edits.removeListener(_changed);
    conversation.removeListener(_changed);
    _disposed = true;
    _epoch++;
    unawaited(shutdown(preserve: true));
  }
}
