import 'vault_repository.dart';

/// Access to the current unlocked repository, never a master key. Resolve at
/// use time so closing/reopening a vault cannot retain a stale repository.
abstract interface class UnlockedVault {
  bool get isUnlocked;

  /// Changes whenever the active repository is closed or replaced.
  int get sessionGeneration;
  VaultRepository get repository;
}
