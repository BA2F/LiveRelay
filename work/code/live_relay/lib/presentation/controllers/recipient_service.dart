import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../application/identity/recipient_runtime.dart';
import '../../core/identity/local_identity.dart';

/// Flutter notification and local file-selection adaptation only.
class RecipientService extends ChangeNotifier {
  RecipientService(this.runtime) {
    _subscription = runtime.changes.listen((_) => notifyListeners());
  }
  final RecipientRuntime runtime;
  late final StreamSubscription<void> _subscription;
  LocalIdentity? get identity => runtime.identity;
  Map<String, Object?>? get snapshot => runtime.snapshot;
  bool get exists => runtime.exists;
  bool get busy => runtime.busy;
  Future<void> initialize() => runtime.initialize();
  Future<void> create(String name, String password) =>
      runtime.create(name, password);
  Future<void> unlock(String password) => runtime.unlock(password);
  Future<Uint8List> exportProtectedIdentity() =>
      runtime.exportProtectedIdentity();
  Future<void> importProtectedIdentity(Uint8List bytes, String password) =>
      runtime.importProtectedIdentity(bytes, password);
  Future<Uint8List> answerChallenge(
    Map<String, Object?> input,
    String fingerprint,
  ) => runtime.answerChallenge(input, fingerprint);
  Future<Map<String, Object?>> inspectEnvelope(Uint8List bytes) =>
      runtime.inspectEnvelope(bytes);
  Future<void> receive(
    Uint8List bytes,
    String fingerprint, {
    bool saved = false,
  }) => runtime.receive(bytes, fingerprint, saved: saved);
  Future<List<File>> savedPackages() async =>
      (await runtime.savedPackages()).map((p) => File(p.path)).toList();
  void lock() => runtime.lock();
  @override
  void dispose() {
    unawaited(_subscription.cancel());
    runtime.dispose();
    super.dispose();
  }
}
