import 'dart:typed_data';

import 'speech_access.dart';
import '../core/domain/entities.dart';
import 'app_controller.dart';
import 'preview_session.dart';

class SpeechPreparation {
  const SpeechPreparation({
    required this.ticket,
    required this.remote,
    required this.name,
    required this.model,
    required this.host,
    required this.length,
  });
  final String ticket, name, model, host;
  final bool remote;
  final int length;
}

class SpeechRecognition {
  const SpeechRecognition(this.text, this.blobId);
  final String text;
  final String? blobId;
}

abstract class SpeechInputBinding {
  PreviewSession get session;
  SpeechAccess? get speech;
  Future<SpeechPreparation> prepare(Uint8List wav);
  Future<SpeechRecognition> recognize(
    SpeechPreparation prepared, {
    required bool saveOriginal,
  });
  Future<void> discard(SpeechPreparation prepared);
  Future<void> saveDraft(String text, {String? blobId});
}

/// Main/mobile composition. Bytes remain owned by the page until recognition.
class LocalSpeechInputBinding implements SpeechInputBinding {
  LocalSpeechInputBinding(this.controller);
  final AppController controller;
  Uint8List? _wav;
  SpeechPreparation? _prepared;
  int? _configuration;
  @override
  PreviewSession get session => controller;
  @override
  SpeechAccess? get speech => controller.speech;
  @override
  Future<SpeechPreparation> prepare(Uint8List wav) async {
    final service = controller.speech!;
    _wav = wav;
    _configuration = service.configurationGeneration;
    final settings = service.remoteSettings;
    return _prepared = SpeechPreparation(
      ticket: 'local',
      remote: service.usingRemote,
      name: settings.name,
      model: settings.model,
      host: Uri.tryParse(settings.endpoint)?.host ?? '',
      length: wav.length,
    );
  }

  @override
  Future<SpeechRecognition> recognize(
    SpeechPreparation prepared, {
    required bool saveOriginal,
  }) async {
    final service = controller.speech!;
    final wav = _wav;
    if (!controller.isUnlocked ||
        !identical(_prepared, prepared) ||
        wav == null ||
        service.configurationGeneration != _configuration) {
      throw const FormatException('语音配置或识别范围已变化，请重新核对');
    }
    final configuration = _configuration!;
    _prepared = null;
    _wav = null;
    String? blobId;
    if (saveOriginal) {
      final original = await controller.importOriginal(
        bytes: Uint8List.fromList(wav),
        originalName: '语音-${DateTime.now().millisecondsSinceEpoch}.wav',
        mimeType: 'audio/wav',
        mediaKind: BlobMediaKind.audio,
      );
      if (!controller.isUnlocked) throw const FormatException('资料库已锁定');
      blobId = (await controller.cardSources(original.id)).first.blobId;
    }
    final text = await service.transcribe(
      wav,
      authorizedRemoteGeneration: prepared.remote ? configuration : null,
    );
    if (!controller.isUnlocked) throw const FormatException('资料库已锁定');
    return SpeechRecognition(text, blobId);
  }

  @override
  Future<void> discard(SpeechPreparation prepared) async {
    if (identical(_prepared, prepared)) {
      _prepared = null;
      _wav = null;
    }
  }

  @override
  Future<void> saveDraft(String text, {String? blobId}) =>
      controller.saveSpeechDraft(text, blobId: blobId);
}
