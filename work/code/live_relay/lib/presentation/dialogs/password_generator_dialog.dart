import 'package:flutter/material.dart';

import '../../core/security/password_generator.dart';
import '../widgets/credential_secret_actions.dart';

Future<String?> showPasswordGenerator(BuildContext context) =>
    showDialog<String>(
      context: context,
      builder: (_) => const _GeneratorDialog(),
    );

class _GeneratorDialog extends StatefulWidget {
  const _GeneratorDialog();
  @override
  State<_GeneratorDialog> createState() => _GeneratorDialogState();
}

class _GeneratorDialogState extends State<_GeneratorDialog> {
  int _length = 20;
  final _selected = [true, true, true, true];
  String _password = PasswordGenerator.generate();
  String? _error;
  void _generate() {
    setState(() {
      try {
        _password = PasswordGenerator.generate(
          length: _length,
          uppercase: _selected[0],
          lowercase: _selected[1],
          digits: _selected[2],
          symbols: _selected[3],
        );
        _error = null;
      } on FormatException catch (e) {
        _error = e.message;
      }
    });
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('生成随机密码'),
    content: SizedBox(
      width: 420,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('长度：$_length'),
            Slider(
              value: _length.toDouble(),
              min: 8,
              max: 64,
              divisions: 56,
              onChanged: (v) {
                _length = v.round();
                _generate();
              },
            ),
            for (var i = 0; i < 4; i++)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(['大写字母', '小写字母', '数字', '符号'][i]),
                value: _selected[i],
                onChanged: (v) {
                  _selected[i] = v ?? false;
                  _generate();
                },
              ),
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            CredentialSecretActions(
              key: ValueKey(_password),
              secret: _password,
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      TextButton(onPressed: _generate, child: const Text('重新生成')),
      FilledButton(
        onPressed: _error == null
            ? () => Navigator.pop(context, _password)
            : null,
        child: const Text('使用此密码'),
      ),
    ],
  );
}
