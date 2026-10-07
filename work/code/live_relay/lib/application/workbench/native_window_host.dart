import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../infrastructure/desktop_window_channel.dart';

import 'package:flutter/services.dart';

import '../app_controller.dart';
import '../agent/agent_conversation.dart';
import 'card_edit_sessions.dart';
import 'window_projection.dart';
import 'window_source_reader.dart';
import 'window_review_reader.dart';
import 'window_conversation_bridge.dart';
import 'window_extension_bridge.dart';
import 'extension_registry.dart';
import '../../core/domain/entities.dart';

class DetachedWorkbenchSession {
  DetachedWorkbenchSession(this.view, this.channel, this.window, this.bounds);
  String view;
  final LocalWindowChannel channel;
  final PresentationWindow window;
  Map<String, double>? bounds;
  bool closed = false;
  WindowReviewReader? reviewReader;
  WindowConversationBridge? conversationBridge;
}

/// The only vault owner remains the main process. Child windows exchange bounded
/// projections and commands through a separate paired channel per window.
class NativeWindowHost {
  NativeWindowHost({
    required this.controller,
    required this.edits,
    required this.conversation,
    required this.onDock,
    this.extensions,
    this.diagnostics = false,
  }) {
    controller.addListener(_changed);
    edits.addListener(_changed);
    conversation.addListener(_changed);
    extensions?.addListener(_changed);
  }
  final AppController controller;
  final CardEditSessions edits;
  final AgentConversation conversation;
  final ExtensionRegistry? extensions;
  bool _supported(String view) =>
      detachableView(view) &&
      (!view.startsWith('extension/') ||
          (extensions?.views.containsKey(view) ?? false));
  final void Function(String) onDock;
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
      if (!_supported(view)) continue;
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
        !_supported(view)) {
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
      window.process.exitCode.then((_) async {
        active.conversationBridge?.clear();
        await active.reviewReader?.clear();
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
        s.conversationBridge?.clear();
        await s.reviewReader?.clear();
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
    var redirected = false;
    for (final s in sessions) {
      if (s.view.startsWith('extension/') &&
          !(extensions?.views.containsKey(s.view) ?? false)) {
        s.view = 'extensions';
        redirected = true;
      }
    }
    if (redirected && controller.isUnlocked) {
      unawaited(_persist().catchError((_) {}));
    }
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
    if (WindowExtensionBridge.methods.contains(call.method)) {
      final registry = extensions;
      if (registry == null) throw const FormatException('扩展管理未就绪');
      await WindowExtensionBridge(
        registry,
        active: () =>
            !_disposed &&
            epoch == _epoch &&
            controller.isUnlocked &&
            !s.closed &&
            s.view == 'extensions',
      ).invoke(call);
      return true;
    }
    if (WindowConversationBridge.methods.contains(call.method)) {
      if (s.view != 'agent') throw const FormatException('请在助手视图操作');
      final bridge = s.conversationBridge ??= WindowConversationBridge(
        conversation,
        active: () =>
            !_disposed && epoch == _epoch && !s.closed && s.view == 'agent',
      );
      return bridge.invoke(call);
    }
    switch (call.method) {
      case 'health':
        return {'epoch': epoch};
      case 'snapshot':
        return _snapshot(s, epoch);
      case 'readSource':
        if (id == null) throw const FormatException('请选择原件');
        return WindowSourceReader(controller).read(
          id: id,
          view: () => s.view,
          active: () => !_disposed && epoch == _epoch && !s.closed,
        );
      case 'readReview':
        if (id == null || a['offset'] is! int) {
          throw const FormatException('确认来源读取范围无效');
        }
        final reader = s.reviewReader ??= WindowReviewReader(
          load: controller.cardReviewSource,
          allowed: (cardId) =>
              !_disposed &&
              epoch == _epoch &&
              !s.closed &&
              controller.isUnlocked &&
              s.view == 'review/$cardId' &&
              controller.cards.any((c) => c.id == cardId && !c.isDeleted),
        );
        return reader.readChunk(id, a['offset'] as int);
      case 'navigate':
        final view = a['view'] as String;
        if (!_supported(view)) throw const FormatException('不支持的视图');
        s.conversationBridge?.clear();
        s.view = view;
        s.conversationBridge?.clear();
        await s.reviewReader?.clear();
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
      case 'openMain':
        if (!{'settings', 'speech'}.contains(a['view'])) {
          throw const FormatException('入口无效');
        }
        onDock(a['view'] as String);
      case 'newCard':
        if (s.view != 'agent') throw const FormatException('请在助手视图新建');
        final existing = controller.cards.map((c) => c.id).toSet();
        await controller.createCard(
          const CardDraft(title: '新卡片', content: '', status: CardStatus.draft),
        );
        final created = controller.cards
            .where((c) => !existing.contains(c.id))
            .firstOrNull;
        if (created != null) {
          s.view = 'card/${created.id}';
          _version++;
          await _persist();
        }
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
        s.conversationBridge?.clear();
        await s.reviewReader?.clear();
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
    final registry = extensions;
    if (registry != null) {
      data['commands'] = [
        for (final command in registry.commands)
          {'id': command.id, 'title': command.title, 'view': command.view},
      ];
      if (s.view == 'extensions') {
        data['extensions'] = windowExtensions(registry);
      }
      if (s.view.startsWith('extension/')) {
        final sourced = <String>{};
        for (final c in controller.cards) {
          if ((await controller.currentCardSources(c.id))
              .any((source) => source.blobId != null)) {
            sourced.add(c.id);
          }
        }
        data['contributed'] = [
          for (final c in registry.filter(
            s.view,
            controller.findInformationCards(''),
            sourced,
          ))
            {'id': c.recordId, 'title': c.title, 'preview': c.preview},
        ];
      }
    }
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
          'size': b.byteLength,
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
      final bridge = s.conversationBridge ??= WindowConversationBridge(
        conversation,
        active: () =>
            !_disposed && epoch == _epoch && !s.closed && s.view == 'agent',
      );
      data.addAll(bridge.snapshot());
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
      s.conversationBridge?.clear();
      await s.reviewReader?.clear();
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
    extensions?.removeListener(_changed);
    _disposed = true;
    _epoch++;
    unawaited(shutdown(preserve: true));
  }
}
