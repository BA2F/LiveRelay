class VaultHeaderMetadata {
  const VaultHeaderMetadata({
    required this.passwordKind,
    required this.wordCount,
    required this.biometricEnabled,
    required this.createdAt,
    this.formatVersion = 1,
    this.recoveryEnabled = false,
    this.dailyPolicy = 'any',
    this.keyFileEnabled = false,
  });

  final int formatVersion;
  final bool recoveryEnabled;
  final String dailyPolicy;
  final bool keyFileEnabled;
  final String passwordKind;
  final int? wordCount;
  final bool biometricEnabled;
  final DateTime createdAt;

  bool get usesChinesePassphrase => passwordKind == 'diceware-cn-v1';
}
