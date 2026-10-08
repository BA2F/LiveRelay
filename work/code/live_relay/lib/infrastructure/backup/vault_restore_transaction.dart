import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:path/path.dart' as path;

import '../../core/storage/recoverable_file.dart';

import '../../core/ports/vault_installation.dart';
import '../../core/storage/vault_failures.dart';

export '../../core/storage/vault_failures.dart' show VaultRecoveryException;

/// A local write-ahead intent plus an independent commit marker. Neither is a
/// credential or a public backup format. Startup never recursively deletes a
/// directory named in a journal; it conservatively rolls back uncommitted work.
class VaultRestoreTransaction implements VaultInstallation {
  VaultRestoreTransaction(this.vault, {this.checkpoint});

  final Directory vault;
  final Future<void> Function(String stage)? checkpoint;
  Directory get parent => vault.parent;
  File get journal => File('${vault.path}.restore.json');
  File get commit => File('${vault.path}.restore.commit.json');
  static final _idPattern = RegExp(r'^[0-9a-f]{32}$');

  Future<void> _type(String name, FileSystemEntityType expected) async {
    final actual = await FileSystemEntity.type(name, followLinks: false);
    if (actual != FileSystemEntityType.notFound && actual != expected) {
      throw const VaultRecoveryException('资料库恢复路径异常，所有文件已保留。');
    }
  }

  Future<void> _validateRoot() async {
    await _type(parent.path, FileSystemEntityType.directory);
    await _type(vault.path, FileSystemEntityType.directory);
    for (final file in [journal, commit]) {
      for (final candidate in [
        file,
        File('${file.path}.tmp'),
        File('${file.path}.previous.tmp'),
      ]) {
        await _type(candidate.path, FileSystemEntityType.file);
      }
    }
  }

  Map<String, dynamic> _decode(List<int> bytes) {
    final value = jsonDecode(utf8.decode(bytes));
    if (value is! Map<String, dynamic> ||
        value['version'] != 1 ||
        value['operationId'] is! String ||
        !_idPattern.hasMatch(value['operationId'] as String)) {
      throw const VaultRecoveryException();
    }
    return value;
  }

  Future<Map<String, dynamic>> _read(File file) async {
    if (await file.length() > 4096) throw const VaultRecoveryException();
    try {
      return _decode(await file.readAsBytes());
    } on Object {
      throw const VaultRecoveryException();
    }
  }

  Future<String> _headerDigest(Directory directory) async {
    await _type(directory.path, FileSystemEntityType.directory);
    final header = File(path.join(directory.path, 'vault-header.json'));
    final database = File(path.join(directory.path, 'vault.sqlite'));
    await _type(header.path, FileSystemEntityType.file);
    await _type(database.path, FileSystemEntityType.file);
    if (!await header.exists() ||
        !await database.exists() ||
        await header.length() > 64 * 1024) {
      throw const VaultRecoveryException();
    }
    return base64UrlEncode(
      (await Sha256().hash(await header.readAsBytes())).bytes,
    );
  }

  Directory _incoming(String id) => Directory('${vault.path}.incoming-$id');
  Directory _rollback(String id) => Directory('${vault.path}.rollback-$id');

  Future<void> _removeState(File file) async {
    // Canonical last: deleting a sidecar cannot resurrect a completed intent.
    for (final candidate in [
      File('${file.path}.tmp'),
      File('${file.path}.previous.tmp'),
      file,
    ]) {
      await _type(candidate.path, FileSystemEntityType.file);
      if (await candidate.exists()) await candidate.delete();
    }
  }

  Future<void> _clearState() async {
    await _removeState(journal);
    await _removeState(commit);
  }

  /// Returns a notice when encrypted remnants were deliberately retained.
  @override
  Future<String?> recover() => _recover();

