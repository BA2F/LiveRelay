import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_relay/application/ai/outbound_consent_service.dart';
import 'package:live_relay/core/ai/outbound_consent.dart';
import 'package:live_relay/core/ports/outbound_consent_repository.dart';
import 'package:live_relay/infrastructure/ai/outbound_consent_store.dart';

class _FailingRepository implements OutboundConsentRepository {
  _FailingRepository({this.failRead = false, this.failWrite = false});
  final bool failRead, failWrite;
  Map<String, Set<OutboundKind>> stored = {};
  @override
  Future<Map<String, Set<OutboundKind>>> read() async {
    if (failRead) throw const FormatException('无法读取');
    return stored;
  }

  @override
  Future<void> write(Map<String, Set<OutboundKind>> grants) async {
    if (failWrite) throw const FormatException('无法写入');
    stored = grants;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final destination = OutboundDestination.ai(
    profileId: 'profile-1',
    endpoint: 'https://api.example.invalid/v1/chat/completions',
    name: '虚构服务',
  );

  test('服务地址或配置文件变化即视为新目标', () {
    expect(destination.id, 'ai:profile-1@api.example.invalid');
    expect(
      OutboundDestination.ai(
        profileId: 'profile-1',
        endpoint: 'https://other.example.invalid/v1/chat/completions',
        name: '虚构服务',
      ).id,
      isNot(destination.id),
    );
    expect(
      OutboundDestination.speech(
        endpoint: 'https://asr.example.invalid/v1',
        name: '远程语音',
      ).id,
      'speech@asr.example.invalid',
    );
  });

  test('存储按服务记录内容与附件授权，未知版本与未知类别拒绝', () async {
    FlutterSecureStorage.setMockInitialValues({});
    final store = OutboundConsentStore();
    expect(await store.read(), isEmpty);
    await store.write({
      destination.id: {OutboundKind.content, OutboundKind.attachment},
    });
    final readBack = await store.read();
    expect(readBack[destination.id], {
      OutboundKind.content,
      OutboundKind.attachment,
    });

    FlutterSecureStorage.setMockInitialValues({
      'liverelay.outbound.consent.v1': jsonEncode({
        'version': 2,
        'grants': {},
      }),
    });
    await expectLater(store.read(), throwsFormatException);
    FlutterSecureStorage.setMockInitialValues({
      'liverelay.outbound.consent.v1': jsonEncode({
        'version': 1,
        'grants': {
          destination.id: ['content', 'unknown-kind'],
        },
      }),
    });
    await expectLater(store.read(), throwsFormatException);
  });

  test('授权写入成功后才生效，可收回；写入失败不静默放行', () async {
    final repository = _FailingRepository();
    final service = OutboundConsentService(repository);
    await service.initialize();
    expect(service.granted(destination, OutboundKind.content), isFalse);

    await service.grant(destination, OutboundKind.content);
    expect(service.granted(destination, OutboundKind.content), isTrue);
    expect(service.granted(destination, OutboundKind.attachment), isFalse);

    await service.grant(destination, OutboundKind.attachment);
    expect(service.grantedKinds(destination.id), {
      OutboundKind.content,
      OutboundKind.attachment,
    });

    await service.revoke(destination.id);
    expect(service.granted(destination, OutboundKind.content), isFalse);
    expect(service.grantedKinds(destination.id), isEmpty);

    final failing = _FailingRepository(failWrite: true);
    final blocked = OutboundConsentService(failing);
    await blocked.initialize();
    await expectLater(
      blocked.grant(destination, OutboundKind.content),
      throwsFormatException,
    );
    expect(blocked.granted(destination, OutboundKind.content), isFalse);
  });

  test('读取失败按未授权处理：首次发送仍然拦一次', () async {
    final service = OutboundConsentService(_FailingRepository(failRead: true));
    await service.initialize();
    expect(service.granted(destination, OutboundKind.content), isFalse);
    // 重新初始化后可恢复读取到的授权。
    final repository = _FailingRepository();
    repository.stored = {
      destination.id: {OutboundKind.content},
    };
    final recovered = OutboundConsentService(repository);
    await recovered.initialize();
    expect(recovered.granted(destination, OutboundKind.content), isTrue);
  });
}
