/// Coarse password strength for the setup and change-password fields.
///
/// The estimate is a heuristic: it adds bits per character class, collapses
/// repeated characters and short arithmetic sequences, and rejects strings
/// that contain a well-known password. [evaluate] exposes only three levels
/// on purpose; the app never shows the underlying number, because a typed
/// password with a predictable shape scores far higher than it deserves.
enum PasswordStrength { weak, medium, strong }

class PasswordStrengthEstimator {
  const PasswordStrengthEstimator._();

  /// Below this many estimated bits the password is weak.
  static const weakBelowBits = 40.0;

  /// From this many estimated bits the password is strong.
  static const strongFromBits = 70.0;

  static const _commonPasswords = [
    'password',
    'passw0rd',
    'qwerty',
    'qwertyuiop',
    '123456',
    '12345678',
    '123456789',
    '1234567890',
    'letmein',
    'iloveyou',
    'admin',
    'welcome',
    'monkey',
    'dragon',
    'abc123',
    'football',
    'sunshine',
    'princess',
    'starwars',
    'trustno1',
  ];

  static PasswordStrength evaluate(String password) {
    if (password.isEmpty) return PasswordStrength.weak;
    final lowered = password.toLowerCase();
    for (final common in _commonPasswords) {
      if (lowered.contains(common)) return PasswordStrength.weak;
    }
    final bits = estimateBits(password);
    if (bits < weakBelowBits) return PasswordStrength.weak;
    if (bits < strongFromBits) return PasswordStrength.medium;
    return PasswordStrength.strong;
  }

  /// Estimated bits for a typed password. Runes, so Chinese counts per
  /// character rather than per UTF-16 unit.
  static double estimateBits(String password) {
    var bits = 0.0;
    for (final rune in _collapsedRunes(password)) {
      bits += _bitsPerRune(rune);
    }
    return bits;
  }

  /// Drops characters that repeat the previous one (`aaaa`) and characters
  /// that continue an arithmetic sequence (`abcd`, `1234`, `2468`). Without
  /// this, a keyboard walk would read as a long random string.
  static List<int> _collapsedRunes(String password) {
    final runes = password.runes.toList();
    final kept = <int>[];
    for (var i = 0; i < runes.length; i++) {
      final rune = runes[i];
      if (i > 0 && rune == runes[i - 1]) continue;
      if (i > 1 && rune - runes[i - 1] == runes[i - 1] - runes[i - 2]) {
        continue;
      }
      kept.add(rune);
    }
    return kept;
  }

  static double _bitsPerRune(int rune) {
    if ((rune >= 0x4E00 && rune <= 0x9FFF) ||
        (rune >= 0x3400 && rune <= 0x4DBF)) {
      return 11.0;
    }
    if (rune >= 0x61 && rune <= 0x7A) return 4.7;
    if (rune >= 0x41 && rune <= 0x5A) return 5.7;
    if (rune >= 0x30 && rune <= 0x39) return 3.3;
    return 5.0;
  }
}
