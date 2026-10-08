/// Errors owned by the application boundary, independent of ZIP/filesystem
/// implementations. Existing UI translations keep their established messages.
class LifeVaultArchiveException implements Exception {
  const LifeVaultArchiveException(this.message);
  final String message;
  @override
  String toString() => message;
}

class VaultRecoveryException implements Exception {
  const VaultRecoveryException([
    this.message = '资料库恢复曾被中断，文件已保留。请保留备份并检查恢复状态。',
  ]);
  final String message;
  @override
  String toString() => message;
}
