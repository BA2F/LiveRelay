import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import '../core/cradle/cradle_records.dart';
import '../core/domain/entities.dart';
import '../core/ports/transfer_medium.dart';
import '../core/ports/vault_lifecycle.dart';
import '../core/security/pickup_code.dart';
import '../core/transfer/webdav_connection.dart';
import 'cradle_service.dart';
import 'handoff_view_service.dart';
import 'local_handoff_service.dart';

enum DeliveryStatus { draft, uploaded, needsUpdate, disabled }

class HandoffDelivery {
  const HandoffDelivery({
    required this.id,
    required this.label,
    required this.email,
    required this.packageName,
    required this.pickupCode,
    required this.scope,
    required this.subject,
    required this.body,
    required this.message,
    required this.enabled,
    required this.updatedAt,
    this.uploadedAt,
  });

  final String id;
  final String label;
  final String email;
  final String packageName;
  final String pickupCode;
  final List<ScopedRecord> scope;
  final String subject;
  final String body;
  final String message;
  final bool enabled;
  final DateTime updatedAt;
  final DateTime? uploadedAt;

  DeliveryStatus get status {
    if (!enabled) return DeliveryStatus.disabled;
    final uploaded = uploadedAt;
    if (uploaded == null) return DeliveryStatus.draft;
    return updatedAt.isAfter(uploaded)
        ? DeliveryStatus.needsUpdate
        : DeliveryStatus.uploaded;
  }

  HandoffDelivery copyWith({
    String? label,
    String? email,
    String? packageName,
    String? pickupCode,
    List<ScopedRecord>? scope,
    String? subject,
    String? body,
    String? message,
    bool? enabled,
    DateTime? updatedAt,
    DateTime? uploadedAt,
  }) => HandoffDelivery(
    id: id,
    label: label ?? this.label,
    email: email ?? this.email,
    packageName: packageName ?? this.packageName,
    pickupCode: pickupCode ?? this.pickupCode,
    scope: scope ?? this.scope,
    subject: subject ?? this.subject,
    body: body ?? this.body,
    message: message ?? this.message,
    enabled: enabled ?? this.enabled,
    updatedAt: updatedAt ?? this.updatedAt,
    uploadedAt: uploadedAt ?? this.uploadedAt,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'label': label,
    'email': email,
    'packageName': packageName,
    'pickupCode': pickupCode,
    'scope': [for (final entry in scope) _scopeToJson(entry)],
    'subject': subject,
    'body': body,
    'message': message,
    'enabled': enabled,
    if (uploadedAt != null) 'uploadedAt': uploadedAt!.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
  };

  static HandoffDelivery parse(Object? raw) {
    if (raw is! Map) throw const FormatException('接收者记录格式错误');
    final data = Map<String, Object?>.from(raw);
    String text(String key, {int max = 20000}) {
      final value = data[key];
      if (value is! String || value.isEmpty || value.length > max) {
        throw const FormatException('接收者记录格式错误');
      }
      return value;
    }

    final scopeRaw = data['scope'];
    final updated = DateTime.tryParse('${data['updatedAt']}');
    if (scopeRaw is! List || updated == null) {
      throw const FormatException('接收者记录格式错误');
    }
    final uploadedRaw = data['uploadedAt'];
    final uploaded = uploadedRaw == null
        ? null
        : DateTime.tryParse('$uploadedRaw');
    if (uploadedRaw != null && uploaded == null) {
      throw const FormatException('接收者记录格式错误');
    }
    final message = data['message'];
    if (message != null && message is! String) {
      throw const FormatException('接收者记录格式错误');
    }
    return HandoffDelivery(
      id: text('id', max: 100),
      label: text('label', max: 100),
      email: text('email', max: 300),
      packageName: text('packageName', max: 200),
      pickupCode: text('pickupCode', max: 200),
      scope: [for (final entry in scopeRaw) _scopeFromJson(entry)],
      subject: text('subject', max: 500),
      body: text('body'),
      message: (message as String?) ?? '',
      enabled: data['enabled'] == true,
      updatedAt: updated.toUtc(),
      uploadedAt: uploaded?.toUtc(),
    );
  }

