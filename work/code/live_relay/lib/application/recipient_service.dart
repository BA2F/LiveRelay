import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';

import '../core/identity/hpke.dart';
import '../core/identity/local_identity.dart';
import '../core/security/header_encoding.dart';
import '../core/security/owner_crypto.dart';
import '../core/security/vault_password_policy.dart';
import '../core/storage/recoverable_file.dart';

/// Separate directory, password, identity, trust and receipts. No Owner session.
class RecipientService extends ChangeNotifier {
  RecipientService(this.resolveDirectory);
  final Future<Directory> Function() resolveDirectory;
  LocalIdentity? identity;
  SecretKey? _protection;
  Uint8List? _salt;
  Map<String, Object?> _state = {};
  Map<String, Object?>? snapshot;
  bool exists = false;
  int _epoch = 0;
  late Directory directory;
  Future<void> initialize() async {
    directory = await resolveDirectory();
    exists = await _read() != null;
    notifyListeners();
  }

  RecoverableFile get _file =>
      RecoverableFile(File('${directory.path}/identity.lridentity'));
  Future<Uint8List?> _read() async {
    await _file.recover((bytes) {
      try {
        _decode(bytes);
        return true;
      } catch (_) {
        return false;
      }
    });
    if (!await _file.file.exists()) return null;
    if (await _file.file.length() > 65536) {
      throw const FormatException('身份文件过大');
    }
    return _file.file.readAsBytes();
  }

  static Map<String, Object?> _decode(List<int> bytes) {
    if (bytes.length > 65536) throw const FormatException('身份文件过大');
    final v = OwnerCrypto.map(jsonDecode(utf8.decode(bytes)), {
      'version',
      'suite',
      'salt',
      'length',
      'box',
    });
    if (v['version'] != 1 ||
        v['suite'] != 'lr-recipient-argon2id64-aes256-v1' ||
        v['length'] is! int ||
        (v['length'] as int) < 1 ||
        (v['length'] as int) > 600000) {
      throw const FormatException('身份文件格式错误');
    }
    HeaderEncoding.decodeBinary(v['salt'], 16);
    final box = OwnerCrypto.map(v['box'], {'nonce', 'cipherText', 'mac'});
    HeaderEncoding.decodeBinary(box['nonce'], 12);
    HeaderEncoding.decodeBinary(box['mac'], 16);
    HeaderEncoding.decodeBinary(box['cipherText'], v['length'] as int);
    return v;
  }

  Future<void> create(String name, String password) async {
    if (exists) throw StateError('接收者身份已经存在');
    final error = VaultPasswordPolicy.creationError(password);
    if (error != null) throw FormatException(error);
    final epoch = _epoch;
    final salt = OwnerCrypto.random(16);
    final key = await OwnerCrypto.password(password, salt);
    final next = await LocalIdentity.create(name);
    try {
      if (epoch != _epoch) throw StateError('身份创建已取消');
      identity = next;
      _protection = key;
      _salt = salt;
      _state = {
        'identity': await next.privateData(),
        'owners': <String, Object?>{},
        'receipts': <String, Object?>{},
      };
      await _save();
      exists = true;
      notifyListeners();
    } catch (_) {
      if (identity != next) {
        next.dispose();
        key.destroy();
        OwnerCrypto.wipe(salt);
      }
      lock();
      rethrow;
    }
  }

