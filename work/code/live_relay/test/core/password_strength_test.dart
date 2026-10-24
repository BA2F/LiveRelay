import 'package:flutter_test/flutter_test.dart';
import 'package:live_relay/core/security/password_strength.dart';

void main() {
  group('PasswordStrengthEstimator', () {
    test('empty and well-known passwords are weak', () {
      expect(PasswordStrengthEstimator.evaluate(''), PasswordStrength.weak);
      expect(
        PasswordStrengthEstimator.evaluate('12345678'),
        PasswordStrength.weak,
      );
      expect(
        PasswordStrengthEstimator.evaluate('password1'),
        PasswordStrength.weak,
      );
    });

    test('keyboard walks collapse instead of counting every character', () {
      expect(
        PasswordStrengthEstimator.evaluate('abcdefghijklmnop'),
        PasswordStrength.weak,
      );
      expect(
        PasswordStrengthEstimator.evaluate('aaaaaaaaaaaaaaaa'),
        PasswordStrength.weak,
      );
    });

    test('twelve or more plain lowercase letters reach medium', () {
      expect(
        PasswordStrengthEstimator.evaluate('mycatlikesfish'),
        PasswordStrength.medium,
      );
    });

    test('mixed classes at length reach strong', () {
      expect(
        PasswordStrengthEstimator.evaluate('Kq7#mZ2!xR9@wT4#'),
        PasswordStrength.strong,
      );
    });

    test('Chinese counts per character', () {
      expect(
        PasswordStrengthEstimator.evaluate('我的密码是安全的'),
        PasswordStrength.strong,
      );
      expect(
        PasswordStrengthEstimator.evaluate('窗台绿萝'),
        PasswordStrength.medium,
      );
    });
  });
}