  Future<String?> _recover({String? expectedStagingName}) async {
    await _validateRoot();
    try {
      await RecoverableFile(journal).recover((bytes) {
        try {
          _decode(bytes);
          return true;
        } on Object {
          return false;
        }
      });
      if (!await journal.exists()) {
        if (await commit.exists()) {
          await _read(commit);
          if (!await vault.exists()) throw const VaultRecoveryException();
          await _removeState(commit);
        }
        if (!await vault.exists() && await parent.exists()) {
          await for (final entity in parent.list(followLinks: false)) {
            final name = path.basename(entity.path);
            if (name == expectedStagingName) continue;
            if (name.startsWith('${path.basename(vault.path)}.rollback-') ||
                name.startsWith('${path.basename(vault.path)}.incoming-') ||
                name.startsWith('liverelay-restore-')) {
              throw const VaultRecoveryException();
            }
          }
        }
        return null;
      }
      final state = await _read(journal);
      if (state.keys.toSet().difference({
            'version',
            'operationId',
            'hadVault',
            'oldHeader',
            'newHeader',
            'stagingName',
          }).isNotEmpty ||
          state['hadVault'] is! bool ||
          state['newHeader'] is! String ||
          state['stagingName'] is! String ||
          !RegExp(r'^liverelay-restore-[a-zA-Z0-9]+$')
              .hasMatch(state['stagingName'] as String) ||
          (state['hadVault'] == true && state['oldHeader'] is! String)) {
        throw const VaultRecoveryException();
      }
      final id = state['operationId'] as String;
      final incoming = _incoming(id);
      final rollback = _rollback(id);
      final originalStaging = Directory(
        path.join(parent.path, state['stagingName'] as String),
      );
      await _type(originalStaging.path, FileSystemEntityType.directory);
      await _type(incoming.path, FileSystemEntityType.directory);
      await _type(rollback.path, FileSystemEntityType.directory);
      if (await commit.exists()) {
        final committed = await _read(commit);
        if (committed['operationId'] != id ||
            committed['newHeader'] != state['newHeader'] ||
            !await vault.exists()) {
          throw const VaultRecoveryException();
        }
        // The installed header may have legitimately changed since commit.
        // Do not delete an old directory using unauthenticated startup state.
        await _clearState();
        return '已完成的恢复已保留；残留加密副本未自动删除。';
      }
      if (state['hadVault'] == true) {
        if (await rollback.exists()) {
          if (await _headerDigest(rollback) != state['oldHeader']) {
            throw const VaultRecoveryException();
          }
          if (await vault.exists()) {
            if (await incoming.exists() ||
                await _headerDigest(vault) != state['newHeader']) {
              throw const VaultRecoveryException();
            }
            await vault.rename(incoming.path);
          }
          await rollback.rename(vault.path);
        } else if (!await vault.exists() ||
            await _headerDigest(vault) != state['oldHeader']) {
          throw const VaultRecoveryException();
        }
        await _clearState();
        return '上次恢复被中断，原资料库已找回。请使用原密码解锁；加密备份副本已保留。';
      }
      if (await rollback.exists()) throw const VaultRecoveryException();
      // First-use restore has no original to roll back. The staged vault was
      // authenticated before this intent was created; keep it locked for the
      // user to authenticate again, and never create an empty replacement.
      if (!await vault.exists() &&
          !await incoming.exists() &&
          await originalStaging.exists()) {
        if (await _headerDigest(originalStaging) != state['newHeader']) {
          throw const VaultRecoveryException();
        }
        await originalStaging.rename(incoming.path);
      }
      if (!await vault.exists() && await incoming.exists()) {
        if (await _headerDigest(incoming) != state['newHeader']) {
          throw const VaultRecoveryException();
        }
        await incoming.rename(vault.path);
      }
      if (!await vault.exists() ||
          await _headerDigest(vault) != state['newHeader']) {
        throw const VaultRecoveryException();
      }
      await _clearState();
      return '已找回中断恢复的资料库，请使用备份密码解锁。';
    } on VaultRecoveryException {
      rethrow;
    } on Object {
      throw const VaultRecoveryException();
    }
  }

  @override
  Future<String?> install(
    Directory staged, {
    required Future<void> Function() verifyInstalled,
    required Future<void> Function() closeInstalled,
  }) async {
    if (path.normalize(path.absolute(staged.parent.path)) !=
            path.normalize(path.absolute(parent.path)) ||
        !RegExp(r'^liverelay-restore-[a-zA-Z0-9]+$')
            .hasMatch(path.basename(staged.path))) {
      throw const VaultRecoveryException('恢复目录必须位于资料库的受控相邻目录。');
    }
    await _recover(expectedStagingName: path.basename(staged.path));
    final newHeader = await _headerDigest(staged);
    final hadVault = await vault.exists();
    final oldHeader = hadVault ? await _headerDigest(vault) : null;
    final random = Random.secure();
    final id = List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    final incoming = _incoming(id);
    final rollback = _rollback(id);
    if (await FileSystemEntity.type(incoming.path, followLinks: false) !=
            FileSystemEntityType.notFound ||
        await FileSystemEntity.type(rollback.path, followLinks: false) !=
            FileSystemEntityType.notFound) {
      throw const VaultRecoveryException();
    }
    await RecoverableFile(
      journal,
      checkpoint: (stage) async => checkpoint?.call('journal.$stage'),
    ).write(
      utf8.encode(
        jsonEncode({
          'version': 1,
          'operationId': id,
          'hadVault': hadVault,
          'oldHeader': oldHeader,
          'newHeader': newHeader,
          'stagingName': path.basename(staged.path),
        }),
      ),
    );
    try {
      await checkpoint?.call('intentWritten');
      await staged.rename(incoming.path);
      await checkpoint?.call('incomingPrepared');
      await checkpoint?.call('beforeOriginalMove');
      if (hadVault) await vault.rename(rollback.path);
      await checkpoint?.call('originalMoved');
      await checkpoint?.call('beforeIncomingInstall');
      await incoming.rename(vault.path);
      await checkpoint?.call('incomingInstalled');
      await verifyInstalled();
      await checkpoint?.call('installedVerified');
      await RecoverableFile(
        commit,
        checkpoint: (stage) async => checkpoint?.call('commit.$stage'),
      ).write(
        utf8.encode(
          jsonEncode({'version': 1, 'operationId': id, 'newHeader': newHeader}),
        ),
      );
    } on Object {
      await closeInstalled();
      await recover();
      rethrow;
    }
    // A failure after the commit point must never roll back a valid new vault.
    try {
      await checkpoint?.call('committed');
      if (hadVault) {
        if (await _headerDigest(rollback) != oldHeader) {
          throw const VaultRecoveryException();
        }
        await checkpoint?.call('beforeCleanup');
        await rollback.delete(recursive: true);
      }
      await _clearState();
      return null;
    } on Object {
      return '资料库已恢复；旧加密副本或恢复记录尚未完成清理，已安全保留。';
    }
  }
}
