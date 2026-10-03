import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import '../ports/device_factor_protection.dart';
import 'header_encoding.dart';
import 'owner_crypto.dart';
import 'recovery_credential.dart';
import 'vault_password_policy.dart';
import 'vault_header_v2.dart';

class VaultHeaderV3 {
  VaultHeaderV3._(this.data);
  final Map<String, Object?> data;
  static const suite = 'lr-owner-v3';
  static const fileProfile = 'hkdf-sha256-keyfile32-v1';
  Uint8List get bytes => HeaderEncoding.encode(data);
  String get vaultId => data['vaultId'] as String;
  int get epoch => data['headerEpoch'] as int;
  int get generation => data['keyGeneration'] as int;
  String get policy => data['dailyPolicy'] as String;
  bool get biometricEnabled => data['biometricEnabled'] == true;
  bool get keyFileEnabled => data['keyFileEnabled'] == true;
  String get passwordKind => data['passwordKind'] as String;
  int? get wordCount => data['wordCount'] as int?;
  DateTime get createdAt => DateTime.parse(data['createdAt'] as String);
  List<Map<String, Object?>> get branches =>
      (data['branches'] as List).cast<Map<String, Object?>>();
  List<String> get deviceReferences => [
    for (final b in branches)
      for (final f in b['factors'] as List)
        if (f['kind'] == 'device') f['deviceReference'] as String,
  ];
  Map<String, Object?> get unsigned => Map.of(data)..remove('headerMac');

  static VaultHeaderV3 decode(List<int> bytes) {
    if (bytes.isEmpty || bytes.length > 65536) {
      throw const FormatException('Header 大小错误');
    }
    final h = OwnerCrypto.map(jsonDecode(utf8.decode(bytes)), {
      'formatVersion',
      'suite',
      'vaultId',
      'headerEpoch',
      'keyGeneration',
      'createdAt',
      'dailyPolicy',
      'passwordKind',
      'wordCount',
      'biometricEnabled',
      'keyFileEnabled',
      'recoveryEnabled',
      'branches',
      'headerMac',
    });
    if (h['formatVersion'] != 3 ||
        h['suite'] != suite ||
        !['any', 'all'].contains(h['dailyPolicy']) ||
        h['recoveryEnabled'] != true ||
        h['biometricEnabled'] is! bool ||
        h['keyFileEnabled'] is! bool) {
      throw const FormatException('不支持此安全格式');
    }
    if (h['vaultId'] is! String ||
        !RegExp(r'^[0-9a-f]{32}$').hasMatch(h['vaultId'] as String)) {
      throw const FormatException('库标识错误');
    }
    for (final field in ['headerEpoch', 'keyGeneration']) {
      if (h[field] is! int ||
          (h[field] as int) < 1 ||
          (h[field] as int) > 2147483647) {
        throw const FormatException('安全代次错误');
      }
    }
    if (h['createdAt'] is! String ||
        DateTime.tryParse(h['createdAt'] as String)
                ?.toUtc()
                .toIso8601String() !=
            h['createdAt']) {
      throw const FormatException('时间错误');
    }
    if (!((h['passwordKind'] == 'custom' && h['wordCount'] == null) ||
        (h['passwordKind'] == 'diceware-cn-v1' &&
            h['wordCount'] is int &&
            (h['wordCount'] as int) >= 4 &&
            (h['wordCount'] as int) <= 12))) {
      throw const FormatException('密码模式错误');
    }
    final kinds = [
      'password',
      if (h['keyFileEnabled'] == true) 'keyFile',
      if (h['biometricEnabled'] == true) 'device',
    ];
    if (h['dailyPolicy'] == 'all' && kinds.length < 2) {
      throw const FormatException('全部解锁至少需要两种方式');
    }
    final expected = h['dailyPolicy'] == 'all'
        ? ['daily-all', 'recovery']
        : [...kinds, 'recovery'];
    final bs = h['branches'];
    if (bs is! List || bs.length != expected.length) {
      throw const FormatException('分支错误');
    }
    final salts = <String>{}, nonces = <String>{};
    void slot(Object? raw) {
      final s = OwnerCrypto.map(raw, {'nonce', 'cipherText', 'mac'});
      HeaderEncoding.decodeBinary(s['nonce'], 12);
      HeaderEncoding.decodeBinary(s['cipherText'], 32);
      HeaderEncoding.decodeBinary(s['mac'], 16);
      if (!nonces.add(s['nonce'] as String)) {
        throw const FormatException('nonce 重复');
      }
    }

    for (var i = 0; i < bs.length; i++) {
      final b = OwnerCrypto.map(bs[i], {
        'branchId',
        'kind',
        'factors',
        'keySlot',
      });
      final recovery = expected[i] == 'recovery';
      if (b['branchId'] != expected[i] ||
          b['kind'] != (recovery ? 'recovery' : 'daily')) {
        throw const FormatException('分支类型错误');
      }
      final fs = b['factors'];
      final fk = recovery
          ? ['recovery']
          : h['dailyPolicy'] == 'all'
          ? kinds
          : [expected[i]];
      if (fs is! List || fs.length != fk.length) {
        throw const FormatException('因素数量错误');
      }
      for (var j = 0; j < fs.length; j++) {
        final device = fk[j] == 'device';
        final f = OwnerCrypto.map(fs[j], {
          'factorId',
          'kind',
          'profile',
          'factorSlot',
          device ? 'deviceReference' : 'salt',
        });
        if (f['factorId'] != fk[j] || f['kind'] != fk[j]) {
          throw const FormatException('因素类型错误');
        }
        final profile = switch (fk[j]) {
          'password' => VaultHeaderV2.passwordProfile,
          'device' => VaultHeaderV2.deviceProfile,
          'recovery' => 'hkdf-sha256-lrr1-v3',
          _ => fileProfile,
        };
        if (f['profile'] != profile) {
          throw const FormatException('因素 profile 错误');
        }
        if (device) {
          if (f['deviceReference'] is! String ||
              !RegExp(r'^[0-9a-f]{32}$')
                  .hasMatch(f['deviceReference'] as String)) {
            throw const FormatException('设备引用错误');
          }
        } else {
          HeaderEncoding.decodeBinary(f['salt'], 16);
          if (!salts.add(f['salt'] as String)) {
            throw const FormatException('盐重复');
          }
        }
        slot(f['factorSlot']);
      }
      slot(b['keySlot']);
    }
    HeaderEncoding.decodeBinary(h['headerMac'], 32);
    if (Mac(bytes) != Mac(HeaderEncoding.encode(h))) {
      throw const FormatException('Header 非规范编码');
    }
    return VaultHeaderV3._(h);
  }

