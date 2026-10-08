import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import '../../core/identity/hpke.dart';
import '../../core/identity/local_identity.dart';
import '../../core/identity/protected_recipient_identity.dart';
import '../../core/identity/scoped_delivery.dart';
import '../../core/ports/recipient_store.dart';
import '../../core/security/header_encoding.dart';
import '../../core/security/owner_crypto.dart';
import '../../core/security/vault_password_policy.dart';

/// Independent recipient use cases; no owner session, Flutter or file APIs.
class RecipientRuntime {
  RecipientRuntime(this.store, {this.derivePasswordKey = OwnerCrypto.password});
  final RecipientStore store;
  final Future<SecretKey> Function(String password, List<int> salt)
  derivePasswordKey;
  LocalIdentity? _identity;
  LocalIdentity? get identity => _identity;
  SecretKey? _protection;
  Uint8List? _salt;
  Map<String, Object?> _state = {};
  Map<String, Object?>? _snapshot;
  Map<String, Object?>? get snapshot => _snapshot;
  bool _exists = false, _initialized = false, _busy = false, _disposed = false;
  bool get exists => _exists;
  bool get busy => _busy;
  int _epoch = 0;
  final _changes = StreamController<void>.broadcast(sync: true);
  Stream<void> get changes => _changes.stream;
  void _notify() {
    if (!_disposed) _changes.add(null);
  }

  void _ensureLive() {
    if (_disposed) throw StateError('接收者服务已关闭');
  }

  void _ensureCurrent(int epoch) {
    _ensureLive();
    if (epoch != _epoch) throw StateError('身份操作已取消');
  }

  Future<T> _run<T>(
    Future<T> Function(int epoch) operation, {
    bool initializing = false,
  }) async {
    _ensureLive();
    if (_busy) throw StateError('请等待当前身份操作完成');
    if (!_initialized && !initializing) throw StateError('请先初始化接收者');
    _busy = true;
    final epoch = _epoch;
    _notify();
    try {
      return await operation(epoch);
    } finally {
      _busy = false;
      _notify();
    }
  }

  Future<void> initialize() => _run((epoch) async {
    await store.initialize();
    _ensureCurrent(epoch);
    final bytes = await store.readIdentity();
    try {
      _ensureCurrent(epoch);
      _exists = bytes != null;
      _initialized = true;
    } finally {
      OwnerCrypto.wipe(bytes);
    }
  }, initializing: true);

  Future<void> create(String name, String password) => _run((epoch) async {
    if (_exists) throw StateError('接收者身份已经存在');
    final error = VaultPasswordPolicy.creationError(password);
    if (error != null) throw FormatException(error);
    LocalIdentity.validateName(name);
    final salt = OwnerCrypto.random(16);
    SecretKey? key;
    LocalIdentity? next;
    bool adopted = false;
    try {
      key = await derivePasswordKey(password, salt);
      _ensureCurrent(epoch);
      next = await LocalIdentity.create(name);
      final state = <String, Object?>{
        'identity': await next.privateData(),
        'owners': <String, Object?>{},
        'receipts': <String, Object?>{},
      };
      await _writeState(state, key, salt, epoch);
      if (!_disposed) _exists = true; // Durable commit may finish after lock.
      _ensureCurrent(epoch);
      _adopt(next, key, salt, state);
      adopted = true;
    } finally {
      if (!adopted) {
        next?.dispose();
        key?.destroy();
        OwnerCrypto.wipe(salt);
      }
    }
  });
  Future<void> unlock(String password) =>
      _run((epoch) => _unlock(password, epoch));
  Future<void> _unlock(String password, int epoch) async {
    final bytes = await store.readIdentity();
    if (bytes == null) throw StateError('请先创建或导入接收者身份');
    Uint8List? salt, clear;
    SecretKey? key;
    LocalIdentity? next;
    bool adopted = false;
    try {
      _ensureCurrent(epoch);
      final data = ProtectedRecipientIdentity.decode(bytes);
      salt = HeaderEncoding.decodeBinary(data['salt'], 16);
      key = await derivePasswordKey(password, salt);
      _ensureCurrent(epoch);
      clear = await OwnerCrypto.open(
        data['box'] as Map,
        key,
        ProtectedRecipientIdentity.aad(salt, data['length'] as int),
        length: data['length'] as int,
      );
      final state = OwnerCrypto.map(jsonDecode(utf8.decode(clear)), {
        'identity',
        'owners',
        'receipts',
      });
      if (state['owners'] is! Map || state['receipts'] is! Map) {
        throw const FormatException('身份状态格式错误');
      }
      next = await LocalIdentity.fromPrivate(state['identity'] as Map);
      _ensureCurrent(epoch);
      _adopt(next, key, salt, state);
      adopted = true;
    } finally {
      OwnerCrypto.wipe(bytes);
      OwnerCrypto.wipe(clear);
      if (!adopted) {
        next?.dispose();
        key?.destroy();
        OwnerCrypto.wipe(salt);
      }
    }
  }

