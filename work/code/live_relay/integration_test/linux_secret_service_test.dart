import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:live_relay/core/ports/ai_provider.dart';
import 'package:live_relay/infrastructure/ai/ai_provider_settings_store.dart';

/// Run ONLY in the disposable rootfs with its own HOME and D-Bus keyring.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'isolated Ubuntu Secret Service persists fictional settings',
    (tester) async {
      expect(Platform.environment['HOME'], '/root');
      expect(await File('/etc/os-release').readAsString(), contains('22.04'));
      final store = AiProviderSettingsStore();
      try {
        await store.clear();
        await store.saveProtocol(AiProtocol.responses);
        await store.save(
          endpoint: 'https://controlled.invalid/v1/responses',
          model: 'fictional-model',
          apiKey: 'fictional-nonfunctional-key',
        );
        final reopened = AiProviderSettingsStore();
        final settings = await reopened.read();
        expect(settings.isConfigured, isTrue);
        expect(settings.protocol, AiProtocol.responses);
        expect(settings.endpoint, 'https://controlled.invalid/v1/responses');
        expect(settings.model, 'fictional-model');
        expect(await reopened.readApiKey(), 'fictional-nonfunctional-key');
        await reopened.clear();
        expect((await store.read()).hasApiKey, isFalse);
        // No network call: only the native libsecret/Secret Service path.
      } finally {
        await store.clear();
      }
    },
    skip:
        !Platform.isLinux ||
        !const bool.fromEnvironment('ISOLATED_UBUNTU_SECRET_SERVICE'),
  );
}
