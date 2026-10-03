import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'vault_password_policy.dart';
import '../storage/recoverable_file.dart';

class VaultUnlockException implements Exception {
  const VaultUnlockException([this.message = '主密码不正确或 Vault 已损坏']);

  final String message;

  @override
  String toString() => message;
}

class VaultHeaderMetadata {
  const VaultHeaderMetadata({
    required this.passwordKind,
    required this.wordCount,
    required this.biometricEnabled,
    required this.createdAt,
  });

  final String passwordKind;
  final int? wordCount;
  final bool biometricEnabled;
  final DateTime createdAt;

  bool get usesChinesePassphrase => passwordKind == 'diceware-cn-v1';
}

/// Owns the small, non-sensitive vault header and the password key slot.
/// Structured data is encrypted separately with the returned random master key.
class VaultKeyManager {
  VaultKeyManager(this.rootDirectory, {this.writeCheckpoint});

  final Future<void> Function(String stage)? writeCheckpoint;

  static const _aad = 'LiveRelay/VaultMasterKey/v1';
  static const _headerName = 'vault-header.json';
  static const _argonMemoryKiB = 19 * 1024;
  static const _argonIterations = 2;
  static const _argonParallelism = 1;

  final Directory rootDirectory;

  File get headerFile => File('${rootDirectory.path}/$_headerName');

  Future<bool> exists() async {
    await _recoverHeader();
    return headerFile.exists();
  }

  Future<void> _recoverHeader() => RecoverableFile(headerFile).recover((bytes) {
    try {
      final header = jsonDecode(utf8.decode(bytes));
      return header is Map &&
          header['formatVersion'] == 1 &&
          header['passwordSlot'] is Map &&
          header['kdf'] is Map &&
          header['passwordKind'] is String &&
          DateTime.tryParse(header['createdAt'] as String? ?? '') != null;
    } on Object {
      return false;
    }
  });

  Future<VaultHeaderMetadata?> readMetadata() async {
    if (!await exists()) return null;
    final header = await _readHeader();
    return _metadataFromHeader(header);
  }

  Future<Uint8List> create({
    required String canonicalPassword,
    required String passwordKind,
    int? wordCount,
  }) async {
    if (await exists()) throw StateError('Vault 已存在');
    final validationError = VaultPasswordPolicy.creationError(
      canonicalPassword,
    );
    if (validationError != null) throw FormatException(validationError);
    await rootDirectory.create(recursive: true);

    final masterKey = _randomBytes(32);
    final salt = _randomBytes(16);
    final wrappingKey = await _deriveKey(canonicalPassword, salt);
    final cipher = AesGcm.with256bits();
    final nonce = _randomBytes(12);
    final box = await cipher.encrypt(
      masterKey,
      secretKey: wrappingKey,
      nonce: nonce,
      aad: utf8.encode(_aad),
    );
    final now = DateTime.now().toUtc();
    final header = <String, Object?>{
      'formatVersion': 1,
      'databaseCipher': 'sqlcipher',
      'createdAt': now.toIso8601String(),
      'passwordKind': passwordKind,
      'wordCount': wordCount,
      'biometricEnabled': false,
      'kdf': <String, Object>{
        'algorithm': 'argon2id',
        'version': 19,
        'memoryKiB': _argonMemoryKiB,
        'iterations': _argonIterations,
        'parallelism': _argonParallelism,
        'hashLength': 32,
        'salt': base64UrlEncode(salt),
      },
      'passwordSlot': <String, Object>{
        'algorithm': 'aes-256-gcm',
        'nonce': base64UrlEncode(box.nonce),
        'cipherText': base64UrlEncode(box.cipherText),
        'mac': base64UrlEncode(box.mac.bytes),
      },
    };
    await _writeHeader(header);
    return masterKey;
  }

  Future<Uint8List> unlock(String canonicalPassword) async {
    try {
      final header = await _readHeader();
      if (header['formatVersion'] != 1) {
        throw const VaultUnlockException('不支持此 Vault 格式版本');
      }
      final kdf = Map<String, Object?>.from(header['kdf']! as Map);
      if (kdf['algorithm'] != 'argon2id') {
        throw const VaultUnlockException('不支持此 Vault KDF');
      }
      final slot = Map<String, Object?>.from(header['passwordSlot']! as Map);
      final salt = base64Url.decode(kdf['salt']! as String);
      final key = await _deriveKey(
        canonicalPassword,
        salt,
        memoryKiB: kdf['memoryKiB']! as int,
        iterations: kdf['iterations']! as int,
        parallelism: kdf['parallelism']! as int,
        hashLength: kdf['hashLength']! as int,
      );
      final box = SecretBox(
        base64Url.decode(slot['cipherText']! as String),
        nonce: base64Url.decode(slot['nonce']! as String),
        mac: Mac(base64Url.decode(slot['mac']! as String)),
      );
      final clear = await AesGcm.with256bits().decrypt(
        box,
        secretKey: key,
        aad: utf8.encode(_aad),
      );
      if (clear.length != 32) throw const VaultUnlockException();
      return Uint8List.fromList(clear);
    } on VaultUnlockException {
      rethrow;
    } on SecretBoxAuthenticationError {
      throw const VaultUnlockException();
    } on Object {
      throw const VaultUnlockException();
    }
  }

  Future<void> setBiometricEnabled(bool value) async {
    final header = await _readHeader();
    header['biometricEnabled'] = value;
    await _writeHeader(header);
  }

  Future<Map<String, Object?>> _readHeader() async {
    await _recoverHeader();
    if (await headerFile.length() > 64 * 1024) {
      throw const FormatException('Vault header 超出允许大小');
    }
    final decoded = jsonDecode(await headerFile.readAsString());
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('Vault header 格式错误');
    }
    return decoded;
  }

  VaultHeaderMetadata _metadataFromHeader(Map<String, Object?> header) {
    return VaultHeaderMetadata(
      passwordKind: header['passwordKind']! as String,
      wordCount: header['wordCount'] as int?,
      biometricEnabled: header['biometricEnabled'] as bool? ?? false,
      createdAt: DateTime.parse(header['createdAt']! as String),
    );
  }

  Future<SecretKey> _deriveKey(
    String password,
    List<int> salt, {
    int memoryKiB = _argonMemoryKiB,
    int iterations = _argonIterations,
    int parallelism = _argonParallelism,
    int hashLength = 32,
  }) {
    return Argon2id(
      parallelism: parallelism,
      memory: memoryKiB,
      iterations: iterations,
      hashLength: hashLength,
    ).deriveKey(secretKey: SecretKey(utf8.encode(password)), nonce: salt);
  }

  Future<void> _writeHeader(Map<String, Object?> header) async {
    await RecoverableFile(
      headerFile,
      checkpoint: writeCheckpoint,
    ).write(utf8.encode(jsonEncode(header)));
  }

  Uint8List _randomBytes(int length) {
    final random = Random.secure();
    return Uint8List.fromList(
      List<int>.generate(length, (_) => random.nextInt(256)),
    );
  }
}
