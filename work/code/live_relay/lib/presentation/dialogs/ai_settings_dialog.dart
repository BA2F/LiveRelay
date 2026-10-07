import 'package:flutter/material.dart';

import '../../application/app_controller.dart';
import '../../core/ports/ai_provider.dart';
import '../../core/ai/ai_service_endpoint.dart';
import '../../infrastructure/ai/ai_provider_settings_store.dart';

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
  late final _name = TextEditingController(
    text: widget.controller.aiSettings.name,
  );
  late final _models = TextEditingController(
    text: widget.controller.aiSettings.models.join("\n"),
  );
  String? _profileId;
  bool _create = false;
  late AiProtocol _protocol = widget.controller.aiSettings.protocol;
  late bool _images = widget.controller.aiSettings.supportsImages;
  late bool _audio = widget.controller.aiSettings.supportsAudio;
  late bool _files = widget.controller.aiSettings.supportsFiles;
  bool _busy = false;
  bool _showKey = false;
  String? _error;
  bool get _deepSeekFlash =>
      Uri.tryParse(_endpoint.text.trim())?.host == 'api.deepseek.com' &&
      {
        'deepseek-flash',
        'deepseek-v4-flash-vision-exp',
      }.contains(_model.text.trim());

  String get _effectiveAddress {
    final uri = Uri.tryParse(_endpoint.text.trim());
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
      return '可填 HTTPS 基础地址或完整接口地址';
    }
    final effective = resolveAiEndpoint(uri, _protocol);
    final display = Uri(
      scheme: effective.scheme,
      host: effective.host,
      port: effective.hasPort ? effective.port : null,
      path: effective.path,
    );
    return '实际请求：$display';
  }

  @override
  void initState() {
    super.initState();
    _profileId = widget.controller.aiSettings.id;
  }

  void _edit(AiProviderSettings? settings) {
    setState(() {
      _create = settings == null;
      _profileId = settings?.id;
      _name.text = settings?.name ?? '';
      _endpoint.text =
          settings?.endpoint ?? 'https://api.openai.com/v1/chat/completions';
      _model.text = settings?.model ?? '';
      _models.text = settings?.models.join('\n') ?? '';
      _protocol = settings?.protocol ?? AiProtocol.chatCompletions;
      _images = settings?.supportsImages ?? false;
      _files = settings?.supportsFiles ?? false;
      _audio = settings?.supportsAudio ?? false;
      _apiKey.clear();
      _error = null;
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _models.dispose();
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
        profileId: _profileId,
        create: _create,
        name: _name.text,
        models: _models.text.split(RegExp(r"[,，\n]")),
        endpoint: _endpoint.text,
        protocol: _protocol,
        supportsImages: _images,
        supportsFiles: _files,
        supportsAudio: _audio,
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
          if (widget.controller.aiProfiles.isNotEmpty)
            DropdownButtonFormField<String>(
              key: ValueKey(_profileId),
              initialValue: _create ? null : _profileId,
              decoration: const InputDecoration(labelText: '编辑服务配置'),
              items: [
                for (final p in widget.controller.aiProfiles)
                  DropdownMenuItem(value: p.id, child: Text(p.name)),
              ],
              onChanged: _busy
                  ? null
                  : (id) => _edit(
                      widget.controller.aiProfiles.firstWhere(
                        (p) => p.id == id,
                      ),
                    ),
            ),
          TextButton.icon(
            onPressed: _busy ? null : () => _edit(null),
            icon: const Icon(Icons.add),
            label: const Text('添加另一个服务'),
          ),
          TextField(
            controller: _name,
            enabled: !_busy,
            decoration: const InputDecoration(labelText: '服务名称'),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<AiProtocol>(
            key: ValueKey("protocol-$_profileId-$_protocol"),
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
                      if (uri != null) {
                        _endpoint.text = resolveAiEndpoint(
                          uri,
                          value,
                        ).toString();
                      }
                    });
                  },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _endpoint,
            enabled: !_busy,
            keyboardType: TextInputType.url,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: _protocol == AiProtocol.responses
                  ? 'HTTPS 服务地址（Responses）'
                  : 'HTTPS 服务地址（Chat Completions）',
              helperText: _effectiveAddress,
              helperMaxLines: 3,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _model,
            enabled: !_busy,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(labelText: '模型名称'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _models,
            enabled: !_busy,
            minLines: 1,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: '可选模型（每行一个）',
              helperText: '输入此服务支持的模型；能力声明适用于这里列出的模型。',
            ),
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('此模型支持图片输入'),
            subtitle: _deepSeekFlash
                ? const Text('DeepSeek Flash 支持图片和已核对的视频采样帧；请启用此项。')
                : null,
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
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('此Chat模型支持WAV/MP3音频输入'),
            value: _audio,
            onChanged: _busy
                ? null
                : (v) => setState(() => _audio = v ?? false),
          ),
          TextField(
            controller: _apiKey,
            enabled: !_busy,
            obscureText: !_showKey,
            decoration: InputDecoration(
              labelText:
                  (!_create &&
                      widget.controller.aiProfiles.any(
                        (p) => p.id == _profileId && p.hasApiKey,
                      ))
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
      if (!_create &&
          widget.controller.aiProfiles.any((p) => p.id == _profileId))
        TextButton(
          onPressed: _busy
              ? null
              : () async {
                  await widget.controller.removeAiProfile(_profileId!);
                  if (context.mounted) Navigator.pop(context);
                },
          child: const Text('移除此服务'),
        ),
      TextButton(
        onPressed: _busy ? null : () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(onPressed: _busy ? null : _save, child: const Text('安全保存')),
    ],
  );
}
