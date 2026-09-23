import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:live_relay/infrastructure/import/edge_password_csv_importer.dart';

void main() {
  const importer = EdgePasswordCsvImporter();

  test('parses Edge native CSV while preserving secrets exactly', () {
    final result = importer.parse(
      Uint8List.fromList(
        utf8.encode(
          '\ufeffname,url,username,password,note\r\n'
          'Example,https://example.com,alice,"0012,Ab!",primary\r\n'
          ',https://sub.example.org,bob,plain-secret,\r\n'
          'No password,https://empty.example,eve,,\r\n',
        ),
      ),
    );

    expect(result.entries, hasLength(2));
    expect(result.entries.first.secret, '0012,Ab!');
    expect(result.entries.first.title, 'Example');
    expect(result.entries.last.title, 'sub.example.org');
    expect(result.entries.last.tags, ['Edge 导入']);
    expect(result.skippedRows, 1);
  });

  test('rejects CSV without Edge password columns', () {
    expect(
      () => importer.parse(
        Uint8List.fromList(utf8.encode('title,account\nExample,alice')),
      ),
      throwsA(isA<FormatException>()),
    );
  });
}
