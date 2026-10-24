import 'package:flutter/material.dart';

import '../../core/security/password_strength.dart';
import '../../l10n/app_localizations.dart';

/// Three-segment strength bar with a short text label.
///
/// Weak fills one red segment, medium two amber, strong three green. The
/// unfilled segments keep a thin outline so the scale stays readable when
/// only one segment is filled. The label repeats the level as text, so the
/// meaning does not depend on colour alone.
class PasswordStrengthBar extends StatelessWidget {
  const PasswordStrengthBar({super.key, required this.strength});

  final PasswordStrength strength;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final (filled, color, label) = switch (strength) {
      PasswordStrength.weak => (
        1,
        const Color(0xFFD32F2F),
        l10n.passwordStrengthWeak,
      ),
      PasswordStrength.medium => (
        2,
        const Color(0xFFF9A825),
        l10n.passwordStrengthMedium,
      ),
      PasswordStrength.strong => (
        3,
        const Color(0xFF2E7D32),
        l10n.passwordStrengthStrong,
      ),
    };
    final textTheme = Theme.of(context).textTheme;
    return Row(
      children: [
        for (var index = 0; index < 3; index++) ...[
          if (index > 0) const SizedBox(width: 4),
          Expanded(
            child: Container(
              height: 6,
              decoration: BoxDecoration(
                color: index < filled ? color : Colors.transparent,
                border: Border.all(
                  color: color.withValues(alpha: 0.45),
                  width: 1,
                ),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
        ],
        const SizedBox(width: 10),
        Text(
          label,
          style: textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}
