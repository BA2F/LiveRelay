import 'dart:convert';
import 'dart:typed_data';

import 'package:uuid/uuid.dart';
import 'package:crypto/crypto.dart';

import '../ports/ai_provider.dart';
import '../media/pcm_wave.dart';

enum ConversationAttachmentKind { text, image, pdf, audio, video, unsupported }

class ConversationAttachment {
  ConversationAttachment._(
    this.id,
    this.name,
    this.mimeType,
    this.bytes,
    this.kind, {
    this.cardId,
    this.cardRevision,
    this.blobId,
  });
  final String id, name, mimeType;
  final String? cardId;
  final int? cardRevision;
  String? blobId;
  final Uint8List bytes;
  final ConversationAttachmentKind kind;
  Uint8List? _normalizedAudio;
  String? _audioStamp;
  Uint8List? get normalizedAudio => _normalizedAudio;
  String? get audioStamp => _audioStamp;
  set normalizedAudio(Uint8List? bytes) {
    _normalizedAudio = bytes;
    _audioStamp = bytes == null ? null : sha256.convert(bytes).toString();
  }

  String? transcript;
  final frames = <({int milliseconds, Uint8List bytes})>[];
  String get sendDescription {
    if (kind == ConversationAttachmentKind.audio) {
      return transcript != null
          ? '仅发送本人核对转写（${transcript!.length}字）'
          : normalizedAudio != null
          ? '发送完整转换WAV音轨（${normalizedAudio!.length}字节）'
          : '发送完整音频（${bytes.length}字节）';
    }
    if (kind == ConversationAttachmentKind.video) {
      return '发送${frames.length}个已检查视频帧与时间；${transcript != null
          ? "仅发送核对音轨文字"
          : normalizedAudio != null
          ? "另发送完整转换音轨"
          : "不发送音轨"}';
    }
    return '发送完整所选内容（${bytes.length}字节）';
  }

  String get text => utf8.decode(bytes);
  String get dataUrl => 'data:$mimeType;base64,${base64Encode(bytes)}';
  static const maxBytes = 2 * 1024 * 1024;
  factory ConversationAttachment.read(
    String name,
    Uint8List bytes, {
    String? cardId,
    int? cardRevision,
    String? blobId,
  }) {
    if (name.isEmpty ||
        name.length > 240 ||
        bytes.isEmpty ||
        bytes.length > maxBytes) {
      throw const FormatException('附件为空或过大；每个最多 2 MB');
    }
    if (cardRevision != null && (cardId == null || cardRevision < 1)) {
      throw const FormatException('所选卡片修订无效');
    }
    bool prefix(List<int> signature) =>
        bytes.length >= signature.length &&
        List.generate(
          signature.length,
          (i) => bytes[i] == signature[i],
        ).every((v) => v);
    var kind = ConversationAttachmentKind.unsupported;
    var mime = 'application/octet-stream';
    if (prefix([137, 80, 78, 71, 13, 10, 26, 10])) {
      kind = ConversationAttachmentKind.image;
      mime = 'image/png';
    } else if (prefix([255, 216, 255])) {
      kind = ConversationAttachmentKind.image;
      mime = 'image/jpeg';
    } else if (prefix([82, 73, 70, 70]) &&
        bytes.length > 12 &&
        ascii.decode(bytes.sublist(8, 12), allowInvalid: true) == 'WEBP') {
      kind = ConversationAttachmentKind.image;
      mime = 'image/webp';
    } else if (prefix([37, 80, 68, 70, 45])) {
      kind = ConversationAttachmentKind.pdf;
      mime = 'application/pdf';
    } else if (prefix([82, 73, 70, 70]) &&
        bytes.length >= 12 &&
        ascii.decode(bytes.sublist(8, 12), allowInvalid: true) == 'WAVE') {
      kind = ConversationAttachmentKind.audio;
      mime = 'audio/wav';
    } else if (prefix([73, 68, 51]) ||
        (bytes.length > 1 &&
            bytes[0] == 255 &&
            (bytes[1] & 224) == 224 &&
            (bytes[1] & 6) != 0)) {
      kind = ConversationAttachmentKind.audio;
      mime = 'audio/mpeg';
    } else if (bytes.length >= 12 &&
        ascii.decode(bytes.sublist(4, 8), allowInvalid: true) == 'ftyp') {
      final audioOnly = RegExp(
        r'\.(m4a|aac)$',
        caseSensitive: false,
      ).hasMatch(name);
      kind = audioOnly
          ? ConversationAttachmentKind.audio
          : ConversationAttachmentKind.video;
      mime = audioOnly ? 'audio/mp4' : 'video/mp4';
    } else if (prefix([26, 69, 223, 163])) {
      kind = ConversationAttachmentKind.video;
      mime = 'video/webm';
    } else if (cardId != null ||
        RegExp(
          r'\.(txt|md|json|csv|tsv|log)$',
          caseSensitive: false,
        ).hasMatch(name)) {
      if (bytes.length > 128 * 1024) {
        throw const FormatException('文字附件最多 128 KB');
      }
      utf8.decode(bytes);
      kind = ConversationAttachmentKind.text;
      mime = 'text/plain';
    }
    return ConversationAttachment._(
      const Uuid().v7(),
      name,
      mime,
      bytes,
      kind,
      cardId: cardId,
      cardRevision: cardRevision,
      blobId: blobId,
    );
  }
  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'mime': mimeType,
    'bytes': base64Encode(bytes),
    'kind': kind.name,
    'card': cardId,
    'cardRevision': cardRevision,
    'blob': blobId,
    if (normalizedAudio != null)
      'normalizedAudio': base64Encode(normalizedAudio!),
    if (transcript != null) 'transcript': transcript,
    'frames': [
      for (final f in frames)
        {'ms': f.milliseconds, 'bytes': base64Encode(f.bytes)},
    ],
  };
  factory ConversationAttachment.fromJson(Map raw) {
    final bytes = base64Decode(raw['bytes'] as String);
    final checked = ConversationAttachment.read(
      raw['name'] as String,
      bytes,
      cardId: raw['card'] as String?,
      cardRevision: raw['cardRevision'] as int?,
      blobId: raw['blob'] as String?,
    );
    if ((checked.kind.name != raw['kind'] || checked.mimeType != raw['mime']) &&
        !(raw['kind'] == 'unsupported' &&
            {
              ConversationAttachmentKind.audio,
              ConversationAttachmentKind.video,
            }.contains(checked.kind))) {
      throw const FormatException('附件记录不匹配');
    }
    final result = ConversationAttachment._(
      raw['id'] as String,
      checked.name,
      checked.mimeType,
      bytes,
      checked.kind,
      cardId: checked.cardId,
      cardRevision: checked.cardRevision,
      blobId: checked.blobId,
    );
    try {
      if (raw['normalizedAudio'] != null) {
        result.normalizedAudio = base64Decode(raw['normalizedAudio'] as String);
        PcmWave.validate(result.normalizedAudio!);
        if (!{
          ConversationAttachmentKind.audio,
          ConversationAttachmentKind.video,
        }.contains(result.kind)) {
          throw const FormatException('附件音轨类型无效');
        }
      }
      final transcript = raw['transcript'];
      if (transcript != null) {
        if (transcript is! String ||
            transcript.trim().isEmpty ||
            transcript.length > 32000 ||
            !{
              ConversationAttachmentKind.audio,
              ConversationAttachmentKind.video,
            }.contains(result.kind)) {
          throw const FormatException('附件转写无效');
        }
        result.transcript = transcript;
      }
    } on Object {
      result.wipe();
      rethrow;
    }
    for (final f in raw['frames'] as List? ?? []) {
      final frame = ConversationAttachment.read(
        'frame.jpg',
        base64Decode(f['bytes'] as String),
      );
      if (frame.kind != ConversationAttachmentKind.image ||
          frame.bytes.length > 256 * 1024 ||
          f['ms'] is! int ||
          f['ms'] < 0 ||
          result.frames.length >= 4) {
        throw const FormatException('视频帧记录无效');
      }
      result.frames.add((milliseconds: f['ms'] as int, bytes: frame.bytes));
    }
    return result;
  }
  Map<String, Object?> wire(
    AiProtocol protocol, {
    required bool images,
    required bool files,
    bool audio = false,
  }) {
    switch (kind) {
      case ConversationAttachmentKind.text:
        return {
          'type': protocol == AiProtocol.responses ? 'input_text' : 'text',
          'text': '附件 $name：\n$text',
        };
      case ConversationAttachmentKind.image:
        if (!images) throw const FormatException('请先在服务设置中确认模型支持图片输入');
        return protocol == AiProtocol.responses
            ? {'type': 'input_image', 'image_url': dataUrl}
            : {
                'type': 'image_url',
                'image_url': {'url': dataUrl},
              };
      case ConversationAttachmentKind.pdf:
        if (!files || protocol != AiProtocol.responses) {
          throw const FormatException('PDF 需要已确认文件输入能力的 Responses 服务');
        }
        return {'type': 'input_file', 'filename': name, 'file_data': dataUrl};
      case ConversationAttachmentKind.audio:
        if (transcript != null) {
          return {
            'type': protocol == AiProtocol.responses ? 'input_text' : 'text',
            'text': '音频 $name：仅发送本人核对的转写，不发送音频。\n$transcript',
          };
        }
        if (!audio ||
            protocol != AiProtocol.chatCompletions ||
            (normalizedAudio == null &&
                !{'audio/wav', 'audio/mpeg'}.contains(mimeType))) {
          throw const FormatException(
            '此音频需要声明音频输入能力的Chat服务和WAV/MP3格式；也可使用独立语音转写。',
          );
        }
        return {
          'type': 'input_audio',
          'input_audio': {
            'data': base64Encode(normalizedAudio ?? bytes),
            'format': normalizedAudio != null || mimeType == 'audio/wav'
                ? 'wav'
                : 'mp3',
          },
        };
      case ConversationAttachmentKind.video:
        throw const FormatException('请先选取并检查视频帧，再发送给支持图片的模型');
      case ConversationAttachmentKind.unsupported:
        throw const FormatException('当前协议尚未适配此文件类型；音频请先转写，视频和其他二进制仍待适配');
    }
  }

  List<Map<String, Object?>> wireParts(
    AiProtocol protocol, {
    required bool images,
    required bool files,
    bool audio = false,
  }) {
    if (kind != ConversationAttachmentKind.video) {
      return [wire(protocol, images: images, files: files, audio: audio)];
    }
    if (!images || frames.isEmpty) {
      if (transcript == null || frames.isNotEmpty) {
        throw const FormatException('请先选取并检查视频帧；服务还需支持图片');
      }
    }
    return [
      {
        'type': protocol == AiProtocol.responses ? 'input_text' : 'text',
        'text':
            '视频 $name：发送${frames.length}个已检查采样帧及时间；不发送视频原件。${transcript != null
                ? "音轨只发送本人核对的转写。"
                : normalizedAudio != null
                ? "另发送完整转换音轨。"
                : "不发送音轨。"}',
      },
      if (transcript != null)
        {
          'type': protocol == AiProtocol.responses ? 'input_text' : 'text',
          'text': '本人核对的视频音轨转写：\n$transcript',
        },
      if (transcript == null && normalizedAudio != null)
        ConversationAttachment.read(
          'video-audio.wav',
          normalizedAudio!,
        ).wire(protocol, images: false, files: false, audio: audio),
      for (final frame in frames) ...[
        {
          'type': protocol == AiProtocol.responses ? 'input_text' : 'text',
          'text': '采样时间 ${frame.milliseconds} ms',
        },
        ConversationAttachment.read(
          'frame.jpg',
          frame.bytes,
        ).wire(protocol, images: true, files: false),
      ],
    ];
  }

  void wipe() {
    bytes.fillRange(0, bytes.length, 0);
    normalizedAudio?.fillRange(0, normalizedAudio!.length, 0);
    normalizedAudio = null;
    transcript = null;
    for (final f in frames) {
      f.bytes.fillRange(0, f.bytes.length, 0);
    }
    frames.clear();
  }
}
