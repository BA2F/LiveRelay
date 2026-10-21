import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../application/cradle_service.dart';
import '../../application/handoff_delivery_service.dart';
import '../../core/cradle/cradle_records.dart';
import '../../core/transfer/webdav_connection.dart';
import '../../infrastructure/transfer/webdav_transfer_medium.dart';
import '../controllers/app_controller.dart';
import '../cradle_auto_checkin.dart';
import 'device_transfer_page.dart';
import 'handoff_page.dart';

/// Check-in record and cradle plan management: the owner-facing half of the
/// cloud cradle (see tasks/specs/2026-10-15_报平安与自动交接.md).
class CradlePage extends StatefulWidget {
  const CradlePage({super.key});

  @override
  State<CradlePage> createState() => _CradlePageState();
}

class _CradlePageState extends State<CradlePage> {
  final _period = TextEditingController(
    text: '${CradlePlan.defaultPeriodDays}',
  );
  final _remindBefore = TextEditingController(
    text: '${CradlePlan.defaultRemindBeforeDays}',
  );
  final _grace = TextEditingController(text: '${CradlePlan.defaultGraceDays}');
  final _ownerEmail = TextEditingController();

  bool _busy = false;
  bool _loaded = false;
  bool _timingApplied = false;
  String? _status;
  String _cloudLabel = '';
  CheckinRecord? _lastCheckin;
  List<HandoffDelivery> _deliveries = const [];
  List<String> _cloudOnlyRecipients = const [];

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
    if (!mounted) return;
    final controller = context.read<AppController>();
    try {
      final connection = await controller.webDavConnection();
      final service = controller.delivery;
      final timing = service == null
          ? CradleTiming.defaults
          : await service.timing();
      final deliveries = service == null
          ? <HandoffDelivery>[]
          : await service.list();
      CheckinRecord? checkin;
      CradlePlan? plan;
      final handoff = controller.handoff;
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
      final localLabels = {for (final delivery in deliveries) delivery.label};
      final cloudOnly = [
        for (final recipient in plan?.recipients ?? const <CradleRecipient>[])
          if (!localLabels.contains(recipient.label)) recipient.label,
      ];
      setState(() {
        _loaded = true;
        _cloudLabel = connection == null
            ? ''
            : '${connection.baseUrl.host}:${connection.baseUrl.port}';
        _lastCheckin = checkin;
        _deliveries = deliveries;
        _cloudOnlyRecipients = cloudOnly;
        if (!_timingApplied) {
          final source = timing.ownerEmail.isNotEmpty
              ? timing
              : plan == null
              ? null
              : CradleTiming(
                  ownerEmail: plan.ownerEmail,
                  periodDays: plan.periodDays,
                  remindBeforeDays: plan.remindBeforeDays,
                  graceDays: plan.graceDays,
                );
          if (source != null) {
            _timingApplied = true;
            _ownerEmail.text = source.ownerEmail;
            _period.text = '${source.periodDays}';
            _remindBefore.text = '${source.remindBeforeDays}';
            _grace.text = '${source.graceDays}';
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
        final record = await CradleService(handoff)
            .uploadCheckin(medium, device: cradleDeviceLabel);
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
      final service = controller.delivery;
      if (handoff == null || service == null) {
        throw StateError('需要先解锁资料库');
      }
      final unready = (await service.list())
          .where(
            (delivery) =>
                delivery.enabled && delivery.status != DeliveryStatus.uploaded,
          )
          .toList();
      if (unready.isNotEmpty) {
        throw FormatException(
          '先到交接页上传或停用：${unready.map((delivery) => delivery.label).join('、')}',
        );
      }
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
      final timing = CradleTiming(
        ownerEmail: ownerEmail,
        periodDays: period,
        remindBeforeDays: remind,
        graceDays: grace,
      );
      await service.saveTiming(timing);
      final medium = await _medium(connection);
      try {
        await service.syncPlan(
          connection: connection,
          timing: timing,
          medium: medium,
        );
      } finally {
        medium.close();
      }
      if (mounted) {
        setState(() {
          _timingApplied = true;
          _status = '摇篮计划已保存到云端';
        });
      }
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

  String _deliveryStatus(DeliveryStatus status) => switch (status) {
    DeliveryStatus.draft => '草稿',
    DeliveryStatus.uploaded => '已上传',
    DeliveryStatus.needsUpdate => '待更新',
    DeliveryStatus.disabled => '已停用',
  };

  bool get _hasUnready => _deliveries.any(
    (delivery) =>
        delivery.enabled && delivery.status != DeliveryStatus.uploaded,
  );

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
                '会按交接页里每人的邮件草稿，把取件链接、账号和取件码发给接收者。',
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
                        Text(connected ? '云端：$_cloudLabel（已配置）' : '云端：未配置'),
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
                      color: _status!.contains('已') || _status!.contains('成功')
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
                onChanged: (_) => setState(() => _timingApplied = true),
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
                      onChanged: (_) => setState(() => _timingApplied = true),
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
                      onChanged: (_) => setState(() => _timingApplied = true),
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
                      onChanged: (_) => setState(() => _timingApplied = true),
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
              if (_deliveries.isEmpty)
                Text(
                  '还没有接收者：先到「交接」页的「交给他人」添加。',
                  style: theme.textTheme.bodySmall,
                )
              else
                for (final delivery in _deliveries)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      delivery.enabled
                          ? Icons.person_outline
                          : Icons.person_off_outlined,
                    ),
                    title: Text(delivery.label),
                    subtitle: Text(
                      '${delivery.email} · '
                      '${_deliveryStatus(delivery.status)}',
                    ),
                  ),
              if (_hasUnready)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    '有 ${_deliveries.where((delivery) => delivery.enabled && delivery.status != DeliveryStatus.uploaded).length} '
                    '位接收者未上传或待更新；先到交接页上传或停用，才能保存计划。',
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ),
              if (_cloudOnlyRecipients.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    '云端计划里还有本机没有的接收者：'
                    '${_cloudOnlyRecipients.join('、')}；保存计划会移除他们。'
                    '请先在交接页重新添加，或确认不再需要。',
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => Navigator.of(context)
                      .push<void>(
                        MaterialPageRoute(
                          builder: (_) => Scaffold(
                            appBar: AppBar(title: const Text('交接')),
                            body: const HandoffPage(),
                          ),
                        ),
                      )
                      .then((_) => _refresh()),
                  icon: const Icon(Icons.people_outline),
                  label: const Text('去交接页管理接收者'),
                ),
              ),
              const SizedBox(height: 8),
              FilledButton.tonal(
                onPressed: connected && !_busy && !_hasUnready
                    ? _savePlan
                    : null,
                child: const Text('保存计划到云端'),
              ),
              const SizedBox(height: 8),
              Text(
                '到点后按交接页里每人的邮件草稿发送；停用的接收者不会写入计划。',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
