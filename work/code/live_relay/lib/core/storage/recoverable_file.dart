import 'dart:io';

/// Keeps a flushed predecessor across platforms whose rename may first unlink
/// the destination. Sidecars end in .tmp and never enter a vault archive.
class RecoverableFile {
  RecoverableFile(this.file, {this.checkpoint});

  final File file;
  final Future<void> Function(String stage)? checkpoint;
  File get pending => File('${file.path}.tmp');
  File get previous => File('${file.path}.previous.tmp');

  Future<void> _regularOrAbsent(File candidate) async {
    final type = await FileSystemEntity.type(
      candidate.path,
      followLinks: false,
    );
    if (type != FileSystemEntityType.notFound &&
        type != FileSystemEntityType.file) {
      throw const FileSystemException('拒绝使用非普通文件作为资料库状态文件');
    }
  }

  Future<void> recover(bool Function(List<int>) valid) async {
    for (final candidate in [file, previous, pending]) {
      await _regularOrAbsent(candidate);
    }
    if (await file.exists()) return;
    // Prefer the predecessor to an operation that never reached its commit.
    for (final candidate in [previous, pending]) {
      if (!await candidate.exists()) continue;
      if (await candidate.length() > 64 * 1024) {
        throw const FileSystemException('资料库状态文件超出允许大小');
      }
      final bytes = await candidate.readAsBytes();
      if (!valid(bytes)) {
        throw const FileSystemException('资料库写入曾被中断，残留文件已保留');
      }
      // Keep the source until the canonical file has been flushed.
      await file.writeAsBytes(bytes, flush: true);
      return;
    }
  }

  Future<void> write(List<int> bytes) async {
    if (bytes.length > 64 * 1024) {
      throw const FileSystemException('资料库状态文件超出允许大小');
    }
    for (final candidate in [file, previous, pending]) {
      await _regularOrAbsent(candidate);
    }
    await file.parent.create(recursive: true);
    if (await file.exists()) {
      if (await file.length() > 64 * 1024) {
        throw const FileSystemException('资料库状态文件超出允许大小');
      }
      await previous.writeAsBytes(await file.readAsBytes(), flush: true);
    }
    await checkpoint?.call('predecessorSaved');
    await pending.writeAsBytes(bytes, flush: true);
    await checkpoint?.call('pendingWritten');
    // No explicit deletion of the canonical file. The predecessor remains
    // recoverable even if the platform unlinks before replacing it.
    await pending.rename(file.path);
    await checkpoint?.call('replaced');
  }
}
