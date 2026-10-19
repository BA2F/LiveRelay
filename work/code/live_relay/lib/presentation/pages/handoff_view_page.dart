import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/app_controller.dart';
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
        const Text('这是本人留在这台设备上的只读交接内容。'),
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

/// Shows the recipient entry only when a handoff view exists on this device.
class HandoffViewEntryButton extends StatefulWidget {
  const HandoffViewEntryButton({super.key});
  @override
  State<HandoffViewEntryButton> createState() => _HandoffViewEntryButtonState();
}

class _HandoffViewEntryButtonState extends State<HandoffViewEntryButton> {
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final view = context.read<AppController>().handoffView;
    if (view == null) return;
    final exists = await view.exists();
    if (mounted) setState(() => _visible = exists);
  }

  @override
  Widget build(BuildContext context) => !_visible
      ? const SizedBox.shrink()
      : TextButton.icon(
          onPressed: () => openHandoffView(context),
          icon: const Icon(Icons.mark_email_read_outlined),
          label: const Text('查看交接内容'),
        );
}
