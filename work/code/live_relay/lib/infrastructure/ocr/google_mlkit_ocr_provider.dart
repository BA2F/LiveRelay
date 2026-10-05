import 'dart:io';
import 'dart:typed_data';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:path/path.dart' as path;

import '../private_cache.dart';

import 'package:uuid/uuid.dart';

import '../../core/domain/entities.dart';
import '../../core/ports/ocr_provider.dart';

class GoogleMlKitOcrProvider implements OcrProvider {
  GoogleMlKitOcrProvider({Uuid? uuid}) : _uuid = uuid ?? const Uuid();

  final Uuid _uuid;

  @override
  Future<OcrResult> recognize({
    required Uint8List imageBytes,
    required String originalName,
  }) async {
    if (!Platform.isAndroid && !Platform.isIOS) {
      throw UnsupportedError('当前桌面平台尚未接入本地 OCR Provider');
    }
    final cache = await privateCacheDirectory();
    final extension = path.extension(originalName).toLowerCase();
    final safeExtension = RegExp(r'^\.[a-z0-9]{1,8}$').hasMatch(extension)
        ? extension
        : '.jpg';
    final temporary = File(
      path.join(cache.path, 'ocr-${_uuid.v7()}$safeExtension'),
    );
    final recognizer = TextRecognizer(script: TextRecognitionScript.chinese);
    try {
      await temporary.writeAsBytes(imageBytes, flush: true);
      final recognized = await recognizer.processImage(
        InputImage.fromFilePath(temporary.path),
      );
      final lines = <OcrLine>[];
      var order = 0;
      for (final block in recognized.blocks) {
        for (final line in block.lines) {
          lines.add(
            OcrLine(
              text: line.text,
              left: line.boundingBox.left,
              top: line.boundingBox.top,
              right: line.boundingBox.right,
              bottom: line.boundingBox.bottom,
              order: order++,
              confidence: line.confidence,
            ),
          );
        }
      }
      return OcrResult(text: recognized.text.trim(), lines: lines);
    } finally {
      await recognizer.close();
      if (await temporary.exists()) await temporary.delete();
    }
  }
}