  Future<void> unlock(String password) async {
    final epoch = _epoch;
    final bytes = await _read();
    if (bytes == null) throw StateError('请先创建或导入接收者身份');
    final data = _decode(bytes),
        salt = HeaderEncoding.decodeBinary(_decode(bytes)['salt'], 16);
    final key = await OwnerCrypto.password(password, salt);
    Uint8List? clear;
    LocalIdentity? next;
    try {
      clear = await OwnerCrypto.open(
        data['box'] as Map,
        key,
        _aad(salt, data['length'] as int),
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
      if (epoch != _epoch) throw StateError('解锁已取消');
      identity?.dispose();
      _protection?.destroy();
      OwnerCrypto.wipe(_salt);
      identity = next;
      _protection = key;
      _salt = salt;
      _state = state;
      snapshot = null;
      notifyListeners();
    } catch (_) {
      next?.dispose();
      key.destroy();
      OwnerCrypto.wipe(salt);
      rethrow;
    } finally {
      OwnerCrypto.wipe(clear);
    }
  }

  List<int> _aad(Uint8List salt, int length) => HeaderEncoding.encode({
    'version': 1,
    'suite': 'lr-recipient-argon2id64-aes256-v1',
    'salt': HeaderEncoding.binary(salt),
    'length': length,
  });
  Future<void> _save() async {
    final clear = LocalIdentity.encodeJson(_state);
    try {
      final header = jsonDecode(
        utf8.decode(_aad(_salt!, clear.length)),
      ) as Map<String, dynamic>;
      await _file.write(
        HeaderEncoding.encode({
          ...header,
          'box': await OwnerCrypto.seal(
            clear,
            _protection!,
            _aad(_salt!, clear.length),
          ),
        }),
      );
    } finally {
      OwnerCrypto.wipe(clear);
    }
  }

  Future<Uint8List> exportProtectedIdentity() async {
    if (identity == null) throw StateError('请先解锁身份');
    return (await _read())!;
  }

  Future<void> importProtectedIdentity(Uint8List bytes, String password) async {
    if (exists) throw StateError('本机已有接收者身份，请使用独立设备或先备份身份');
    final data = _decode(bytes),
        salt = HeaderEncoding.decodeBinary(_decode(bytes)['salt'], 16);
    final key = await OwnerCrypto.password(password, salt);
    Uint8List? clear;
    try {
      clear = await OwnerCrypto.open(
        data['box'] as Map,
        key,
        _aad(salt, data['length'] as int),
        length: data['length'] as int,
      );
      final next = await LocalIdentity.fromPrivate(
        (jsonDecode(utf8.decode(clear)) as Map)['identity'] as Map,
      );
      next.dispose();
      await _file.write(bytes);
      exists = true;
      await unlock(password);
    } finally {
      OwnerCrypto.wipe(clear);
      key.destroy();
      OwnerCrypto.wipe(salt);
    }
  }

  Future<Uint8List> answerChallenge(
    Map<String, Object?> input,
    String trustedOwnerFingerprint,
  ) async {
    final current = identity;
    if (current == null) throw StateError('请先解锁接收者身份');
    final epoch = _epoch;
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
      if (epoch != _epoch) {
        OwnerCrypto.wipe(bytes);
        throw StateError('响应已取消');
      }
      return bytes;
    } finally {
      OwnerCrypto.wipe(clear);
    }
  }

  Future<Map<String, Object?>> inspectEnvelope(Uint8List bytes) async {
    if (bytes.length > 180 * 1024 * 1024) throw const FormatException('交接包过大');
    final data = OwnerCrypto.map(jsonDecode(utf8.decode(bytes)), {
      'version',
      'kind',
      'packageId',
      'owner',
      'recipient',
      'scopeEpoch',
      'sequence',
      'createdAt',
      'scopeDigest',
      'box',
      'signature',
    });
    if (data['version'] != 1 ||
        data['kind'] != 'scoped-delivery' ||
        data['scopeEpoch'] != 1 ||
        data['sequence'] is! int ||
        (data['sequence'] as int) < 1 ||
        data['packageId'] is! String ||
        !RegExp(r'^[0-9a-f]{32}$').hasMatch(data['packageId'] as String) ||
        DateTime.tryParse('${data['createdAt']}') == null) {
      throw const FormatException('交接包格式错误');
    }
    final owner = LocalIdentity.validatePublic(data['owner']);
    final unsigned = Map<String, Object?>.from(data)..remove('signature');
    await LocalIdentity.verify(
      owner,
      HeaderEncoding.encode(unsigned),
      data['signature'],
    );
    return data;
  }

