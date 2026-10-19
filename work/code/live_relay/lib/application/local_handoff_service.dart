import 'dart:convert';
import 'dart:typed_data';

import '../core/domain/entities.dart';
import '../core/ports/vault_repository.dart';
import '../core/identity/local_identity.dart';
import '../core/identity/hpke.dart';
import '../core/security/header_encoding.dart';
import '../core/security/owner_crypto.dart';
import 'release_preview.dart';
import '../core/ports/vault_lifecycle.dart';
import '../core/ports/vault_originals.dart';

import 'package:cryptography/cryptography.dart';

class ScopedRecord {
  const ScopedRecord(
    this.type,
    this.id,
    this.level, {
    this.history = false,
    this.originalIds = const [],
  });
  final String type, id;
  final VisibilityLevel level;
  final bool history;
  final List<String> originalIds;
}

class LocalHandoffService {
  LocalHandoffService(this.session, {required this.originals});
  final VaultLifecycle session;
  final VaultOriginals originals;
  void _current(int generation) {
    if (!session.isUnlocked || generation != session.sessionGeneration) {
      throw StateError('会话已锁定或重开');
    }
  }

  Future<T> _owned<T>(Future<T> Function() operation) async {
    T? result;
    try {
      return await session.runMutation(() async {
        final generation = session.sessionGeneration;
        final value = await operation();
        result = value;
        _current(generation);
        return value;
      });
    } on Object {
      final late = result;
      if (late is Uint8List) OwnerCrypto.wipe(late);
      rethrow;
    }
  }

  Future<void> saveProfile(String name, String contact, String note) =>
      _owned(() => _saveProfile(name, contact, note));
  Future<Map<String, Object?>> publicIdentity() => _owned(_publicIdentity);

  /// Signs a canonical payload with the owner identity; returns the base64
  /// signature. Used by cradle check-in records.
  Future<String> signPayload(List<int> canonicalBytes) => _owned(() async {
    final owner = await _owner();
    try {
      return await owner.sign(canonicalBytes);
    } finally {
      owner.dispose();
    }
  });

  Future<Uint8List> createChallenge(
    Map<String, Object?> recipient,
    String fingerprint,
  ) {
    final input = Map<String, Object?>.unmodifiable(recipient);
    return _owned(() => _createChallenge(input, fingerprint));
  }

  Future<void> acceptProof(Map<String, Object?> response) {
    final input = Map<String, Object?>.unmodifiable(response);
    return _owned(() => _acceptProof(input));
  }

  Future<Uint8List> exportScope(
    String fingerprint,
    List<ScopedRecord> selections,
  ) {
    final input = List<ScopedRecord>.unmodifiable([
      for (final selection in selections)
        ScopedRecord(
          selection.type,
          selection.id,
          selection.level,
          history: selection.history,
          originalIds: List.unmodifiable(selection.originalIds),
        ),
    ]);
    return _owned(() => _exportScope(fingerprint, input));
  }

  VaultRepository get _repository {
    if (!session.isUnlocked) throw StateError('请先解锁所有者资料库');
    return session.repository;
  }

  Future<Map<String, Object?>> profile() async {
    final generation = session.sessionGeneration;
    final raw = await _repository.readLocalValue('identity.profile');
    _current(generation);
    return raw == null
        ? {'name': '本人', 'contact': '', 'note': ''}
        : Map<String, Object?>.from(jsonDecode(raw) as Map);
  }

  Future<void> _saveProfile(String name, String contact, String note) async {
    LocalIdentity.validateName(name);
    if (contact.length > 300 || note.length > 2000) {
      throw const FormatException('身份资料过长');
    }
    await _repository.writeLocalValue(
      'identity.profile',
      jsonEncode({'name': name.trim(), 'contact': contact, 'note': note}),
    );
  }

  Future<void> _initializeOwner() async {
    final r = _repository, epoch = session.sessionGeneration;
    if (await r.readLocalValue('handoff.owner') != null) return;
    final identity = await LocalIdentity.create(
      (await profile())['name'] as String,
    );
    try {
      if (epoch != session.sessionGeneration) throw StateError('会话已锁定');
      await r.writeLocalValue(
        'handoff.owner',
        jsonEncode(await identity.privateData()),
      );
    } finally {
      identity.dispose();
    }
  }

  Future<LocalIdentity> _owner() async {
    await _initializeOwner();
    final stored = await _repository.readLocalValue('handoff.owner');
    return LocalIdentity.fromPrivate(jsonDecode(stored!) as Map);
  }

  Future<Map<String, Object?>> _public(LocalIdentity identity) async => {
    ...await identity.publicData(),
    'name': HeaderEncoding.binary(
      utf8.encode((await profile())['name'] as String),
    ),
  };
  Future<Map<String, Object?>> _publicIdentity() async {
    final owner = await _owner();
    try {
      return await _public(owner);
    } finally {
      owner.dispose();
    }
  }

