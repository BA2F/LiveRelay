import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/app_controller.dart';
import '../../core/security/pickup_code.dart';
import '../widgets/read_only_snapshot.dart';

class HandoffViewPage extends StatelessWidget {
  const HandoffViewPage({super.key, required this.snapshot});
  final Map<String, Object?> snapshot;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('交接内容')),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Text('这是本人留给你的只读内容。'),
        ReadOnlySnapshot(data: snapshot),
      ],
    ),
  );
}

/// Opens the local handoff view with the shared password.
///
/// The recipient uses this from the unlock screen; the owner's vault stays
/// locked and is never opened by this path.
Future<void> openHandoffView(BuildContext context) async {
  final view = context.read<AppController>().handoffView;
  if (view == null) return;
  if (!await view.exists()) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('本机还没有交接内容')));
    }
    return;
  }
  if (!context.mounted) return;
  final password = await _askPassword(context);
  if (password == null) return;
  try {
    final snapshot = await view.open(password);
    if (!context.mounted) return;
    await Navigator.push<void>(
      context,
      MaterialPageRoute(builder: (_) => HandoffViewPage(snapshot: snapshot)),
    );
  } on FormatException catch (error) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(error.message)));
  } on StateError catch (error) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(error.message)));
  }
}

/// Opens a package downloaded from the cloud with its pickup code.
///
/// This path needs neither a recipient identity nor the owner's vault. The
/// package is the same password envelope as the local handoff view.
Future<void> openHandoffPackage(BuildContext context) async {
  final view = context.read<AppController>().handoffView;
  if (view == null) return;
  final file = await FilePicker.pickFile(dialogTitle: '选择交接包');
  if (file == null) return;
  Uint8List? bytes;
  try {
    bytes = await file.readAsBytes();
    if (!context.mounted) return;
    final code = await _askPickupCode(context);
    if (code == null || !context.mounted) return;
    final snapshot = await view.openBytes(bytes, code);
    if (!context.mounted) return;
    await Navigator.push<void>(
      context,
      MaterialPageRoute(builder: (_) => HandoffViewPage(snapshot: snapshot)),
    );
  } on FormatException catch (error) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(error.message)));
  } on StateError catch (error) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(error.message)));
  } finally {
    bytes?.fillRange(0, bytes.length, 0);
  }
}

Future<String?> _askPickupCode(BuildContext context) async {
  var value = '';
  return showDialog<String>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, refresh) {
        final normalized = PickupCode.normalize(value);
        return AlertDialog(
          title: const Text('输入取件码'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('取件码在邮件里；不区分大小写，空格和连字符可以不输。'),
                const SizedBox(height: 12),
                TextField(
                  autofocus: true,
                  onChanged: (text) => refresh(() => value = text),
                  onSubmitted: (text) {
                    if (PickupCode.isValid(text)) {
                      Navigator.pop(context, PickupCode.normalize(text));
                    }
                  },
                  decoration: const InputDecoration(labelText: '取件码'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: PickupCode.isValid(normalized)
                  ? () => Navigator.pop(context, normalized)
                  : null,
              child: const Text('打开'),
            ),
          ],
        );
      },
    ),
  );
}

Future<String?> _askPassword(BuildContext context) async {
  var value = '';
  return showDialog<String>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, refresh) => AlertDialog(
        title: const Text('输入交接密码'),
        content: SizedBox(
          width: 420,
          child: TextField(
            obscureText: true,
            autofocus: true,
            onChanged: (text) => refresh(() => value = text),
            onSubmitted: (text) =>
                text.isEmpty ? null : Navigator.pop(context, text),
            decoration: const InputDecoration(labelText: '交接密码'),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: value.isEmpty
                ? null
                : () => Navigator.pop(context, value),
            child: const Text('查看'),
          ),
        ],
      ),
    ),
  );
}

/// Secondary lock-screen entry. A remote package opens directly; a local
/// handoff view on this device adds a second choice.
class PickupEntryButton extends StatelessWidget {
  const PickupEntryButton({super.key});

  @override
  Widget build(BuildContext context) => TextButton.icon(
    onPressed: () => _openPickup(context),
    icon: const Icon(Icons.file_open_outlined),
    label: const Text('打开交接包'),
  );
}

Future<void> _openPickup(BuildContext context) async {
  final view = context.read<AppController>().handoffView;
  final hasLocal = view != null && await view.exists();
  if (!context.mounted) return;
  if (!hasLocal) {
    await openHandoffPackage(context);
    return;
  }
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
          child: Text('选择取件方式', style: Theme.of(context).textTheme.titleLarge),
        ),
        ListTile(
          leading: const Icon(Icons.file_open_outlined),
          title: const Text('打开交接包'),
          subtitle: const Text('用邮件里的取件码打开'),
          onTap: () {
            Navigator.pop(sheetContext);
            openHandoffPackage(context);
          },
        ),
        ListTile(
          leading: const Icon(Icons.mark_email_read_outlined),
          title: const Text('查看本机交接内容'),
          subtitle: const Text('在同一台设备输入交接密码'),
          onTap: () {
            Navigator.pop(sheetContext);
            openHandoffView(context);
          },
        ),
        const SizedBox(height: 8),
      ],
    ),
  );
}
