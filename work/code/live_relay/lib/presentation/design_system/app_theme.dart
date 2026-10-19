import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/material.dart';

import 'appearance_tokens.dart';

class LiveRelayTheme {
  const LiveRelayTheme._();

  static const seed = Color(0xFF9A4D16);

  /// Flutter's Windows text theme asks for Segoe UI, which has no CJK glyphs;
  /// Chinese then falls back to a second family per glyph, so one line can mix
  /// two typefaces and two sets of weights. One CJK-capable UI family keeps
  /// Latin, digits and Chinese on the same face.
  static const windowsUiFont = 'Microsoft YaHei UI';
  static const _windowsFallback = ['Microsoft YaHei', 'Segoe UI', 'Arial'];

  static ThemeData light({
    Color seedColor = seed,
    AppearanceTokens tokens = const AppearanceTokens(),
  }) => _theme(Brightness.light, seedColor, tokens);

  static ThemeData dark({
    Color seedColor = seed,
    AppearanceTokens tokens = const AppearanceTokens(),
  }) => _theme(Brightness.dark, seedColor, tokens);

  static ThemeData _theme(
    Brightness brightness,
    Color seedColor,
    AppearanceTokens tokens,
  ) {
    final scheme = ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: brightness,
      dynamicSchemeVariant: DynamicSchemeVariant.tonalSpot,
    );
    return ThemeData(
      useMaterial3: true,
      extensions: [tokens],
      fontFamily: defaultTargetPlatform == TargetPlatform.windows
          ? windowsUiFont
          : null,
      fontFamilyFallback: defaultTargetPlatform == TargetPlatform.windows
          ? _windowsFallback
          : null,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(minimumSize: const Size(48, 48)),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
      ),
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      appBarTheme: AppBarTheme(
        centerTitle: false,
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surfaceContainerLow,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(tokens.cardRadius),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(tokens.fieldRadius),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(tokens.fieldRadius),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(tokens.fieldRadius),
          borderSide: BorderSide(color: scheme.primary, width: 1.5),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        height: 72,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }
}
