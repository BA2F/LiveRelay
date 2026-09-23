import 'dart:convert';
import 'dart:typed_data';

import 'package:csv/csv.dart';

import '../../core/domain/entities.dart';

class EdgePasswordImportResult {
  const EdgePasswordImportResult({
    required this.entries,
    required this.skippedRows,
  });

  final List<CredentialDraft> entries;
  final int skippedRows;
}

/// Parses Microsoft Edge's native plaintext password CSV without logging or
/// persisting the source. Imported secrets retain their exact string value.
class EdgePasswordCsvImporter {
  const EdgePasswordCsvImporter();

  EdgePasswordImportResult parse(Uint8List bytes) {
    String text;
    try {
      text = utf8.decode(bytes);
    } on Object {
      throw const FormatException('Edge CSV 必须使用 UTF-8 编码');
    }
    final rows = Csv(dynamicTyping: false).decode(text);
    if (rows.isEmpty) throw const FormatException('Edge CSV 为空');
    final headers = <String, int>{};
    for (var index = 0; index < rows.first.length; index++) {
      final normalized = rows.first[index]
          .toString()
          .replaceFirst('\ufeff', '')
          .trim()
          .toLowerCase();
      if (normalized.isNotEmpty) headers[normalized] = index;
    }
    final nameIndex = _find(headers, const ['name', 'title']);
    final urlIndex = _find(headers, const ['url', 'website', 'origin']);
    final usernameIndex = _find(headers, const [
      'username',
      'user name',
      'login',
    ]);
    final passwordIndex = _find(headers, const ['password']);
    final noteIndex = _find(headers, const ['note', 'notes']);
    if (urlIndex == null || usernameIndex == null || passwordIndex == null) {
      throw const FormatException(
        '不是受支持的 Edge 密码 CSV：需要 url、username、password 列',
      );
    }

    final entries = <CredentialDraft>[];
    var skipped = 0;
    for (final row in rows.skip(1)) {
      final url = _cell(row, urlIndex).trim();
      final username = _cell(row, usernameIndex).trim();
      final password = _cell(row, passwordIndex);
      final suppliedName = nameIndex == null
          ? ''
          : _cell(row, nameIndex).trim();
      if (url.isEmpty &&
          username.isEmpty &&
          password.isEmpty &&
          suppliedName.isEmpty) {
        skipped++;
        continue;
      }
      if (password.isEmpty) {
        skipped++;
        continue;
      }
      entries.add(
        CredentialDraft(
          title: suppliedName.isNotEmpty ? suppliedName : _fallbackTitle(url),
          username: username,
          secret: password,
          website: url,
          notes: noteIndex == null ? '' : _cell(row, noteIndex).trim(),
          tags: const ['Edge 导入'],
        ),
      );
    }
    if (entries.isEmpty) {
      throw const FormatException('CSV 中没有可导入的密码条目');
    }
    return EdgePasswordImportResult(entries: entries, skippedRows: skipped);
  }

  int? _find(Map<String, int> headers, List<String> candidates) {
    for (final candidate in candidates) {
      final index = headers[candidate];
      if (index != null) return index;
    }
    return null;
  }

  String _cell(List<dynamic> row, int index) =>
      index < row.length ? row[index]?.toString() ?? '' : '';

  String _fallbackTitle(String url) {
    final uri = Uri.tryParse(url);
    if (uri != null && uri.host.isNotEmpty) return uri.host;
    return url.isEmpty ? '未命名账号' : url;
  }
}
