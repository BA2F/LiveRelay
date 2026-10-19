import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_relay/presentation/design_system/app_theme.dart';

void main() {
  test('Windows text theme asks for one CJK-capable family', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final theme = LiveRelayTheme.light();
    for (final style in [
      theme.textTheme.bodyMedium,
      theme.textTheme.titleLarge,
      theme.textTheme.labelLarge,
    ]) {
      expect(style?.fontFamily, LiveRelayTheme.windowsUiFont);
      expect(style?.fontFamilyFallback, contains('Microsoft YaHei'));
    }
  });

  test('other platforms keep their own text theme', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final theme = LiveRelayTheme.light();
    expect(
      theme.textTheme.bodyMedium?.fontFamily,
      isNot(LiveRelayTheme.windowsUiFont),
    );
  });
}
