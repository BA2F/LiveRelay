import 'dart:convert';
import 'dart:typed_data';

/// Restricted ASCII canonical JSON used only by Header v2's fixed schema.
/// This is deliberately not a general-purpose JCS implementation.
class HeaderEncoding {
  static Uint8List encode(Object? value) =>
      Uint8List.fromList(utf8.encode(_encode(value)));

  static String _encode(Object? value) {
    if (value == null || value is bool || value is int) {
      return jsonEncode(value);
    }
    if (value is String) {
      if (value.codeUnits.any((c) => c < 32 || c > 126)) {
        throw const FormatException('Header 包含不支持的字符');
      }
      return jsonEncode(value);
    }
    if (value is List) return '[${value.map(_encode).join(',')}]';
    if (value is Map<String, Object?>) {
      final keys = value.keys.toList()..sort();
      return '{${keys.map((k) => '${_encode(k)}:${_encode(value[k])}').join(',')}}';
    }
    throw const FormatException('Header 包含不支持的类型');
  }

  static String binary(List<int> bytes) =>
      base64UrlEncode(bytes).replaceAll('=', '');

  static Uint8List decodeBinary(Object? text, int length) {
    if (text is! String || !RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(text)) {
      throw const FormatException('Header 二进制编码错误');
    }
    final bytes = Uint8List.fromList(
      base64Url.decode(base64Url.normalize(text)),
    );
    if (bytes.length != length || binary(bytes) != text) {
      throw const FormatException('Header 二进制长度或编码错误');
    }
    return bytes;
  }

  static String hex(List<int> bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}
