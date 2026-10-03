import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class CredentialSecretActions extends StatefulWidget {
  const CredentialSecretActions({super.key, required this.secret});
  final String secret;
  @override
  State<CredentialSecretActions> createState() =>
      _CredentialSecretActionsState();
}

class _CredentialSecretActionsState extends State<CredentialSecretActions> {
  bool _visible = false;
  Timer? _timer;
  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _toggle() {
    _timer?.cancel();
    setState(() => _visible = !_visible);
    if (_visible) {
      _timer = Timer(const Duration(seconds: 30), () {
        if (mounted) setState(() => _visible = false);
      });
    }
  }

  Future<void> _copy() async {
    final secret = widget.secret;
    await Clipboard.setData(ClipboardData(text: secret));
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('已复制；30 秒后尝试清空剪贴板')));
    }
    unawaited(
      Future<void>.delayed(const Duration(seconds: 30), () async {
        try {
          final current = await Clipboard.getData(Clipboard.kTextPlain);
          if (current?.text == secret) {
            await Clipboard.setData(const ClipboardData(text: ''));
          }
        } on Object {
          /* Some systems restrict reading the clipboard. */
        }
      }),
    );
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (_visible)
        SelectableText(widget.secret)
      else
        const Text('••••••••', semanticsLabel: '密码已遮盖'),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          OutlinedButton.icon(
            onPressed: _toggle,
            icon: Icon(_visible ? Icons.visibility_off : Icons.visibility),
            label: Text(_visible ? '隐藏密码' : '显示密码 30 秒'),
          ),
          FilledButton.tonalIcon(
            onPressed: _copy,
            icon: const Icon(Icons.copy),
            label: const Text('复制密码'),
          ),
        ],
      ),
    ],
  );
}
