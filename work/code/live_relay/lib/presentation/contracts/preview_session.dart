import 'package:flutter/foundation.dart';

/// Presentation lifetime only; carries no repository, credentials or keys.
abstract interface class PreviewSession implements Listenable {
  bool get isUnlocked;
  void registerPreviewCleanup(Future<void> Function() cleanup);
  void unregisterPreviewCleanup(Future<void> Function() cleanup);
}