  void _adopt(
    LocalIdentity next,
    SecretKey key,
    Uint8List salt,
    Map<String, Object?> state,
  ) {
    _identity?.dispose();
    _protection?.destroy();
    OwnerCrypto.wipe(_salt);
    _identity = next;
    _protection = key;
    _salt = salt;
    _state = state;
    _snapshot = null;
  }

  Future<void> _writeState(
    Map<String, Object?> state,
    SecretKey key,
    Uint8List salt,
    int epoch,
  ) async {
    _ensureCurrent(epoch);
    final clear = LocalIdentity.encodeJson(state);
    Uint8List? encoded;
    try {
      final aad = ProtectedRecipientIdentity.aad(salt, clear.length);
      final header = jsonDecode(utf8.decode(aad)) as Map<String, dynamic>;
      encoded = HeaderEncoding.encode({
        ...header,
        'box': await OwnerCrypto.seal(clear, key, aad),
      });
      _ensureCurrent(epoch);
      await store.writeIdentity(encoded);
    } finally {
      OwnerCrypto.wipe(clear);
      OwnerCrypto.wipe(encoded);
    }
  }

  Future<Uint8List> exportProtectedIdentity() => _run((epoch) async {
    if (_identity == null) throw StateError('请先解锁身份');
    final bytes = await store.readIdentity();
    try {
      _ensureCurrent(epoch);
      if (bytes == null) throw StateError('身份文件不存在');
      return bytes;
    } on Object {
      OwnerCrypto.wipe(bytes);
      rethrow;
    }
  });
  Future<void> importProtectedIdentity(Uint8List bytes, String password) =>
      _run((epoch) async {
        if (_exists) throw StateError('本机已有接收者身份，请使用独立设备或先备份身份');
        final data = ProtectedRecipientIdentity.decode(bytes);
        final salt = HeaderEncoding.decodeBinary(data['salt'], 16);
        SecretKey? key;
        Uint8List? clear;
        LocalIdentity? next;
        bool adopted = false;
        try {
          key = await derivePasswordKey(password, salt);
          _ensureCurrent(epoch);
          clear = await OwnerCrypto.open(
            data['box'] as Map,
            key,
            ProtectedRecipientIdentity.aad(salt, data['length'] as int),
            length: data['length'] as int,
          );
          final state = OwnerCrypto.map(jsonDecode(utf8.decode(clear)), {
            'identity',
            'owners',
            'receipts',
          });
          if (state['owners'] is! Map || state['receipts'] is! Map) {
            throw const FormatException('身份状态格式错误');
          }
          next = await LocalIdentity.fromPrivate(state['identity'] as Map);
          _ensureCurrent(epoch);
          await store.writeIdentity(bytes);
          if (!_disposed) _exists = true;
          _ensureCurrent(epoch);
          // Adopt the identity we just authenticated; no second password derivation.
          _adopt(next, key, salt, state);
          adopted = true;
        } finally {
          OwnerCrypto.wipe(clear);
          if (!adopted) {
            next?.dispose();
            key?.destroy();
            OwnerCrypto.wipe(salt);
          }
        }
      });
  Future<Uint8List> answerChallenge(
    Map<String, Object?> input,
    String trustedOwnerFingerprint,
  ) => _run((epoch) async {
    final current = _identity;
    if (current == null) throw StateError('请先解锁接收者身份');
    final data = OwnerCrypto.map(input, {
      'version',
      'kind',
      'id',
      'owner',
      'recipient',
      'box',
      'signature',
    });
    final owner = LocalIdentity.validatePublic(data['owner']);
    if (data['version'] != 1 ||
        data['kind'] != 'recipient-challenge' ||
        data['recipient'] != await current.fingerprint() ||
        trustedOwnerFingerprint != await LocalIdentity.fingerprintOf(owner)) {
      throw const FormatException('请核对所有者指纹与挑战接收者');
    }
    final unsigned = Map<String, Object?>.from(data)..remove('signature');
    await LocalIdentity.verify(
      owner,
      HeaderEncoding.encode(unsigned),
      data['signature'],
    );
    final header = Map<String, Object?>.from(unsigned)..remove('box');
    final clear = await LocalHpke.open(
      Map<String, Object?>.from(data['box'] as Map),
      current.dh,
      HeaderEncoding.encode(header),
      info: 'LiveRelay/IdentityChallenge/v1',
    );
    try {
      if (clear.length != 32) throw const FormatException('挑战长度错误');
      final response = <String, Object?>{
        'version': 1,
        'kind': 'recipient-proof',
        'id': data['id'],
        'owner': trustedOwnerFingerprint,
        'recipient': data['recipient'],
        'proof': HeaderEncoding.binary(clear),
      };
      final bytes = HeaderEncoding.encode({
        ...response,
        'signature': await current.sign(HeaderEncoding.encode(response)),
      });
      if (_disposed || epoch != _epoch) {
        OwnerCrypto.wipe(bytes);
        _ensureCurrent(epoch);
      }
      return bytes;
    } finally {
      OwnerCrypto.wipe(clear);
    }
  });
  Future<Map<String, Object?>> inspectEnvelope(Uint8List bytes) async {
    _ensureLive();
    return ScopedDelivery.inspectEnvelope(bytes);
  }

