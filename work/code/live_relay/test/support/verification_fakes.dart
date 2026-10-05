import 'dart:convert';
import 'dart:typed_data';

import 'package:live_relay/core/ports/biometric_key_store.dart';
import 'package:live_relay/core/ports/ai_provider.dart';
import 'package:live_relay/core/ports/ai_conversation_provider.dart';
import 'package:live_relay/core/ports/ocr_provider.dart';
import 'package:live_relay/core/domain/entities.dart';
import 'package:live_relay/infrastructure/ai/ai_provider_settings_store.dart';

class NoBiometrics implements BiometricKeyStore {
  @override
  Future<bool> isAvailable() async => false;
  @override
  Future<void> clear() async {}
  @override
  Future<Uint8List?> readMasterKey() async => null;
  @override
  Future<void> saveMasterKey(Uint8List key) async {}
}

class TestAiSettings extends AiProviderSettingsStore {
  bool configured = false;
  bool images = false, files = false;
  bool audio = false;
  @override
  Future<AiProviderSettings> read() async => AiProviderSettings(
    endpoint: configured
        ? 'https://verification.invalid/v1/chat/completions'
        : '',
    model: configured ? 'verification-model' : '',
    hasApiKey: configured,
    models: configured ? const ['verification-model'] : const [],
    supportsImages: images,
    supportsFiles: files,
    supportsAudio: audio,
  );
  @override
  Future<String?> readApiKey() async => configured ? 'test-key' : null;
  @override
  Future<List<AiProviderSettings>> readProfiles() async => [
    if (configured) await read(),
  ];
  @override
  Future<void> save({
    required String endpoint,
    required String model,
    String? apiKey,
  }) async {
    configured = true;
  }

  @override
  Future<void> saveCapabilities({
    required bool images,
    required bool files,
    bool audio = false,
  }) async {
    this.images = images;
    this.files = files;
    this.audio = audio;
  }

  @override
  Future<void> clear() async {
    configured = false;
  }
}

class TestOcr implements OcrProvider {
  @override
  Future<OcrResult> recognize({
    required Uint8List imageBytes,
    required String originalName,
  }) async => const OcrResult(
    text: '备用钥匙在鞋柜第二层\n测试私密备注',
    lines: [
      OcrLine(
        text: '备用钥匙在鞋柜第二层',
        left: 0,
        top: 0,
        right: 100,
        bottom: 20,
        order: 0,
      ),
      OcrLine(
        text: '测试私密备注',
        left: 0,
        top: 20,
        right: 100,
        bottom: 40,
        order: 1,
      ),
    ],
  );
}

class RecordingAi implements AiProvider {
  final requests = <AiProviderRequest>[];
  @override
  Future<String> organize(AiProviderRequest request) async {
    requests.add(request);
    return jsonEncode({
      'cards': [
        {
          'title': '识别资料整理',
          'content': request.redactedText,
          'kind': 'location',
          'inference': false,
        },
      ],
    });
  }
}

/// Fixture only: never contacts an upstream AI service.
class RecordingConversationAi extends RecordingAi
    implements AiConversationProvider {
  final turns = <List<Map<String, Object?>>>[];
  bool invalidReply = false;
  @override
  Future<AiConversationResponse> converse(
    AiProviderRequest request,
    List<Map<String, Object?>> history,
  ) async {
    requests.add(request);
    turns.add(List.of(history));
    final content = jsonEncode({
      'reply': invalidReply ? '[[UNKNOWN_SECRET_99]]' : '收到你的补充',
      'cards': turns.length == 1
          ? []
          : [
              {
                'title': '模型建议',
                'content': '${history.first['content']}，本人补充',
                'kind': 'note',
                'inference': false,
              },
            ],
    });
    return AiConversationResponse(
      content: content,
      output: [
        {'role': 'assistant', 'content': content},
      ],
    );
  }
}
