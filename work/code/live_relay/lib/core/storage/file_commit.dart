import 'dart:io';

import 'package:path/path.dart' as path;

/// Publishes flushed sidecar content at its canonical path.
///
/// `rename` is the atomic commit on POSIX and on ordinary NTFS paths, so it is
/// always attempted first and keeps that behaviour wherever the platform
/// supports it. A Windows profile whose application directories carry the
/// Encrypted (EFS) attribute refuses the metadata rename inside
/// `%APPDATA%`/`%LOCALAPPDATA%` with `ERROR_NOT_SAME_DEVICE` even though the
/// sidecar and the canonical path share one volume, which is the same
/// limitation Windows' own move API degrades around. In that case the commit
/// falls back to an overwriting copy plus removing the sidecar: the end state
/// Windows produces for a cross-volume move.
///
/// The fallback is not atomic, so callers keep their flushed predecessor and
/// verify installed content afterwards; an interrupted fallback is detected
/// instead of being accepted as a committed state.
Future<void> commitFile(File pending, File target) async {
  try {
    await pending.rename(target.path);
    return;
  } on FileSystemException {
    // Only continue when the failed rename left the sidecar in place.
    if (!await pending.exists()) rethrow;
  }
  await pending.copy(target.path);
  await pending.delete();
}

/// Publishes a staged directory at [target], which must not exist yet.
///
/// Windows cannot copy a directory in a single call, so the fallback for the
/// restricted profiles above walks the tree and then removes the staging
/// directory. Callers authenticate or verify the installed tree before
/// committing the operation.
Future<void> commitDirectory(Directory pending, Directory target) async {
  try {
    await pending.rename(target.path);
    return;
  } on FileSystemException {
    if (!await pending.exists()) rethrow;
  }
  if (await FileSystemEntity.type(target.path, followLinks: false) !=
      FileSystemEntityType.notFound) {
    throw FileSystemException('目标目录已存在，拒绝覆盖', target.path);
  }
  await _copyTree(pending, target);
  await pending.delete(recursive: true);
}

Future<void> _copyTree(Directory source, Directory target) async {
  await target.create(recursive: true);
  await for (final entity in source.list(followLinks: false)) {
    final destination = path.join(target.path, path.basename(entity.path));
    switch (entity) {
      case Directory():
        await _copyTree(entity, Directory(destination));
      case Link():
        await Link(destination).create(await entity.target());
      case File():
        await entity.copy(destination);
      default:
        throw FileSystemException('恢复目录包含不支持的文件类型', entity.path);
    }
  }
}
