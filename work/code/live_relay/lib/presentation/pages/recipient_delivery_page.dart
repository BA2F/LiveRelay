import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../application/handoff_delivery_service.dart';
import '../../application/local_handoff_service.dart';
import '../../core/domain/entities.dart';
import '../../core/security/pickup_code.dart';
import '../../core/transfer/webdav_connection.dart';
import '../../infrastructure/transfer/webdav_transfer_medium.dart';
import '../controllers/app_controller.dart';
import '../model_labels.dart';
import '../widgets/read_only_snapshot.dart';

/// Edits one password-protected handoff package: scope, pickup code, email
/// draft, upload, test send, disable and delete.
class RecipientDeliveryPage extends StatefulWidget {
  const RecipientDeliveryPage({super.key, required this.deliveryId});

  final String deliveryId;

  @override
  State<RecipientDeliveryPage> createState() => _RecipientDeliveryPageState();
}

class _RecipientDeliveryPageState extends State<RecipientDeliveryPage> {
  final _label = TextEditingController();
  final _email = TextEditingController();
  final _subject = TextEditingController();
  final _body = TextEditingController();
  final _message = TextEditingController();

  HandoffDelivery? _delivery;
  List<HandoffDelivery> _all = [];
  List<ScopedRecord> _scope = [];
  String? _pendingCode;
  String? _pendingPackageName;
  bool _loaded = false;
  bool _busy = false;
  bool _showCode = false;
  String? _error;
  String? _notice;
  String? _lastTestRequestedAt;

  @override
  void initState() {
    super.initState();
    _label.addListener(_onFieldChanged);
    _email.addListener(_onFieldChanged);
    _subject.addListener(_onFieldChanged);
    _message.addListener(_onFieldChanged);
    _body.addListener(_onFieldChanged);
    _load();
  }

  @override
  void dispose() {
    _label.removeListener(_onFieldChanged);
    _email.removeListener(_onFieldChanged);
    _subject.removeListener(_onFieldChanged);
    _message.removeListener(_onFieldChanged);
    _body.removeListener(_onFieldChanged);
    _label.dispose();
    _email.dispose();
    _subject.dispose();
    _body.dispose();
    _message.dispose();
    super.dispose();
  }

