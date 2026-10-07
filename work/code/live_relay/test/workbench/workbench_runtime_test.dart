import 'dart:io';
import 'dart:ui' show AppExitResponse;

import 'package:flutter_test/flutter_test.dart';
import 'package:live_relay/application/workbench/workbench_runtime.dart';
import 'package:live_relay/core/domain/entities.dart';
import 'package:live_relay/infrastructure/app_composition.dart';

import '../support/verification_fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('desktop save, lock and exit preserve pending edits until storage is available', () async {
    final root = await Directory.systemTemp.createTemp('liverelay-runtime-');
    final c = createAppController(
      root,
      NoBiometrics(),
      TestOcr(),
      RecordingConversationAi(),
      TestAiSettings(),
    );
    WorkbenchRuntime? runtime;
    try {
      await c.initialize();
      await c.setupVault(
        password: 'fixture-runtime-password',
        usesChinesePassphrase: false,
      );
      await c.createCard(
        const CardDraft(
          title: 'before',
          content: 'fixture',
          status: CardStatus.draft,
        ),
      );
      runtime = WorkbenchRuntime(c);
      expect(await runtime.requestExit(), AppExitResponse.cancel);
      expect(await c.readWorkbenchState(), isNull);
      await runtime.load(preset: 'assistant');
      expect(runtime.loaded, isTrue);
      final edit = runtime.edits.session(c.cards.single);
      runtime.edits.edit(edit, title: 'pending title');
      runtime.conversation.updateDraft('pending conversation');
      runtime.layout.open('changes');
      // The controller's exclusive-operation flag blocks writes, never drops them.
      c.isBusy = true;
      await expectLater(runtime.saveAndLock(), throwsFormatException);
      expect(c.isUnlocked, isTrue);
      expect(runtime.edits.hasUnsaved, isTrue);
      expect(await runtime.requestExit(), AppExitResponse.cancel);
      c.isBusy = false;
      await runtime.saveAndLock();
      expect(c.isUnlocked, isFalse);
      runtime.dispose();
      runtime = null;
      await c.unlockWithPassword('fixture-runtime-password');
      expect(c.cards.single.title, 'pending title');
      expect(c.cards.single.status, CardStatus.draft);
      runtime = WorkbenchRuntime(c);
      await runtime.load();
      expect(runtime.conversation.draft, 'pending conversation');
      expect(runtime.layout.containing('changes'), isNotNull);
      expect(await runtime.requestExit(), AppExitResponse.exit);
    } finally {
      c.isBusy = false;
      runtime?.dispose();
      await c.lock();
      c.dispose();
      await root.delete(recursive: true);
    }
  });
}
