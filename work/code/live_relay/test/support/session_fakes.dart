import 'dart:io';
import 'dart:typed_data';

import 'package:live_relay/application/vault_session.dart';
import 'package:live_relay/core/domain/entities.dart';
import 'package:live_relay/core/ports/vault_blob_store.dart';
import 'package:live_relay/core/ports/vault_repository.dart';
import 'package:live_relay/core/security/chinese_passphrase.dart';

import 'verification_fakes.dart';

class SessionRepository implements VaultRepository {
  int closes = 0;
  bool failClose = false;
  @override
  Future<void> close() async {
    closes++;
    if (failClose) throw StateError('test close failure');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class TrackingBlobStore implements VaultBlobStore {
  Uint8List? borrowedKey;
  @override
  Future<Uint8List> read({
    required Directory vaultDirectory,
    required Uint8List masterKey,
    required VaultBlob blob,
  }) async {
    borrowedKey = masterKey;
    return Uint8List.fromList([1, 2, 3]);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

VaultSession fixtureSession({
  Directory? directory,
  OpenVaultRepository? openRepository,
  TrackingBlobStore? blobStore,
}) => VaultSession(
  resolveDirectory: () async => directory ?? Directory('/unused-test-vault'),
  loadPassphraseCodec: () async => ChinesePassphraseCodec.parse(
    await File('assets/wordlists/new-default-pinyin.wordlist').readAsString(),
  ),
  openRepository: openRepository ?? (_, _) async => SessionRepository(),
  biometricKeyStore: NoBiometrics(),
  blobStore: blobStore ?? TrackingBlobStore(),
);
