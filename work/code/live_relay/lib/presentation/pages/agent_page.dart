import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/app_controller.dart';
import '../../application/draft_agent_service.dart';
import '../../core/ai/outbound_consent.dart';
import '../../core/domain/entities.dart';
import '../dialogs/ai_settings_dialog.dart';
import '../dialogs/outbound_consent_dialog.dart';

class AgentPage extends StatefulWidget {
  const AgentPage({super.key});
  @override
  State<AgentPage> createState() => _AgentPageState();
}

class _AgentPageState extends State<AgentPage> {
  final _text = TextEditingController();
  final _marks = <int, SensitiveFieldKind>{};
  late AppController _controller;
  AgentDraftBatch? _batch;
  bool _working = false;
  bool _allowCommands = false;
  int _generation = 0;
  String? _error;
  @override
  void initState() {
    super.initState();
    _controller = context.read<AppController>();
    _controller.addListener(_sessionChanged);
  }

  void _sessionChanged() {
    if (!_controller.isUnlocked) {
      _generation++;
      _text.clear();
      _marks.clear();
      _batch = null;
      if (mounted) setState(() {});
    }
  }

  @override
  void dispose() {
    if (_working) _controller.cancelAgentTask();
    _controller.removeListener(_sessionChanged);
    _text.dispose();
    super.dispose();
  }

  OutboundDestination get _destination {
    final settings = _controller.aiSettings;
    return OutboundDestination.ai(
      profileId: settings.id,
      endpoint: settings.endpoint,
      name: settings.name,
    );
  }

