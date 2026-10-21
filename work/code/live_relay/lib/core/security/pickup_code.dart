import 'dart:math';

/// Pickup codes gate a password-protected handoff package.
///
/// Generated codes use 12 characters from an unambiguous uppercase alphabet
/// and are displayed in groups of four. Custom codes are normalized the same
/// way (whitespace and hyphens removed, Latin letters uppercased) and must be
/// at least 12 characters; the same normalization runs on the recipient side,
/// so a code copied from the email always matches.
class PickupCode {
  const PickupCode._();

  static const length = 12;
  static const _alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  static final _separators = RegExp(r'[\s\-]+');
  static final _random = Random.secure();

  static String generate() {
    final buffer = StringBuffer();
    for (var index = 0; index < length; index++) {
      buffer.write(_alphabet[_random.nextInt(_alphabet.length)]);
    }
    return buffer.toString();
  }

  static String normalize(String input) =>
      input.replaceAll(_separators, '').toUpperCase();

  static bool isValid(String input) => normalize(input).length >= length;

  /// Groups the 12-character generated form for display. Custom codes with
  /// other characters are returned normalized without inserted hyphens.
  static String format(String code) {
    final normalized = normalize(code);
    if (normalized.length != length ||
        normalized.split('').any((char) => !_alphabet.contains(char))) {
      return normalized;
    }
    return '${normalized.substring(0, 4)}-'
        '${normalized.substring(4, 8)}-'
        '${normalized.substring(8, 12)}';
  }
}
