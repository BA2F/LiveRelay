import 'dart:typed_data';

import '../domain/entities.dart';

abstract interface class OcrProvider {
  Future<OcrResult> recognize({
    required Uint8List imageBytes,
    required String originalName,
  });
}
