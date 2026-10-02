import 'package:flutter/material.dart';

import '../../application/app_controller.dart';

class AiSettingsDialog extends StatefulWidget {
  const AiSettingsDialog({super.key, required this.controller});

  final AppController controller;

  @override
  State<AiSettingsDialog> createState() => AiSettingsDialogState();
}

class AiSettingsDialogState extends State<AiSettingsDialog> {
  late final _endpoint = TextEditingController(
    text: widget.controller.aiSettings.endpoint.isEmpty
        ? 'https://api.openai.com/v1/chat/completions'
        : widget.controller.aiSettings.endpoint,
  );
  late final _model = TextEditingController(
    text: widget.controller.aiSettings.model,
  );
  final _apiKey = TextEditingController();
  bool _busy = false;
  bool _showKey = false;
  String? _error;

  @override
  void dispose() {
    _endpoint.dispose();
    _model.dispose();
    _apiKey.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.controller.saveAiSettings(
        endpoint: _endpoint.text,
        model: _model.text,
        apiKey: _apiKey.text.isEmpty ? null : _apiKey.text,
      );
      if (mounted) Navigator.pop(context);
    } on Object {
      if (mounted) {
        setState(() => _error = widget.controller.lastError ?? '保存失败');
      }
    } finally {
      _apiKey.clear();
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    icon: const Icon(Icons.auto_awesome_outlined),
    title: const Text('AI 服务设置'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('默认关闭。配置不代表授权；每次外发前仍会展示范围并要求单次确认。'),
          const SizedBox(height: 16),
          TextField(
            controller: _endpoint,
            enabled: !_busy,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              labelText: 'HTTPS 服务地址（Chat Completions）',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _model,
            enabled: !_busy,
            decoration: const InputDecoration(labelText: '模型名称'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _apiKey,
            enabled: !_busy,
            obscureText: !_showKey,
            decoration: InputDecoration(
              labelText: widget.controller.aiSettings.hasApiKey
                  ? '服务密钥（留空则保留原值）'
                  : '服务密钥',
              suffixIcon: IconButton(
                tooltip: _showKey ? '遮挡服务密钥' : '显示服务密钥',
                onPressed: () => setState(() => _showKey = !_showKey),
                icon: Icon(_showKey ? Icons.visibility_off : Icons.visibility),
              ),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
    ),
    actions: [
      if (widget.controller.aiSettings.isConfigured)
        TextButton(
          onPressed: _busy
              ? null
              : () async {
                  await widget.controller.clearAiSettings();
                  if (context.mounted) Navigator.pop(context);
                },
          child: const Text('清除配置'),
        ),
      TextButton(
        onPressed: _busy ? null : () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(onPressed: _busy ? null : _save, child: const Text('安全保存')),
    ],
  );
}
