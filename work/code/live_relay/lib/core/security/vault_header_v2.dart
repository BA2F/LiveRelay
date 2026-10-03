import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import '../ports/device_factor_protection.dart';
import 'header_encoding.dart';
import 'recovery_credential.dart';
import 'vault_password_policy.dart';

/// Evaluation suite only: default app creation remains v1 until device,
/// backup and recovery-confirmation gates are met. No AND or legacy fallback.
class VaultHeaderV2 {
  VaultHeaderV2._(this._header);
  static const suite = 'lr-or-recovery-v2-evaluation';
  static const deviceSuite = 'lr-or-recovery-device-v2-evaluation';
  static const deviceProfile =
      'android-keystore-aes256-gcm-biometric-per-use-v1';
  static const passwordProfile = 'argon2id-v19-m65536-t3-p1-l32';
  static const recoveryProfile = 'hkdf-sha256-lrr1';
  final Map<String, Object?> _header;
  static final _cipher = AesGcm.with256bits();

  Uint8List get bytes => HeaderEncoding.encode(_header);
  bool get biometricEnabled => _header['biometricEnabled'] == true;
  String? get deviceReference => biometricEnabled
      ? ((_header['branches']! as List)[2] as Map)['deviceReference'] as String
      : null;
  String get passwordKind => _header['passwordKind']! as String;
  int? get wordCount => _header['wordCount'] as int?;
  DateTime get createdAt => DateTime.parse(_header['createdAt']! as String);

  static VaultHeaderV2 decode(List<int> bytes) {
    if (bytes.isEmpty || bytes.length > 64 * 1024) {
      throw const FormatException('Header 超出允许大小');
    }
    final decoded = jsonDecode(utf8.decode(bytes));
    final header = _map(decoded, {
      'formatVersion',
      'suite',
      'vaultId',
      'headerEpoch',
      'keyGeneration',
      'createdAt',
      'dailyPolicy',
      'biometricEnabled',
      'passwordKind',
      'wordCount',
      'recoveryEnabled',
      'branches',
      'headerMac',
    });
    final hasDevice = header['suite'] == deviceSuite;
    if (header['formatVersion'] is! int ||
        header['formatVersion'] != 2 ||
        (header['suite'] != suite && !hasDevice) ||
        header['dailyPolicy'] != 'any' ||
        header['biometricEnabled'] != hasDevice ||
        header['recoveryEnabled'] != true) {
      throw const FormatException('不支持此 Header 版本或策略');
    }
    final id = header['vaultId'];
    if (id is! String || !RegExp(r'^[0-9a-f]{32}$').hasMatch(id)) {
      throw const FormatException('Header 标识错误');
    }
    for (final name in ['headerEpoch', 'keyGeneration']) {
      final n = header[name];
      if (n is! int || n < 1 || n > 2147483647) {
        throw const FormatException('Header 代次错误');
      }
    }
    final date = header['createdAt'];
    if (date is! String ||
        DateTime.tryParse(date)?.toUtc().toIso8601String() != date) {
      throw const FormatException('Header 时间错误');
    }
    final count = header['wordCount'];
    if (!((header['passwordKind'] == 'custom' && count == null) ||
        (header['passwordKind'] == 'diceware-cn-v1' &&
            count is int &&
            count >= 4 &&
            count <= 12))) {
      throw const FormatException('Header 输入模式错误');
    }
    HeaderEncoding.decodeBinary(header['headerMac'], 32);
    final branches = header['branches'];
    if (branches is! List || branches.length != (hasDevice ? 3 : 2)) {
      throw const FormatException('Header 分支错误');
    }
    final salts = <String>{};
    final nonces = <String>{};
    for (var i = 0; i < branches.length; i++) {
      final device = i == 2;
      final branch = _map(branches[i], {
        'branchId',
        'kind',
        'factorSlot',
        'keySlot',
        if (device) ...[
          'deviceProfile',
          'deviceReference',
        ] else ...[
          'kdfProfile',
          'salt',
        ],
      });
      final kind = ['password', 'recovery', 'device'][i];
      if (branch['branchId'] != kind || branch['kind'] != kind) {
        throw const FormatException('不支持此 Header 分支');
      }
      if (device) {
        final reference = branch['deviceReference'];
        if (branch['deviceProfile'] != deviceProfile ||
            reference is! String ||
            !RegExp(r'^[0-9a-f]{32}$').hasMatch(reference)) {
          throw const FormatException('不支持此设备分支');
        }
      } else {
        if (branch['kdfProfile'] !=
            (i == 0 ? passwordProfile : recoveryProfile)) {
          throw const FormatException('不支持此 Header KDF');
        }
        HeaderEncoding.decodeBinary(branch['salt'], 16);
        if (!salts.add(branch['salt']! as String)) {
          throw const FormatException('Header 盐重复');
        }
      }
      for (final field in ['factorSlot', 'keySlot']) {
        final slot = _map(branch[field], {'nonce', 'cipherText', 'mac'});
        HeaderEncoding.decodeBinary(slot['nonce'], 12);
        HeaderEncoding.decodeBinary(slot['cipherText'], 32);
        HeaderEncoding.decodeBinary(slot['mac'], 16);
        if (!nonces.add(slot['nonce']! as String)) {
          throw const FormatException('Header nonce 重复');
        }
      }
    }
    final canonical = HeaderEncoding.encode(header);
    if (!_equal(bytes, canonical)) {
      throw const FormatException('Header 必须使用规范字节');
    }
    return VaultHeaderV2._(header);
  }

