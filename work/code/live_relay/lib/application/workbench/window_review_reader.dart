import 'dart:convert';
import 'dart:typed_data';

import '../../core/ai/review_source.dart';

/// A presentation window receives only its current card's confirmation record.
/// Chunking keeps large evidence below the private channel's frame limit.
class WindowReviewReader {
  WindowReviewReader({required this.load, required this.allowed});
  final Future<ReviewSource?> Function(String cardId) load;
  final bool Function(String cardId) allowed;
  static const chunkBytes = 256 * 1024;
  // The existing record limit counts UTF-16 units. UTF-8 needs at most 3 bytes
  // per unit, including surrogate pairs, without changing that stored format.
  static const maxBytes = 3 * ReviewSource.maxLength;
  Uint8List? _bytes;
  String? _cardId;
  Future<void>? _loading;
  int _generation = 0, _offset = 0;
  bool _missing = false;

  Future<void> _load(String id, int generation) async {
    final source = await load(id);
    Uint8List? bytes;
    try {
      if (generation != _generation || !allowed(id)) {
        throw const FormatException('确认来源视图已失效');
      }
      if (source != null) {
        bytes = Uint8List.fromList(utf8.encode(source.encode()));
        if (bytes.length > maxBytes) {
          throw const FormatException('确认来源过大');
        }
      }
      _bytes = bytes;
      bytes = null;
      _missing = source == null;
    } finally {
      source?.wipe();
      bytes?.fillRange(0, bytes.length, 0);
    }
  }

  Future<Map<String, Object?>> readChunk(String id, int offset) async {
    if (!allowed(id) || offset < 0 || offset > maxBytes) {
      throw const FormatException('确认来源读取范围无效');
    }
    if (_cardId == null) {
      if (offset != 0) throw const FormatException('请从头读取确认来源');
      _cardId = id;
      _loading = _load(id, _generation);
    }
    final generation = _generation;
    try {
      await _loading;
    } on Object {
      if (generation == _generation) await clear();
      rethrow;
    }
    if (generation != _generation || !allowed(id) || _cardId != id) {
      throw const FormatException('确认来源视图已失效');
    }
    if (offset != _offset) throw const FormatException('确认来源分块顺序无效');
    if (_missing) {
      await clear();
      return {'offset': 0, 'length': 0, 'bytes': Uint8List(0)};
    }
    final bytes = _bytes!;
    final end = (offset + chunkBytes).clamp(0, bytes.length);
    final chunk = Uint8List.fromList(bytes.sublist(offset, end));
    _offset = end;
    final result = <String, Object?>{
      'generation': generation,
      'offset': offset,
      'length': bytes.length,
      'bytes': chunk,
    };
    if (end == bytes.length) await clear();
    if (!allowed(id)) {
      chunk.fillRange(0, chunk.length, 0);
      throw const FormatException('确认来源视图已失效');
    }
    return result;
  }

  Future<void> clear() async {
    _generation++;
    _bytes?.fillRange(0, _bytes!.length, 0);
    _bytes = null;
    final pending = _loading;
    try {
      await pending;
    } on Object {
      // A revoked pending read wipes its record before completing.
    }
    if (identical(_loading, pending)) {
      _loading = null;
      _cardId = null;
      _offset = 0;
      _missing = false;
    }
  }
}
