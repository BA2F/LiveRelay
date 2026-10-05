import 'package:flutter/material.dart';

import '../../application/app_controller.dart';
import '../../core/ports/ai_provider.dart';

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
  late AiProtocol _protocol = widget.controller.aiSettings.protocol;
  late bool _images = widget.controller.aiSettings.supportsImages;
  late bool _files = widget.controller.aiSettings.supportsFiles;
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
        protocol: _protocol,
        supportsImages: _images,
        supportsFiles: _files,
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
          DropdownButtonFormField<AiProtocol>(
            initialValue: _protocol,
            decoration: const InputDecoration(labelText: '服务协议'),
            items: const [
              DropdownMenuItem(
                value: AiProtocol.chatCompletions,
                child: Text('Chat Completions 整理'),
              ),
              DropdownMenuItem(
                value: AiProtocol.responses,
                child: Text('Responses Agent'),
              ),
            ],
            onChanged: _busy
                ? null
                : (value) {
                    if (value == null) return;
                    setState(() {
                      _protocol = value;
                      final uri = Uri.tryParse(_endpoint.text);
                      if (uri != null &&
                          (uri.path.endsWith('/chat/completions') ||
                              uri.path.endsWith('/responses'))) {
                        final prefix = uri.path.endsWith('/responses')
                            ? uri.path.substring(0, uri.path.length - 10)
                            : uri.path.substring(0, uri.path.length - 17);
                        _endpoint.text = uri
                            .replace(
                              path:
                                  '$prefix/${value == AiProtocol.responses ? 'responses' : 'chat/completions'}',
                            )
                            .toString();
                      }
                    });
                  },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _endpoint,
            enabled: !_busy,
            keyboardType: TextInputType.url,
            decoration: InputDecoration(
              labelText: _protocol == AiProtocol.responses
                  ? 'HTTPS 服务地址（Responses）'
                  : 'HTTPS 服务地址（Chat Completions）',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _model,
            enabled: !_busy,
            decoration: const InputDecoration(labelText: '模型名称'),
          ),
          const SizedBox(height: 12),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('此模型支持图片输入'),
            value: _images,
            onChanged: _busy
                ? null
                : (v) => setState(() => _images = v ?? false),
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('此 Responses 模型支持 PDF 输入'),
            value: _files,
            onChanged: _busy
                ? null
                : (v) => setState(() => _files = v ?? false),
          ),
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
