import 'dart:async';

import 'package:flutter/material.dart';

import '../../application/release_preview.dart';
import '../model_labels.dart';

class ReleasePreviewPanel extends StatefulWidget {
  const ReleasePreviewPanel({super.key, required this.preview});
  final ReleasePreview preview;
  @override
  State<ReleasePreviewPanel> createState() => _ReleasePreviewPanelState();
}

class _ReleasePreviewPanelState extends State<ReleasePreviewPanel> {
  bool _revealed = false;
  Timer? _timer;
  @override
  void didUpdateWidget(ReleasePreviewPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    _revealed = false;
    _timer?.cancel();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _toggle() {
    _timer?.cancel();
    setState(() => _revealed = !_revealed);
    if (_revealed) {
      _timer = Timer(const Duration(seconds: 30), () {
        if (mounted) setState(() => _revealed = false);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final preview = widget.preview;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '可见范围：${preview.level.label}',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 8),
            Text(preview.explanation),
            if (preview.title != null) ...[
              const Divider(),
              Text(
                preview.title!,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              SelectableText(preview.body),
            ],
            if (preview.secret != null) ...[
              const SizedBox(height: 8),
              Semantics(
                label: _revealed ? '密码已显示' : '密码已遮挡',
                child: Text(_revealed ? preview.secret! : '••••••••••••'),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _toggle,
                  icon: Icon(
                    _revealed ? Icons.visibility_off : Icons.visibility,
                  ),
                  label: Text(_revealed ? '立即遮挡密码' : '显示密码 30 秒'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
