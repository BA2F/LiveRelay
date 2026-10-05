import 'dart:convert';
import 'dart:typed_data';

import 'package:uuid/uuid.dart';

import '../ports/ai_provider.dart';

enum ConversationAttachmentKind { text, image, pdf, unsupported }

class ConversationAttachment {
  ConversationAttachment._(
    this.id,
    this.name,
    this.mimeType,
    this.bytes,
    this.kind, {
    this.cardId,
    this.blobId,
  });
  final String id, name, mimeType;
  final String? cardId;
  String? blobId;
  final Uint8List bytes;
  final ConversationAttachmentKind kind;
  String get text => utf8.decode(bytes);
  String get dataUrl => 'data:$mimeType;base64,${base64Encode(bytes)}';
  static const maxBytes = 2 * 1024 * 1024;
  factory ConversationAttachment.read(
    String name,
    Uint8List bytes, {
    String? cardId,
    String? blobId,
  }) {
    if (name.isEmpty ||
        name.length > 240 ||
        bytes.isEmpty ||
        bytes.length > maxBytes) {
      throw const FormatException('附件为空或过大；每个最多 2 MB');
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
    'blob': blobId,
  };
  factory ConversationAttachment.fromJson(Map raw) {
    final bytes = base64Decode(raw['bytes'] as String);
    final checked = ConversationAttachment.read(
      raw['name'] as String,
      bytes,
      cardId: raw['card'] as String?,
      blobId: raw['blob'] as String?,
    );
    if (checked.kind.name != raw['kind'] || checked.mimeType != raw['mime']) {
      throw const FormatException('附件记录不匹配');
    }
    return ConversationAttachment._(
      raw['id'] as String,
      checked.name,
      checked.mimeType,
      bytes,
      checked.kind,
      cardId: checked.cardId,
      blobId: checked.blobId,
    );
  }
  Map<String, Object?> wire(
    AiProtocol protocol, {
    required bool images,
    required bool files,
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
      case ConversationAttachmentKind.unsupported:
        throw const FormatException('当前协议尚未适配此文件类型；音频请先转写，视频和其他二进制仍待适配');
    }
  }

  void wipe() => bytes.fillRange(0, bytes.length, 0);
}
