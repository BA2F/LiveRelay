import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_relay/core/identity/local_identity.dart';
import 'package:live_relay/presentation/pages/manual_handoff_page.dart';
import 'package:live_relay/presentation/pages/recipient_page.dart';
import 'package:qr_flutter/qr_flutter.dart';

void main() {
  testWidgets('recipient QR renders the public identity payload', (
    tester,
  ) async {
    final identity = await LocalIdentity.create('虚构接收者');
    addTearDown(identity.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showRecipientQr(context, identity),
            child: const Text('显示'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('显示'));
    await tester.pumpAndSettle();
    expect(find.byType(QrImageView), findsOneWidget);
    expect(find.text('请所有者当面扫码。二维码只包含公开身份，不包含私钥。'), findsOneWidget);
  });

  test('recipient QR payload decodes to the same identity', () async {
    final identity = await LocalIdentity.create('虚构接收者');
    addTearDown(identity.dispose);
    final decoded = decodeRecipientQr(jsonEncode(await identity.publicData()));
    expect(decoded, isNotNull);
    expect(decoded!['version'], 1);
    expect(
      await LocalIdentity.fingerprintOf(LocalIdentity.validatePublic(decoded)),
      await identity.fingerprint(),
    );
  });

  test('malformed and unrelated QR payloads are ignored', () {
    expect(decodeRecipientQr('not-json'), isNull);
    expect(decodeRecipientQr('[]'), isNull);
    expect(decodeRecipientQr('{"version":1}'), isNotNull);
  });
}
