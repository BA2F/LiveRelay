import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:live_relay/application/app_preferences.dart';

void main() {
  late Directory directory;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('relay-prefs-');
  });
  tearDown(() async {
    await directory.delete(recursive: true);
  });
  test('appearance and unfinished onboarding survive restart; writes are serialized', () async {
    final file = File('${directory.path}/preferences.json');
    final p = AppPreferences(file);
    await p.load(hasExistingVault: false);
    await Future.wait([
      p.setAppearance(mode: AppearanceMode.dark),
      p.setAppearance(size: ReadingSize.large),
      p.beginOnboarding(),
    ]);
    final reopened = AppPreferences(file);
    await reopened.load(hasExistingVault: true);
    expect(reopened.appearance, AppearanceMode.dark);
    expect(reopened.readingSize, ReadingSize.large);
    expect(reopened.onboardingComplete, isFalse);
    expect(reopened.onboardingStarted, isTrue);
    await reopened.finishOnboarding();
    final completed = AppPreferences(file);
    await completed.load(hasExistingVault: true);
    expect(completed.onboardingComplete, isTrue);
    expect(await File('${file.path}.tmp').exists(), isFalse);
    p.dispose();
    reopened.dispose();
    completed.dispose();
  });
  test(
    'legacy vault and corrupt preferences cannot trigger new vault onboarding',
    () async {
      final file = File('${directory.path}/preferences.json');
      final legacy = AppPreferences(file);
      await legacy.load(hasExistingVault: true);
      expect(legacy.onboardingComplete, isTrue);
      await file.writeAsString('{invalid');
      final corrupt = AppPreferences(file);
      await corrupt.load(hasExistingVault: true);
      expect(corrupt.onboardingComplete, isTrue);
      expect(corrupt.appearance, AppearanceMode.system);
      final fresh = AppPreferences(file);
      await fresh.load(hasExistingVault: false);
      expect(fresh.onboardingComplete, isFalse);
      legacy.dispose();
      corrupt.dispose();
      fresh.dispose();
    },
  );
  test(
    'failed persistence does not claim settings or onboarding were saved',
    () async {
      final blocker = File('${directory.path}/blocker');
      await blocker.writeAsString('not a directory');
      final p = AppPreferences(File('${blocker.path}/preferences.json'));
      await p.load(hasExistingVault: false);
      await expectLater(
        p.setAppearance(mode: AppearanceMode.dark),
        throwsA(isA<FileSystemException>()),
      );
      await expectLater(
        p.finishOnboarding(),
        throwsA(isA<FileSystemException>()),
      );
      expect(p.appearance, AppearanceMode.system);
      expect(p.onboardingComplete, isFalse);
      expect(await blocker.readAsString(), 'not a directory');
      p.dispose();
    },
  );
}