  Future<List<int>> get descriptor async {
    final d = unsigned;
    d['branches'] = [
      for (final b in branches)
        {
          ...b,
          'factors': [
            for (final raw in b['factors'] as List)
              Map<String, Object?>.from(raw as Map)..remove('factorSlot'),
          ],
        }..remove('keySlot'),
    ];
    return (await Sha256().hash(HeaderEncoding.encode(d))).bytes;
  }

  static Uint8List aad(
    List<int> d,
    String branch,
    String stage, [
    String factor = '',
  ]) => HeaderEncoding.encode([
    'LiveRelay/Header/v3/$stage',
    HeaderEncoding.hex(d),
    branch,
    factor,
  ]);
  static Future<SecretKey> factorKey(
    Map f, {
    String? password,
    Uint8List? keyFile,
    RecoveryCredential? recovery,
  }) async {
    final salt = HeaderEncoding.decodeBinary(f['salt'], 16);
    switch (f['kind']) {
      case 'password':
        if (password == null) throw const FormatException('需要密码');
        return OwnerCrypto.password(password, salt);
      case 'keyFile':
        if (keyFile?.length != 32) throw const FormatException('需要原随机密钥文件');
        return OwnerCrypto.hkdf(
          keyFile!,
          salt,
          'LiveRelay/Header/v3/KeyFileFactor',
        );
      case 'recovery':
        if (recovery == null) throw const FormatException('需要恢复凭证');
        return recovery.deriveWrappingKey(
          salt,
          domain: 'LiveRelay/Header/v3/RecoveryFactor',
        );
      default:
        throw const FormatException('不支持此因素');
    }
  }

