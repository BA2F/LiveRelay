import 'dart:typed_data';

class SavedRecipientPackage {
  const SavedRecipientPackage(this.path);
  final String path;
}

/// Owns encrypted identity and package IO. Returned bytes are caller-owned;
/// write inputs are borrowed for the duration of the call.
abstract interface class RecipientStore {
  Future<void> initialize();
  Future<Uint8List?> readIdentity();
  Future<void> writeIdentity(Uint8List bytes);
  Future<void> writePackage(String packageId, Uint8List bytes);
  Future<List<SavedRecipientPackage>> savedPackages();
}