  static Map<String, Object?> _map(Object? value, Set<String> fields) {
    if (value is! Map<String, Object?> ||
        value.length != fields.length ||
        !fields.containsAll(value.keys)) {
      throw const FormatException('Header 字段错误');
    }
    return value;
  }

  Map<String, Object?> get _unsigned => Map.of(_header)..remove('headerMac');
  Future<List<int>> get descriptorHash async {
    final descriptor = _unsigned;
    descriptor['branches'] = (_header['branches']! as List).map((b) {
      final branch = Map<String, Object?>.from(b as Map);
      return branch
        ..remove('factorSlot')
        ..remove('keySlot');
    }).toList();
    return (await Sha256().hash(HeaderEncoding.encode(descriptor))).bytes;
  }

  static Uint8List aad(String stage, List<int> descriptor, String branch) =>
      HeaderEncoding.encode([
        'LiveRelay/Header/v2/$stage',
        HeaderEncoding.hex(descriptor),
        branch,
      ]);

  static Future<SecretKey> _passwordKey(String password, List<int> salt) async {
    if (password.length > 4096) throw const FormatException('密码输入超出允许大小');
    final bytes = utf8.encode(password);
    if (bytes.length > 4096) throw const FormatException('密码输入超出允许大小');
    final input = SecretKey(bytes);
    try {
      return await Argon2id(
        memory: 65536,
        iterations: 3,
        parallelism: 1,
        hashLength: 32,
      ).deriveKey(secretKey: input, nonce: salt);
    } finally {
      input.destroy();
      bytes.fillRange(0, bytes.length, 0);
    }
  }

  static Future<SecretKey> _hkdf(
    List<int> secret,
    List<int> salt,
    String info,
  ) async {
    final input = SecretKey(secret);
    try {
      return await Hkdf(
        hmac: Hmac.sha256(),
        outputLength: 32,
      ).deriveKey(secretKey: input, nonce: salt, info: utf8.encode(info));
    } finally {
      input.destroy();
    }
  }

  static Future<Map<String, Object?>> _seal(
    List<int> clear,
    SecretKey key,
    List<int> aad,
  ) async {
    final box = await _cipher.encrypt(
      clear,
      secretKey: key,
      nonce: _random(12),
      aad: aad,
    );
    return {
      'nonce': HeaderEncoding.binary(box.nonce),
      'cipherText': HeaderEncoding.binary(box.cipherText),
      'mac': HeaderEncoding.binary(box.mac.bytes),
    };
  }