  Future<void> receive(
    Uint8List bytes,
    String confirmedOwnerFingerprint, {
    bool saved = false,
  }) => _run((epoch) async {
    final current = _identity;
    if (current == null) throw StateError('请先解锁接收者身份');
    final data = await ScopedDelivery.inspectEnvelope(bytes);
    final owner = LocalIdentity.validatePublic(data['owner']),
        fp = await LocalIdentity.fingerprintOf(
          LocalIdentity.validatePublic(data['owner']),
        );
    if (confirmedOwnerFingerprint != fp ||
        data['recipient'] != await current.fingerprint()) {
      throw const FormatException('交接包身份不匹配，请核对所有者指纹');
    }
    _ensureCurrent(epoch);
    final owners = Map<String, Object?>.from(_state['owners'] as Map),
        receipts = Map<String, Object?>.from(_state['receipts'] as Map);
    final prior = owners[fp] as Map?;
    final digest = HeaderEncoding.hex((await Sha256().hash(bytes)).bytes);
    if (saved) {
      if (receipts[data['packageId']] != digest) {
        throw StateError('此包没有已验证接收记录');
      }
    } else if (receipts.containsKey(data['packageId']) ||
        (prior != null &&
            (data['sequence'] as int) <= (prior['sequence'] as int))) {
      throw StateError('重复或旧版本交接包已拒绝');
    }
    final header = Map<String, Object?>.from(data)
      ..remove('signature')
      ..remove('box');
    final clear = await LocalHpke.open(
      Map<String, Object?>.from(data['box'] as Map),
      current.dh,
      HeaderEncoding.encode(header),
    );
    try {
      if (HeaderEncoding.hex((await Sha256().hash(clear)).bytes) !=
          data['scopeDigest']) {
        throw const FormatException('范围摘要校验失败');
      }
      final payload = OwnerCrypto.map(jsonDecode(utf8.decode(clear)), {
        'version',
        'records',
        'originals',
      });
      if (payload['version'] != 1 ||
          payload['records'] is! List ||
          (payload['records'] as List).length > 200 ||
          payload['originals'] is! Map) {
        throw const FormatException('只读资料格式错误');
      }
      ScopedDelivery.validatePayload(payload);
      _ensureCurrent(epoch);
      if (!saved) {
        if (receipts.length >= 200) throw StateError('本机接收记录已达上限，请保存身份备份后整理');
        owners[fp] = {'public': owner, 'sequence': data['sequence']};
        receipts[data['packageId'] as String] = digest;
        if (owners.length > 64) throw StateError('本机信任身份已达上限');
        final nextState = {..._state, 'owners': owners, 'receipts': receipts};
        _ensureCurrent(epoch);
        await store.writePackage(data['packageId'] as String, bytes);
        _ensureCurrent(epoch);
        await _writeState(nextState, _protection!, _salt!, epoch);
        _ensureCurrent(epoch);
        _state = nextState;
      }
      _ensureCurrent(epoch);
      _snapshot = _freezeJson({
        ...payload,
        'ownerName': LocalIdentity.displayName(owner),
        'date': data['createdAt'],
      }) as Map<String, Object?>;
    } finally {
      OwnerCrypto.wipe(clear);
    }
  });
  Future<List<SavedRecipientPackage>> savedPackages() => _run((epoch) async {
    if (_identity == null) throw StateError('请先解锁接收者身份');
    final result = await store.savedPackages();
    _ensureCurrent(epoch);
    return List.unmodifiable(result);
  });
  static Object? _freezeJson(Object? value) => value is Map
      ? Map<String, Object?>.unmodifiable({
          for (final e in value.entries) e.key as String: _freezeJson(e.value),
        })
      : value is List
      ? List<Object?>.unmodifiable(value.map(_freezeJson))
      : value;
  void lock() {
    _epoch++;
    _identity?.dispose();
    _identity = null;
    _protection?.destroy();
    _protection = null;
    OwnerCrypto.wipe(_salt);
    _salt = null;
    _state = {};
    _snapshot = null;
    _notify();
  }

  void dispose() {
    if (_disposed) return;
    lock();
    _disposed = true;
    unawaited(_changes.close());
  }
}
