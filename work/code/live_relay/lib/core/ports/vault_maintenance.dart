import 'dart:io';
import 'dart:typed_data';

import '../domain/entities.dart';
import '../security/vault_header_v3.dart';
import '../security/vault_header_metadata.dart';
import 'device_factor_protection.dart';
import 'vault_originals.dart';
import 'vault_lifecycle.dart';
import 'vault_repository.dart';

enum VaultSessionState {
  loading,
  needsSetup,
  locked,
  unlocked,
  recovering,
  failure,
}

/// Privileged in-process capability for authenticated backup and key rotation.
/// Presentation/Agent receive narrower ports; borrowed keys must be wiped by
/// the caller and must never be serialized into an IPC or presentation event.
/// Directory is a local Dart IO location, not a portable public wire contract.
abstract interface class VaultMaintenance
    implements VaultOriginals, VaultLifecycle {
  VaultSessionState get state;
  VaultHeaderMetadata? get header;
  Directory get directory;
  int get operationEpoch;
  DeviceFactorProtection? get deviceProtection;
  Future<T> exclusiveMaintenance<T>(Future<T> Function() operation);
  Future<T> withMasterKey<T>(Future<T> Function(Uint8List key) operation);
  Future<Uint8List> authenticateDaily(String password, {Uint8List? keyFile});
  Future<Uint8List> authenticateRecovery(String text);
  Future<VaultHeaderV3?> modernHeader();

  /// Identity for layered-archive pairing: the vault id plus the current key
  /// epoch. Stable across exports until credentials rotate. Null when the
  /// vault predates format v3.
  Future<({String vaultId, int epoch})?> archiveIdentity();
  String canonicalizePassword(String password, VaultHeaderMetadata metadata);
  Future<VaultHeaderMetadata?> readStagedHeader(Directory staged);
  Future<Uint8List> authenticateStaged(
    Directory staged,
    String credential,
    VaultHeaderMetadata metadata,
  );
  Future<void> disableStagedLegacyBiometric(Directory staged);
  Future<void> writeStagedHeader(Directory staged, VaultHeaderV3 header);
  Future<VaultRepository> openTemporary(Directory directory, Uint8List key);
  Future<void> openWithKey(Uint8List key);
  Future<void> suspendDatabase();
  Future<void> close();
  Future<void> reloadHeader();
  Future<void> inspectRecoveredHeader();
  Future<void> clearDeviceKeyAfterRestore();
  Future<void> copyBlobUnderKey({
    Directory? source,
    required Directory target,
    required Uint8List oldKey,
    required Uint8List newKey,
    required VaultBlob blob,
  });
  Future<void> writeBlobCiphertext({
    required Directory target,
    required VaultBlob blob,
    required Uint8List bytes,
  });
  void markUnlocked();
  void markRecovering();
  void fail();
}
