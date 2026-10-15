import 'dart:io';

import 'package:flutter/foundation.dart';

import '../application/cradle_service.dart';
import '../infrastructure/transfer/webdav_transfer_medium.dart';
import 'controllers/app_controller.dart';

DateTime? _lastAttempt;
const _minimumInterval = Duration(hours: 1);

/// Device label for check-in records; must stay ASCII because the record
/// payload is signed through the canonical HeaderEncoding encoder.
String get cradleDeviceLabel =>
    Platform.isAndroid || Platform.isIOS ? 'phone' : 'desktop';

/// Fire-and-forget check-in right after unlock: "opening the app counts as
/// one check-in". Failures stay silent (the manual button and the next
/// unlock retry); at most once per hour per process.
Future<void> maybeAutoCheckIn(AppController controller) async {
  final now = DateTime.now();
  final last = _lastAttempt;
  if (last != null && now.difference(last) < _minimumInterval) return;
  _lastAttempt = now;
  final handoff = controller.handoff;
  if (handoff == null) return;
  try {
    final connection = await controller.webDavConnection();
    if (connection == null) return;
    final medium = WebDavTransferMedium(
      baseUrl: connection.baseUrl,
      username: connection.username,
      password: connection.password,
      timeout: const Duration(seconds: 30),
    );
    try {
      await CradleService(handoff).uploadCheckin(
        medium,
        device: cradleDeviceLabel,
      );
    } finally {
      medium.close();
    }
  } on Object catch (error) {
    debugPrint('cradle: auto check-in skipped ($error)');
  }
}
