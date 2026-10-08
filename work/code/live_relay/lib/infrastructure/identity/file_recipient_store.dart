import 'dart:io';
import 'dart:typed_data';

import '../../core/ports/recipient_store.dart';
import '../../core/identity/protected_recipient_identity.dart';
import '../../core/storage/recoverable_file.dart';

class FileRecipientStore implements RecipientStore {
  FileRecipientStore(this.resolveDirectory);
  final Future<Directory> Function() resolveDirectory;
  late Directory directory;
  @override
  Future<void> initialize() async {
    directory = await resolveDirectory();
  }

  RecoverableFile get _file =>
      RecoverableFile(File('${directory.path}/identity.lridentity'));
  @override
  Future<Uint8List?> readIdentity() async {
    await _file.recover((bytes) {
      try {
        ProtectedRecipientIdentity.decode(bytes);
        return true;
      } on Object {
        return false;
      }
    });
    if (!await _file.file.exists()) return null;
    if (await _file.file.length() > 65536) {
      throw const FormatException('身份文件过大');
    }
    return _file.file.readAsBytes();
  }

  @override
  Future<void> writeIdentity(Uint8List bytes) => _file.write(bytes);
  @override
  Future<void> writePackage(String packageId, Uint8List bytes) async {
    if (!RegExp(r'^[0-9a-f]{32}$').hasMatch(packageId)) {
      throw const FormatException('交接包标识错误');
    }
    final output = File('${directory.path}/packages/$packageId.lrshare');
    await output.parent.create(recursive: true);
    await output.writeAsBytes(bytes, flush: true);
  }

  @override
  Future<List<SavedRecipientPackage>> savedPackages() async {
    final folder = Directory('${directory.path}/packages');
    if (!await folder.exists()) return [];
    return (await folder.list().toList())
        .whereType<File>()
        .where((f) => f.path.endsWith('.lrshare'))
        .map((f) => SavedRecipientPackage(f.path))
        .toList();
  }
}
