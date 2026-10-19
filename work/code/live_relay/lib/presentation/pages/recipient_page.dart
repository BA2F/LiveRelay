import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/app_controller.dart';
import '../../application/recipient_service.dart';
import '../../core/identity/local_identity.dart';
import '../../l10n/app_localizations.dart';
import '../dialogs/local_file_dialogs.dart';
import '../widgets/read_only_snapshot.dart';

Future<void> openRecipientEntry(BuildContext context) async {
  final controller = context.read<AppController>();
  if (controller.recipient == null) return;
  if (controller.isUnlocked) await controller.lock();
  if (context.mounted) {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => RecipientPage(service: controller.recipient!),
      ),
    );
  }
}

class RecipientEntryButton extends StatelessWidget {
  const RecipientEntryButton({super.key});
  @override
  Widget build(BuildContext context) =>
      context.watch<AppController>().recipient == null
      ? const SizedBox.shrink()
      : TextButton.icon(
          onPressed: () => openRecipientEntry(context),
          icon: const Icon(Icons.mark_email_read_outlined),
          label: Text(AppLocalizations.of(context).recipientEntry),
        );
}

class RecipientPage extends StatefulWidget {
  const RecipientPage({super.key, required this.service});
  final RecipientService service;
  @override
  State<RecipientPage> createState() => _RecipientPageState();
}

class _RecipientPageState extends State<RecipientPage> {
  final name = TextEditingController(),
      password = TextEditingController(),
      confirmation = TextEditingController();
  bool busy = true;
  String? error, fingerprint;
  @override
  void initState() {
    super.initState();
    widget.service.addListener(changed);
    initialize();
  }

  void changed() {
    if (mounted) setState(() {});
  }

  Future<void> initialize() async {
    await run(() async {
      await widget.service.initialize();
    });
  }

