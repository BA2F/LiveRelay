import 'dart:typed_data';

import '../controllers/app_controller.dart';
import 'window_projection.dart' show windowSourcePreviewMaxBytes;

/// A child may request bytes only for its current source view, never a vault
/// path or an arbitrary ID. The limit leaves room for IPC base64 framing.
class WindowSourceReader {
  WindowSourceReader(this.controller);
  final AppController controller;
  static const maxBytes = windowSourcePreviewMaxBytes;

  Future<Uint8List> read({
    required String id,
    required String Function() view,
    required bool Function() active,
  }) async {
    void check() {
      if (!active() || !controller.isUnlocked || view() != 'source/$id') {
        throw const FormatException('原件视图已失效');
      }
    }

    check();
    final blob = controller.blobs.where((b) => b.id == id).firstOrNull;
    if (blob == null || controller.recycledBlobIds.contains(id)) {
      throw const FormatException('原件已回收或不存在');
    }
    if (blob.byteLength > maxBytes) {
      throw const FormatException('独立窗口预览最多8 MB，请在主工作台查看');
    }
    final bytes = await controller.readOriginal(id);
    try {
      check();
      if (bytes.length > maxBytes) throw const FormatException('原件过大');
      return bytes;
    } on Object {
      bytes.fillRange(0, bytes.length, 0);
      rethrow;
    }
  }
}
