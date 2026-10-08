import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:cryptography/cryptography.dart';
import 'package:path/path.dart' as path;

import '../../core/security/vault_header_v3.dart';
import '../../core/security/header_encoding.dart';
import '../../core/security/owner_crypto.dart';

import '../../core/ports/vault_archive.dart';
import '../../core/storage/vault_failures.dart';

export '../../core/ports/vault_archive.dart' show StagedLifeVault;
export '../../core/storage/vault_failures.dart' show LifeVaultArchiveException;

/// Open, versioned `.lvault` container used to move an already encrypted
/// runtime vault. ZIP is only the envelope: SQLCipher and encrypted blobs keep
/// contents confidential, while a VMK-derived HMAC authenticates completeness.
class LifeVaultArchiveService implements VaultArchive {
  static const formatName = 'LiveRelay LifeVault';
  static const formatVersion = 1;
  static const _containerName = 'container.json';
  static const _manifestName = 'manifest.json';
  static const _manifestMacName = 'manifest.mac';
  static const _vaultPrefix = 'vault/';
  static const _macInfo = 'LiveRelay/LifeVaultManifest/v1';
  static const _maximumEntryCount = 10000;
  static const _maximumExpandedBytes = 2 * 1024 * 1024 * 1024;

  final _sha256 = Sha256();
  final _hmac = Hmac.sha256();
  final _hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);

  @override
  Future<Uint8List> create({
    required Directory vaultDirectory,
    required Uint8List masterKey,
    DateTime? createdAt,
    String kind = 'full',
    String? snapshotId,
  }) async {
    final header = File(path.join(vaultDirectory.path, 'vault-header.json'));
    final database = File(path.join(vaultDirectory.path, 'vault.sqlite'));
    if (!await header.exists() || !await database.exists()) {
      throw const LifeVaultArchiveException('Vault 文件不完整，无法导出');
    }

    final rawHeader = await header.readAsBytes();
    final modern = jsonDecode(utf8.decode(rawHeader))['formatVersion'] == 3;
    final version = modern ? 2 : 1;
    if (modern) {
      VaultHeaderV3.decode(rawHeader);
    } else {
      _requireLegacyHeader(rawHeader);
    }
    if (!['full', 'database', 'attachments'].contains(kind) ||
        (!modern && kind != 'full')) {
      throw const LifeVaultArchiveException('分层备份需要先升级安全格式');
    }
    final snapshot = snapshotId ?? HeaderEncoding.hex(OwnerCrypto.random(16));

    final files = <File>[];
    await for (final entity in vaultDirectory.list(recursive: true)) {
      if (entity is! File) continue;
      final relative = path.relative(entity.path, from: vaultDirectory.path);
      if (_isRuntimeSidecar(relative)) continue;
      files.add(entity);
    }
    files.sort((a, b) => a.path.compareTo(b.path));

    final containerBytes = Uint8List.fromList(
      utf8.encode(
        jsonEncode(<String, Object>{
          'format': formatName,
          'formatVersion': version,
          'createdAt': (createdAt ?? DateTime.now().toUtc()).toIso8601String(),
          'payload': 'encrypted-runtime-vault',
          if (modern) 'kind': kind,
          if (modern) 'snapshotId': snapshot,
          'manifestAuthentication': 'hkdf-sha256+hmac-sha256',
        }),
      ),
    );
    final archive = Archive();
    archive.addFile(
      ArchiveFile.noCompress(
        _containerName,
        containerBytes.length,
        containerBytes,
      ),
    );

    final entries = <String, Object?>{};
    entries[_containerName] = await _descriptor(containerBytes);
    final omitted = <String, Object?>{};
    for (final file in files) {
      final relative = path
          .relative(file.path, from: vaultDirectory.path)
          .replaceAll(path.separator, '/');
      final archiveName = '$_vaultPrefix$relative';
      final bytes = await file.readAsBytes();
      final blob = relative.startsWith('blobs/');
      if (kind == 'database' && blob) {
        omitted[relative] = await _descriptor(bytes);
        continue;
      }
      if (kind == 'attachments' && !blob && relative != 'vault-header.json') {
        continue;
      }
      entries[archiveName] = await _descriptor(bytes);
      archive.addFile(ArchiveFile.noCompress(archiveName, bytes.length, bytes));
    }

    final manifestBytes = Uint8List.fromList(
      utf8.encode(
        jsonEncode(<String, Object?>{
          'formatVersion': version,
          'entries': entries,
          if (modern) 'omitted': omitted,
        }),
      ),
    );
    final mac = await _calculateManifestMac(
      manifestBytes,
      masterKey,
      version: version,
    );
    archive
      ..addFile(
        ArchiveFile.noCompress(
          _manifestName,
          manifestBytes.length,
          manifestBytes,
        ),
      )
      ..addFile(
        ArchiveFile.string(_manifestMacName, base64UrlEncode(mac.bytes)),
      );
    return ZipEncoder().encodeBytes(archive, level: 0);
  }

  @override
  Future<StagedLifeVault> stage({
    required Uint8List archiveBytes,
    required Directory stagingParent,
  }) async {
    Archive decoded;
    try {
      decoded = ZipDecoder().decodeBytes(archiveBytes, verify: true);
    } on Object {
      throw const LifeVaultArchiveException('无法读取 .lvault，文件可能已损坏');
    }
    if (decoded.length > _maximumEntryCount) {
      throw const LifeVaultArchiveException('.lvault 条目数量异常');
    }

    final byName = <String, ArchiveFile>{};
    var expandedBytes = 0;
    for (final entry in decoded) {
      if (!entry.isFile || entry.isSymbolicLink) {
        throw const LifeVaultArchiveException('.lvault 包含不支持的目录或链接');
      }
      if (byName.containsKey(entry.name)) {
        throw const LifeVaultArchiveException('.lvault 包含重复条目');
      }
      expandedBytes += entry.size;
      if (expandedBytes > _maximumExpandedBytes) {
        throw const LifeVaultArchiveException('.lvault 解包体积异常');
      }
      byName[entry.name] = entry;
    }

    final containerBytes = _requiredBytes(byName, _containerName);
    final manifestBytes = _requiredBytes(byName, _manifestName);
    final manifestMacText = utf8.decode(
      _requiredBytes(byName, _manifestMacName),
    );
    final manifestMac = _decodeMac(manifestMacText);
    final container = _decodeMap(containerBytes, '容器头');
    if (container['format'] != formatName ||
        ![1, 2].contains(container['formatVersion'])) {
      throw const LifeVaultArchiveException('不支持此 .lvault 格式版本');
    }

    final version = container['formatVersion'] as int;
    final rawHeader = _requiredBytes(
      byName,
      '${_vaultPrefix}vault-header.json',
    );
    if (version == 1) {
      _requireLegacyHeader(rawHeader);
    } else {
      VaultHeaderV3.decode(rawHeader);
    }
    final kind = version == 1 ? 'full' : container['kind'];
    if (!['full', 'database', 'attachments'].contains(kind) ||
        (version == 2 &&
            (container['snapshotId'] is! String ||
                !RegExp(r'^[0-9a-f]{32}$')
                    .hasMatch(container['snapshotId'] as String)))) {
      throw const LifeVaultArchiveException('分层备份标识错误');
    }
    final manifest = _decodeMap(manifestBytes, '清单');
    if (manifest['formatVersion'] != version ||
        manifest['entries'] is! Map ||
        (version == 2 && manifest['omitted'] is! Map)) {
      throw const LifeVaultArchiveException('.lvault 清单格式错误');
    }
    final omitted = version == 1
        ? <String, Object?>{}
        : Map<String, Object?>.from(manifest['omitted'] as Map);
    if ((kind != 'database' && omitted.isNotEmpty) ||
        omitted.length > _maximumEntryCount) {
      throw const LifeVaultArchiveException('缺失原件清单错误');
    }
    for (final item in omitted.entries) {
      _validatePayloadPath('vault/${item.key}');
      if (!item.key.startsWith('blobs/') ||
          item.value is! Map ||
          (item.value as Map)['size'] is! int ||
          (item.value as Map)['size'] as int < 36 ||
          (item.value as Map)['sha256'] is! String) {
        throw const LifeVaultArchiveException('缺失原件清单错误');
      }
    }
    final descriptors = Map<String, Object?>.from(manifest['entries']! as Map);
    if (descriptors.keys.any(
      (name) => name != _containerName && !name.startsWith(_vaultPrefix),
    )) {
      throw const LifeVaultArchiveException('.lvault 清单包含未知条目');
    }
    final expectedNames = descriptors.keys.toSet()
      ..add(_manifestName)
      ..add(_manifestMacName);
    if (!expectedNames.containsAll(byName.keys) ||
        !byName.keys.toSet().containsAll(expectedNames)) {
      throw const LifeVaultArchiveException('.lvault 清单与文件不一致');
    }

    await _verifyDescriptor(
      _containerName,
      containerBytes,
      descriptors[_containerName],
    );
    final staging = await stagingParent.createTemp('liverelay-restore-');
    try {
      for (final name in descriptors.keys.where(
        (name) => name.startsWith(_vaultPrefix),
      )) {
        _validatePayloadPath(name);
        final bytes = _requiredBytes(byName, name);
        await _verifyDescriptor(name, bytes, descriptors[name]);
        final relative = name.substring(_vaultPrefix.length);
        final target = File(
          path.joinAll([staging.path, ...relative.split('/')]),
        );
        await target.parent.create(recursive: true);
        await target.writeAsBytes(bytes, flush: true);
      }
      if (!await File(path.join(staging.path, 'vault-header.json')).exists() ||
          (kind != 'attachments' &&
              !await File(path.join(staging.path, 'vault.sqlite')).exists())) {
        throw const LifeVaultArchiveException('.lvault 缺少必要 Vault 文件');
      }
      return StagedLifeVault(
        directory: staging,
        manifestBytes: manifestBytes,
        manifestMac: manifestMac,
        version: version,
        kind: kind as String,
        snapshotId: container['snapshotId'] as String?,
        omitted: omitted,
        createdAt: DateTime.tryParse('${container["createdAt"]}'),
      );
    } on Object {
      if (await staging.exists()) await staging.delete(recursive: true);
      rethrow;
    }
  }

  void _requireLegacyHeader(List<int> bytes) {
    if (bytes.length > 64 * 1024) {
      throw const LifeVaultArchiveException('Vault Header 超出允许大小');
    }
    final header = _decodeMap(Uint8List.fromList(bytes), 'Vault Header');
    if (header['formatVersion'] != 1) {
      throw const LifeVaultArchiveException('.lvault v1 不支持此 Header；新格式备份尚未提供');
    }
  }

  @override
  Future<void> verifyAuthentication({
    required StagedLifeVault staged,
    required Uint8List masterKey,
  }) async {
    final calculated = await _calculateManifestMac(
      staged.manifestBytes,
      masterKey,
      version: staged.version,
    );
    if (calculated != Mac(staged.manifestMac)) {
      throw const LifeVaultArchiveException('.lvault 完整性校验失败，文件可能被篡改或密码不正确');
    }
  }

  Future<Map<String, Object>> _descriptor(Uint8List bytes) async {
    final digest = await _sha256.hash(bytes);
    return <String, Object>{
      'size': bytes.length,
      'sha256': base64UrlEncode(digest.bytes),
    };
  }

  Future<void> _verifyDescriptor(
    String name,
    Uint8List bytes,
    Object? descriptor,
  ) async {
    if (descriptor is! Map) {
      throw LifeVaultArchiveException('$name 的清单条目错误');
    }
    final item = Map<String, Object?>.from(descriptor);
    final digest = await _sha256.hash(bytes);
    if (item['size'] != bytes.length ||
        item['sha256'] != base64UrlEncode(digest.bytes)) {
      throw LifeVaultArchiveException('$name 完整性校验失败');
    }
  }

  Future<Mac> _calculateManifestMac(
    Uint8List manifest,
    Uint8List masterKey, {
    int version = 1,
  }) async {
    final macKey = await _hkdf.deriveKey(
      secretKey: SecretKey(masterKey),
      // RFC 5869's omitted salt is HashLen zero bytes. This is HMAC-equivalent
      // to the v1 empty salt, but Android's SecretKeySpec rejects an empty key.
      nonce: List<int>.filled(32, 0),
      info: utf8.encode(
        version == 1 ? _macInfo : 'LiveRelay/LifeVaultManifest/v2',
      ),
    );
    return _hmac.calculateMac(manifest, secretKey: macKey);
  }

  Uint8List _requiredBytes(Map<String, ArchiveFile> entries, String name) {
    final bytes = entries[name]?.readBytes();
    if (bytes == null) {
      throw LifeVaultArchiveException('.lvault 缺少 $name');
    }
    return bytes;
  }

  Uint8List _decodeMac(String value) {
    try {
      final bytes = base64Url.decode(value.trim());
      if (bytes.length != 32) throw const FormatException();
      return Uint8List.fromList(bytes);
    } on Object {
      throw const LifeVaultArchiveException('.lvault 清单认证码格式错误');
    }
  }

  Map<String, Object?> _decodeMap(Uint8List bytes, String label) {
    try {
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is Map<String, Object?>) return decoded;
    } on Object {
      // Report the stable, non-sensitive format error below.
    }
    throw LifeVaultArchiveException('.lvault $label格式错误');
  }

  void _validatePayloadPath(String name) {
    if (!name.startsWith(_vaultPrefix) ||
        name.contains('\\') ||
        name.startsWith('/') ||
        name
            .split('/')
            .any(
              (segment) => segment.isEmpty || segment == '.' || segment == '..',
            )) {
      throw const LifeVaultArchiveException('.lvault 包含非法路径');
    }
  }

  bool _isRuntimeSidecar(String relative) =>
      relative.endsWith('-wal') ||
      relative.endsWith('-shm') ||
      relative.endsWith('.tmp');
}
