import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../application/cradle_service.dart';
import '../../application/local_handoff_service.dart';
import '../../core/cradle/cradle_records.dart';
import '../../core/identity/local_identity.dart';
import '../../core/transfer/webdav_connection.dart';
import '../../infrastructure/transfer/webdav_transfer_medium.dart';
import '../controllers/app_controller.dart';
import '../cradle_auto_checkin.dart';
import 'device_transfer_page.dart';

/// Check-in record and cradle plan management: the owner-facing half of the
/// cloud cradle (see tasks/specs/2026-10-15_报平安与自动交接.md).
class CradlePage extends StatefulWidget {
  const CradlePage({super.key});

  @override
  State<CradlePage> createState() => _CradlePageState();
}

class _RecipientDraft {
  _RecipientDraft({this.fingerprint, String email = ''})
    : email = TextEditingController(text: email);

  String? fingerprint;
  final TextEditingController email;

  void dispose() => email.dispose();
}

class _CradlePageState extends State<CradlePage> {
  final _period = TextEditingController(
    text: '${CradlePlan.defaultPeriodDays}',
  );
  final _remindBefore = TextEditingController(
    text: '${CradlePlan.defaultRemindBeforeDays}',
  );
  final _grace = TextEditingController(
    text: '${CradlePlan.defaultGraceDays}',
  );
  final _ownerEmail = TextEditingController();
  final _drafts = <_RecipientDraft>[];