  Future<void> run(Future<void> Function() action) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await action();
      if (widget.service.identity != null) {
        fingerprint = await widget.service.identity!.fingerprint();
      }
    } on Object catch (e) {
      if (mounted) {
        setState(() => error = e is FormatException ? e.message : '$e');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    widget.service.removeListener(changed);
    widget.service.lock();
    name.dispose();
    password.clear();
    confirmation.clear();
    password.dispose();
    confirmation.dispose();
    super.dispose();
  }

  Future<void> importPackage({
    bool saved = false,
    Uint8List? savedBytes,
  }) async {
    final service = widget.service;
    Uint8List? bytes = savedBytes;
    try {
      if (bytes == null) {
        final file = await FilePicker.pickFile(dialogTitle: '选择限定范围交接包');
        if (file == null) return;
        bytes = await file.readAsBytes();
      }
      final envelope = await service.inspectEnvelope(bytes);
      final owner = LocalIdentity.validatePublic(envelope['owner']);
      final fp = await LocalIdentity.fingerprintOf(owner);
      if (!mounted) return;
      final confirmed = saved
          ? fp
          : await askFingerprint(context, fp, LocalIdentity.displayName(owner));
      if (confirmed != null) {
        await service.receive(bytes, confirmed, saved: saved);
      }
    } finally {
      bytes?.fillRange(0, bytes.length, 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final service = widget.service, identity = service.identity;
    return PopScope(
      canPop: !busy,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('接收者 · 独立只读资料库'),
          actions: [
            if (identity != null)
              TextButton(
                onPressed: busy
                    ? null
                    : () {
                        service.lock();
                        password.clear();
                        confirmation.clear();
                        fingerprint = null;
                      },
                child: const Text('锁定身份'),
              ),
          ],
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 800),
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                const Text('接收者使用独立密码和身份密钥。只能读取所有者明确交付的范围；不会打开所有者资料库。'),
                if (identity == null) ...[
                  if (!service.exists)
                    TextField(
                      controller: name,
                      enabled: !busy,
                      decoration: const InputDecoration(labelText: '接收者显示名称'),
                    ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: password,
                    obscureText: true,
                    enabled: !busy,
                    decoration: const InputDecoration(labelText: '接收者身份密码'),
                  ),
                  if (!service.exists) ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: confirmation,
                      obscureText: true,
                      enabled: !busy,
                      decoration: const InputDecoration(labelText: '重复密码'),
                    ),
                  ],
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: busy
                        ? null
                        : () => run(() async {
                            if (service.exists) {
                              await service.unlock(password.text);
                            } else {
                              if (password.text != confirmation.text) {
                                throw const FormatException('两次密码不一致');
                              }
                              await service.create(name.text, password.text);
                            }
                            password.clear();
                            confirmation.clear();
                          }),
                    child: Text(service.exists ? '解锁接收者身份' : '创建独立接收者身份'),
                  ),
                  if (!service.exists)
                    TextButton(
                      onPressed: busy
                          ? null
                          : () => run(() async {
                              final file = await FilePicker.pickFile(
                                dialogTitle: '选择加密身份备份',
                              );
                              if (file == null) return;
                              final bytes = await file.readAsBytes();
                              try {
                                await service.importProtectedIdentity(
                                  bytes,
                                  password.text,
                                );
                                password.clear();
                              } finally {
                                bytes.fillRange(0, bytes.length, 0);
                              }
                            }),
                      child: const Text('用上方密码导入加密身份备份'),
                    ),
                ] else ...[
                  const SizedBox(height: 16),
                  Text('当前身份：${identity.name}'),
                  if (fingerprint != null) SelectableText(fingerprint!),
                  Wrap(
                    spacing: 8,
                    children: [
                      OutlinedButton(
                        onPressed: busy
                            ? null
                            : () => run(() async {
                                final bytes = LocalIdentity.encodeJson(
                                  await identity.publicData(),
                                );
                                try {
                                  await saveLocalBytes(
                                    bytes,
                                    'Recipient.lrpublic',
                                  );
                                } finally {
                                  bytes.fillRange(0, bytes.length, 0);
                                }
                              }),
                        child: const Text('导出公开身份给所有者'),
                      ),
                      OutlinedButton(
                        onPressed: busy
                            ? null
                            : () => run(() async {
                                final bytes = await service
                                    .exportProtectedIdentity();
                                try {
                                  await saveLocalBytes(
                                    bytes,
                                    'Recipient.lridentity',
                                  );
                                } finally {
                                  bytes.fillRange(0, bytes.length, 0);
                                }
                              }),
                        child: const Text('备份加密身份密钥'),
                      ),
                      OutlinedButton(
                        onPressed: busy
                            ? null
                            : () => run(() async {
                                final data = await pickLocalJson(
                                  title: '选择所有者发出的验证挑战',
                                );
                                if (data == null) return;
                                final owner = LocalIdentity.validatePublic(
                                  data['owner'],
                                );
                                final fp = await LocalIdentity.fingerprintOf(
                                  owner,
                                );
                                if (!context.mounted) return;
                                final trusted = await askFingerprint(
                                  context,
                                  fp,
                                  LocalIdentity.displayName(owner),
                                );
                                if (trusted == null) return;
                                final bytes = await service.answerChallenge(
                                  data,
                                  trusted,
                                );
                                try {
                                  await saveLocalBytes(
                                    bytes,
                                    'Recipient.lrproof',
                                  );
                                } finally {
                                  bytes.fillRange(0, bytes.length, 0);
                                }
                              }),
                        child: const Text('响应身份验证挑战'),
                      ),
                    ],
                  ),
                  const Divider(),
                  FilledButton.icon(
                    onPressed: busy ? null : () => run(importPackage),
                    icon: const Icon(Icons.file_open_outlined),
                    label: const Text('核对所有者并接收交接包'),
                  ),
                  TextButton(
                    onPressed: busy
                        ? null
                        : () => run(() async {
                            final files = await service.savedPackages();
                            if (!context.mounted) return;
                            final file = await showDialog(
                              context: context,
                              builder: (context) => SimpleDialog(
                                title: const Text('已验证的本机资料包'),
                                children: [
                                  for (final file in files)
                                    SimpleDialogOption(
                                      onPressed: () =>
                                          Navigator.pop(context, file),
                                      child: Text(file.uri.pathSegments.last),
                                    ),
                                  if (files.isEmpty)
                                    const Padding(
                                      padding: EdgeInsets.all(16),
                                      child: Text('尚未接收资料包'),
                                    ),
                                ],
                              ),
                            );
                            if (file != null) {
                              await importPackage(
                                saved: true,
                                savedBytes: await file.readAsBytes(),
                              );
                            }
                          }),
                    child: const Text('打开此前接收的本机资料包'),
                  ),
                  if (service.snapshot != null)
                    ReadOnlySnapshot(data: service.snapshot!),
                ],
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Text(
                      error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                if (busy) const LinearProgressIndicator(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
