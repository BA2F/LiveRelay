import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Plaintext working copies belong to the app, never the shared system cache.
Future<Directory> privateCacheDirectory() async {
  final root = await getTemporaryDirectory();
  final directory = Directory('${root.path}/liverelay-private-cache');
  if (await FileSystemEntity.isLink(directory.path)) {
    throw const FileSystemException('临时资料目录不能是链接');
  }
  await directory.create(recursive: true);
  if (Platform.isLinux || Platform.isMacOS) {
    final result = await Process.run('chmod', ['700', directory.path]);
    if (result.exitCode != 0) throw const FileSystemException('无法保护临时资料目录');
  }
  return directory;
}

Future<void> clearPrivateCache(Directory root) async {
  final owned = Directory('${root.path}/liverelay-private-cache');
  if (await FileSystemEntity.isLink(owned.path)) return;
  if (await owned.exists()) {
    await for (final entity in owned.list(followLinks: false)) {
      await entity.delete(recursive: true);
    }
  }
  // Older versions wrote these exact generated file names at cache root.
  // Do not recurse into other applications' directories or match by extension.
  final legacy = RegExp(
    r'^((recording|speech|view)-\d+|ocr-[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})\.[a-z0-9]{1,8}$',
  );
  await for (final entity in root.list(followLinks: false)) {
    if (entity is File && legacy.hasMatch(entity.uri.pathSegments.last)) {
      await entity.delete();
    }
  }
}