  static Future<VaultHeaderV3> create({
    required String password,
    required Uint8List masterKey,
    required RecoveryCredential recovery,
    String passwordKind = 'custom',
    int? wordCount,
    String policy = 'any',
    Uint8List? keyFile,
    DeviceFactorProtection? device,
    String? vaultId,
    int epoch = 1,
    int generation = 1,
    DateTime? createdAt,
  }) async {
    final error = VaultPasswordPolicy.creationError(password);
    if (error != null) throw FormatException(error);
    if (masterKey.length != 32 ||
        (keyFile != null && keyFile.length != 32) ||
        !['any', 'all'].contains(policy)) {
      throw const FormatException('安全参数错误');
    }
    if (device != null &&
        !(await device.capability()).supportsRequiredProtection) {
      throw const DeviceFactorException(DeviceFactorFailure.unavailable);
    }
    final kinds = [
      'password',
      if (keyFile != null) 'keyFile',
      if (device != null) 'device',
    ];
    if (policy == 'all' && kinds.length < 2) {
      throw const FormatException('全部解锁至少需要两种方式');
    }
    final groups = policy == 'all'
        ? [
            kinds,
            ['recovery'],
          ]
        : [
            for (final k in kinds) [k],
            ['recovery'],
          ];
    final bs = <Map<String, Object?>>[
      for (final group in groups)
        {
          'branchId': group.length > 1 ? 'daily-all' : group.single,
          'kind': group.singleOrNull == 'recovery' ? 'recovery' : 'daily',
          'factors': [
            for (final k in group)
              <String, Object?>{
                'factorId': k,
                'kind': k,
                'profile': switch (k) {
                  'password' => VaultHeaderV2.passwordProfile,
                  'device' => VaultHeaderV2.deviceProfile,
                  'recovery' => 'hkdf-sha256-lrr1-v3',
                  _ => fileProfile,
                },
                if (k == 'device')
                  'deviceReference': HeaderEncoding.hex(OwnerCrypto.random(16))
                else
                  'salt': HeaderEncoding.binary(OwnerCrypto.random(16)),
              },
          ],
        },
    ];
    final h = <String, Object?>{
      'formatVersion': 3,
      'suite': suite,
      'vaultId': vaultId ?? HeaderEncoding.hex(OwnerCrypto.random(16)),
      'headerEpoch': epoch,
      'keyGeneration': generation,
      'createdAt': (createdAt ?? DateTime.now().toUtc())
          .toUtc()
          .toIso8601String(),
      'dailyPolicy': policy,
      'passwordKind': passwordKind,
      'wordCount': wordCount,
      'biometricEnabled': device != null,
      'keyFileEnabled': keyFile != null,
      'recoveryEnabled': true,
      'branches': bs,
    };
    final result = VaultHeaderV3._(h);
    final d = await result.descriptor;
    final created = <String>[];
    try {
      for (final b in bs) {
        final id = b['branchId'] as String, fs = b['factors'] as List;
        final secret = OwnerCrypto.random(32), combined = Uint8List(32);
        try {
          for (var i = 0; i < fs.length; i++) {
            final f = fs[i] as Map<String, Object?>;
            final share = i == fs.length - 1
                ? Uint8List.fromList([
                    for (var j = 0; j < 32; j++) secret[j] ^ combined[j],
                  ])
                : OwnerCrypto.random(32);
            for (var j = 0; j < 32; j++) {
              combined[j] ^= share[j];
            }
            SecretKey? key;
            try {
              final context = aad(d, id, 'factor', f['factorId'] as String);
              if (f['kind'] == 'device') {
                final ref = f['deviceReference'] as String;
                final box = await device!.protectFactor(
                  DeviceFactorContext(reference: ref, aad: context),
                  share,
                );
                created.add(ref);
                f['factorSlot'] = {
                  'nonce': HeaderEncoding.binary(box.nonce),
                  'cipherText': HeaderEncoding.binary(box.cipherText),
                  'mac': HeaderEncoding.binary(box.mac),
                };
              } else {
                key = await factorKey(
                  f,
                  password: password,
                  keyFile: keyFile,
                  recovery: recovery,
                );
                f['factorSlot'] = await OwnerCrypto.seal(share, key, context);
              }
            } finally {
              key?.destroy();
              OwnerCrypto.wipe(share);
            }
          }
          final key = await OwnerCrypto.hkdf(
            secret,
            d,
            'LiveRelay/Header/v3/BranchKey/$id',
          );
          try {
            b['keySlot'] = await OwnerCrypto.seal(
              masterKey,
              key,
              aad(d, id, 'master'),
            );
          } finally {
            key.destroy();
          }
        } finally {
          OwnerCrypto.wipe(secret);
          OwnerCrypto.wipe(combined);
        }
      }
      h['headerMac'] = HeaderEncoding.binary(await result.mac(masterKey));
      return decode(result.bytes);
    } on Object {
      for (final ref in created) {
        try {
          await device!.deleteFactor(ref);
        } on Object {
          /* no host fallback */
        }
      }
      rethrow;
    }
  }

