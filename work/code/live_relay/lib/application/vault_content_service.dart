import 'dart:typed_data';

import '../core/domain/entities.dart';
import '../core/ports/ocr_provider.dart';
import '../core/ports/vault_originals.dart';
import 'import/edge_password_csv_importer.dart';

/// Original/derived content use cases, independent of Flutter and concrete
/// storage. Failed registration compensates the encrypted file write; temporary
/// input/OCR buffers are wiped even when parsing, recognition or saving fails.
class VaultContentService {
  const VaultContentService({
    required this.vault,
    required this.ocr,
    this.importer = const EdgePasswordCsvImporter(),
  });
  final VaultOriginals vault;
  final OcrProvider ocr;
  final EdgePasswordCsvImporter importer;

  int _begin() {
    if (!vault.isUnlocked) throw StateError('请先解锁资料库');
    return vault.sessionGeneration;
  }

  void _check(int generation) {
    if (!vault.isUnlocked || generation != vault.sessionGeneration) {
      throw StateError('资料库已关闭或重开，本次结果已丢弃');
    }
  }

  Future<VaultBlob> _blob(String id, int generation) async {
    final blob = await vault.repository.getBlob(id);
    _check(generation);
    if (blob == null) throw StateError('原始资料不存在');
    return blob;
  }

  Future<LifeCard> importOriginal({
    required Uint8List bytes,
    required String originalName,
    required String mimeType,
    required BlobMediaKind mediaKind,
  }) async {
    try {
      final generation = _begin();
      final blob = await vault.writeOriginal(
        bytes: bytes,
        originalName: originalName,
        mimeType: mimeType,
        mediaKind: mediaKind,
      );
      late LifeCard card;
      try {
        _check(generation);
        card = await vault.repository.registerBlob(blob);
      } on Object {
        // A replaced vault may contain restored files: compensate only the same
        // session; never delete a file from a later installed vault by old ID.
        if (generation == vault.sessionGeneration) {
          await vault.deleteOriginal(blob);
        }
        rethrow;
      }
      _check(generation);
      return card;
    } finally {
      bytes.fillRange(0, bytes.length, 0);
    }
  }

  Future<Uint8List> readOriginal(String id) async {
    final generation = _begin();
    final blob = await _blob(id, generation);
    final bytes = await vault.readOriginal(blob);
    try {
      _check(generation);
      return bytes;
    } on Object {
      bytes.fillRange(0, bytes.length, 0);
      rethrow;
    }
  }

  Future<LifeCard> runOcr(String id) async {
    final generation = _begin();
    final blob = await _blob(id, generation);
    if (blob.mediaKind != BlobMediaKind.image) {
      throw const FormatException('只有图片原件可以执行 OCR');
    }
    final bytes = await vault.readOriginal(blob);
    late OcrResult result;
    try {
      _check(generation);
      result = await ocr.recognize(
        imageBytes: bytes,
        originalName: blob.originalName,
      );
    } finally {
      bytes.fillRange(0, bytes.length, 0);
    }
    _check(generation);
    final card = await vault.repository.saveOcrResult(blob.id, result);
    _check(generation);
    return card;
  }

  Future<EdgePasswordImportResult> importEdgePasswords(Uint8List bytes) async {
    try {
      final generation = _begin();
      final parsed = importer.parse(bytes);
      await vault.repository.importCredentials(parsed.entries);
      _check(generation);
      return parsed;
    } finally {
      bytes.fillRange(0, bytes.length, 0);
    }
  }

  Future<LifeCard> saveSpeechDraft(String text, {String? blobId}) {
    _begin();
    final content = text.trim();
    if (content.isEmpty || content.length > 32000) {
      throw const FormatException('语音文字为空或过长');
    }
    final draft = CardDraft(
      title: String.fromCharCodes(content.split('\n').first.runes.take(28)),
      content: content,
      kind: CardKind.note,
      status: CardStatus.draft,
      tags: ['语音', '待确认'],
    );
    if (blobId != null) {
      return vault.repository.createCardFromOriginal(
        blobId,
        draft,
        sourceKind: SourceKind.audio,
        sourceLabel: '本地语音识别 · 本人校对',
      );
    }
    return vault.repository.createCard(
      draft,
      sourceKind: SourceKind.ownerInput,
      sourceLabel: '语音页手动输入 · 本人校对',
    );
  }
}