  Future<void> _runAgent() async {
    final generation = _generation;
    final text = _text.text;
    final marks = [
      for (final e in _marks.entries)
        SensitiveMark(lineOrder: e.key, kind: e.value),
    ];
    try {
      _controller.previewAgentDisclosure(text, marks);
    } on Object catch (e) {
      setState(() => _error = e is FormatException ? e.message : '无法准备资料');
      return;
    }
    // 首次向该服务发送内容拦一次；之后按输入区上方的“将发送”面板直接整理。
    final allowed = await ensureOutboundConsent(
      context,
      _controller,
      destination: _destination,
      kind: OutboundKind.content,
    );
    if (!allowed || !mounted || !_controller.isUnlocked || generation != _generation) {
      return;
    }
    setState(() {
      _working = true;
      _error = null;
      _batch = null;
    });
    try {
      final batch = await _controller.proposeAgentDrafts(
        text,
        marks,
        allowCommands: _allowCommands,
      );
      if (mounted && _controller.isUnlocked && generation == _generation) {
        setState(() => _batch = batch);
      }
    } on Object {
      if (mounted) {
        setState(() => _error = _controller.lastError ?? '整理失败，输入仍保留');
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _save() async {
    final batch = _batch;
    if (batch == null) return;
    setState(() => _working = true);
    try {
      await _controller.saveAgentDrafts(batch);
      if (mounted) {
        setState(() => _batch = null);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已加密保存 ${batch.suggestions.length} 张待整理草稿')),
        );
      }
    } on Object {
      if (mounted) setState(() => _error = _controller.lastError ?? '保存失败');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  /// 输入区旁边的“将发送”面板：实际外发文字就放在整理按钮上方，
  /// 不再靠每轮的授权弹窗展示发送范围。
  Widget _previewPanel(AppController controller) {
    if (_text.text.trim().isEmpty) return const SizedBox.shrink();
    final settings = controller.aiSettings;
    final service =
        '${settings.model} · ${Uri.tryParse(settings.endpoint)?.host ?? "尚未配置"}';
    String? disclosure;
    String? error;
    try {
      disclosure = controller.previewAgentDisclosure(_text.text, [
        for (final e in _marks.entries)
          SensitiveMark(lineOrder: e.key, kind: e.value),
      ]);
    } on Object catch (e) {
      error = e is FormatException ? e.message : '无法准备资料';
    }
    final granted = controller.outboundConsent.granted(
      _destination,
      OutboundKind.content,
    );
    return OutboundPreviewPanel(
      service: service,
      children: [
        if (error != null)
          Text(error, style: TextStyle(color: Theme.of(context).colorScheme.error))
        else ...[
          const Text('实际发送的文字（未标记行原样发送）：'),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 160),
            child: SingleChildScrollView(child: SelectableText(disclosure!)),
          ),
          if (_allowCommands)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text('本次还允许隔离命令处理这些内容；无网络，不能访问本机资料库或个人文件。'),
            ),
          if (!granted)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text('首次向这个服务发送会先确认一次；之后按本面板的范围直接整理。'),
            ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    final lines = _text.text.split('\n');
    return Scaffold(
      appBar: AppBar(
        title: const Text('Agent 整理'),
        actions: [
          IconButton(
            tooltip: 'AI 服务设置',
            icon: const Icon(Icons.settings_outlined),
            onPressed: _working
                ? null
                : () => showDialog<void>(
                    context: context,
                    builder: (_) => AiSettingsDialog(controller: controller),
                  ),
          ),
        ],
      ),
      body: !controller.isUnlocked
          ? const Center(child: Text('请先解锁资料库'))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text('粘贴本次资料，标记敏感行，核对外发内容。结果先供本人检查，再保存为草稿。'),
                const SizedBox(height: 12),
                TextField(
                  controller: _text,
                  enabled: !_working,
                  minLines: 6,
                  maxLines: 12,
                  maxLength: 32000,
                  decoration: const InputDecoration(
                    labelText: '本次资料',
                    alignLabelWithHint: true,
                  ),
                  onChanged: (_) => setState(() {
                    _marks.clear();
                    _batch = null;
                    _error = null;
                  }),
                ),
                if (_text.text.isNotEmpty) ...[
                  const Text('敏感标记（整行替换）'),
                  for (var i = 0; i < lines.length && i < 200; i++)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${i + 1}. ${lines[i]}',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          DropdownButton<SensitiveFieldKind?>(
                            value: _marks[i],
                            items: const [
                              DropdownMenuItem(
                                value: null,
                                child: Text('普通内容'),
                              ),
                              DropdownMenuItem(
                                value: SensitiveFieldKind.account,
                                child: Text('账号'),
                              ),
                              DropdownMenuItem(
                                value: SensitiveFieldKind.secret,
                                child: Text('秘密'),
                              ),
                              DropdownMenuItem(
                                value: SensitiveFieldKind.money,
                                child: Text('金额'),
                              ),
                              DropdownMenuItem(
                                value: SensitiveFieldKind.note,
                                child: Text('私密备注'),
                              ),
                            ],
                            onChanged: _working
                                ? null
                                : (v) => setState(() {
                                    if (v == null) {
                                      _marks.remove(i);
                                    } else {
                                      _marks[i] = v;
                                    }
                                    _batch = null;
                                  }),
                          ),
                        ],
                      ),
                    ),
                ],
                CheckboxListTile(
                  value: _allowCommands,
                  title: const Text('本次允许隔离命令处理'),
                  subtitle: Text(
                    controller.agentCommandsAvailable
                        ? '仅处理本次脱敏资料，无网络；最多 10 秒／次'
                        : '此设备尚未提供隔离命令，文字整理仍可使用',
                  ),
                  onChanged: _working || !controller.agentCommandsAvailable
                      ? null
                      : (v) => setState(() => _allowCommands = v ?? false),
                ),
                if (_error != null)
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                if (_working) ...[
                  const LinearProgressIndicator(),
                  TextButton(
                    onPressed: _controller.cancelAgentTask,
                    child: const Text('取消本次整理'),
                  ),
                ],
                const SizedBox(height: 12),
                _previewPanel(controller),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed:
                      _working || controller.isBusy || controller.isAgentBusy
                      ? null
                      : _runAgent,
                  icon: const Icon(Icons.auto_awesome),
                  label: const Text('用 AI 整理'),
                ),
                if (_batch != null) ...[
                  const SizedBox(height: 20),
                  Text(
                    '待核对草稿 · ${_batch!.suggestions.length}',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  if (_batch!.commandHistory.isNotEmpty)
                    ExpansionTile(
                      title: Text('本次隔离命令 · ${_batch!.commandHistory.length}'),
                      children: [
                        for (final command in _batch!.commandHistory)
                          ListTile(
                            title: SelectableText(command.command),
                            subtitle: SelectableText(
                              '退出码 ${command.exitCode}\n${command.stdout}\n${command.stderr}',
                            ),
                          ),
                      ],
                    ),
                  for (final suggestion in _batch!.suggestions)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              suggestion.title,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            if (suggestion.isInference)
                              const Text('包含 AI 推断，请核对'),
                            const SizedBox(height: 8),
                            SelectableText(suggestion.content),
                          ],
                        ),
                      ),
                    ),
                  FilledButton(
                    onPressed: _working ? null : _save,
                    child: const Text('已核对，保存为待整理草稿'),
                  ),
                  TextButton(
                    onPressed: _working
                        ? null
                        : () => setState(() => _batch = null),
                    child: const Text('丢弃本次结果'),
                  ),
                ],
              ],
            ),
    );
  }
}
