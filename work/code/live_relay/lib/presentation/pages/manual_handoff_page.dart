import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/app_controller.dart';
import '../../application/cradle_service.dart';
import '../../application/local_handoff_service.dart';
import '../../application/release_preview.dart';
import '../../core/cradle/cradle_records.dart';
import '../../core/domain/entities.dart';
import '../../core/identity/local_identity.dart';
import '../../infrastructure/transfer/webdav_transfer_medium.dart';
import '../dialogs/local_file_dialogs.dart';
import '../model_labels.dart';

class ManualHandoffPage extends StatefulWidget {
  const ManualHandoffPage({super.key});
  @override
  State<ManualHandoffPage> createState() => _ManualHandoffPageState();
}

class _ManualHandoffPageState extends State<ManualHandoffPage> {
  Map<String, Object?>? recipient;
  String? fingerprint, error;
  bool busy = false;
  final levels = <String, VisibilityLevel>{},
      histories = <String>{},
      originals = <String, List<String>>{};

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

  Future<void> chooseRecipient() async {
    final service = context.read<AppController>().handoff!;
    final public = await pickLocalJson(title: '选择接收者公开身份');
    if (public == null || !mounted) return;
    await run(() async {
      LocalIdentity.validatePublic(public);
      final fp = await LocalIdentity.fingerprintOf(public);
      if (!mounted) return;
      final confirmed = await askFingerprint(
        context,
        fp,
        LocalIdentity.displayName(public),
      );
      if (confirmed == null || !mounted) return;
      await service.confirmRecipient(public, confirmed);
      if (!mounted) return;
      setState(() {
        recipient = public;
        fingerprint = confirmed;
        levels.clear();
        histories.clear();
        originals.clear();
      });
    });
  }

  void clearRecipient() {
    setState(() {
      recipient = null;
      fingerprint = null;
      levels.clear();
      histories.clear();
      originals.clear();
    });
  }