  static Future<Uint8List> _open(
    Object? slot,
    SecretKey key,
    List<int> aad,
  ) async {
    final map = slot! as Map<String, Object?>;
    return Uint8List.fromList(
      await _cipher.decrypt(
        SecretBox(
          HeaderEncoding.decodeBinary(map['cipherText'], 32),
          nonce: HeaderEncoding.decodeBinary(map['nonce'], 12),
          mac: Mac(HeaderEncoding.decodeBinary(map['mac'], 16)),
        ),
        secretKey: key,
        aad: aad,
      ),
    );
  }

  static Future<VaultHeaderV2> createForEvaluation({
    required String canonicalPassword,
    required RecoveryCredential recovery,
    required Uint8List masterKey,
    String passwordKind = 'custom',
    int? wordCount,
    DeviceFactorProtection? deviceProtection,
  }) async {
    final error = VaultPasswordPolicy.creationError(canonicalPassword);
    if (error != null) throw FormatException(error);
    if (masterKey.length != 32) throw const FormatException('VMK 长度错误');
    if (!((passwordKind == 'custom' && wordCount == null) ||
        (passwordKind == 'diceware-cn-v1' &&
            wordCount != null &&
            wordCount >= 4 &&
            wordCount <= 12))) {
      throw const FormatException('Header 输入模式错误');
    }
    if (deviceProtection != null &&
        !(await deviceProtection.capability()).supportsRequiredProtection) {
      throw const DeviceFactorException(DeviceFactorFailure.unavailable);
    }
    final reference = deviceProtection == null
        ? null
        : HeaderEncoding.hex(_random(16));
    final branches = <Map<String, Object?>>[
      {
        'branchId': 'password',
        'kind': 'password',
        'kdfProfile': passwordProfile,
        'salt': HeaderEncoding.binary(_random(16)),
      },
      {
        'branchId': 'recovery',
        'kind': 'recovery',
        'kdfProfile': recoveryProfile,
        'salt': HeaderEncoding.binary(_random(16)),
      },
    ];
    if (reference != null) {
      branches.add({
        'branchId': 'device',
        'kind': 'device',
        'deviceProfile': deviceProfile,
        'deviceReference': reference,
      });
    }
    final header = <String, Object?>{
      'formatVersion': 2,
      'suite': reference == null ? suite : deviceSuite,
      'vaultId': HeaderEncoding.hex(_random(16)),
      'headerEpoch': 1,
      'keyGeneration': 1,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'dailyPolicy': 'any',
      'biometricEnabled': reference != null,
      'passwordKind': passwordKind,
      'wordCount': wordCount,
      'recoveryEnabled': true,
      'branches': branches,
    };
    final result = VaultHeaderV2._(header);
    final descriptor = await result.descriptorHash;
    var deviceFactorCreated = false;
    try {
      for (final branch in branches) {
        final id = branch['branchId']! as String;
        final secret = _random(32);
        SecretKey? factorKey;
        SecretKey? wrapKey;
        try {
          final factorAad = aad('factor', descriptor, id);
          if (id == 'device') {
            final wrapped = await deviceProtection!.protectFactor(
              DeviceFactorContext(reference: reference!, aad: factorAad),
              secret,
            );
            deviceFactorCreated = true;
            branch['factorSlot'] = {
              'nonce': HeaderEncoding.binary(wrapped.nonce),
              'cipherText': HeaderEncoding.binary(wrapped.cipherText),
              'mac': HeaderEncoding.binary(wrapped.mac),
            };
          } else {
            final salt = HeaderEncoding.decodeBinary(branch['salt'], 16);
            factorKey = id == 'password'
                ? await _passwordKey(canonicalPassword, salt)
                : await recovery.deriveWrappingKey(salt);
            branch['factorSlot'] = await _seal(secret, factorKey, factorAad);
          }
          wrapKey = await _hkdf(
            secret,
            descriptor,
            'LiveRelay/Header/v2/BranchKey/$id',
          );
          branch['keySlot'] = await _seal(
            masterKey,
            wrapKey,
            aad('master', descriptor, id),
          );
        } finally {
          factorKey?.destroy();
          wrapKey?.destroy();
          secret.fillRange(0, secret.length, 0);
        }
      }
      header['headerMac'] = HeaderEncoding.binary(await result._mac(masterKey));
      return decode(result.bytes);
    } on Object {
      if (deviceFactorCreated && reference != null) {
        try {
          await deviceProtection!.deleteFactor(reference);
        } on Object {
          // An orphan has no VMK, but may require later device cleanup.
        }
      }
      rethrow;
    }
  }