  Future<List<int>> mac(List<int> master) async {
    final salt = [
      for (var i = 0; i < 16; i++)
        int.parse(vaultId.substring(i * 2, i * 2 + 2), radix: 16),
    ];
    final key = await OwnerCrypto.hkdf(
      master,
      salt,
      'LiveRelay/Header/v3/HeaderMac',
    );
    try {
      return (await Hmac.sha256().calculateMac(
        HeaderEncoding.encode(unsigned),
        secretKey: key,
      )).bytes;
    } finally {
      key.destroy();
    }
  }

  Future<void> verifyMasterKey(Uint8List key) async {
    if (key.length != 32 ||
        Mac(await mac(key)) !=
            Mac(HeaderEncoding.decodeBinary(data['headerMac'], 32))) {
      throw const FormatException('凭证不正确或 Header 已损坏');
    }
  }

  Future<Uint8List> unlock({
    String? password,
    Uint8List? keyFile,
    DeviceFactorProtection? device,
    RecoveryCredential? recovery,
    String preferred = 'password',
  }) async {
    final id = recovery != null
        ? 'recovery'
        : policy == 'all'
        ? 'daily-all'
        : preferred;
    final candidates = branches.where((b) => b['branchId'] == id);
    if (candidates.isEmpty) throw const FormatException('此方式未启用');
    final b = candidates.single, fs = b['factors'] as List;
    // Reject missing daily factors before asking the device to authorize.
    for (final f in fs) {
      if (f['kind'] == 'password' && password == null ||
          f['kind'] == 'keyFile' && keyFile?.length != 32 ||
          f['kind'] == 'device' && device == null) {
        throw const FormatException('请提供全部已启用的日常凭证');
      }
    }
    final d = await descriptor, secret = Uint8List(32);
    Uint8List? master;
    try {
      for (final raw in fs) {
        final f = raw as Map,
            context = aad(d, id, 'factor', f['factorId'] as String);
        SecretKey? key;
        Uint8List? share;
        try {
          if (f['kind'] == 'device') {
            final slot = f['factorSlot'] as Map;
            share = await device!.unprotectFactor(
              DeviceFactorContext(
                reference: f['deviceReference'] as String,
                aad: context,
              ),
              WrappedDeviceFactor(
                nonce: HeaderEncoding.decodeBinary(slot['nonce'], 12),
                cipherText: HeaderEncoding.decodeBinary(slot['cipherText'], 32),
                mac: HeaderEncoding.decodeBinary(slot['mac'], 16),
              ),
            );
          } else {
            key = await factorKey(
              f,
              password: password,
              keyFile: keyFile,
              recovery: recovery,
            );
            share = await OwnerCrypto.open(
              f['factorSlot'] as Map,
              key,
              context,
            );
          }
          if (share.length != 32) throw const FormatException('因素长度错误');
          for (var j = 0; j < 32; j++) {
            secret[j] ^= share[j];
          }
        } finally {
          key?.destroy();
          OwnerCrypto.wipe(share);
        }
      }
      final key = await OwnerCrypto.hkdf(
        secret,
        d,
        'LiveRelay/Header/v3/BranchKey/$id',
      );
      try {
        master = await OwnerCrypto.open(
          b['keySlot'] as Map,
          key,
          aad(d, id, 'master'),
        );
      } finally {
        key.destroy();
      }
      await verifyMasterKey(master);
      final result = master;
      master = null;
      return result;
    } finally {
      OwnerCrypto.wipe(secret);
      OwnerCrypto.wipe(master);
    }
  }
}
