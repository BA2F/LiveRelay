import '../widgets/liverelay_logo.dart';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/app_controller.dart';
import '../../core/security/chinese_passphrase.dart';
import '../../core/security/vault_password_policy.dart';
import '../../l10n/app_localizations.dart';
import '../design_system/atoms.dart';
import '../dialogs/backup_dialogs.dart';
import '../dialogs/security_dialogs.dart';
import '../dialogs/transfer_dialogs.dart';
import 'handoff_view_page.dart';

class _GateScaffold extends StatelessWidget {
  const _GateScaffold({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);
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
                  if (Navigator.of(context).canPop())
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.arrow_back),
                        label: Text(l10n.back),
                      ),
                    ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: scheme.primaryContainer,
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: const Padding(
                        padding: EdgeInsets.all(18),
                        child: LiveRelayLogo(size: 38),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    l10n.brandName,
                    style: Theme.of(context).textTheme.displaySmall,
                  ),
                  Text(
                    l10n.gateTagline,
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
  bool _useGenerator = false;
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
    final l10n = AppLocalizations.of(context);
    if (!_useGenerator && !_passwordValid) return;
    if (!_savedPassphrase) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l10n.setupSaveFirst)));
      return;
    }
    if (!_useGenerator && _password.text != _confirmation.text) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l10n.setupMismatch)));
      return;
    }
    if (_useGenerator && _generated == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l10n.setupGenerateFirst)));
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
        setState(
          () => _creationError =
              controller.lastError ??
              AppLocalizations.of(context).setupCreateFailed,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    final l10n = AppLocalizations.of(context);
    return _GateScaffold(
      title: l10n.setupTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.setupIntro),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: controller.isBusy
                ? null
                : () => restoreFromBackup(context, controller),
            icon: const Icon(Icons.settings_backup_restore),
            label: Text(l10n.setupRestore),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: controller.isBusy
                ? null
                : () => importFromMediumFlow(context, controller),
            icon: const Icon(Icons.import_export),
            label: Text(l10n.setupImportMedium),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final choice in [false, true])
                ChoiceChip(
                  label: Text(
                    choice ? l10n.setupChipPhrase : l10n.setupChipCustom,
                  ),
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
            Text(l10n.setupPhraseHint),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: Text(l10n.setupAdvancedLength),
              children: [
                Row(
                  children: [
                    Text(l10n.setupWordCountLabel),
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
                    Text(l10n.setupWordCountValue(_wordCount)),
                  ],
                ),
              ],
            ),
            OutlinedButton.icon(
              onPressed: controller.isBusy ? null : () => _generate(controller),
              icon: const Icon(Icons.auto_awesome),
              label: Text(l10n.setupGenerate),
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
              labelText: _useGenerator
                  ? l10n.setupPhraseLabel
                  : l10n.setupPasswordLabel,
              helperText: _useGenerator
                  ? (_generated == null
                        ? l10n.setupPhraseHelperEmpty
                        : l10n.setupPhraseHelperGenerated)
                  : l10n.setupPasswordHelper(VaultPasswordPolicy.minimumLength),
              helperMaxLines: 3,
              errorMaxLines: 2,
              errorText: !_useGenerator && _password.text.isNotEmpty
                  ? VaultPasswordPolicy.creationError(_password.text)
                  : null,
              prefixIcon: const Icon(Icons.key),
              suffixIcon: IconButton(
                tooltip: _obscure ? l10n.setupShow : l10n.setupHide,
                onPressed: () => setState(() => _obscure = !_obscure),
                icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
              ),
            ),
          ),
          if (!_useGenerator && _passwordValid)
            _ValidationCheck(l10n.setupLengthOk),
          const SizedBox(height: 12),
          if (!_useGenerator)
            TextField(
              controller: _confirmation,
              obscureText: _obscure,
              enabled: !controller.isBusy,
              onChanged: (_) => setState(() => _creationError = null),
              decoration: InputDecoration(
                labelText: l10n.setupConfirmLabel,
                prefixIcon: const Icon(Icons.verified_user_outlined),
                errorMaxLines: 2,
                errorText:
                    _confirmation.text.isNotEmpty && !_confirmationMatches
                    ? l10n.setupMismatch
                    : null,
              ),
            ),
          if (!_useGenerator && _confirmationMatches)
            _ValidationCheck(l10n.setupConfirmOk),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: _savedPassphrase,
            onChanged: controller.isBusy
                ? null
                : (value) => setState(() {
                    _savedPassphrase = value ?? false;
                    _creationError = null;
                  }),
            title: Text(l10n.setupSavedCheck),
            subtitle: Text(l10n.setupSavedSubtitle),
          ),
          if (controller.biometricAvailable) ...[
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _enableBiometric,
              onChanged: controller.isBusy
                  ? null
                  : (value) => setState(() => _enableBiometric = value),
              title: Text(l10n.setupBiometric),
              subtitle: Text(l10n.setupBiometricSubtitle),
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
            label: Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Text(l10n.setupSubmit),
            ),
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

  Future<void> _showMoreUnlockOptions(AppController controller) async {
    final l10n = AppLocalizations.of(context);
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(
              l10n.captureMore,
              style: Theme.of(sheetContext).textTheme.titleLarge,
            ),
          ),
          ListTile(
            leading: const Icon(Icons.settings_backup_restore),
            title: Text(l10n.unlockRestore),
            onTap: () {
              Navigator.pop(sheetContext);
              restoreFromBackup(context, controller);
            },
          ),
          ListTile(
            leading: const Icon(Icons.import_export),
            title: Text(l10n.setupImportMedium),
            onTap: () {
              Navigator.pop(sheetContext);
              importFromMediumFlow(context, controller);
            },
          ),
          if (controller.header?.keyFileEnabled == true)
            ListTile(
              leading: const Icon(Icons.description_outlined),
              title: Text(l10n.unlockKeyFile),
              onTap: () {
                Navigator.pop(sheetContext);
                unlockWithKeyFile(context, controller, _password.text);
              },
            ),
          if (controller.header?.recoveryEnabled == true)
            ListTile(
              leading: const Icon(Icons.health_and_safety_outlined),
              title: Text(l10n.unlockRecovery),
              onTap: () {
                Navigator.pop(sheetContext);
                beginIndependentRecovery(context, controller);
              },
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    final l10n = AppLocalizations.of(context);
    final canUseBiometric =
        controller.biometricAvailable &&
        (controller.header?.biometricEnabled ?? false);
    return _GateScaffold(
      title: l10n.unlockTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const PickupEntryButton(),
          TextField(
            controller: _password,
            obscureText: _obscure,
            enabled: !controller.isBusy,
            autofocus: true,
            onSubmitted: (_) => _unlock(controller),
            decoration: InputDecoration(
              labelText: controller.header?.usesChinesePassphrase ?? false
                  ? l10n.unlockFieldPhrase
                  : l10n.setupPasswordLabel,
              prefixIcon: const Icon(Icons.key),
              suffixIcon: IconButton(
                tooltip: _obscure ? l10n.setupShow : l10n.setupHide,
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
            label: Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Text(l10n.unlockButton),
            ),
          ),
          const SizedBox(height: 12),
          if (canUseBiometric) ...[
            OutlinedButton.icon(
              onPressed: controller.isBusy
                  ? null
                  : () => _unlockBiometric(controller),
              icon: const Icon(Icons.fingerprint),
              label: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(l10n.unlockBiometric),
              ),
            ),
            const SizedBox(height: 8),
          ],
          TextButton.icon(
            onPressed: controller.isBusy
                ? null
                : () => _showMoreUnlockOptions(controller),
            icon: const Icon(Icons.more_horiz),
            label: Text(l10n.captureMore),
          ),
        ],
      ),
    );
  }
}