  bool _busy = false;
  bool _loaded = false;
  bool _planApplied = false;
  String? _status;
  String _cloudLabel = '';
  CheckinRecord? _lastCheckin;
  var _availableRecipients = <({String fingerprint, String name})>[];

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _period.dispose();
    _remindBefore.dispose();
    _grace.dispose();
    _ownerEmail.dispose();
    for (final draft in _drafts) {
      draft.dispose();
    }
    super.dispose();
  }

  Future<WebDavTransferMedium> _medium(WebDavConnection connection) async =>
      WebDavTransferMedium(
        baseUrl: connection.baseUrl,
        username: connection.username,
        password: connection.password,
        timeout: const Duration(seconds: 20),
      );

  Future<void> _refresh() async {
    final controller = context.read<AppController>();
    try {
      final connection = await controller.webDavConnection();
      var recipients = <({String fingerprint, String name})>[];
      final handoff = controller.handoff;
      if (handoff != null) recipients = await _loadRecipients(handoff);
      CheckinRecord? checkin;
      CradlePlan? plan;
      if (connection != null && handoff != null) {
        final medium = await _medium(connection);
        try {
          final cradle = CradleService(handoff);
          checkin = await cradle.readCheckin(medium);
          plan = await cradle.readPlan(medium);
        } finally {
          medium.close();
        }
      }
      if (!mounted) return;
      setState(() {
        _loaded = true;
        _cloudLabel = connection == null
            ? ''
            : '${connection.baseUrl.host}:${connection.baseUrl.port}';
        _lastCheckin = checkin;
        _availableRecipients = recipients;
        if (!_planApplied && plan != null) {
          _planApplied = true;
          _ownerEmail.text = plan.ownerEmail;
          _period.text = '${plan.periodDays}';
          _remindBefore.text = '${plan.remindBeforeDays}';
          _grace.text = '${plan.graceDays}';
          for (final recipient in plan.recipients) {
            final match = recipients.firstWhereOrNull(
              (r) => r.name == recipient.label,
            );
            _drafts.add(
              _RecipientDraft(
                fingerprint: match?.fingerprint,
                email: recipient.email,
              ),
            );
          }
        }
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _loaded = true;
        _status = '$error';
      });
    }
  }

  Future<List<({String fingerprint, String name})>> _loadRecipients(
    LocalHandoffService handoff,
  ) async {
    final bindings = await handoff.recipients();
    return [
      for (final entry in bindings.entries)
        if (entry.value is Map && (entry.value as Map)['public'] is Map)
          (
            fingerprint: entry.key,
            name: LocalIdentity.displayName(
              Map<String, Object?>.from((entry.value as Map)['public'] as Map),
            ),
          ),
    ];
  }

  Future<void> _checkIn() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _status = null;
    });
    final controller = context.read<AppController>();
    try {
      final handoff = controller.handoff;
      if (handoff == null) throw StateError('需要先解锁资料库');
      final connection = await controller.webDavConnection();
      if (connection == null) {
        throw StateError('还没有配置云端连接：先到「设备间搬运」里配置云端');
      }
      final medium = await _medium(connection);
      try {
        final record = await CradleService(
          handoff,
        ).uploadCheckin(medium, device: cradleDeviceLabel);
        if (mounted) setState(() => _lastCheckin = record);
      } finally {
        medium.close();
      }
      if (mounted) setState(() => _status = '已报平安，云端已更新');
    } on Object catch (error) {
      if (mounted) setState(() => _status = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _savePlan() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _status = null;
    });
    final controller = context.read<AppController>();
    try {
      final handoff = controller.handoff;
      if (handoff == null) throw StateError('需要先解锁资料库');
      final connection = await controller.webDavConnection();
      if (connection == null) {
        throw StateError('还没有配置云端连接：先到「设备间搬运」里配置云端');
      }
      final period = int.tryParse(_period.text.trim());
      final remind = int.tryParse(_remindBefore.text.trim());
      final grace = int.tryParse(_grace.text.trim());
      if (period == null || remind == null || grace == null) {
        throw const FormatException('天数需填写整数');
      }
      final validation = CradlePlan.validationError(
        periodDays: period,
        remindBeforeDays: remind,
        graceDays: grace,
      );
      if (validation != null) throw FormatException(validation);
      final ownerEmail = _ownerEmail.text.trim();
      if (!ownerEmail.contains('@') || ownerEmail.length < 3) {
        throw const FormatException('请填写你的提醒邮箱（接收超期提醒）');
      }
      final recipients = <CradleRecipient>[];
      for (final draft in _drafts) {
        final fingerprint = draft.fingerprint;
        final match = _availableRecipients.firstWhereOrNull(
          (r) => r.fingerprint == fingerprint,
        );
        if (match == null) throw const FormatException('请为每个接收者选择身份');
        final email = draft.email.text.trim();
        if (!email.contains('@') || email.length < 3) {
          throw FormatException('请为「${match.name}」填写邮箱');
        }
        recipients.add(
          CradleRecipient(
            label: match.name,
            email: email,
            packageName: CradleRecipient.packageNameFor(match.name),
            cloudUrl: connection.baseUrl.toString(),
            cloudUser: connection.username,
            cloudPassword: connection.password,
          ),
        );
      }
      final plan = CradlePlan(
        ownerEmail: ownerEmail,
        periodDays: period,
        remindBeforeDays: remind,
        graceDays: grace,
        recipients: List.unmodifiable(recipients),
      );
      final medium = await _medium(connection);
      try {
        await CradleService(handoff).uploadPlan(medium, plan);
      } finally {
        medium.close();
      }
      if (mounted) setState(() => _status = '摇篮计划已保存到云端');
    } on Object catch (error) {
      if (mounted) setState(() => _status = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _planPreview() {
    final period = int.tryParse(_period.text.trim());
    final remind = int.tryParse(_remindBefore.text.trim());
    final grace = int.tryParse(_grace.text.trim());
    if (period == null || remind == null || grace == null) return '天数需填写整数';
    final error = CradlePlan.validationError(
      periodDays: period,
      remindBeforeDays: remind,
      graceDays: grace,
    );
    if (error != null) return error;
    return '报平安后第 ${period - remind} 天开始提醒你；第 ${period + grace} 天仍无报平安时，通知接收者取件。';
  }

  String _formatTime(DateTime time) {
    final local = time.toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final connected = _cloudLabel.isNotEmpty;
    return Scaffold(
      appBar: AppBar(title: const Text('报平安与自动交接')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text(
                '长期没有报平安时，云端会先发邮件提醒你；继续超过宽限期，'
                '会按下面预先授权的内容通知接收者，凭云端账号自行取件。',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (!_loaded)
                        const LinearProgressIndicator()
                      else ...[
                        Text(
                          connected
                              ? '云端：$_cloudLabel（已配置）'
                              : '云端：未配置',
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _lastCheckin == null
                              ? '最近报平安：尚无记录'
                              : '最近报平安：${_formatTime(_lastCheckin!.checkedAt)}'
                                    '（${_lastCheckin!.device}）',
                        ),
                        if (!connected) ...[
                          const SizedBox(height: 12),
                          OutlinedButton(
                            onPressed: () => Navigator.of(context).push<void>(
                              MaterialPageRoute(
                                builder: (_) => const DeviceTransferPage(),
                              ),
                            ),
                            child: const Text('去配置云端连接'),
                          ),
                        ],
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: connected && !_busy ? _checkIn : null,
                icon: const Icon(Icons.favorite),
                label: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text('报平安', style: TextStyle(fontSize: 18)),
                ),
              ),
              Text(
                '打开 App 也会自动记一次，隔一会儿才重复。',
                style: theme.textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
              if (_status != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    _status!,
                    style: TextStyle(
                      color: _status!.contains('已') ||
                              _status!.contains('成功')
                          ? theme.colorScheme.primary
                          : theme.colorScheme.error,
                    ),
                  ),
                ),
              const Divider(height: 40),
              Text('摇篮计划', style: theme.textTheme.titleMedium),
              const SizedBox(height: 12),
              TextField(
                controller: _ownerEmail,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: '提醒邮箱（发给你本人的超期提醒）',
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _period,
                      keyboardType: TextInputType.number,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                        labelText: '周期（天）',
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _remindBefore,
                      keyboardType: TextInputType.number,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                        labelText: '提前（天）',
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _grace,
                      keyboardType: TextInputType.number,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                        labelText: '宽限（天）',
                        isDense: true,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(_planPreview(), style: theme.textTheme.bodySmall),
              const SizedBox(height: 16),
              Text('接收者通知', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              if (_availableRecipients.isEmpty)
                Text(
                  '还没有已验证的接收者身份：先到「交接」页完成接收者核对。',
                  style: theme.textTheme.bodySmall,
                )
              else ...[
                for (var index = 0; index < _drafts.length; index++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: DropdownButtonFormField<String>(
                            initialValue: _drafts[index].fingerprint,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: '接收者',
                              isDense: true,
                            ),
                            items: [
                              for (final recipient in _availableRecipients)
                                DropdownMenuItem(
                                  value: recipient.fingerprint,
                                  child: Text(
                                    recipient.name,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                            ],
                            onChanged: (value) => setState(
                              () => _drafts[index].fingerprint = value,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 4,
                          child: TextField(
                            controller: _drafts[index].email,
                            decoration: const InputDecoration(
                              labelText: '邮箱',
                              isDense: true,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () => setState(
                            () => _drafts.removeAt(index).dispose(),
                          ),
                          icon: const Icon(Icons.close),
                          tooltip: '移除',
                        ),
                      ],
                    ),
                  ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () =>
                        setState(() => _drafts.add(_RecipientDraft())),
                    icon: const Icon(Icons.add),
                    label: const Text('添加接收者'),
                  ),
                ),
              ],
              const SizedBox(height: 8),
              FilledButton.tonal(
                onPressed: connected && !_busy ? _savePlan : null,
                child: const Text('保存计划到云端'),
              ),
              const SizedBox(height: 8),
              Text(
                '预先授权的交接包上传（取件内容本身）还在下一步提供；'
                '现在可以先设好计划与提醒。',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