  static Map<String, Object?> _scopeToJson(ScopedRecord record) => {
    'type': record.type,
    'id': record.id,
    'level': record.level.name,
    if (record.history) 'history': true,
    if (record.originalIds.isNotEmpty) 'originalIds': record.originalIds,
  };

  static ScopedRecord _scopeFromJson(Object? raw) {
    if (raw is! Map) throw const FormatException('交接范围格式错误');
    final data = Map<String, Object?>.from(raw);
    final type = data['type'];
    final id = data['id'];
    final level = data['level'];
    final history = data['history'];
    final originalIds = data['originalIds'];
    if (type is! String ||
        id is! String ||
        level is! String ||
        (history != null && history is! bool) ||
        (originalIds != null && originalIds is! List)) {
      throw const FormatException('交接范围格式错误');
    }
    final parsedLevel = VisibilityLevel.values
        .where((value) => value.name == level)
        .firstOrNull;
    if (parsedLevel == null || parsedLevel == VisibilityLevel.hidden) {
      throw const FormatException('交接范围格式错误');
    }
    return ScopedRecord(
      type,
      id,
      parsedLevel,
      history: history == true,
      originalIds: [
        if (originalIds is List)
          for (final value in originalIds)
            if (value is String)
              value
            else
              throw const FormatException('交接范围格式错误'),
      ],
    );
  }
}

class CradleTiming {
  const CradleTiming({
    required this.ownerEmail,
    this.periodDays = CradlePlan.defaultPeriodDays,
    this.remindBeforeDays = CradlePlan.defaultRemindBeforeDays,
    this.graceDays = CradlePlan.defaultGraceDays,
  });

  static const defaults = CradleTiming(ownerEmail: '');

  final String ownerEmail;
  final int periodDays;
  final int remindBeforeDays;
  final int graceDays;

  String? get validationError {
    if (ownerEmail.trim().isEmpty || !ownerEmail.contains('@')) {
      return '请先在「我的 → 报平安与自动交接」填写提醒邮箱';
    }
    return CradlePlan.validationError(
      periodDays: periodDays,
      remindBeforeDays: remindBeforeDays,
      graceDays: graceDays,
    );
  }

  Map<String, Object?> toJson() => {
    'ownerEmail': ownerEmail,
    'periodDays': periodDays,
    'remindBeforeDays': remindBeforeDays,
    'graceDays': graceDays,
  };

  static CradleTiming parse(Object? raw) {
    if (raw is! Map) throw const FormatException('摇篮时间设置格式错误');
    final data = Map<String, Object?>.from(raw);
    final ownerEmail = data['ownerEmail'];
    final period = data['periodDays'];
    final remind = data['remindBeforeDays'];
    final grace = data['graceDays'];
    if (ownerEmail is! String ||
        period is! int ||
        remind is! int ||
        grace is! int) {
      throw const FormatException('摇篮时间设置格式错误');
    }
    return CradleTiming(
      ownerEmail: ownerEmail,
      periodDays: period,
      remindBeforeDays: remind,
      graceDays: grace,
    );
  }
}

