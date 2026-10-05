import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:live_relay/core/ports/ai_provider.dart';
import 'package:live_relay/infrastructure/ai/ai_provider_settings_store.dart';
import 'package:live_relay/infrastructure/speech/remote_speech_settings_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  test('legacy credentials migrate, profiles retain independent protocol/models/keys, removing one preserves others', () async {
    FlutterSecureStorage.setMockInitialValues({
      'endpoint': 'https://legacy.invalid/chat',
      'model': 'legacy-model',
      'api-key': 'fixture-legacy-key',
      'unrelated-key': 'retain',
    });
    final store = AiProviderSettingsStore();
    expect((await store.read()).id, 'legacy');
    expect(await store.readApiKey(), 'fixture-legacy-key');
    await store.saveProfile(
      create: true,
      name: '第二服务',
      endpoint: 'https://second.invalid/responses',
      model: 'new-model',
      models: ['new-model', 'other-model'],
      protocol: AiProtocol.responses,
      images: true,
      files: true,
      apiKey: 'fixture-second-key',
    );
    final second = await store.read();
    expect((await store.readProfiles()).length, 2);
    expect(second.protocol, AiProtocol.responses);
    await store.select('legacy', 'legacy-model');
    expect(await store.readApiKey(), 'fixture-legacy-key');
    await store.select(second.id, 'other-model');
    expect((await store.read()).model, 'other-model');
    expect(await store.readApiKey(), 'fixture-second-key');
    await store.saveProfile(
      id: second.id,
      name: '编辑服务',
      endpoint: second.endpoint,
      model: 'new-model',
      models: second.models,
      protocol: second.protocol,
      images: false,
      files: false,
    );
    expect(await store.readApiKey(), 'fixture-second-key');
    await store.remove('legacy');
    expect((await store.read()).name, '编辑服务');
    await expectLater(
      store.select(second.id, 'unknown'),
      throwsFormatException,
    );
    final speech = RemoteSpeechSettingsStore();
    await speech.save(
      name: '独立语音',
      endpoint: 'https://asr.invalid/transcriptions',
      model: 'asr',
      apiKey: 'fixture-asr-key',
    );
    await store.clear();
    expect(await speech.readApiKey(), 'fixture-asr-key');
    expect(
      await const FlutterSecureStorage().read(key: 'unrelated-key'),
      'retain',
    );
  });
  test('invalid endpoint and unreadable future configuration do not replace existing credentials', () async {
    final store = AiProviderSettingsStore();
    await expectLater(
      store.saveProfile(
        name: 'bad',
        endpoint: 'https://secret:credential@bad.invalid/chat',
        model: 'model',
        models: [],
        protocol: AiProtocol.chatCompletions,
        images: false,
        files: false,
        apiKey: 'fixture',
      ),
      throwsFormatException,
    );
    final raw = jsonEncode({'version': 99, 'future': 'preserve'});
    FlutterSecureStorage.setMockInitialValues({
      'liverelay.ai.profiles.v2': raw,
    });
    await expectLater(store.readProfiles(), throwsFormatException);
    await expectLater(
      store.save(endpoint: 'https://new.invalid/chat', model: 'new'),
      throwsFormatException,
    );
    expect(
      await const FlutterSecureStorage().read(key: 'liverelay.ai.profiles.v2'),
      raw,
    );
  });
}
