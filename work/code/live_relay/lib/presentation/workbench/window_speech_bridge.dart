import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import '../../core/media/pcm_wave.dart';
import '../../core/speech/remote_speech_settings.dart';
import '../../core/domain/entities.dart';
import '../../core/ai/conversation_attachment.dart';
import '../controllers/app_controller.dart';
import '../controllers/agent_conversation.dart';
import '../contracts/preview_session.dart';
import '../controllers/speech_input_binding.dart';
import '../contracts/speech_access.dart';

Map<String, Object?> windowSpeech(AppController controller) {
  final s = controller.speech;
  if (s == null) return {'available': false};
  return {
    'available': true,
    'ready': s.ready,
    'supported': s.supported,
    'installed': s.installed,
    'busy': s.busy,
    'received': s.received,
    'total': s.total,
    'error': s.error,
    'remote': s.usingRemote,
    'name': s.remoteSettings.name,
    'host': Uri.tryParse(s.remoteSettings.endpoint)?.host ?? '',
    'model': s.remoteSettings.model,
    'configured': s.remoteSettings.configured,
  };
}

/// The owner keeps the exact prepared WAV and its one-use authorization scope.
class WindowSpeechBridge {
  WindowSpeechBridge(
    this.controller,
    this.conversation, {
    required this.active,
  });
  final AppController controller;
  final AgentConversation conversation;
  final bool Function() active;
  Uint8List? _wav;
  ConversationAttachment? _original;
  String? _ticket;
  int? _configuration;
  int _generation = 0;
  Future<Map<String, Object?>>? _work;
  final _saved = <String>{};
  Future<void>? _modelWork;
  static const methods = {
    'prepareSpeech',
    'recognizeSpeech',
    'discardSpeech',
    'cancelSpeech',
    'chooseSpeech',
    'downloadSpeech',
    'installSpeech',
    'removeSpeech',
    'cancelSpeechModel',
    'saveSpeechDraft',
    'speechBackfill',
  };

  void _check() {
    if (!active() || !controller.isUnlocked || controller.speech == null) {
      throw const FormatException('语音视图已关闭');
    }
  }

  void _discard() {
    _wav?.fillRange(0, _wav!.length, 0);
    _wav = null;
    _original?.wipe();
    _original = null;
    _ticket = null;
    _configuration = null;
  }

  Future<void> clear() async {
    _generation++;
    _discard();
    if (_work != null) controller.speech?.cancelTranscription();
    try {
      await _work;
    } on Object {
      /* The caller receives the failure. */
    }
    if (_modelWork != null) {
      await controller.speech?.cancel();
      try {
        await _modelWork;
      } on Object {
        /* Public service status retains failure. */
      }
    }
    _saved.clear();
  }

  void _startModel(Future<void> Function() operation) {
    if (_modelWork != null || controller.speech!.busy) {
      throw const FormatException('请等待当前语音操作完成');
    }
    final work = operation();
    _modelWork = work;
    unawaited(
      work.then((_) {}, onError: (Object _) {}).whenComplete(() {
        if (identical(_modelWork, work)) _modelWork = null;
      }),
    );
  }

