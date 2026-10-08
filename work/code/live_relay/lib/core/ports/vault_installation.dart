import 'dart:io';

/// Installation must verify the authenticated replacement before the durable
/// commit point, roll back pre-commit failures and retain ambiguous remnants.
abstract interface class VaultInstallation {
  Future<String?> recover();
  Future<String?> install(
    Directory staged, {
    required Future<void> Function() verifyInstalled,
    required Future<void> Function() closeInstalled,
  });
}

typedef VaultInstallationFactory = VaultInstallation Function(Directory vault);
