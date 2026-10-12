import 'package:flutter/material.dart';

import '../controllers/app_controller.dart';
import '../../core/ai/outbound_consent.dart';
import '../../core/domain/entities.dart';
import 'card_dialogs.dart';
import 'ai_settings_dialog.dart';
import 'outbound_consent_dialog.dart';

Future<void> showAiPrivacyWorkspace(
  BuildContext context,
  AppController controller,
  VaultBlob blob,
) async {
  await showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _AiPrivacyWorkspace(controller: controller, blob: blob),
  );
}

class _AiPrivacyWorkspace extends StatefulWidget {
  const _AiPrivacyWorkspace({required this.controller, required this.blob});

  final AppController controller;
  final VaultBlob blob;

  @override
  State<_AiPrivacyWorkspace> createState() => _AiPrivacyWorkspaceState();
}

class _AiPrivacyWorkspaceState extends State<_AiPrivacyWorkspace> {
  late final Map<int, SensitiveFieldKind> _marks = {
    for (final mark in widget.blob.sensitiveMarks) mark.lineOrder: mark.kind,
  };
  bool _working = false;

  OutboundDestination get _destination {
    final settings = widget.controller.aiSettings;
    return OutboundDestination.ai(
      profileId: settings.id,
      endpoint: settings.endpoint,
      name: settings.name,
    );
  }

  List<SensitiveMark> get _markList => _marks.entries
      .map((entry) => SensitiveMark(lineOrder: entry.key, kind: entry.value))
      .toList(growable: false);

  Future<void> _save() async {
    setState(() => _working = true);
    try {
      await widget.controller.saveSensitiveMarks(widget.blob.id, _markList);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('人工敏感标记已加密保存')));
      }
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(widget.controller.lastError ?? '保存失败')),
        );
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _organize() async {
    try {
      widget.controller.previewAiDisclosure(widget.blob.id, _markList);
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$error')));
      }
      return;
    }
    if (!mounted) return;
    // 首次向该服务发送内容拦一次；之后按下方常驻的“将发送”预览直接整理。
    final allowed = await ensureOutboundConsent(
      context,
      widget.controller,
      destination: _destination,
      kind: OutboundKind.content,
    );
    if (!allowed || !mounted) return;
    setState(() => _working = true);
    try {
      final count = await widget.controller.organizeWithAi(
        widget.blob.id,
        _markList,
      );
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('云 AI 已生成 $count 张待确认草稿')));
      }
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(widget.controller.lastError ?? 'AI 整理失败')),
        );
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) => FractionallySizedBox(
    heightFactor: 0.9,
    child: ListView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      children: [
        Text('检查将发送的内容', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        const Text('选择需要隐藏的行。隐藏行会在本机替换为代号；未标记的文字仍会原样发送。请逐项检查，不能保证自动排除所有隐私信息。'),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          icon: const Icon(Icons.edit_note),
          label: const Text('不使用 AI，手工整理'),
          onPressed: _working
              ? null
              : () => showCardEditor(
                  context,
                  widget.controller,
                  sourceBlobId: widget.blob.id,
                  initialContent: widget.blob.ocrText,
                ),
        ),
        if (!widget.controller.aiSettings.isConfigured)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('尚未配置 AI 服务'),
            subtitle: const Text('手工整理随时可用；配置不会自动授权发送'),
            trailing: const Icon(Icons.settings_outlined),
            onTap: _working
                ? null
                : () async {
                    await showDialog<void>(
                      context: context,
                      builder: (_) =>
                          AiSettingsDialog(controller: widget.controller),
                    );
                    if (mounted) setState(() {});
                  },
          ),
        for (final line in widget.blob.ocrLines)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(line.text),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<SensitiveFieldKind?>(
                    initialValue: _marks[line.order],
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: '此行外发处理'),
                    items: [
                      const DropdownMenuItem<SensitiveFieldKind?>(
                        child: Text('原样发送'),
                      ),
                      for (final kind in SensitiveFieldKind.values)
                        DropdownMenuItem<SensitiveFieldKind?>(
                          value: kind,
                          child: Text('隐藏：${_label(kind)}'),
                        ),
                    ],
                    onChanged: _working
                        ? null
                        : (value) => setState(() {
                            if (value == null) {
                              _marks.remove(line.order);
                            } else {
                              _marks[line.order] = value;
                            }
                          }),
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 12),
        _previewPanel(),
        OutlinedButton(
          onPressed: _working ? null : _save,
          child: const Text('仅保存隐藏标记'),
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          icon: const Icon(Icons.auto_awesome),
          onPressed: _working || !widget.controller.aiSettings.isConfigured
              ? null
              : _organize,
          label: Text(_working ? '正在整理…' : '用 AI 整理'),
        ),
      ],
    ),
  );

  /// 常驻的“将发送”预览：正文常驻在整理按钮上方，所见即所发；
  /// 只有首次向该服务发送时才在按钮按下后确认一次。
  Widget _previewPanel() {
    final settings = widget.controller.aiSettings;
    final service =
        '${settings.model} · ${Uri.tryParse(settings.endpoint)?.host ?? "尚未配置"}';
    final granted = widget.controller.outboundConsent.granted(
      _destination,
      OutboundKind.content,
    );
    String? disclosure;
    String? error;
    try {
      disclosure = widget.controller.previewAiDisclosure(
        widget.blob.id,
        _markList,
      );
    } on Object catch (e) {
      error = e is FormatException ? e.message : '无法准备外发内容';
    }
    return OutboundPreviewPanel(
      service: service,
      children: [
        Text('实际发送的文字（${_marks.length} 行隐藏，未标记行原样发送）：'),
        if (error != null)
          Text(error, style: TextStyle(color: Theme.of(context).colorScheme.error))
        else
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 160),
            child: SingleChildScrollView(
              child: SelectableText(disclosure ?? ''),
            ),
          ),
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: const Text('对照识别原文'),
          children: [SelectableText(widget.blob.ocrText ?? '')],
        ),
        if (!granted)
          const Text('首次向这个服务发送会先确认一次；之后按本预览直接整理。'),
      ],
    );
  }

  String _label(SensitiveFieldKind kind) => switch (kind) {
    SensitiveFieldKind.account => '账号',
    SensitiveFieldKind.secret => '密码与密钥',
    SensitiveFieldKind.money => '金额',
    SensitiveFieldKind.note => '私密备注',
  };
}