  Future<Map<String, Object?>> recipients() async {
    final generation = session.sessionGeneration;
    final raw = await _repository.readLocalValue('handoff.recipients');
    _current(generation);
    return raw == null ? {} : Map<String, Object?>.from(jsonDecode(raw) as Map);
  }

  /// Records the recipient the owner checked through an independent channel.
  ///
  /// The recipient is usually absent while the owner prepares a handoff, so
  /// possession of the private key is proven when they open the package. This
  /// binding keeps the owner's fingerprint check and lets cradle plans pick the
  /// recipient by name; the package itself is still encrypted to that identity.
  Future<void> confirmRecipient(
    Map<String, Object?> recipient,
    String confirmedFingerprint,
  ) {
    final input = Map<String, Object?>.unmodifiable(recipient);
    return _owned(() => _confirmRecipient(input, confirmedFingerprint));
  }

  Future<void> _confirmRecipient(
    Map<String, Object?> recipient,
    String confirmedFingerprint,
  ) async {
    LocalIdentity.validatePublic(recipient);
    final fp = await LocalIdentity.fingerprintOf(recipient);
    if (confirmedFingerprint != fp) {
      throw const FormatException('请通过独立渠道核对并完整输入接收者指纹');
    }
    final epoch = session.sessionGeneration;
    final bindings = await recipients();
    bindings[fp] = {
      'public': recipient,
      'verifiedAt': DateTime.now().toUtc().toIso8601String(),
    };
    if (epoch != session.sessionGeneration) throw StateError('身份核对已取消');
    await _repository.writeLocalValue(
      'handoff.recipients',
      jsonEncode(bindings),
    );
  }

  Future<Uint8List> _createChallenge(
    Map<String, Object?> recipient,
    String confirmedFingerprint,
  ) async {
    final fp = await LocalIdentity.fingerprintOf(recipient);
    if (confirmedFingerprint != fp) {
      throw const FormatException('请通过独立渠道核对并完整输入接收者指纹');
    }
    final epoch = session.sessionGeneration;
    final owner = await _owner();
    final random = OwnerCrypto.random(32);
    try {
      final header = <String, Object?>{
        'version': 1,
        'kind': 'recipient-challenge',
        'id': HeaderEncoding.hex(OwnerCrypto.random(16)),
        'owner': await _public(owner),
        'recipient': fp,
      };
      final box = await LocalHpke.seal(
        random,
        HeaderEncoding.decodeBinary(recipient['encryptionKey'], 32),
        HeaderEncoding.encode(header),
        info: 'LiveRelay/IdentityChallenge/v1',
      );
      final unsigned = {...header, 'box': box};
      final output = {
        ...unsigned,
        'signature': await owner.sign(HeaderEncoding.encode(unsigned)),
      };
      if (epoch != session.sessionGeneration) throw StateError('会话已锁定');
      await _repository.writeLocalValue(
        'handoff.challenge',
        jsonEncode({
          'header': header,
          'random': HeaderEncoding.binary(random),
          'recipient': recipient,
          'expires': DateTime.now()
              .toUtc()
              .add(const Duration(days: 7))
              .toIso8601String(),
        }),
      );
      return HeaderEncoding.encode(output);
    } finally {
      OwnerCrypto.wipe(random);
      owner.dispose();
    }
  }

  Future<void> _acceptProof(Map<String, Object?> response) async {
    final r = _repository, epoch = session.sessionGeneration;
    final raw = await r.readLocalValue('handoff.challenge');
    if (raw == null || raw == '{}') throw StateError('没有待验证挑战');
    final pending = jsonDecode(raw) as Map;
    final header = pending['header'] as Map;
    final recipient = Map<String, Object?>.from(pending['recipient'] as Map);
    final data = OwnerCrypto.map(response, {
      'version',
      'kind',
      'id',
      'owner',
      'recipient',
      'proof',
      'signature',
    });
    if (data['version'] != 1 ||
        data['kind'] != 'recipient-proof' ||
        data['id'] != header['id'] ||
        data['recipient'] != header['recipient'] ||
        data['owner'] !=
            await LocalIdentity.fingerprintOf(
              Map<String, Object?>.from(header['owner'] as Map),
            ) ||
        data['proof'] != pending['random'] ||
        !DateTime.now().toUtc().isBefore(
          DateTime.parse(pending['expires'] as String),
        )) {
      throw const FormatException('身份挑战不匹配或已过期');
    }
    final unsigned = Map<String, Object?>.from(data)..remove('signature');
    await LocalIdentity.verify(
      recipient,
      HeaderEncoding.encode(unsigned),
      data['signature'],
    );
    final bindings = await recipients();
    bindings[data['recipient'] as String] = {
      'public': recipient,
      'verifiedAt': DateTime.now().toUtc().toIso8601String(),
    };
    if (epoch != session.sessionGeneration) throw StateError('身份验证已取消');
    await r.writeLocalValues({
      'handoff.recipients': jsonEncode(bindings),
      'handoff.challenge': '{}',
    });
  }

