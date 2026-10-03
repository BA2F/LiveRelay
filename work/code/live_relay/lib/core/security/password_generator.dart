import 'dart:math';

class PasswordGenerator {
  static String generate({
    int length = 20,
    bool uppercase = true,
    bool lowercase = true,
    bool digits = true,
    bool symbols = true,
  }) {
    if (length < 8 || length > 128) throw const FormatException('密码长度需为 8～128');
    final groups = <String>[
      if (uppercase) 'ABCDEFGHJKLMNPQRSTUVWXYZ',
      if (lowercase) 'abcdefghijkmnopqrstuvwxyz',
      if (digits) '23456789',
      if (symbols) '!@#%&*+-_=?:',
    ];
    if (groups.isEmpty) throw const FormatException('至少选择一种字符');
    final random = Random.secure();
    final alphabet = groups.join();
    // Rejection sampling keeps the distribution uniform among passwords
    // containing every selected character class.
    while (true) {
      final result = List.generate(
        length,
        (_) => alphabet[random.nextInt(alphabet.length)],
      ).join();
      if (groups.every((g) => result.split('').any(g.contains))) return result;
    }
  }
}
