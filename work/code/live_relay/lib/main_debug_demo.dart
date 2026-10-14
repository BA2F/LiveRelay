import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';

import 'application/local_handoff_service.dart';
import 'core/identity/local_identity.dart';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'application/app_preferences.dart';
import 'application/app_controller.dart';
import 'core/domain/entities.dart';
import 'core/ports/biometric_key_store.dart';
import 'core/ports/device_factor_protection.dart';
import 'core/ports/development_controls.dart';
import 'infrastructure/app_composition.dart';
import 'presentation/app.dart';
import 'development/demo_controls.dart';

/// Explicit demo entry point. Every runtime service receives this fresh root.
/// Never reads or upgrades a production vault and never exports demo as real.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final root = await Directory.systemTemp.createTemp('liverelay-demo-');
  final controls = DemoControls(root);
  final controller = createAppController(
    root,
    _NoBiometrics(),
    null,
    null,
    null,
    null,
    _NoDevice(),
    () => controls.now,
  );
  controls.controller = controller;
  await controller.initialize();
  final r = await controller.generateRecovery();
  await controller.setupModernVault(
    password: 'Demo-only-2026',
    recoveryText: r,
    recoveryConfirmation: r,
  );
  await _populateFictionalVault(controller);
  final preferences = createAppPreferences(
    File('${root.path}/demo-preferences.json'),
  );
  await preferences.finishOnboarding();
  debugPrint('独立演示已初始化：${root.path}');
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AppController>.value(value: controller),
        ChangeNotifierProvider<AppPreferences>.value(value: preferences),
        Provider<DevelopmentControls>.value(value: _DemoEntry(controls)),
      ],
      child: LiveRelayApp(
        environmentOverlay: controls.buildOverlay,
        navigatorKey: controls.navigatorKey,
      ),
    ),
  );
}

