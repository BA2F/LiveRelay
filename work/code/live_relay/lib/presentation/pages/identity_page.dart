import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../application/app_controller.dart';
import '../../core/identity/local_identity.dart';
import '../dialogs/local_file_dialogs.dart';
import 'manual_handoff_page.dart';

class IdentityPage extends StatefulWidget {
  const IdentityPage({super.key});
  @override
  State<IdentityPage> createState() => _IdentityPageState();
}

class _IdentityPageState extends State<IdentityPage> {
  final name = TextEditingController(),
      contact = TextEditingController(),
      note = TextEditingController();
  String? fingerprint, error;
  bool busy = false;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final service = context.read<AppController>().handoff!;
      final profile = await service.profile();
      final fp = await LocalIdentity.fingerprintOf(
        await service.publicIdentity(),
      );
      if (mounted) {
        setState(() {
          name.text = profile['name'] as String;
          contact.text = profile['contact'] as String;
          note.text = profile['note'] as String;
          fingerprint = fp;
        });
      }
    } on Object catch (e) {
      if (mounted) setState(() => error = '$e');
    }
  }

  Future<void> run(Future<void> Function() action) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await action();
    } on Object catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    name.dispose();
    contact.dispose();
    note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    if (!controller.isUnlocked) {
      return const Scaffold(body: Center(child: Text('资料库已锁定')));
    }
    final service = controller.handoff!;
    return Scaffold(
      appBar: AppBar(title: const Text('本人身份资料')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              TextField(
                controller: name,
                enabled: !busy,
                decoration: const InputDecoration(labelText: '显示名称'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: contact,
                enabled: !busy,
                decoration: const InputDecoration(labelText: '联系方式（只保存在本库）'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: note,
                enabled: !busy,
                maxLines: 3,
                decoration: const InputDecoration(labelText: '身份备注'),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: busy
                    ? null
                    : () => run(() async {
                        await controller.saveOwnerProfile(
                          name.text,
                          contact.text,
                          note.text,
                        );
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('身份资料已保存')),
                          );
                        }
                      }),
                child: const Text('保存资料'),
              ),
              const SizedBox(height: 24),
              const Text('交接身份指纹（换密码不会改变）'),
              if (fingerprint != null) SelectableText(fingerprint!),
              OutlinedButton(
                onPressed: busy
                    ? null
                    : () => run(() async {
                        final bytes = LocalIdentity.encodeJson(
                          await service.publicIdentity(),
                        );
                        try {
                          await saveLocalBytes(bytes, 'Owner.lrpublic');
                        } finally {
                          bytes.fillRange(0, bytes.length, 0);
                        }
                      }),
                child: const Text('导出公开身份'),
              ),
              const Divider(),
              ListTile(
                title: const Text('接收者验证与限定范围交接'),
                subtitle: const Text('核对指纹、验证私钥、选择本次交接的具体内容'),
                trailing: const Icon(Icons.chevron_right),
                onTap: busy
                    ? null
                    : () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const ManualHandoffPage(),
                        ),
                      ),
              ),
              if (error != null) Text(error!),
              if (busy) const LinearProgressIndicator(),
            ],
          ),
        ),
      ),
    );
  }
}
