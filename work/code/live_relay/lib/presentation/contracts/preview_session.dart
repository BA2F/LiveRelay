import 'package:flutter/foundation.dart';

/// Presentation lifetime only; carries no repository, credentials or keys.
abstract interface class PreviewSession implements Listenable {
  bool get isUnlocked;
  void registerPreviewCleanup(Future<void> Function() cleanup);
  void unregisterPreviewCleanup(Future<void> Function() cleanup);
}

/// Child windows lose permission before waiting for decoder/cache cleanup.
class DetachedPreviewSession extends ChangeNotifier implements PreviewSession {
  bool _unlocked = true;
  final _cleanups = <Future<void> Function()>{};
  Future<void>? _revocation;
  @override
  bool get isUnlocked => _unlocked;
  @override
  void registerPreviewCleanup(Future<void> Function() cleanup) =>
      _cleanups.add(cleanup);
  @override
  void unregisterPreviewCleanup(Future<void> Function() cleanup) =>
      _cleanups.remove(cleanup);

  Future<void> revoke() {
    if (_revocation != null) return _revocation!;
    _unlocked = false;
    notifyListeners();
    return _revocation = Future.wait([
      for (final cleanup in List.of(_cleanups)) cleanup(),
    ]).then((_) {});
  }
}