/// 虚构人物「林晚舟」的完整资料库：卡片、密码、原件、身份与已验证
/// 接收者，另留少量修订与授权历史。生命状态演练入口在七击浮层里。
Future<void> _populateFictionalVault(AppController controller) async {
  Future<LifeCard> card(
    CardDraft draft, {
    bool confirm = true,
  }) async {
    await controller.createCard(draft);
    final created = controller.cards.firstWhere(
      (c) => c.title == draft.title.trim(),
    );
    if (confirm) await controller.confirmCard(created.id);
    return created;
  }

  final location = await card(
    const CardDraft(
      title: '重要资料存放位置',
      content: '房产与保单资料放在书房铁盒里，父母家留了一份副本。备用钥匙在鞋柜第二层。',
      kind: CardKind.location,
      tags: ['家庭', '资料'],
    ),
  );
  // 一条修订历史：补记副本移交时间。
  await controller.updateCard(
    location.id,
    const CardDraft(
      title: '重要资料存放位置',
      content: '房产与保单资料放在书房铁盒里，父母家留了一份副本。备用钥匙在鞋柜第二层。副本已于十月移交给父母保管。',
      kind: CardKind.location,
      status: CardStatus.confirmed,
      tags: ['家庭', '资料'],
    ),
    changeNote: '补记副本移交时间',
  );
  await card(
    const CardDraft(
      title: '想留给家人的话',
      content: '谢谢你们一直陪着我。家里的账目和保险都在资料库里有记录，遇到事情按顺序慢慢来。',
      kind: CardKind.wish,
      tags: ['家庭'],
    ),
  );
  await card(
    const CardDraft(
      title: '家里每月要办的事',
      content: '每月十号前缴水电燃气，二十号扣房贷。物业费按季度交。',
      kind: CardKind.familyOperation,
      tags: ['日常'],
    ),
  );
  await card(
    const CardDraft(
      title: '常用账户与绑定说明',
      content: '手机号绑定了银行、邮箱和云盘，换号时记得逐一改绑。各网站密码见密码库条目。',
      kind: CardKind.account,
      tags: ['账号'],
    ),
  );
  // 留一条待整理内容，让「待整理」入口在演示里也有东西。
  await card(
    const CardDraft(
      title: '重要联系人',
      content: '理财顾问、家庭医生的联系方式逐步补到这里。',
      kind: CardKind.relationship,
      tags: ['联系人'],
    ),
    confirm: false,
  );

  await controller.saveCredential(
    const CredentialDraft(
      title: '家庭邮箱',
      username: 'family@example.invalid',
      secret: 'fictional-only-password',
      website: 'https://mail.example.invalid',
      notes: '用于接收账单和通知。',
      tags: ['账号'],
    ),
  );
  final mail = controller.credentials.firstWhere(
    (c) => c.title == '家庭邮箱',
  );
  await controller.saveCredential(
    const CredentialDraft(
      title: '水电缴费账户',
      username: 'linwanzhou-demo',
      secret: 'fictional-utility-password',
      website: 'https://billing.example.invalid',
      notes: '户号见纸质账单。',
      tags: ['日常'],
    ),
  );

  // 原件：导入一份虚构的保单摘要，并把原件关联到存放位置卡片。
  final summaryCard = await controller.importOriginal(
    bytes: Uint8List.fromList(
      utf8.encode('虚构保单摘要\n- 保障内容：演示数据，非真实保单\n- 受理电话：000-0000-0000\n'),
    ),
    originalName: '保单摘要.txt',
    mimeType: 'text/plain',
    mediaKind: BlobMediaKind.document,
  );
  await controller.confirmCard(summaryCard.id);
  final sources = await controller.cardSources(summaryCard.id);
  final summaryBlobId = sources.isEmpty ? null : sources.first.blobId;
  if (summaryBlobId != null) {
    await controller.setCardOriginals(location.id, [summaryBlobId]);
  }

  // 授权：演示交接页与接收者预览里能看到实际释放内容。
  await controller.saveReleasePolicy(
    ReleasePolicy(
      recordType: 'card',
      recordId: location.id,
      incapacitated: VisibilityLevel.summary,
      deceased: VisibilityLevel.full,
    ),
  );
  await controller.saveReleasePolicy(
    ReleasePolicy(
      recordType: 'credential',
      recordId: mail.id,
      incapacitated: VisibilityLevel.hidden,
      deceased: VisibilityLevel.secret,
    ),
  );

  await controller.handoff!.saveProfile(
    '林晚舟',
    'linwanzhou@example.invalid',
    '完全虚构的人物档案，数据位于独立临时目录',
  );

  // 接收者：建身份、完成指纹核对挑战，并真实接收一个限定范围交接包。
  await controller.recipient!.initialize();
  await controller.recipient!.create('沈知微', 'Recipient-demo-2026');
  final receiver = controller.recipient!;
  final public = await receiver.identity!.publicData();
  final fingerprint = await receiver.identity!.fingerprint();
  final challenge = jsonDecode(
    utf8.decode(await controller.handoff!.createChallenge(public, fingerprint)),
  ) as Map<String, Object?>;
  final ownerFingerprint = await LocalIdentity.fingerprintOf(
    await controller.handoff!.publicIdentity(),
  );
  final proof = jsonDecode(
    utf8.decode(await receiver.answerChallenge(challenge, ownerFingerprint)),
  ) as Map<String, Object?>;
  await controller.handoff!.acceptProof(proof);
  final package = await controller.handoff!.exportScope(fingerprint, [
    ScopedRecord('card', location.id, VisibilityLevel.summary),
  ]);
  try {
    await receiver.receive(package, ownerFingerprint);
  } finally {
    package.fillRange(0, package.length, 0);
  }
  receiver.lock();
}

class _NoBiometrics implements BiometricKeyStore {
  @override
  Future<bool> isAvailable() async => false;
  @override
  Future<void> saveMasterKey(Uint8List key) async =>
      throw UnsupportedError('Demo');
  @override
  Future<Uint8List?> readMasterKey() async => null;
  @override
  Future<void> clear() async {}
}

class _NoDevice implements DeviceFactorProtection {
  @override
  Future<DeviceFactorCapability> capability() async =>
      const DeviceFactorCapability(
        available: false,
        reason: 'Demo has no device key',
      );
  @override
  Future<WrappedDeviceFactor> protectFactor(
    DeviceFactorContext context,
    Uint8List share,
  ) async => throw UnsupportedError('Demo');
  @override
  Future<Uint8List> unprotectFactor(
    DeviceFactorContext context,
    WrappedDeviceFactor wrapped,
  ) async => throw UnsupportedError('Demo');
  @override
  Future<void> deleteFactor(String reference) async {}
  @override
  Future<void> cancel() async {}
}

class _DemoEntry implements DevelopmentControls {
  const _DemoEntry(this.controls);
  final DemoControls controls;
  @override
  void activate() => controls.activate();
}