/// Local delivery records, package generation and plan upload for the
/// password-package handoff path (2026-10-21 spec).
class HandoffDeliveryService {
  HandoffDeliveryService({
    required this.session,
    required this.handoff,
    required this.view,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final VaultLifecycle session;
  final LocalHandoffService handoff;
  final HandoffViewService view;
  final DateTime Function() _clock;

  static const deliveriesKey = 'handoff.deliveries';
  static const timingKey = 'handoff.cradle.timing';
  static const testRequestName = 'liverelay-cradle-test.json';
  static const testResultName = 'liverelay-cradle-test-result.json';
  static const appDownloadUrl =
      'https://github.com/BA2F/LiveRelay/releases/latest';

  static const _idAlphabet = 'abcdefghijklmnopqrstuvwxyz234567';
  static final _random = Random.secure();

  Future<List<HandoffDelivery>> list() async {
    final raw = await _read(deliveriesKey);
    if (raw == null || raw.isEmpty) return [];
    final decoded = jsonDecode(raw);
    if (decoded is! Map || decoded['deliveries'] is! List) {
      throw const FormatException('接收者列表格式错误');
    }
    return [
      for (final entry in decoded['deliveries'] as List)
        HandoffDelivery.parse(entry),
    ];
  }

  Future<HandoffDelivery?> find(String id) async {
    for (final delivery in await list()) {
      if (delivery.id == id) return delivery;
    }
    return null;
  }

  Future<CradleTiming> timing() async {
    final raw = await _read(timingKey);
    if (raw == null || raw.isEmpty) return CradleTiming.defaults;
    try {
      return CradleTiming.parse(jsonDecode(raw));
    } on FormatException {
      return CradleTiming.defaults;
    }
  }

  Future<void> saveTiming(CradleTiming timing) =>
      _write(timingKey, jsonEncode(timing.toJson()));

  Future<HandoffDelivery> add({
    required String label,
    required String email,
    required List<ScopedRecord> scope,
    required WebDavConnection connection,
  }) async {
    final cleanLabel = label.trim();
    final cleanEmail = email.trim();
    if (cleanLabel.isEmpty) throw const FormatException('请填写接收者称呼');
    if (!cleanEmail.contains('@') || cleanEmail.length < 3) {
      throw const FormatException('请填写接收者邮箱');
    }
    final profile = await handoff.profile();
    final ownerName = (profile['name'] as String?)?.trim().isNotEmpty == true
        ? (profile['name'] as String).trim()
        : '本人';
    final code = PickupCode.generate();
    final packageName = _newPackageName();
    final message = '';
    final delivery = HandoffDelivery(
      id: _newId(),
      label: cleanLabel,
      email: cleanEmail,
      packageName: packageName,
      pickupCode: code,
      scope: List.unmodifiable(scope),
      subject: defaultSubject(ownerName),
      body: defaultBody(
        message: message,
        packageUrl: packageUrl(connection, packageName).toString(),
        packageName: packageName,
        cloudUser: connection.username,
        cloudPassword: connection.password,
        pickupCode: code,
      ),
      message: message,
      enabled: true,
      updatedAt: _clock().toUtc(),
    );
    return save(delivery);
  }

  /// Saves edits and marks the record as changed. Upload clears the pending
  /// state by writing [HandoffDelivery.uploadedAt] afterwards.
  Future<HandoffDelivery> save(HandoffDelivery delivery) async {
    final label = delivery.label.trim();
    if (label.isEmpty) throw const FormatException('请填写接收者称呼');
    if (label.length > 100) throw const FormatException('接收者称呼过长');
    final email = delivery.email.trim();
    if (!email.contains('@') || email.length < 3) {
      throw const FormatException('请填写接收者邮箱');
    }
    if (email.length > 300) throw const FormatException('接收者邮箱过长');
    if (delivery.subject.trim().isEmpty) {
      throw const FormatException('邮件主题不能为空');
    }
    if (delivery.subject.length > 500) {
      throw const FormatException('邮件主题过长');
    }
    if (delivery.body.trim().isEmpty) {
      throw const FormatException('邮件正文不能为空');
    }
    if (delivery.body.length > 20000) {
      throw const FormatException('邮件正文过长');
    }
    if (delivery.message.length > 20000) {
      throw const FormatException('留言过长');
    }
    final saved = delivery.copyWith(
      label: label,
      email: email,
      updatedAt: _clock().toUtc(),
    );
    await _upsert(saved);
    return saved;
  }

  Future<void> remove(String id) async {
    final all = await list()
      ..removeWhere((delivery) => delivery.id == id);
    await _saveAll(all);
  }

  Future<Map<String, Object?>> preview(HandoffDelivery delivery) async {
    final profile = await handoff.profile();
    return {
      ...await handoff.snapshotFor(delivery.scope),
      'ownerName': (profile['name'] as String?) ?? '本人',
      'date': _clock().toUtc().toIso8601String(),
    };
  }

  Future<Uint8List> encodePackage(HandoffDelivery delivery) async => view
      .encode(password: delivery.pickupCode, snapshot: await preview(delivery));

  Future<HandoffDelivery> upload(
    HandoffDelivery delivery, {
    required WebDavConnection connection,
    required CradleTiming timing,
    required TransferMedium medium,
  }) async {
    final bytes = await encodePackage(delivery);
    try {
      final cradle = CradleService(handoff);
      await cradle.uploadPackage(
        medium,
        packageName: delivery.packageName,
        bytes: bytes,
      );
      final uploaded = delivery.copyWith(uploadedAt: _clock().toUtc());
      final all = await list();
      final index = all.indexWhere((entry) => entry.id == delivery.id);
      if (index == -1) {
        all.add(uploaded);
      } else {
        all[index] = uploaded;
      }
      final plan = buildPlan(all, timing, connection);
      await cradle.uploadPlan(medium, plan);
      await _upsert(uploaded);
      return uploaded;
    } finally {
      bytes.fillRange(0, bytes.length, 0);
    }
  }

  Future<void> syncPlan({
    required WebDavConnection connection,
    required CradleTiming timing,
    required TransferMedium medium,
  }) async {
    final plan = buildPlan(await list(), timing, connection);
    await CradleService(handoff).uploadPlan(medium, plan);
  }

  Future<void> deletePackage(HandoffDelivery delivery, TransferMedium medium) =>
      CradleService(handoff)
          .deletePackage(medium, packageName: delivery.packageName);

  CradlePlan buildPlan(
    List<HandoffDelivery> deliveries,
    CradleTiming timing,
    WebDavConnection connection,
  ) {
    final problem = timing.validationError;
    if (problem != null) throw FormatException(problem);
    final ready = deliveries
        .where((entry) => entry.status == DeliveryStatus.uploaded)
        .toList();
    for (final delivery in ready) {
      if (delivery.label.trim().isEmpty) {
        throw const FormatException('接收者称呼不能为空');
      }
      if (!delivery.email.contains('@')) {
        throw FormatException('「${delivery.label}」的邮箱不完整');
      }
      if (delivery.subject.trim().isEmpty) {
        throw FormatException('「${delivery.label}」的邮件主题不能为空');
      }
      if (delivery.body.trim().isEmpty) {
        throw FormatException('「${delivery.label}」的邮件正文不能为空');
      }
    }
    return CradlePlan(
      ownerEmail: timing.ownerEmail.trim(),
      periodDays: timing.periodDays,
      remindBeforeDays: timing.remindBeforeDays,
      graceDays: timing.graceDays,
      recipients: List.unmodifiable([
        for (final delivery in ready)
          CradleRecipient(
            label: delivery.label,
            email: delivery.email,
            packageName: delivery.packageName,
            cloudUrl: connection.baseUrl.toString(),
            cloudUser: connection.username,
            cloudPassword: connection.password,
            subject: delivery.subject,
            body: delivery.body,
          ),
      ]),
    );
  }

  Future<String> requestTestSend({
    required String to,
    required String subject,
    required String body,
    required TransferMedium medium,
  }) async {
    final address = to.trim();
    if (!address.contains('@') || address.length < 3) {
      throw const FormatException('请填写测试收件邮箱');
    }
    if (address.length > 300) throw const FormatException('测试收件邮箱过长');
    if (subject.trim().isEmpty) throw const FormatException('邮件主题不能为空');
    if (subject.length > 500) throw const FormatException('邮件主题过长');
    if (body.trim().isEmpty) throw const FormatException('邮件正文不能为空');
    if (body.length > 20000) throw const FormatException('邮件正文过长');
    final requestedAt = _clock().toUtc().toIso8601String();
    final payload = {
      'kind': 'liverelay-cradle-test',
      'version': 1,
      'to': address,
      'subject': subject,
      'body': body,
      'requestedAt': requestedAt,
    };
    await medium.writeAtomic(
      testRequestName,
      Uint8List.fromList(utf8.encode(jsonEncode(payload))),
    );
    return requestedAt;
  }

  Future<Map<String, Object?>?> readTestResult(TransferMedium medium) async {
    try {
      final bytes = await medium.read(testResultName);
      final decoded = jsonDecode(utf8.decode(bytes));
      return decoded is Map ? Map<String, Object?>.from(decoded) : null;
    } on TransferMediumException catch (error) {
      if (error.notFound) return null;
      rethrow;
    } on FormatException {
      return null;
    }
  }

  static String defaultSubject(String ownerName) => '【留灯】$ownerName 给你留了内容';

  static String defaultBody({
    required String message,
    required String packageUrl,
    required String packageName,
    required String cloudUser,
    required String cloudPassword,
    required String pickupCode,
  }) {
    final parts = <String>[];
    if (message.trim().isNotEmpty) parts.add(message.trim());
    parts.add(
      '取件链接：$packageUrl\n'
      '云端账号：$cloudUser\n'
      '云端密码：$cloudPassword\n'
      '取件码：${PickupCode.format(pickupCode)}',
    );
    parts.add(
      'LiveRelay 下载：$appDownloadUrl\n\n'
      '步骤：\n'
      '1. 打开取件链接，输入上面的账号和密码，下载 $packageName。\n'
      '2. 安装 LiveRelay（如果还没装）。\n'
      '3. 打开 LiveRelay，点「打开交接包」，选择下载的文件。\n'
      '4. 输入取件码，查看内容。',
    );
    parts.add('如果可能，请先试着联系本人确认情况。');
    return parts.join('\n\n');
  }

  static bool bodyContainsCode(String body, String pickupCode) {
    final normalized = PickupCode.normalize(pickupCode);
    if (normalized.isEmpty) return false;
    return body.contains(PickupCode.format(normalized)) ||
        body.contains(normalized);
  }

  static String replaceCode(String body, String oldCode, String newCode) {
    final formattedOld = PickupCode.format(oldCode);
    final formattedNew = PickupCode.format(newCode);
    var result = body;
    if (formattedOld.isNotEmpty) {
      result = result.replaceAll(formattedOld, formattedNew);
    }
    final normalizedOld = PickupCode.normalize(oldCode);
    if (normalizedOld.isNotEmpty && normalizedOld != formattedOld) {
      result = result.replaceAll(normalizedOld, formattedNew);
    }
    return result;
  }

  static Uri packageUrl(WebDavConnection connection, String packageName) {
    final base =
        connection.baseUrl.path.endsWith('/') || connection.baseUrl.path.isEmpty
        ? connection.baseUrl
        : connection.baseUrl.replace(path: '${connection.baseUrl.path}/');
    return base.resolve(Uri.encodeComponent(packageName));
  }

  /// Creates a new ASCII package file name. Changing the pickup code uses a
  /// new name so an already-sent email keeps pointing at its old package.
  String generatePackageName() => _newPackageName();

  Future<String?> _read(String key) async {
    if (!session.isUnlocked) throw StateError('请先解锁所有者资料库');
    return session.repository.readLocalValue(key);
  }

  Future<void> _write(String key, String value) async {
    if (!session.isUnlocked) throw StateError('请先解锁所有者资料库');
    await session.repository.writeLocalValue(key, value);
  }

  Future<void> _upsert(HandoffDelivery delivery) async {
    final all = await list();
    final index = all.indexWhere((entry) => entry.id == delivery.id);
    if (index == -1) {
      all.add(delivery);
    } else {
      all[index] = delivery;
    }
    await _saveAll(all);
  }

  Future<void> _saveAll(List<HandoffDelivery> deliveries) => _write(
    deliveriesKey,
    jsonEncode({
      'version': 1,
      'deliveries': [for (final delivery in deliveries) delivery.toJson()],
    }),
  );

  String _newId() {
    final buffer = StringBuffer('d_');
    for (var index = 0; index < 8; index++) {
      buffer.write(_idAlphabet[_random.nextInt(_idAlphabet.length)]);
    }
    return buffer.toString();
  }

  String _newPackageName() {
    final buffer = StringBuffer('liverelay-handoff-');
    for (var index = 0; index < 8; index++) {
      buffer.write(_idAlphabet[_random.nextInt(_idAlphabet.length)]);
    }
    buffer.write('.lrshare');
    return buffer.toString();
  }
}