  Future<void> chooseOriginals(String cardId) async {
    final controller = context.read<AppController>();
    final sources = await controller.cardSources(cardId);
    final available = controller.blobs
        .where((b) => sources.any((s) => s.blobId == b.id))
        .toList();
    if (!mounted) return;
    final ids = <String>{...?originals[cardId]};
    final result = await showDialog<List<String>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, refresh) => AlertDialog(
          title: const Text('另行授权原件'),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('勾选的文件会完整交付，包括图片、录音等原始内容。'),
                  for (final blob in available)
                    CheckboxListTile(
                      value: ids.contains(blob.id),
                      title: Text(blob.originalName),
                      onChanged: (v) => refresh(() {
                        if (v!) {
                          ids.add(blob.id);
                        } else {
                          ids.remove(blob.id);
                        }
                      }),
                    ),
                  if (available.isEmpty) const Text('此卡片没有关联原件'),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, ids.toList()),
              child: const Text('确认原件范围'),
            ),
          ],
        ),
      ),
    );
    if (result != null && mounted) setState(() => originals[cardId] = result);
  }

  Future<void> export() async {
    final controller = context.read<AppController>();
    final selections = [
      for (final item in levels.entries)
        ScopedRecord(
          item.key.startsWith('card/') ? 'card' : 'credential',
          item.key.substring(item.key.indexOf('/') + 1),
          item.value,
          history: histories.contains(item.key),
          originalIds:
              originals[item.key.substring(item.key.indexOf('/') + 1)] ?? [],
        ),
    ];
    final approved = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认本次真实交接'),
        content: SizedBox(
          width: 600,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  '以下是交付预览。原件和完整历史只有在单独勾选后才会附带。此资料包可以被接收者永久保存；之后修改权限无法撤回已交付副本。',
                ),
                for (final s in selections) ...[
                  const Divider(),
                  Text(
                    '${s.type == 'card' ? controller.cards.singleWhere((c) => c.id == s.id).title : controller.credentials.singleWhere((c) => c.id == s.id).title} · ${s.level.label}',
                  ),
                  SelectableText(
                    s.type == 'card'
                        ? ReleasePreview.card(
                            controller.cards.singleWhere((c) => c.id == s.id),
                            s.level,
                          ).body
                        : ReleasePreview.credential(
                            controller.credentials.singleWhere(
                              (c) => c.id == s.id,
                            ),
                            s.level,
                          ).body,
                  ),
                  if (s.type == 'credential' &&
                      s.level.index >= VisibilityLevel.secret.index)
                    const Text('包含当前密码（接收端默认遮挡）'),
                  Text(
                    '${s.history ? '附带完整修订历史' : '不附带历史'} · ${s.originalIds.length} 个原件',
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          OutlinedButton(
            onPressed: () => Navigator.pop(context, 'local'),
            child: const Text('导出为本地文件'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, 'cloud'),
            child: const Text('上传到云端摇篮'),
          ),
        ],
      ),
    );
    if (approved == null || !controller.isUnlocked) return;
    final bytes = await controller.handoff!.exportScope(
      fingerprint!,
      selections,
    );
    try {
      if (!controller.isUnlocked) return;
      if (approved == 'local') {
        await saveLocalBytes(bytes, 'LiveRelay-scoped.lrshare');
        return;
      }
      await uploadToCradle(controller, bytes);
    } finally {
      bytes.fillRange(0, bytes.length, 0);
    }
  }

  /// Uploads the exported package as this recipient's pre-authorized cradle
  /// package. The name follows CradleRecipient.packageNameFor so the cradle
  /// service's pickup mail points at this exact file.
  Future<void> uploadToCradle(AppController controller, Uint8List bytes) async {
    final connection = await controller.webDavConnection();
    if (connection == null) {
      throw StateError('还没有配置云端连接：先到「设备间搬运」里配置云端');
    }
    final public = recipient;
    if (public == null) throw StateError('请先选择接收者');
    final label = LocalIdentity.displayName(public);
    final packageName = CradleRecipient.packageNameFor(label);
    final medium = WebDavTransferMedium(
      baseUrl: connection.baseUrl,
      username: connection.username,
      password: connection.password,
      timeout: const Duration(seconds: 120),
    );
    try {
      await CradleService(controller.handoff!)
          .uploadPackage(medium, packageName: packageName, bytes: bytes);
    } finally {
      medium.close();
    }
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('已上传到云端摇篮：$packageName')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    if (!controller.isUnlocked) {
      return Scaffold(
        appBar: AppBar(title: const Text('真实限定范围交接')),
        body: const Center(child: Text('资料库已锁定')),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('真实限定范围交接')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Text(
            '接收者不必在场。导入他的公开身份并核对完整指纹，选好本次交付内容后打包；'
            '接收者打开交接包时，由他的设备验证私钥。',
          ),
          const SizedBox(height: 20),
          Text('1 · 接收者', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if (recipient == null)
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                onPressed: busy ? null : chooseRecipient,
                icon: const Icon(Icons.person_search_outlined),
                label: const Text('导入接收者公开身份'),
              ),
            )
          else
            Card(
              child: ListTile(
                leading: const Icon(Icons.badge_outlined),
                title: Text(LocalIdentity.displayName(recipient!)),
                subtitle: SelectableText(
                  fingerprint!,
                  style: const TextStyle(fontFamily: 'monospace'),
                ),
                trailing: TextButton(
                  onPressed: busy ? null : clearRecipient,
                  child: const Text('重新选择'),
                ),
              ),
            ),
          if (recipient != null) ...[
            const SizedBox(height: 24),
            Text('2 · 交付内容', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            const Text('逐条选择这次交付的范围；没有选择的记录保持私密。'),
            const Divider(),
            for (final record in <InformationCard>[
              ...controller.cards,
              ...controller.credentials,
            ]) ...[
              Builder(
                builder: (context) {
                  final key =
                      '${record is LifeCard ? 'card' : 'credential'}/${record.id}';
                  final level = levels[key];
                  return Column(
                    children: [
                      ListTile(
                        title: Text(record.title),
                        subtitle: Text(record is LifeCard ? '卡片' : '密码条目'),
                        trailing: DropdownButton<VisibilityLevel>(
                          value: level ?? VisibilityLevel.hidden,
                          items: [
                            for (final v in VisibilityLevel.values)
                              DropdownMenuItem(
                                value: v,
                                child: Text(
                                  [
                                    '不交付',
                                    '仅存在',
                                    '摘要',
                                    '完整正文',
                                    '密码',
                                    '原件',
                                  ][v.index],
                                ),
                              ),
                          ],
                          onChanged: busy
                              ? null
                              : (v) => setState(() {
                                  if (v == VisibilityLevel.hidden) {
                                    levels.remove(key);
                                  } else {
                                    levels[key] = v!;
                                  }
                                  histories.remove(key);
                                  originals.remove(record.id);
                                }),
                        ),
                      ),
                      if (level != null &&
                          level.index >=
                              (record is LifeCard
                                  ? VisibilityLevel.full.index
                                  : VisibilityLevel.secret.index))
                        CheckboxListTile(
                          value: histories.contains(key),
                          title: const Text('另行附带完整修订历史'),
                          onChanged: busy
                              ? null
                              : (v) => setState(() {
                                  if (v!) {
                                    histories.add(key);
                                  } else {
                                    histories.remove(key);
                                  }
                                }),
                        ),
                      if (record is LifeCard &&
                          level == VisibilityLevel.original)
                        TextButton(
                          onPressed: busy
                              ? null
                              : () => chooseOriginals(record.id),
                          child: Text(
                            '选择原件 · ${originals[record.id]?.length ?? 0} 个',
                          ),
                        ),
                    ],
                  );
                },
              ),
            ],
            if (error != null) Text(error!),
            if (busy) const LinearProgressIndicator(),
            FilledButton(
              onPressed: busy || levels.isEmpty ? null : () => run(export),
              child: const Text('核对本次范围并导出交接包'),
            ),
          ] else if (error != null)
            Text(error!),
        ],
      ),
    );
  }
}
