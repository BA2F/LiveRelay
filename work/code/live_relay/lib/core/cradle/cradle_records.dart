/// Cradle records: the check-in log and the cradle plan that the cloud-side
/// cradle service reads. Internal engineering formats; not a frozen external
/// contract. The check-in record is signed with the owner identity using the
/// canonical HeaderEncoding payload, so every signed string must stay ASCII.
library;

class CheckinRecord {
  const CheckinRecord({
    required this.checkedAt,
    required this.device,
    required this.publicIdentity,
    required this.signature,
  });

  static const kind = 'liverelay-checkin';
  static const version = 1;
  static const fileName = 'liverelay-checkin.json';

  final DateTime checkedAt;
  final String device;
  final Map<String, Object?> publicIdentity;
  final String signature;

  Map<String, Object?> unsignedData() => {
    'kind': kind,
    'version': version,
    'checkedAt': checkedAt.toUtc().toIso8601String(),
    'device': device,
    'publicIdentity': publicIdentity,
  };

  Map<String, Object?> toJson() => {...unsignedData(), 'signature': signature};

  static CheckinRecord parse(Object? raw) {
    if (raw is! Map) throw const FormatException('报平安记录格式错误');
    final data = Map<String, Object?>.from(raw);
    final checkedAt = DateTime.tryParse('${data['checkedAt']}');
    final device = data['device'];
    final signature = data['signature'];
    final publicIdentity = data['publicIdentity'];
    if (data['kind'] != kind ||
        data['version'] != version ||
        checkedAt == null ||
        device is! String ||
        signature is! String ||
        publicIdentity is! Map) {
      throw const FormatException('报平安记录格式错误');
    }
    return CheckinRecord(
      checkedAt: checkedAt.toUtc(),
      device: device,
      publicIdentity: Map<String, Object?>.unmodifiable(publicIdentity),
      signature: signature,
    );
  }
}

class CradleRecipient {
  const CradleRecipient({
    required this.label,
    required this.email,
    required this.packageName,
    required this.cloudUrl,
    required this.cloudUser,
    required this.cloudPassword,
  });

  /// Canonical cloud file name of this recipient's pre-authorized handoff
  /// package. The plan stores it and the cradle service mails it to the
  /// recipient, so the upload in the handoff flow must use the same name.
  static String packageNameFor(String label) =>
      'liverelay-handoff-${label.replaceAll(RegExp(r'[/\\]'), '_')}.lrshare';

  final String label;
  final String email;
  final String packageName;
  final String cloudUrl;
  final String cloudUser;
  final String cloudPassword;

  Map<String, Object?> toJson() => {
    'label': label,
    'email': email,
    'package': packageName,
    'cloudUrl': cloudUrl,
    'cloudUser': cloudUser,
    'cloudPassword': cloudPassword,
  };

  static CradleRecipient parse(Object? raw) {
    if (raw is! Map) throw const FormatException('摇篮接收者格式错误');
    final data = Map<String, Object?>.from(raw);
    String text(String key, {int max = 300}) {
      final value = data[key];
      if (value is! String || value.isEmpty || value.length > max) {
        throw const FormatException('摇篮接收者格式错误');
      }
      return value;
    }

    return CradleRecipient(
      label: text('label', max: 100),
      email: text('email'),
      packageName: text('package', max: 200),
      cloudUrl: text('cloudUrl', max: 500),
      cloudUser: text('cloudUser', max: 200),
      cloudPassword: text('cloudPassword', max: 200),
    );
  }
}

class CradlePlan {
  const CradlePlan({
    required this.ownerEmail,
    required this.periodDays,
    required this.remindBeforeDays,
    required this.graceDays,
    required this.recipients,
  });

  static const kind = 'liverelay-cradle-plan';
  static const version = 1;
  static const fileName = 'liverelay-cradle-plan.json';
  static const defaultPeriodDays = 7;
  static const defaultRemindBeforeDays = 1;
  static const defaultGraceDays = 3;

  /// Where the cradle service sends owner reminders.
  final String ownerEmail;
  final int periodDays;
  final int remindBeforeDays;
  final int graceDays;
  final List<CradleRecipient> recipients;

  /// Whole days without a check-in after which the owner is reminded.
  int get remindAfterDays => periodDays - remindBeforeDays;

  /// Whole days without a check-in after which recipients are notified.
  int get triggerAfterDays => periodDays + graceDays;

  static String? validationError({
    required int periodDays,
    required int remindBeforeDays,
    required int graceDays,
  }) {
    if (periodDays < 1 || periodDays > 365) return '周期需在 1–365 天之间';
    if (remindBeforeDays < 0 || remindBeforeDays >= periodDays) {
      return '提前提醒需小于周期';
    }
    if (graceDays < 0 || graceDays > 90) return '宽限期需在 0–90 天之间';
    return null;
  }

  Map<String, Object?> toJson() => {
    'kind': kind,
    'version': version,
    'ownerEmail': ownerEmail,
    'periodDays': periodDays,
    'remindBeforeDays': remindBeforeDays,
    'graceDays': graceDays,
    'recipients': [for (final r in recipients) r.toJson()],
  };

  static CradlePlan parse(Object? raw) {
    if (raw is! Map) throw const FormatException('摇篮计划格式错误');
    final data = Map<String, Object?>.from(raw);
    final ownerEmail = data['ownerEmail'];
    final periodDays = data['periodDays'];
    final remindBeforeDays = data['remindBeforeDays'];
    final graceDays = data['graceDays'];
    final recipients = data['recipients'];
    if (data['kind'] != kind ||
        data['version'] != version ||
        ownerEmail is! String ||
        ownerEmail.isEmpty ||
        ownerEmail.length > 300 ||
        periodDays is! int ||
        remindBeforeDays is! int ||
        graceDays is! int ||
        recipients is! List) {
      throw const FormatException('摇篮计划格式错误');
    }
    if (validationError(
          periodDays: periodDays,
          remindBeforeDays: remindBeforeDays,
          graceDays: graceDays,
        ) !=
        null) {
      throw const FormatException('摇篮计划格式错误');
    }
    return CradlePlan(
      ownerEmail: ownerEmail,
      periodDays: periodDays,
      remindBeforeDays: remindBeforeDays,
      graceDays: graceDays,
      recipients: List.unmodifiable(recipients.map(CradleRecipient.parse)),
    );
  }
}
