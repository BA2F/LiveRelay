import 'dart:convert';
import 'dart:typed_data';

import '../core/cradle/cradle_records.dart';
import '../core/identity/local_identity.dart';
import '../core/ports/transfer_medium.dart';
import '../core/security/header_encoding.dart';
import 'local_handoff_service.dart';

/// Cradle (报平安与自动交接) application service: prepares and signs the
/// check-in record and the plan, and moves them through a caller-supplied
/// [TransferMedium] so this layer stays free of infrastructure imports.
/// The cloud-side cradle service reads the same files; sizing and trigger
/// semantics are in tasks/specs/2026-10-15_报平安与自动交接.md.
class CradleService {
  CradleService(this.handoff);

  final LocalHandoffService handoff;

  Future<CheckinRecord> buildCheckin({required String device}) async {
    final unsigned = {
      'kind': CheckinRecord.kind,
      'version': CheckinRecord.version,
      'checkedAt': DateTime.now().toUtc().toIso8601String(),
      'device': device,
      'publicIdentity': await handoff.publicIdentity(),
    };
    final signature = await handoff.signPayload(
      HeaderEncoding.encode(unsigned),
    );
    return CheckinRecord.parse({...unsigned, 'signature': signature});
  }

  Future<CheckinRecord> uploadCheckin(
    TransferMedium medium, {
    required String device,
  }) async {
    final record = await buildCheckin(device: device);
    await medium.writeAtomic(
      CheckinRecord.fileName,
      Uint8List.fromList(utf8.encode(jsonEncode(record.toJson()))),
    );
    return record;
  }

  Future<void> uploadPlan(TransferMedium medium, CradlePlan plan) =>
      medium.writeAtomic(
        CradlePlan.fileName,
        Uint8List.fromList(utf8.encode(jsonEncode(plan.toJson()))),
      );

  /// Uploads a pre-authorized scoped-delivery package for one recipient.
  /// The caller derives [packageName] with CradleRecipient.packageNameFor so
  /// the cradle service's pickup mail points at this exact file.
  Future<void> uploadPackage(
    TransferMedium medium, {
    required String packageName,
    required Uint8List bytes,
  }) {
    _validatePackageName(packageName);
    return medium.writeAtomic(packageName, bytes);
  }

  /// Removes a recipient's package. A missing file is not an error.
  Future<void> deletePackage(
    TransferMedium medium, {
    required String packageName,
  }) {
    _validatePackageName(packageName);
    return medium.delete(packageName);
  }

  static void _validatePackageName(String packageName) {
    if (packageName.isEmpty ||
        packageName.length > 200 ||
        packageName.contains('/') ||
        packageName.contains('\\')) {
      throw const FormatException('交接包文件名不合法');
    }
  }

  /// Reads the last check-in back from the cloud; null when none exists yet.
  Future<CheckinRecord?> readCheckin(TransferMedium medium) async {
    final bytes = await _readOrNull(medium, CheckinRecord.fileName);
    if (bytes == null) return null;
    return CheckinRecord.parse(jsonDecode(utf8.decode(bytes)));
  }

  Future<CradlePlan?> readPlan(TransferMedium medium) async {
    final bytes = await _readOrNull(medium, CradlePlan.fileName);
    if (bytes == null) return null;
    return CradlePlan.parse(jsonDecode(utf8.decode(bytes)));
  }

  Future<Uint8List?> _readOrNull(TransferMedium medium, String name) async {
    try {
      return await medium.read(name);
    } on TransferMediumException catch (error) {
      if (error.notFound) return null;
      rethrow;
    }
  }

  /// Verifies a check-in record against its embedded owner identity; used by
  /// tests and by recipients auditing what the cloud relayed.
  static Future<bool> verifyCheckin(CheckinRecord record) async {
    try {
      await LocalIdentity.verify(
        record.publicIdentity,
        HeaderEncoding.encode(record.unsignedData()),
        record.signature,
      );
      return true;
    } on Object {
      return false;
    }
  }
}