  void _onFieldChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    try {
      final service = context.read<AppController>().delivery!;
      final delivery = await service.find(widget.deliveryId);
      final all = await service.list();
      if (!mounted) return;
      if (delivery != null) {
        _label.text = delivery.label;
        _email.text = delivery.email;
        _subject.text = delivery.subject;
        _body.text = delivery.body;
        _message.text = delivery.message;
      }
      setState(() {
        _delivery = delivery;
        _all = all;
        _pendingCode = null;
        _pendingPackageName = null;
        _scope = delivery == null ? [] : List.of(delivery.scope);
        _loaded = true;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _error = '$error';
        _loaded = true;
      });
    }
  }

  HandoffDelivery? _current() {
    final delivery = _delivery;
    if (delivery == null) return null;
    return delivery.copyWith(
      label: _label.text.trim(),
      email: _email.text.trim(),
      pickupCode: _pendingCode,
      packageName: _pendingPackageName,
      scope: List.unmodifiable(_scope),
      subject: _subject.text,
      body: _body.text,
      message: _message.text,
    );
  }

  bool get _dirty {
    final current = _current();
    final saved = _delivery;
    if (current == null || saved == null) return false;
    return jsonEncode(current.toJson()) != jsonEncode(saved.toJson());
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      await action();
    } on Object catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  WebDavTransferMedium _medium(WebDavConnection connection) =>
      WebDavTransferMedium(
        baseUrl: connection.baseUrl,
        username: connection.username,
        password: connection.password,
        timeout: const Duration(seconds: 120),
      );

  Future<void> _saveOnly() async {
    final controller = context.read<AppController>();
    final service = controller.delivery!;
    final current = _current();
    if (current == null) return;
    final saved = await service.save(current);
    if (mounted) {
      setState(() {
        _delivery = saved;
        _pendingCode = null;
        _pendingPackageName = null;
      });
    }
  }

  void _validateMessageInBody() {
    final message = _message.text.trim();
    if (message.isNotEmpty && !_body.text.contains(message)) {
      throw const FormatException('留言还没有放进正文：先点「从留言重新生成正文」');
    }
  }

  Future<void> _upload() async {
    final controller = context.read<AppController>();
    final service = controller.delivery!;
    final current = _current();
    if (current == null) return;
    if (_scope.isEmpty) {
      throw const FormatException('先选择至少一条要交付的内容');
    }
    _validateMessageInBody();
    final connection = await controller.webDavConnection();
    if (connection == null) {
      throw StateError('还没有配置云端连接：先到「设备间搬运」里配置云端');
    }
    final timing = await service.timing();
    final problem = timing.validationError;
    if (problem != null) throw FormatException(problem);
    final medium = _medium(connection);
    try {
      final saved = await service.upload(
        current,
        connection: connection,
        timing: timing,
        medium: medium,
      );
      final all = await service.list();
      final ready = all
          .where((delivery) => delivery.status == DeliveryStatus.uploaded)
          .length;
      final unready = all
          .where(
            (delivery) =>
                delivery.enabled && delivery.status != DeliveryStatus.uploaded,
          )
          .length;
      if (!mounted) return;
      setState(() {
        _delivery = saved;
        _pendingCode = null;
        _pendingPackageName = null;
        _notice =
            '交接包已上传，计划已更新（$ready 位已准备'
            '${unready > 0 ? '；$unready 位未上传或待更新' : ''}）';
      });
    } finally {
      medium.close();
    }
  }

  Future<void> _preview() async {
    final controller = context.read<AppController>();
    final current = _current();
    if (current == null) return;
    if (_scope.isEmpty) {
      throw const FormatException('先选择至少一条要交付的内容');
    }
    final snapshot = await controller.delivery!.preview(current);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${current.label} 将看到'),
        content: SizedBox(
          width: 640,
          child: SingleChildScrollView(child: ReadOnlySnapshot(data: snapshot)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  Future<void> _resetDraft() async {
    final controller = context.read<AppController>();
    final current = _current();
    if (current == null) return;
    final connection = await controller.webDavConnection();
    if (connection == null) {
      throw StateError('还没有配置云端连接：先到「设备间搬运」里配置云端');
    }
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('重新生成邮件草稿？'),
        content: const Text('会覆盖当前正文；留言会保留。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('重新生成'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    _body.text = HandoffDeliveryService.defaultBody(
      message: _message.text,
      packageUrl: HandoffDeliveryService.packageUrl(
        connection,
        current.packageName,
      ).toString(),
      packageName: current.packageName,
      cloudUser: connection.username,
      cloudPassword: connection.password,
      pickupCode: current.pickupCode,
    );
    if (mounted) setState(() => _notice = '邮件正文已从留言重新生成');
  }

  Future<void> _changeCode({required bool regenerate}) async {
    final current = _current();
    if (current == null) return;
    String? next;
    if (regenerate) {
      next = PickupCode.generate();
    } else {
      final controller = TextEditingController();
      try {
        next = await showDialog<String>(
          context: context,
          builder: (context) => StatefulBuilder(
            builder: (context, refresh) => AlertDialog(
              title: const Text('自定义取件码'),
              content: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('至少 12 位；不区分大小写，忽略空格和连字符。'),
                    const SizedBox(height: 12),
                    TextField(
                      controller: controller,
                      onChanged: (_) => refresh(() {}),
                      decoration: const InputDecoration(labelText: '取件码'),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: PickupCode.isValid(controller.text)
                      ? () => Navigator.pop(
                          context,
                          PickupCode.normalize(controller.text),
                        )
                      : null,
                  child: const Text('确定'),
                ),
              ],
            ),
          ),
        );
      } finally {
        controller.dispose();
      }
    }
    if (next == null || !mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('更换取件码？'),
        content: const Text(
          '旧码对之后下载的包失效，旧包会保留；已经发出的邮件仍指向旧包和旧码。'
          '草稿里的旧码会一并替换。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('更换'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final service = context.read<AppController>().delivery!;
    final oldCode = current.pickupCode;
    final newPackageName = service.generatePackageName();
    final packageLinked = _body.text.contains(current.packageName);
    final codeLinked = HandoffDeliveryService.bodyContainsCode(
      _body.text,
      oldCode,
    );
    var newBody = _body.text.replaceAll(current.packageName, newPackageName);
    newBody = HandoffDeliveryService.replaceCode(newBody, oldCode, next);
    _body.text = newBody;
    setState(() {
      _pendingCode = next;
      _pendingPackageName = newPackageName;
      _notice = packageLinked || codeLinked
          ? '取件码和交接包已更换；点「上传/更新交接包」后生效'
          : '取件码和交接包已更换；草稿里没有旧链接，请点「从留言重新生成正文」更新';
    });
  }

  Future<void> _chooseOriginals(String cardId) async {
    final controller = context.read<AppController>();
    final sources = await controller.cardSources(cardId);
    final available = controller.blobs
        .where((blob) => sources.any((source) => source.blobId == blob.id))
        .toList();
    if (!mounted) return;
    final existing = _scope.firstWhereOrNull(
      (entry) => entry.type == 'card' && entry.id == cardId,
    );
    final ids = <String>{...?existing?.originalIds};
    final result = await showDialog<List<String>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, refresh) => AlertDialog(
          title: const Text('交付哪些原件'),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('勾选的文件会完整交付，包括图片、录音等原始内容。'),
                  for (final blob in available)
                    CheckboxListTile(
                      value: ids.contains(blob.id),
                      title: Text(blob.originalName),
                      onChanged: (value) => refresh(() {
                        if (value == true) {
                          ids.add(blob.id);
                        } else {
                          ids.remove(blob.id);
                        }
                      }),
                    ),
                  if (available.isEmpty) const Text('此卡片没有关联原件'),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, ids.toList()),
              child: const Text('确认原件范围'),
            ),
          ],
        ),
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      final index = _scope.indexWhere(
        (entry) => entry.type == 'card' && entry.id == cardId,
      );
      if (index == -1) return;
      final record = _scope[index];
      _scope[index] = ScopedRecord(
        record.type,
        record.id,
        result.isEmpty ? VisibilityLevel.full : VisibilityLevel.original,
        history: record.history,
        originalIds: result,
      );
    });
  }

  Future<void> _copyPreviousScope() async {
    final controller = context.read<AppController>();
    final index = _all.indexWhere((entry) => entry.id == widget.deliveryId);
    if (index <= 0) {
      setState(() => _error = '没有上一位接收者可以复制');
      return;
    }
    final source = _all[index - 1].scope;
    final valid = <ScopedRecord>[];
    for (final entry in source) {
      if (entry.type == 'card') {
        final card = controller.cards.firstWhereOrNull((c) => c.id == entry.id);
        if (card == null) continue;
        final sources = await controller.cardSources(card.id);
        final available = {
          for (final blob in controller.blobs)
            if (sources.any((source) => source.blobId == blob.id)) blob.id,
        };
        final originals = entry.originalIds.where(available.contains).toList();
        valid.add(
          ScopedRecord(
            'card',
            entry.id,
            entry.level == VisibilityLevel.original && originals.isEmpty
                ? VisibilityLevel.full
                : entry.level,
            history: entry.history,
            originalIds: originals,
          ),
        );
      } else if (controller.credentials.any((c) => c.id == entry.id)) {
        valid.add(entry);
      }
    }
    if (!mounted) return;
    setState(() {
      _scope = valid;
      _notice = '已复制 ${_all[index - 1].label} 的范围';
    });
  }

  Future<void> _toggleEnabled(bool enabled) async {
    final controller = context.read<AppController>();
    final service = controller.delivery!;
    final current = _current();
    if (current == null) return;
    final saved = await service.save(current.copyWith(enabled: enabled));
    if (mounted) {
      setState(() {
        _delivery = saved;
        _pendingCode = null;
        _pendingPackageName = null;
        _notice = enabled ? '已启用；上传/更新后生效' : '已停用';
      });
    }
    if (enabled) return;
    final connection = await controller.webDavConnection();
    if (connection == null) {
      if (mounted) {
        setState(() => _error = '已在本机停用，但还没有云端连接，计划未更新');
      }
      return;
    }
    final timing = await service.timing();
    final problem = timing.validationError;
    if (problem != null) {
      if (mounted) setState(() => _error = '已在本机停用，但计划未更新：$problem');
      return;
    }
    final medium = _medium(connection);
    try {
      await service.syncPlan(
        connection: connection,
        timing: timing,
        medium: medium,
      );
      if (mounted) setState(() => _notice = '已停用，云端计划已更新');
    } on Object catch (error) {
      if (mounted) {
        setState(() => _error = '已在本机停用，但云端计划未更新，仍可能发送：$error');
      }
    } finally {
      medium.close();
    }
  }

  Future<void> _delete() async {
    final controller = context.read<AppController>();
    final service = controller.delivery!;
    final current = _current();
    if (current == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('删除接收者「${current.label}」？'),
        content: const Text(
          '会从摇篮计划移除并删除云端交接包。如果邮件已经发出，收件人将无法下载；'
          '已经下载的副本无法收回。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final persistedPackageName = _delivery?.packageName;
    await _run(() async {
      final disabled = await service.save(current.copyWith(enabled: false));
      final connection = await controller.webDavConnection();
      if (connection == null) {
        throw StateError('已在本机停用，但还没有云端连接，计划未更新；收件人仍可能收到邮件');
      }
      final timing = await service.timing();
      final problem = timing.validationError;
      if (problem != null) {
        throw StateError('已在本机停用，但计划未更新：$problem');
      }
      final medium = _medium(connection);
      try {
        await service.syncPlan(
          connection: connection,
          timing: timing,
          medium: medium,
        );
        await service.deletePackage(disabled, medium);
        if (persistedPackageName != null &&
            persistedPackageName != disabled.packageName) {
          await service.deletePackage(
            disabled.copyWith(packageName: persistedPackageName),
            medium,
          );
        }
      } finally {
        medium.close();
      }
      await service.remove(disabled.id);
      if (mounted) Navigator.pop(context);
    });
  }

  Future<void> _testSend() async {
    final controller = context.read<AppController>();
    final service = controller.delivery!;
    final current = _current();
    if (current == null) return;
    if (_dirty || current.uploadedAt == null) {
      throw const FormatException('先点「上传/更新交接包」，再发测试邮件');
    }
    _validateMessageInBody();
    final connection = await controller.webDavConnection();
    if (connection == null) {
      throw StateError('还没有配置云端连接：先到「设备间搬运」里配置云端');
    }
    final timing = await service.timing();
    if (!mounted) return;
    final target = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('发送测试邮件'),
        content: Text(
          '测试邮件会用当前草稿发送。发到接收者邮箱前先确认对方知道这是测试。\n\n'
          '接收者：${current.label} <${current.email}>',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          OutlinedButton(
            onPressed: timing.ownerEmail.contains('@')
                ? () => Navigator.pop(context, false)
                : null,
            child: const Text('发到我的邮箱'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('发到接收者邮箱'),
          ),
        ],
      ),
    );
    if (target == null || !mounted) return;
    final to = target ? current.email : timing.ownerEmail;
    final medium = _medium(connection);
    try {
      final requestedAt = await service.requestTestSend(
        to: to,
        subject: _subject.text,
        body: _body.text,
        medium: medium,
      );
      if (!mounted) return;
      setState(() {
        _lastTestRequestedAt = requestedAt;
        _notice = '测试邮件已提交给摇篮服务，稍后点「检查测试结果」查看';
      });
    } finally {
      medium.close();
    }
  }

  Future<void> _checkTestResult() async {
    final controller = context.read<AppController>();
    final connection = await controller.webDavConnection();
    if (connection == null) {
      throw StateError('还没有配置云端连接');
    }
    final medium = _medium(connection);
    try {
      final result = await controller.delivery!.readTestResult(medium);
      if (!mounted) return;
      if (result == null) {
        setState(() => _notice = '摇篮服务还没有留下测试结果，稍后再试');
        return;
      }
      if (_lastTestRequestedAt != null &&
          result['requestedAt'] != _lastTestRequestedAt) {
        setState(() => _notice = '摇篮服务还没处理这次测试；文件里是上一次的结果');
        return;
      }
      final error = result['error'];
      final sentAt = result['sentAt'];
      setState(() {
        _notice = error != null && '$error'.isNotEmpty
            ? '测试邮件失败：$error'
            : sentAt != null
            ? '测试邮件已发送：$sentAt'
            : '测试请求已提交，服务端尚未发送';
      });
    } finally {
      medium.close();
    }
  }

  String _statusLabel(DeliveryStatus status) => switch (status) {
    DeliveryStatus.draft => '草稿',
    DeliveryStatus.uploaded => '已上传',
    DeliveryStatus.needsUpdate => '待更新',
    DeliveryStatus.disabled => '已停用',
  };

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    if (!_loaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final delivery = _delivery;
    if (delivery == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('接收者详情')),
        body: const Center(child: Text('这个接收者已被删除')),
      );
    }
    final records = <InformationCard>[
      ...controller.cards,
      ...controller.credentials,
    ];
    final allSelected =
        records.isNotEmpty &&
        records.every((record) {
          final type = record is LifeCard ? 'card' : 'credential';
          return _scope.any(
            (entry) => entry.type == type && entry.id == record.id,
          );
        });
    final someSelected = _scope.isNotEmpty;
    final code = _pendingCode ?? delivery.pickupCode;
    final statusLabel = _dirty && delivery.status != DeliveryStatus.disabled
        ? '待更新'
        : _statusLabel(delivery.status);
    final codeInDraft = HandoffDeliveryService.bodyContainsCode(
      _body.text,
      code,
    );
    final selectedRecords = [
      for (final record in records)
        if (_scope.any(
          (entry) =>
              entry.type == (record is LifeCard ? 'card' : 'credential') &&
              entry.id == record.id,
        ))
          record,
    ];
    return Scaffold(
      appBar: AppBar(
        title: Text(
          '接收者 · ${_label.text}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _label,
                    enabled: !_busy,
                    decoration: const InputDecoration(labelText: '称呼'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _email,
                    enabled: !_busy,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(labelText: '邮箱'),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Chip(label: Text(statusLabel)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _dirty
                              ? '有未保存修改'
                              : delivery.uploadedAt == null
                              ? '还没有上传交接包'
                              : '上次上传：${delivery.uploadedAt!.toLocal()}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text('内容', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          const Text('默认交付完整正文和当前密码；原件默认不附。'),
          CheckboxListTile(
            value: allSelected
                ? true
                : someSelected
                ? null
                : false,
            tristate: true,
            title: const Text('全选'),
            subtitle: Text('已选 ${_scope.length} / ${records.length} 条'),
            onChanged: _busy
                ? null
                : (value) => setState(() {
                    if (value == true) {
                      for (final record in records) {
                        final type = record is LifeCard ? 'card' : 'credential';
                        if (!_scope.any(
                          (entry) =>
                              entry.type == type && entry.id == record.id,
                        )) {
                          _scope.add(
                            ScopedRecord(
                              type,
                              record.id,
                              record is LifeCard
                                  ? VisibilityLevel.full
                                  : VisibilityLevel.secret,
                            ),
                          );
                        }
                      }
                    } else {
                      _scope = [];
                    }
                  }),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _busy ? null : _copyPreviousScope,
              icon: const Icon(Icons.copy_all_outlined),
              label: const Text('复制上一位的范围'),
            ),
          ),
          const Divider(),
          for (final record in records)
            CheckboxListTile(
              value: _scope.any(
                (entry) =>
                    entry.type ==
                        (record is LifeCard ? 'card' : 'credential') &&
                    entry.id == record.id,
              ),
              title: Text(record.title),
              subtitle: Text(
                record is LifeCard
                    ? '卡片 · 完整正文${_scope.any((entry) => entry.type == 'card' && entry.id == record.id && entry.originalIds.isNotEmpty) ? ' · 含原件' : ''}'
                    : '密码条目 · 账号、网址、备注和当前密码',
              ),
              onChanged: _busy
                  ? null
                  : (value) => setState(() {
                      final type = record is LifeCard ? 'card' : 'credential';
                      if (value == true) {
                        if (!_scope.any(
                          (entry) =>
                              entry.type == type && entry.id == record.id,
                        )) {
                          _scope.add(
                            ScopedRecord(
                              type,
                              record.id,
                              record is LifeCard
                                  ? VisibilityLevel.full
                                  : VisibilityLevel.secret,
                            ),
                          );
                        }
                      } else {
                        _scope.removeWhere(
                          (entry) =>
                              entry.type == type && entry.id == record.id,
                        );
                      }
                    }),
            ),
          if (selectedRecords.isNotEmpty) ...[
            const SizedBox(height: 8),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('高级范围'),
              subtitle: const Text('逐条可见级别、修订历史和原件'),
              children: [
                for (final record in selectedRecords) _advancedRecord(record),
              ],
            ),
          ],
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: _busy ? null : _preview,
              icon: const Icon(Icons.visibility_outlined),
              label: const Text('预览对方将看到的内容'),
            ),
          ),
          const SizedBox(height: 20),
          Text('取件码', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    _showCode ? PickupCode.format(code) : '••••-••••-••••',
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 18,
                      letterSpacing: 1.5,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      TextButton(
                        onPressed: () => setState(() => _showCode = !_showCode),
                        child: Text(_showCode ? '遮住' : '显示'),
                      ),
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () async {
                                await Clipboard.setData(
                                  ClipboardData(text: PickupCode.format(code)),
                                );
                                if (mounted) {
                                  setState(() => _notice = '取件码已复制');
                                }
                              },
                        child: const Text('复制'),
                      ),
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () => _changeCode(regenerate: true),
                        child: const Text('重新生成'),
                      ),
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () => _changeCode(regenerate: false),
                        child: const Text('自定义'),
                      ),
                    ],
                  ),
                  Text(
                    codeInDraft ? '邮件草稿包含取件码' : '邮件草稿不含取件码，接收者需要你另行告知',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text('邮件草稿', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          TextField(
            controller: _subject,
            enabled: !_busy,
            decoration: const InputDecoration(labelText: '主题'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _message,
            enabled: !_busy,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: '留言（会放进正文）',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _body,
            enabled: !_busy,
            minLines: 12,
            maxLines: 24,
            decoration: const InputDecoration(
              labelText: '正文',
              alignLabelWithHint: true,
              border: OutlineInputBorder(),
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _busy ? null : _resetDraft,
              icon: const Icon(Icons.refresh),
              label: const Text('从留言重新生成正文'),
            ),
          ),
          const Text(
            '更换云端连接后，点「从留言重新生成正文」更新链接和账号。',
            style: TextStyle(fontSize: 12),
          ),
          if (_notice != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                _notice!,
                style: TextStyle(color: Theme.of(context).colorScheme.primary),
              ),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          if (_busy) const LinearProgressIndicator(),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: _busy
                ? null
                : () => _run(() async {
                    await _saveOnly();
                    await _upload();
                  }),
            child: const Text('上传/更新交接包'),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton(
                onPressed: _busy ? null : () => _run(_testSend),
                child: const Text('发送测试邮件'),
              ),
              OutlinedButton(
                onPressed: _busy ? null : () => _run(_checkTestResult),
                child: const Text('检查测试结果'),
              ),
              if (delivery.enabled)
                OutlinedButton(
                  onPressed: _busy
                      ? null
                      : () => _run(() => _toggleEnabled(false)),
                  child: const Text('停用'),
                )
              else
                OutlinedButton(
                  onPressed: _busy
                      ? null
                      : () => _run(() => _toggleEnabled(true)),
                  child: const Text('启用'),
                ),
              TextButton(
                onPressed: _busy ? null : _delete,
                child: Text(
                  '删除接收者',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _advancedRecord(InformationCard record) {
    final type = record is LifeCard ? 'card' : 'credential';
    final index = _scope.indexWhere(
      (entry) => entry.type == type && entry.id == record.id,
    );
    if (index == -1) return const SizedBox.shrink();
    final entry = _scope[index];
    final qualifiesForHistory = record is LifeCard
        ? entry.level.index >= VisibilityLevel.full.index
        : entry.level.index >= VisibilityLevel.secret.index;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(record.title, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            DropdownButtonFormField<VisibilityLevel>(
              initialValue: entry.level,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: '可见级别',
                isDense: true,
              ),
              items: [
                for (final level in VisibilityLevel.values)
                  DropdownMenuItem(value: level, child: Text(level.label)),
              ],
              onChanged: _busy
                  ? null
                  : (value) {
                      if (value == null) return;
                      setState(() {
                        if (value == VisibilityLevel.hidden) {
                          _scope.removeAt(index);
                          return;
                        }
                        _scope[index] = ScopedRecord(
                          entry.type,
                          entry.id,
                          value,
                          history: entry.history,
                          originalIds: entry.originalIds,
                        );
                      });
                    },
            ),
            if (qualifiesForHistory)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: entry.history,
                title: const Text('附带完整修订历史'),
                onChanged: _busy
                    ? null
                    : (value) => setState(() {
                        _scope[index] = ScopedRecord(
                          entry.type,
                          entry.id,
                          entry.level,
                          history: value == true,
                          originalIds: entry.originalIds,
                        );
                      }),
              ),
            if (record is LifeCard)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: _busy ? null : () => _chooseOriginals(record.id),
                  child: Text(
                    entry.originalIds.isEmpty
                        ? '选择原件（默认不附）'
                        : '已选 ${entry.originalIds.length} 个原件',
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