  Future<dynamic> invoke(MethodCall call) async {
    _check();
    final s = controller.speech!;
    final a = call.arguments is Map ? call.arguments as Map : const {};
    switch (call.method) {
      case 'prepareSpeech':
        if (_work != null) throw const FormatException('请等待当前识别完成');
        _discard();
        final bytes = a['wav'];
        if (bytes is! Uint8List || bytes.length > 2 * 1024 * 1024) {
          throw const FormatException('音频超过识别范围');
        }
        PcmWave.validate(bytes);
        if (!s.ready || s.busy) throw const FormatException('语音服务尚未就绪');
        final raw = a['original'] ?? bytes;
        final name =
            a['originalName'] ??
            '语音-${DateTime.now().millisecondsSinceEpoch}.wav';
        if (raw is! Uint8List ||
            raw.length > 2 * 1024 * 1024 ||
            name is! String) {
          throw const FormatException('音频原件无效');
        }
        final owned = Uint8List.fromList(raw);
        late final ConversationAttachment source;
        try {
          source = ConversationAttachment.read(name, owned);
        } on Object {
          owned.fillRange(0, owned.length, 0);
          rethrow;
        }
        if (!{
          ConversationAttachmentKind.audio,
          ConversationAttachmentKind.video,
        }.contains(source.kind)) {
          source.wipe();
          throw const FormatException('请选择音频或视频原件');
        }
        _original = source;
        _wav = Uint8List.fromList(bytes);
        _ticket = const Uuid().v4();
        _configuration = s.configurationGeneration;
        return {
          'ticket': _ticket,
          'remote': s.usingRemote,
          'name': s.remoteSettings.name,
          'model': s.remoteSettings.model,
          'host': Uri.tryParse(s.remoteSettings.endpoint)?.host ?? '',
          'length': bytes.length,
        };
      case 'discardSpeech':
        if (a['ticket'] == _ticket) _discard();
      case 'cancelSpeech':
        _generation++;
        _discard();
        if (_work != null) s.cancelTranscription();
      case 'recognizeSpeech':
        if (_work != null ||
            a['ticket'] != _ticket ||
            _wav == null ||
            _configuration != s.configurationGeneration ||
            a['saveOriginal'] is! bool) {
          throw const FormatException('音频授权或服务配置已变化，请重新核对');
        }
        final wav = _wav!;
        final configuration = _configuration!;
        _wav = null;
        _ticket = null;
        _configuration = null;
        final generation = _generation;
        final original = a['saveOriginal'] == true ? _original : null;
        if (original == null) _original?.wipe();
        _original = null;
        final work = (() async {
          try {
            final text = await s.transcribe(
              wav,
              authorizedRemoteGeneration: s.usingRemote ? configuration : null,
            );
            _check();
            if (generation != _generation) throw const FormatException('识别已取消');
            String? blobId;
            if (original != null) {
              final card = await controller.importOriginal(
                bytes: Uint8List.fromList(original.bytes),
                originalName: original.name,
                mimeType: original.mimeType,
                mediaKind: original.kind == ConversationAttachmentKind.video
                    ? BlobMediaKind.video
                    : BlobMediaKind.audio,
              );
              _check();
              if (generation != _generation) {
                throw const FormatException('识别已取消');
              }
              blobId = (await controller.cardSources(card.id)).first.blobId;
              if (blobId != null) _saved.add(blobId);
            }
            _check();
            if (generation != _generation) throw const FormatException('识别已取消');
            return <String, Object?>{'text': text, 'blobId': blobId};
          } finally {
            wav.fillRange(0, wav.length, 0);
            original?.wipe();
          }
        })();
        _work = work;
        try {
          return await work;
        } finally {
          if (identical(_work, work)) _work = null;
        }
      case 'chooseSpeech':
        if (a['remote'] is! bool) throw const FormatException('识别提供方无效');
        _discard();
        await s.chooseRemote(a['remote'] as bool);
      case 'downloadSpeech':
        _startModel(s.download);
      case 'installSpeech':
        final path = a['path'];
        if (path is! String ||
            !path.startsWith('/') ||
            !path.endsWith('.bz2')) {
          throw const FormatException('请选择本机官方模型包');
        }
        _startModel(() => s.install(path));
      case 'removeSpeech':
        await s.remove();
      case 'cancelSpeechModel':
        await s.cancel();
      case 'saveSpeechDraft':
        final text = a['text'];
        final blobId = a['blobId'];
        if (text is! String ||
            text.trim().isEmpty ||
            text.length > 32000 ||
            (blobId != null && !_saved.contains(blobId))) {
          throw const FormatException('语音草稿或关联原件无效');
        }
        await controller.saveSpeechDraft(text, blobId: blobId as String?);
      case 'speechBackfill':
        final text = a['text'];
        if (text is! String ||
            text.trim().isEmpty ||
            text.length > 32000 ||
            conversation.working) {
          throw const FormatException('暂不能填入助手');
        }
        final draft = conversation.draft.isEmpty
            ? text
            : '${conversation.draft}\n$text';
        if (draft.length > 32000) throw const FormatException('助手输入过长，请先整理');
        conversation.updateDraft(draft);
      default:
        throw const FormatException('语音操作无效');
    }
    _check();
    return true;
  }
}

class RemoteSpeechInputBinding extends ChangeNotifier
    implements SpeechInputBinding, SpeechAccess {
  RemoteSpeechInputBinding(this.session, this.request);
  @override
  final PreviewSession session;
  final Future<dynamic> Function(String, Map<String, Object?>) request;
  Map _status = {};
  void update(Map status) {
    _status = status;
    notifyListeners();
  }

  @override
  SpeechAccess get speech => this;
  @override
  bool get usingRemote => _status['remote'] == true;
  @override
  bool get ready => _status['ready'] == true;
  @override
  bool get supported => _status['supported'] == true;
  @override
  bool get installed => _status['installed'] == true;
  @override
  bool get busy => _status['busy'] == true;
  @override
  int get received => _status['received'] as int? ?? 0;
  @override
  int? get total => _status['total'] as int?;
  @override
  String? get error => _status['error'] as String?;
  @override
  RemoteSpeechSettings get remoteSettings => RemoteSpeechSettings(
    name: _status['name'] as String? ?? '远程语音服务',
    endpoint: 'https://${_status['host'] ?? ''}',
    model: _status['model'] as String? ?? '',
    selected: usingRemote,
    hasApiKey: _status['configured'] == true,
  );
  @override
  Future<void> chooseRemote(bool remote) async {
    await request('chooseSpeech', {'remote': remote});
  }

  @override
  Future<void> download() async {
    await request('downloadSpeech', {});
  }

  @override
  Future<void> install(String path) async {
    await request('installSpeech', {'path': path});
  }

  @override
  Future<void> remove() async {
    await request('removeSpeech', {});
  }

  @override
  Future<void> cancel() async {
    await request('cancelSpeechModel', {});
  }

  @override
  void cancelTranscription() {
    unawaited(request('cancelSpeech', {}).catchError((_) => null));
  }

  @override
  Future<SpeechPreparation> prepare(
    Uint8List wav, {
    Uint8List? original,
    String? originalName,
  }) async {
    final d = await request('prepareSpeech', {
      'wav': wav,
      'original': ?original,
      'originalName': ?originalName,
    }) as Map;
    return SpeechPreparation(
      ticket: d['ticket'] as String,
      remote: d['remote'] == true,
      name: d['name'] as String,
      model: d['model'] as String,
      host: d['host'] as String,
      length: d['length'] as int,
    );
  }

  @override
  Future<SpeechRecognition> recognize(
    SpeechPreparation prepared, {
    required bool saveOriginal,
  }) async {
    final d = await request('recognizeSpeech', {
      'ticket': prepared.ticket,
      'saveOriginal': saveOriginal,
    }) as Map;
    return SpeechRecognition(d['text'] as String, d['blobId'] as String?);
  }

  @override
  Future<void> discard(SpeechPreparation prepared) async {
    await request('discardSpeech', {'ticket': prepared.ticket});
  }

  @override
  Future<void> saveDraft(String text, {String? blobId}) async {
    await request('saveSpeechDraft', {'text': text, 'blobId': blobId});
  }
}
