import 'dart:io';
import 'dart:convert';

import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  final output = Directory(
    '../../paper/uiux-review-2026-10-01/implementation-screenshots',
  );
  await output.create(recursive: true);
  await integrationDriver(
    onScreenshot:
        (String name, List<int> bytes, [Map<String, Object?>? args]) async {
          await File('${output.path}/$name.png').writeAsBytes(bytes);
          return bytes.length > 8 && bytes[0] == 137 && bytes[1] == 80;
        },
    writeResponseOnFailure: true,
    responseDataCallback: (data) async {
      final names = (data?['screenshots'] as List? ?? [])
          .map((v) => (v as Map)['screenshotName'])
          .toList();
      await File('${output.path}/capture-index.json')
          .writeAsString(jsonEncode({'screenshots': names}));
    },
  );
}
