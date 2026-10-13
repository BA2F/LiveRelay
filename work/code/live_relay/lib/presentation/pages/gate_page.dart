import '../widgets/liverelay_logo.dart';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/app_controller.dart';
import '../../core/security/chinese_passphrase.dart';
import '../../core/security/vault_password_policy.dart';
import '../design_system/atoms.dart';
import '../dialogs/backup_dialogs.dart';
import '../dialogs/security_dialogs.dart';
import '../dialogs/transfer_dialogs.dart';
import 'recipient_page.dart';

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
                        child: const LiveRelayLogo(size: 38),
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
  bool _savedPassphrase = false;
  bool _enableBiometric = true;
  bool _obscure = true;
  int _wordCount = 6;
  ChinesePassphrase? _generated;
  String? _creationError;

  bool get _passwordValid =>
      VaultPasswordPolicy.creationError(_password.text) == null;
  bool get _confirmationMatches =>
      _confirmation.text.isNotEmpty && _confirmation.text == _password.text;
  bool get _canCreate =>
      _savedPassphrase &&
      (_useGenerator
          ? _generated != null
          : _passwordValid && _confirmationMatches);

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
      _confirmation.clear();
      _savedPassphrase = false;
      _creationError = null;
    });
  }

  Future<void> _submit(AppController controller) async {
    if (!_useGenerator && !_passwordValid) return;
    if (!_savedPassphrase) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('请先确认已妥善保存口令')));
      return;
    }
    if (!_useGenerator && _password.text != _confirmation.text) {
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
      setState(() => _creationError = null);
      if (controller.supportsModernSecurity) {
        final r = await confirmNewRecovery(context, controller);
        if (r == null || !mounted) return;
        await controller.setupModernVault(
          password: _password.text,
          recoveryText: r,
          recoveryConfirmation: r,
          chinese: _useGenerator,
          wordCount: _useGenerator ? _wordCount : null,
          biometric: _enableBiometric && controller.biometricAvailable,
        );
      } else {
        await controller.setupVault(
          password: _password.text,
          usesChinesePassphrase: _useGenerator,
          wordCount: _useGenerator ? _wordCount : null,
          enableBiometric: _enableBiometric && controller.biometricAvailable,
        );
      }
      if (mounted && controller.isUnlocked && Navigator.of(context).canPop()) {
        Navigator.pop(context);
      }
    } on Object {
      if (mounted) {
        setState(() => _creationError = controller.lastError ?? '资料库未创建，请重试');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    return _GateScaffold(
      title: '创建你的加密资料库',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            '记下资料位置、账号、资产或想交代的事。内容加密保存在本机，默认只有本人可见。请定期导出加密备份，设备丢失后可用口令恢复。',
          ),
          const RecipientEntryButton(),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: controller.isBusy
                ? null
                : () => restoreFromBackup(context, controller),
            icon: const Icon(Icons.settings_backup_restore),
            label: const Text('已有加密备份？从备份恢复'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: controller.isBusy
                ? null
                : () => importFromMediumFlow(context, controller),
            icon: const Icon(Icons.import_export),
            label: const Text('从介质导入（设备间搬运，整库替换）'),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final choice in [true, false])
                ChoiceChip(
                  label: Text(choice ? '中文词组（推荐）' : '自定密码'),
                  selected: _useGenerator == choice,
                  onSelected: controller.isBusy
                      ? null
                      : (_) => setState(() {
                          _useGenerator = choice;
                          _generated = null;
                          _password.clear();
                          _confirmation.clear();
                          _savedPassphrase = false;
                          _creationError = null;
                        }),
                ),
            ],
          ),
          const SizedBox(height: 18),
          if (_useGenerator) ...[
            const Text('默认使用 6 个随机词组。保存好口令，汉字或拼音均可解锁。'),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('高级：口令长度'),
              children: [
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
                                _password.clear();
                                _confirmation.clear();
                                _savedPassphrase = false;
                                _creationError = null;
                              }),
                      ),
                    ),
                    Text('$_wordCount 个'),
                  ],
                ),
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
                        '请离线妥善保存这组口令。',
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
            readOnly: _useGenerator,
            enabled: !controller.isBusy,
            onChanged: (_) => setState(() {
              _savedPassphrase = false;
              _creationError = null;
            }),
            decoration: InputDecoration(
              labelText: _useGenerator ? '中文词组口令' : '主密码',
              helperText: _useGenerator
                  ? (_generated == null ? '点击上方按钮生成口令' : '已生成，请妥善保存')
                  : '至少 ${VaultPasswordPolicy.minimumLength} 个字符，支持中文、字母、数字和符号',
              helperMaxLines: 3,
              errorMaxLines: 2,
              errorText: !_useGenerator && _password.text.isNotEmpty
                  ? VaultPasswordPolicy.creationError(_password.text)
                  : null,
              prefixIcon: const Icon(Icons.key),
              suffixIcon: IconButton(
                tooltip: _obscure ? '显示口令' : '遮挡口令',
                onPressed: () => setState(() => _obscure = !_obscure),
                icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
              ),
            ),
          ),
          if (!_useGenerator && _passwordValid)
            const _ValidationCheck('密码长度符合要求'),
          const SizedBox(height: 12),
          if (!_useGenerator)
            TextField(
              controller: _confirmation,
              obscureText: _obscure,
              enabled: !controller.isBusy,
              onChanged: (_) => setState(() => _creationError = null),
              decoration: InputDecoration(
                labelText: '再次输入主密码',
                prefixIcon: Icon(Icons.verified_user_outlined),
                helperText: '请再次输入相同的密码',
                helperMaxLines: 2,
                errorMaxLines: 2,
                errorText:
                    _confirmation.text.isNotEmpty && !_confirmationMatches
                    ? '两次输入的密码不一致'
                    : null,
              ),
            ),
          if (!_useGenerator && _confirmationMatches)
            const _ValidationCheck('两次输入一致'),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: _savedPassphrase,
            onChanged: controller.isBusy
                ? null
                : (value) => setState(() {
                    _savedPassphrase = value ?? false;
                    _creationError = null;
                  }),
            title: const Text('我已妥善保存口令'),
            subtitle: const Text('口令无法找回。换设备后需要口令才能解锁。'),
          ),
          if (controller.biometricAvailable) ...[
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _enableBiometric,
              onChanged: controller.isBusy
                  ? null
                  : (value) => setState(() => _enableBiometric = value),
              title: const Text('启用指纹解锁'),
              subtitle: const Text('换设备后仍需使用解锁口令'),
              secondary: const Icon(Icons.fingerprint),
            ),
          ],
          if (_creationError != null) ...[
            const SizedBox(height: 12),
            ErrorBanner(_creationError!),
          ],
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: controller.isBusy || !_canCreate
                ? null
                : () => _submit(controller),
            icon: controller.isBusy
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.lock_outline),
            label: const Padding(
              padding: EdgeInsets.symmetric(vertical: 14),
              child: Text('创建并进入资料库'),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '创建后即可记录，AI 为可选服务。',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _ValidationCheck extends StatelessWidget {
  const _ValidationCheck(this.message);
  final String message;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          Icons.check_circle_outline,
          size: 20,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(message, style: Theme.of(context).textTheme.bodySmall),
        ),
      ],
    ),
  );
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
      if (controller.header?.formatVersion == 3 &&
          controller.header?.dailyPolicy == 'all' &&
          controller.header?.keyFileEnabled == true) {
        await unlockWithKeyFile(context, controller, _password.text);
      } else {
        await controller.unlockWithPassword(_password.text);
      }
    } on Object {
      _password.clear();
    }
  }

  Future<void> _unlockBiometric(AppController controller) async {
    try {
      if (controller.header?.dailyPolicy == 'all') {
        await _unlock(controller);
      } else {
        await controller.unlockWithBiometric();
      }
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
      title: '解锁你的加密资料库',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const RecipientEntryButton(),
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
                tooltip: _obscure ? '显示口令' : '遮挡口令',
                onPressed: () => setState(() => _obscure = !_obscure),
                icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
              ),
            ),
          ),
          if (controller.recoveryNotice != null) ...[
            const SizedBox(height: 12),
            Text(controller.recoveryNotice!),
          ],
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
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: controller.isBusy
                ? null
                : () => restoreFromBackup(context, controller),
            icon: const Icon(Icons.settings_backup_restore),
            label: const Text('从加密备份恢复'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: controller.isBusy
                ? null
                : () => importFromMediumFlow(context, controller),
            icon: const Icon(Icons.import_export),
            label: const Text('从介质导入（设备间搬运，整库替换）'),
          ),
          if (controller.header?.keyFileEnabled == true)
            OutlinedButton.icon(
              onPressed: controller.isBusy
                  ? null
                  : () =>
                        unlockWithKeyFile(context, controller, _password.text),
              icon: const Icon(Icons.description_outlined),
              label: const Text('使用密钥文件解锁'),
            ),
          if (controller.header?.recoveryEnabled == true)
            TextButton(
              onPressed: controller.isBusy
                  ? null
                  : () => beginIndependentRecovery(context, controller),
              child: const Text('忘记密码？使用独立恢复凭证'),
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
