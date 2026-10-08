import 'unlocked_vault.dart';

/// Public in-process session signals. Revocation is delivered synchronously so
/// application memory can be cleared before waiting for platform cleanup.
abstract interface class VaultLifecycle implements UnlockedVault {
  Stream<void> get changes;
  bool get isMaintaining;
  bool get isWriting;

  /// Shared local command gate; maintenance cannot snapshot/swap a vault while
  /// a confirmed command is in flight. Locking may always revoke the session.
  Future<T> runMutation<T>(Future<T> Function() operation);
}
