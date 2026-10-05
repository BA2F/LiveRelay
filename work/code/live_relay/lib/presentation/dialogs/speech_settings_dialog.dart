import 'package:flutter/material.dart';

import '../../application/speech_service.dart';

class SpeechSettingsDialog extends StatefulWidget {
  const SpeechSettingsDialog({super.key, required this.service});
  final SpeechService service;
  @override
  State<SpeechSettingsDialog> createState() => _SpeechSettingsDialogState();
}

class _SpeechSettingsDialogState extends State<SpeechSettingsDialog> {
  late final _name = TextEditingController(
    text: widget.service.remoteSettings.name,
  );
  late final _endpoint = TextEditingController(
    text: widget.service.remoteSettings.endpoint.isEmpty
        ? 'https://api.openai.com/v1/audio/transcriptions'
        : widget.service.remoteSettings.endpoint,
  );
  late final _model = TextEditingController(
    text: widget.service.remoteSettings.model,
  );
  final _key = TextEditingController();
  bool _busy = false;
  String? _error;
  @override
  void dispose() {
    _name.dispose();
    _endpoint.dispose();
    _model.dispose();
    _key.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('远程语音服务设置'),
    content: SizedBox(
      width: 480,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '语音与对话服务独立。使用音频转写 multipart 协议，返回 JSON text；配置后每次音频上传仍需确认。',
            ),
            TextField(
              controller: _name,
              enabled: !_busy,
              decoration: const InputDecoration(labelText: '语音服务名称'),
            ),
            TextField(
              controller: _endpoint,
              enabled: !_busy,
              decoration: const InputDecoration(labelText: 'HTTPS 音频转写地址'),
            ),
            TextField(
              controller: _model,
              enabled: !_busy,
              decoration: const InputDecoration(labelText: '语音识别模型'),
            ),
            TextField(
              controller: _key,
              enabled: !_busy,
              obscureText: true,
              decoration: InputDecoration(
                labelText: widget.service.remoteSettings.hasApiKey
                    ? '语音密钥（留空保留）'
                    : '语音密钥',
              ),
            ),
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      ),
    ),
    actions: [
      if (widget.service.remoteSettings.configured)
        TextButton(
          onPressed: _busy
              ? null
              : () async {
                  await widget.service.clearRemote();
                  if (context.mounted) Navigator.pop(context);
                },
          child: const Text('清除远程语音配置'),
        ),
      TextButton(
        onPressed: _busy ? null : () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: _busy
            ? null
            : () async {
                setState(() {
                  _busy = true;
                  _error = null;
                });
                try {
                  await widget.service.configureRemote(
                    name: _name.text,
                    endpoint: _endpoint.text,
                    model: _model.text,
                    apiKey: _key.text.isEmpty ? null : _key.text,
                  );
                  if (context.mounted) Navigator.pop(context);
                } on Object {
                  if (mounted) {
                    setState(() => _error = widget.service.error ?? '保存失败');
                  }
                } finally {
                  _key.clear();
                  if (mounted) setState(() => _busy = false);
                }
              },
        child: const Text('安全保存'),
      ),
    ],
  );
}
