import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../application/app_controller.dart';
import '../../core/security/chinese_passphrase.dart';
import '../design_system/atoms.dart';

class _GateScaffold extends StatelessWidget {
  const _GateScaffold({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: scheme.primaryContainer,
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(18),
                        child: Icon(
                          Icons.lightbulb_rounded,
                          size: 38,
                          color: scheme.onPrimaryContainer,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text('留灯', style: Theme.of(context).textTheme.displaySmall),
                  Text(
                    'LiveRelay · 把重要信息留在你能掌控的地方',
                    style: Theme.of(context).textTheme.bodyLarge
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 32),
                  Text(title, style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 20),
                  child,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class SetupVaultPage extends StatefulWidget {
  const SetupVaultPage({super.key});

  @override
  State<SetupVaultPage> createState() => _SetupVaultPageState();
}

class _SetupVaultPageState extends State<SetupVaultPage> {
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  bool _useGenerator = true;
  bool _enableBiometric = true;
  bool _obscure = true;
  int _wordCount = 6;
  ChinesePassphrase? _generated;

  @override
  void dispose() {
    _password.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  void _generate(AppController controller) {
    final phrase = controller.generatePassphrase(count: _wordCount);
    setState(() {
      _generated = phrase;
      _password.text = phrase.chinese;
      _confirmation.text = phrase.chinese;
    });
  }

  Future<void> _submit(AppController controller) async {
    if (_password.text != _confirmation.text) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('两次输入的主密码不一致')));
      return;
    }
    if (_useGenerator && _generated == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('请先生成中文词组口令')));
      return;
    }
    try {
      await controller.setupVault(
        password: _password.text,
        usesChinesePassphrase: _useGenerator,
        wordCount: _useGenerator ? _wordCount : null,
        enableBiometric: _enableBiometric && controller.biometricAvailable,
      );
    } on Object {
      // The controller exposes a safe user-facing error below.
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    return _GateScaffold(
      title: '创建你的加密 Vault',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(
                value: true,
                icon: Icon(Icons.casino_outlined),
                label: Text('中文词组'),
              ),
              ButtonSegment(
                value: false,
                icon: Icon(Icons.password),
                label: Text('自定密码'),
              ),
            ],
            selected: {_useGenerator},
            onSelectionChanged: controller.isBusy
                ? null
                : (selection) => setState(() {
                    _useGenerator = selection.first;
                    _generated = null;
                    _password.clear();
                    _confirmation.clear();
                  }),
          ),
          const SizedBox(height: 18),
          if (_useGenerator) ...[
            Row(
              children: [
                const Text('词数'),
                Expanded(
                  child: Slider(
                    value: _wordCount.toDouble(),
                    min: 4,
                    max: 10,
                    divisions: 6,
                    label: '$_wordCount',
                    onChanged: controller.isBusy
                        ? null
                        : (value) => setState(() {
                            _wordCount = value.round();
                            _generated = null;
                          }),
                  ),
                ),
                Text('$_wordCount 个'),
              ],
            ),
            OutlinedButton.icon(
              onPressed: controller.isBusy ? null : () => _generate(controller),
              icon: const Icon(Icons.auto_awesome),
              label: const Text('安全生成一组口令'),
            ),
            if (_generated != null) ...[
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SelectableText(
                        _generated!.chinese,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      SelectableText(_generated!.pinyin),
                      const SizedBox(height: 8),
                      Text(
                        '约 ${_generated!.entropyBits.toStringAsFixed(1)} bit；汉字或拼音均可解锁。请离线保存。',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 16),
          ],
          TextField(
            controller: _password,
            obscureText: _obscure,
            enabled: !controller.isBusy,
            decoration: InputDecoration(
              labelText: _useGenerator ? '中文词组口令' : '主密码',
              prefixIcon: const Icon(Icons.key),
              suffixIcon: IconButton(
                onPressed: () => setState(() => _obscure = !_obscure),
                icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _confirmation,
            obscureText: _obscure,
            enabled: !controller.isBusy,
            decoration: const InputDecoration(
              labelText: '再次输入',
              prefixIcon: Icon(Icons.verified_user_outlined),
            ),
          ),
          if (controller.biometricAvailable) ...[
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _enableBiometric,
              onChanged: controller.isBusy
                  ? null
                  : (value) => setState(() => _enableBiometric = value),
              title: const Text('启用 Android 强生物识别'),
              subtitle: const Text('主密码仍是恢复 Vault 的必要入口'),
              secondary: const Icon(Icons.fingerprint),
            ),
          ],
          if (controller.lastError != null) ...[
            const SizedBox(height: 12),
            ErrorBanner(controller.lastError!),
          ],
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: controller.isBusy ? null : () => _submit(controller),
            icon: controller.isBusy
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.lock_outline),
            label: const Padding(
              padding: EdgeInsets.symmetric(vertical: 14),
              child: Text('创建并进入 Vault'),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '结构化数据将存入整页加密的 SQLCipher 数据库。主密码只用于解封随机主密钥。',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class UnlockVaultPage extends StatefulWidget {
  const UnlockVaultPage({super.key});

  @override
  State<UnlockVaultPage> createState() => _UnlockVaultPageState();
}

class _UnlockVaultPageState extends State<UnlockVaultPage> {
  final _password = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _unlock(AppController controller) async {
    try {
      await controller.unlockWithPassword(_password.text);
    } on Object {
      _password.clear();
    }
  }

  Future<void> _unlockBiometric(AppController controller) async {
    try {
      await controller.unlockWithBiometric();
    } on Object {
      // Error is shown by the controller.
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    final canUseBiometric =
        controller.biometricAvailable &&
        (controller.header?.biometricEnabled ?? false);
    return _GateScaffold(
      title: '解锁你的 Vault',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _password,
            obscureText: _obscure,
            enabled: !controller.isBusy,
            autofocus: true,
            onSubmitted: (_) => _unlock(controller),
            decoration: InputDecoration(
              labelText: controller.header?.usesChinesePassphrase ?? false
                  ? '中文词组或拼音'
                  : '主密码',
              prefixIcon: const Icon(Icons.key),
              suffixIcon: IconButton(
                onPressed: () => setState(() => _obscure = !_obscure),
                icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
              ),
            ),
          ),
          if (controller.lastError != null) ...[
            const SizedBox(height: 12),
            ErrorBanner(controller.lastError!),
          ],
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: controller.isBusy ? null : () => _unlock(controller),
            icon: controller.isBusy
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.lock_open),
            label: const Padding(
              padding: EdgeInsets.symmetric(vertical: 14),
              child: Text('解锁'),
            ),
          ),
          if (canUseBiometric) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: controller.isBusy
                  ? null
                  : () => _unlockBiometric(controller),
              icon: const Icon(Icons.fingerprint),
              label: const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('使用指纹解锁'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
