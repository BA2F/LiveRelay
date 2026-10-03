import 'dart:convert';
import 'dart:io';

import 'package:live_relay/core/security/header_encoding.dart';
import 'package:live_relay/core/security/recovery_credential.dart';
import 'package:live_relay/core/security/vault_header_v2.dart';

import 'fictional_device_protection.dart';

/// Writes only public fictional fixtures for the independent Python reader.
Future<void> main(List<String> args) async {
  if (args.isEmpty ||
      args.length > 2 ||
      (args.length == 2 && args[1] != "--device")) {
    throw ArgumentError('Supply an isolated fixture output path');
  }
  final vectors = jsonDecode(
    await File('test/fixtures/header_v2/vectors.json').readAsString(),
  ) as Map;
  final r = await RecoveryCredential.parse(
    vectors['recoveryCredential'] as String,
  );
  final vmk = HeaderEncoding.decodeBinary(vectors['masterKey'], 32);
  final device = args.length == 2 ? FictionalDeviceProtection() : null;
  String? reference;
  final watch = Stopwatch()..start();
  try {
    final header = await VaultHeaderV2.createForEvaluation(
      canonicalPassword:
          (vectors['fixtures'] as List).first['canonicalPassword'] as String,
      recovery: r,
      masterKey: vmk,
      deviceProtection: device,
    );
    reference = header.deviceReference;
    await File(args.first).writeAsBytes(header.bytes, flush: true);
    stdout.writeln(
      'Evaluation header creation desktop elapsed: ${watch.elapsedMilliseconds} ms; not an Android performance gate',
    );
  } finally {
    if (reference != null) await device!.deleteFactor(reference);
    r.dispose();
    vmk.fillRange(0, vmk.length, 0);
  }
}