  Future<void> receive(
    Uint8List bytes,
    String confirmedOwnerFingerprint, {
    bool saved = false,
  }) async {
    final current = identity;
    if (current == null) throw StateError('请先解锁接收者身份');
    final epoch = _epoch, data = await inspectEnvelope(bytes);
    final owner = LocalIdentity.validatePublic(data['owner']),
        fp = await LocalIdentity.fingerprintOf(
          LocalIdentity.validatePublic(data['owner']),
        );
    if (confirmedOwnerFingerprint != fp ||
        data['recipient'] != await current.fingerprint()) {
      throw const FormatException('交接包身份不匹配，请核对所有者指纹');
    }
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
      _validatePayload(payload);
      if (epoch != _epoch) throw StateError('接收已取消');
      if (!saved) {
        if (receipts.length >= 200) throw StateError('本机接收记录已达上限，请保存身份备份后整理');
        final output = File(
          '${directory.path}/packages/${data['packageId']}.lrshare',
        );
        await output.parent.create(recursive: true);
        await output.writeAsBytes(bytes, flush: true);
        owners[fp] = {'public': owner, 'sequence': data['sequence']};
        receipts[data['packageId'] as String] = digest;
        if (owners.length > 64) throw StateError('本机信任身份已达上限');
        final nextState = {..._state, 'owners': owners, 'receipts': receipts};
        final previous = _state;
        _state = nextState;
        try {
          await _save();
        } catch (_) {
          _state = previous;
          rethrow;
        }
      }
      if (epoch != _epoch) throw StateError('接收已取消');
      snapshot = {
        ...payload,
        'ownerName': LocalIdentity.displayName(owner),
        'date': data['createdAt'],
      };
      notifyListeners();
    } finally {
      OwnerCrypto.wipe(clear);
    }
  }

  static void _validatePayload(Map<String, Object?> payload) {
    final referenced = <String>{};
    final seen = <String>{};
    for (final raw in payload['records'] as List) {
      if (raw is! Map<String, Object?>) throw const FormatException('交接记录格式错误');
      OwnerCrypto.map(raw, {
        'type',
        'id',
        'level',
        'title',
        'body',
        'history',
        'originalIds',
        if (raw.containsKey('secret')) 'secret',
      });
      if (!['card', 'credential'].contains(raw['type']) ||
          raw['id'] is! String ||
          (raw['id'] as String).length > 100 ||
          !seen.add('${raw['type']}/${raw['id']}') ||
          ![
            'existence',
            'summary',
            'full',
            'secret',
            'original',
          ].contains(raw['level']) ||
          raw['title'] is! String ||
          raw['body'] is! String ||
          raw['history'] is! List ||
          (raw['history'] as List).length > 10000 ||
          raw['originalIds'] is! List) {
        throw const FormatException('交接记录格式错误');
      }
      final credential = raw['type'] == 'credential';
      if (raw.containsKey('secret') &&
          (!credential ||
              !['secret', 'original'].contains(raw['level']) ||
              raw['secret'] is! String)) {
        throw const FormatException('交接密码范围错误');
      }
      final history = raw['history'] as List;
      if (history.isNotEmpty &&
          (credential
              ? !['secret', 'original'].contains(raw['level'])
              : !['full', 'secret', 'original'].contains(raw['level']))) {
        throw const FormatException('交接历史范围错误');
      }
      for (final revision in history) {
        final r = OwnerCrypto.map(
          revision,
          credential
              ? {'number', 'title', 'username', 'secret', 'website', 'notes'}
              : {'number', 'title', 'body', 'date'},
        );
        if (r['number'] is! int ||
            (r['number'] as int) < 1 ||
            r.entries.any((e) => e.key != 'number' && e.value is! String)) {
          throw const FormatException('修订格式错误');
        }
      }
      final ids = raw['originalIds'] as List;
      if (ids.isNotEmpty && (credential || raw['level'] != 'original')) {
        throw const FormatException('交接原件范围错误');
      }
      for (final id in ids) {
        if (id is! String || id.length > 100) {
          throw const FormatException('原件标识错误');
        }
        referenced.add(id);
      }
    }
    final originals = payload['originals'] as Map;
    if (originals.length != referenced.length ||
        !referenced.containsAll(originals.keys.cast<String>())) {
      throw const FormatException('原件范围与记录不一致');
    }
    var total = 0;
    for (final raw in originals.values) {
      final original = OwnerCrypto.map(raw, {'name', 'mimeType', 'bytes'});
      if (original['name'] is! String ||
          (original['name'] as String).length > 1000 ||
          original['mimeType'] is! String ||
          original['bytes'] is! String ||
          (original['bytes'] as String).length > 96 * 1024 * 1024) {
        throw const FormatException('原件格式错误');
      }
      final bytes = Uint8List.fromList(
        base64Url.decode(base64Url.normalize(original['bytes'] as String)),
      );
      try {
        total += bytes.length;
        if (total > 64 * 1024 * 1024 ||
            HeaderEncoding.binary(bytes) != original['bytes']) {
          throw const FormatException('原件大小或编码错误');
        }
      } finally {
        OwnerCrypto.wipe(bytes);
      }
    }
  }

  Future<List<File>> savedPackages() async {
    if (identity == null) throw StateError('请先解锁接收者身份');
    final folder = Directory('${directory.path}/packages');
    if (!await folder.exists()) return [];
    return (await folder.list().toList())
        .whereType<File>()
        .where((f) => f.path.endsWith('.lrshare'))
        .toList();
  }

  void lock() {
    _epoch++;
    identity?.dispose();
    identity = null;
    _protection?.destroy();
    _protection = null;
    OwnerCrypto.wipe(_salt);
    _salt = null;
    _state = {};
    snapshot = null;
    notifyListeners();
  }

  @override
  void dispose() {
    identity?.dispose();
    _protection?.destroy();
    OwnerCrypto.wipe(_salt);
    super.dispose();
  }
}
