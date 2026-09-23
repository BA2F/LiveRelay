import 'package:flutter/material.dart';

import '../../application/app_controller.dart';
import '../../core/domain/entities.dart';

Future<void> showAiPrivacyWorkspace(
  BuildContext context,
  AppController controller,
  VaultBlob blob,
) async {
  if (blob.ocrLines.isEmpty) {
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('请先执行本地 OCR')));
    return;
  }
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
    String disclosure;
    try {
      disclosure = widget.controller.previewAiDisclosure(
        widget.blob.id,
        _markList,
      );
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$error')));
      }
      return;
    }
    if (!mounted) return;
    final settings = widget.controller.aiSettings;
    final allowed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.cloud_upload_outlined),
        title: const Text('允许这一次云 AI 整理？'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Provider：${Uri.parse(settings.endpoint).host}'),
              Text('模型：${settings.model}'),
              Text('范围：仅此图片 OCR 的脱敏文本'),
              Text('人工标记：${_marks.length} 个 Token'),
              const SizedBox(height: 12),
              const Text(
                '不上传原图、Token Map、Vault 其他内容或密码库原文。'
                '不保存“始终允许”。',
              ),
              const SizedBox(height: 8),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: const Text('查看本次外发文本'),
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    color: Theme.of(context).colorScheme.surfaceContainer,
                    child: SelectableText(disclosure),
                  ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('拒绝'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('仅允许本次'),
          ),
        ],
      ),
    );
    if (allowed != true || !mounted) return;
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
    child: Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'AI Privacy · 人工标记',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 6),
              const Text(
                '未标记文本会在你单次授权后发给 Provider；'
                '标记行会先在本地替换为 Token。',
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            itemCount: widget.blob.ocrLines.length,
            itemBuilder: (context, index) {
              final line = widget.blob.ocrLines[index];
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(line.text),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<SensitiveFieldKind?>(
                        initialValue: _marks[line.order],
                        decoration: const InputDecoration(
                          labelText: '外发处理',
                          isDense: true,
                        ),
                        items: [
                          const DropdownMenuItem<SensitiveFieldKind?>(
                            child: Text('可发送（不替换）'),
                          ),
                          for (final kind in SensitiveFieldKind.values)
                            DropdownMenuItem<SensitiveFieldKind?>(
                              value: kind,
                              child: Text('替换为 ${_label(kind)} Token'),
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
              );
            },
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _working ? null : _save,
                    child: const Text('仅保存标记'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed:
                        _working || !widget.controller.aiSettings.isConfigured
                        ? null
                        : _organize,
                    icon: _working
                        ? const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.auto_awesome),
                    label: Text(
                      widget.controller.aiSettings.isConfigured
                          ? '授权 AI 整理'
                          : '请先配置 Provider',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );

  String _label(SensitiveFieldKind kind) => switch (kind) {
    SensitiveFieldKind.account => 'Account',
    SensitiveFieldKind.secret => 'Secret',
    SensitiveFieldKind.money => 'Money',
    SensitiveFieldKind.note => 'Note',
  };
}