  Future<List<int>> _mac(List<int> masterKey) async {
    final id = _header['vaultId']! as String;
    final salt = List.generate(
      16,
      (i) => int.parse(id.substring(i * 2, i * 2 + 2), radix: 16),
    );
    final key = await _hkdf(masterKey, salt, 'LiveRelay/Header/v2/HeaderMac');
    try {
      return (await Hmac.sha256().calculateMac(
        HeaderEncoding.encode(_unsigned),
        secretKey: key,
      )).bytes;
    } finally {
      key.destroy();
    }
  }

  Future<void> verifyMasterKey(Uint8List key) async {
    if (key.length != 32 ||
        Mac(await _mac(key)) !=
            Mac(HeaderEncoding.decodeBinary(_header['headerMac'], 32))) {
      throw const FormatException('凭证不正确或 Header 已损坏');
    }
  }

  Future<Uint8List> unlockPassword(String canonicalPassword) =>
      _unlock(0, (salt) => _passwordKey(canonicalPassword, salt));
  Future<Uint8List> unlockRecovery(RecoveryCredential recovery) =>
      _unlock(1, recovery.deriveWrappingKey);

  Future<Uint8List> unlockDevice(DeviceFactorProtection protection) {
    if (!biometricEnabled) {
      throw const DeviceFactorException(DeviceFactorFailure.missing);
    }
    return _unlock(2, null, protection: protection);
  }

  Future<Uint8List> _unlock(
    int index,
    Future<SecretKey> Function(List<int>)? factorKey, {
    DeviceFactorProtection? protection,
  }) async {
    Uint8List? secret;
    Uint8List? masterKey;
    SecretKey? factor;
    SecretKey? wrapKey;
    try {
      final branch =
          (_header['branches']! as List)[index] as Map<String, Object?>;
      final id = branch['branchId']! as String;
      final descriptor = await descriptorHash;
      final factorAad = aad('factor', descriptor, id);
      if (index == 2) {
        final slot = branch['factorSlot']! as Map;
        secret = await protection!.unprotectFactor(
          DeviceFactorContext(reference: deviceReference!, aad: factorAad),
          WrappedDeviceFactor(
            nonce: HeaderEncoding.decodeBinary(slot['nonce'], 12),
            cipherText: HeaderEncoding.decodeBinary(slot['cipherText'], 32),
            mac: HeaderEncoding.decodeBinary(slot['mac'], 16),
          ),
        );
        if (secret.length != 32) {
          throw const DeviceFactorException(DeviceFactorFailure.rejected);
        }
      } else {
        factor = await factorKey!(
          HeaderEncoding.decodeBinary(branch['salt'], 16),
        );
        secret = await _open(branch['factorSlot'], factor, factorAad);
      }
      wrapKey = await _hkdf(
        secret,
        descriptor,
        'LiveRelay/Header/v2/BranchKey/$id',
      );
      masterKey = await _open(
        branch['keySlot'],
        wrapKey,
        aad('master', descriptor, id),
      );
      await verifyMasterKey(masterKey);
      final result = masterKey;
      masterKey = null;
      return result;
    } finally {
      factor?.destroy();
      wrapKey?.destroy();
      secret?.fillRange(0, secret.length, 0);
      masterKey?.fillRange(0, masterKey.length, 0);
    }
  }

  static bool _equal(List<int> a, List<int> b) => Mac(a) == Mac(b);
  static Uint8List _random(int count) {
    final random = Random.secure();
    return Uint8List.fromList(List.generate(count, (_) => random.nextInt(256)));
  }
}