  Future<Uint8List> _exportScope(
    String recipientFingerprint,
    List<ScopedRecord> selections,
  ) async {
    if (!session.isUnlocked || selections.isEmpty || selections.length > 200) {
      throw StateError('请选择 1–200 条明确授权的记录');
    }
    final r = _repository, epoch = session.sessionGeneration;
    final binding = (await recipients())[recipientFingerprint];
    if (binding is! Map) throw StateError('请先验证接收者身份');
    final recipient = Map<String, Object?>.from(binding['public'] as Map);
    final records = <Map<String, Object?>>[],
        files = <String, Object?>{},
        seen = <String>{};
    final blobs = await r.listBlobs();
    var total = 0;
    for (final selection in selections) {
      if (!['card', 'credential'].contains(selection.type) ||
          selection.level == VisibilityLevel.hidden ||
          !seen.add('${selection.type}/${selection.id}')) {
        throw const FormatException('交接范围包含重复或无效记录');
      }
      ReleasePreview preview;
      final history = <Map<String, Object?>>[];
      if (selection.type == 'card') {
        final card = await r.getCard(selection.id);
        if (card == null || card.isDeleted) throw StateError('所选卡片已经不存在');
        preview = ReleasePreview.card(card, selection.level);
        if (selection.history) {
          if (selection.level.index < VisibilityLevel.full.index) {
            throw StateError('低可见级别不能附带完整历史');
          }
          for (final rev in await r.cardHistory(card.id)) {
            history.add({
              'number': rev.number,
              'title': rev.title,
              'body': rev.content,
              'date': rev.createdAt.toUtc().toIso8601String(),
            });
          }
        }
        if (selection.originalIds.isNotEmpty) {
          if (selection.level != VisibilityLevel.original) {
            throw StateError('只有原件级别可附带明确选择的原件');
          }
          final sources = await r.cardSources(card.id);
          for (final id in selection.originalIds) {
            if (!sources.any((s) => s.blobId == id)) {
              throw StateError('原件不属于所选卡片');
            }
            if (files.containsKey(id)) continue;
            final blob = blobs.singleWhere((b) => b.id == id);
            total += blob.byteLength;
            if (total > 64 * 1024 * 1024) {
              throw StateError('本地交接原件总计不能超过 64 MB');
            }
            final clear = await originals.readOriginal(blob);
            try {
              files[id] = {
                'name': blob.originalName,
                'mimeType': blob.mimeType,
                'bytes': HeaderEncoding.binary(clear),
              };
            } finally {
              OwnerCrypto.wipe(clear);
            }
          }
        }
      } else {
        if (selection.originalIds.isNotEmpty) throw StateError('密码条目没有原件');
        final entry = (await r.listCredentials()).singleWhere(
          (c) => c.id == selection.id,
        );
        preview = ReleasePreview.credential(entry, selection.level);
        if (selection.history) {
          if (selection.level.index < VisibilityLevel.secret.index) {
            throw StateError('密码历史需要密码级别及另行勾选');
          }
          for (final rev in await r.credentialHistory(entry.id)) {
            history.add({
              'number': rev.number,
              'title': rev.title,
              'username': rev.username,
              'secret': rev.secret,
              'website': rev.website,
              'notes': rev.notes,
            });
          }
        }
      }
      records.add({
        'type': selection.type,
        'id': selection.id,
        'level': selection.level.name,
        'title': preview.title,
        'body': preview.body,
        if (preview.secret != null) 'secret': preview.secret,
        'history': history,
        'originalIds': selection.originalIds,
      });
    }
    final clear = LocalIdentity.encodeJson({
      'version': 1,
      'records': records,
      'originals': files,
    });
    if (clear.length > 128 * 1024 * 1024) {
      OwnerCrypto.wipe(clear);
      throw StateError('交接包过大');
    }
    final owner = await _owner();
    try {
      final sequence =
          int.parse(await r.readLocalValue('handoff.sequence') ?? '0') + 1;
      final header = <String, Object?>{
        'version': 1,
        'kind': 'scoped-delivery',
        'packageId': HeaderEncoding.hex(OwnerCrypto.random(16)),
        'owner': await _public(owner),
        'recipient': recipientFingerprint,
        'scopeEpoch': 1,
        'sequence': sequence,
        'createdAt': DateTime.now().toUtc().toIso8601String(),
        'scopeDigest': HeaderEncoding.hex((await Sha256().hash(clear)).bytes),
      };
      final box = await LocalHpke.seal(
        clear,
        HeaderEncoding.decodeBinary(recipient['encryptionKey'], 32),
        HeaderEncoding.encode(header),
      );
      final unsigned = {...header, 'box': box};
      final bytes = HeaderEncoding.encode({
        ...unsigned,
        'signature': await owner.sign(HeaderEncoding.encode(unsigned)),
      });
      if (epoch != session.sessionGeneration) {
        OwnerCrypto.wipe(bytes);
        throw StateError('交接已取消');
      }
      await r.writeLocalValue('handoff.sequence', '$sequence');
      return bytes;
    } finally {
      owner.dispose();
      OwnerCrypto.wipe(clear);
    }
  }
}
