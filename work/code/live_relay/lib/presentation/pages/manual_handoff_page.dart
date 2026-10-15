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
  Map<String, Object?> recipients = {};
  String? selected, error;
  bool busy = false;
  final levels = <String, VisibilityLevel>{},
      histories = <String>{},
      originals = <String, List<String>>{};
  @override
  void initState() {
    super.initState();
    refresh();
  }

  Future<void> refresh() async {
    final data = await context.read<AppController>().handoff!.recipients();
    if (mounted) setState(() => recipients = data);
  }

  Future<void> run(Future<void> Function() action) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await action();
      await refresh();
    } on Object catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> challenge() async {
    final service = context.read<AppController>().handoff!;
    final public = await pickLocalJson(title: '选择接收者公开身份');
    if (public == null || !mounted) return;
    LocalIdentity.validatePublic(public);
    final fp = await LocalIdentity.fingerprintOf(public);
    if (!mounted) return;
    final confirmed = await askFingerprint(
      context,
      fp,
      LocalIdentity.displayName(public),
    );
    if (confirmed == null) return;
    final bytes = await service.createChallenge(public, confirmed);
    try {
      await saveLocalBytes(bytes, 'Recipient-challenge.lrchallenge');
    } finally {
      bytes.fillRange(0, bytes.length, 0);
    }
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
    final bytes = await controller.handoff!.exportScope(selected!, selections);
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
  Future<void> uploadToCradle(
    AppController controller,
    Uint8List bytes,
  ) async {
    final connection = await controller.webDavConnection();
    if (connection == null) {
      throw StateError('还没有配置云端连接：先到「设备间搬运」里配置云端');
    }
    final binding = recipients[selected];
    final public = binding is Map ? binding['public'] : null;
    if (public is! Map) throw StateError('接收者身份已失效，请重新核对');
    final label = LocalIdentity.displayName(Map<String, Object?>.from(public));
    final packageName = CradleRecipient.packageNameFor(label);
    final medium = WebDavTransferMedium(
      baseUrl: connection.baseUrl,
      username: connection.username,
      password: connection.password,
      timeout: const Duration(seconds: 120),
    );
    try {
      await CradleService(controller.handoff!).uploadPackage(
        medium,
        packageName: packageName,
        bytes: bytes,
      );
    } finally {
      medium.close();
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已上传到云端摇篮：$packageName')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    if (!controller.isUnlocked) {
      return Scaffold(
        appBar: AppBar(title: const Text('接收者与本次交接')),
        body: const Center(child: Text('资料库已锁定')),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('接收者与本次交接')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Text('先验证接收者，再选择本次交付范围并导出。'),
          Wrap(
            spacing: 8,
            children: [
              OutlinedButton(
                onPressed: busy ? null : () => run(challenge),
                child: const Text('导入身份并生成验证挑战'),
              ),
              OutlinedButton(
                onPressed: busy
                    ? null
                    : () => run(() async {
                        final proof = await pickLocalJson(title: '选择接收者挑战响应');
                        if (proof != null) {
                          await controller.handoff!.acceptProof(proof);
                        }
                      }),
                child: const Text('导入响应，完成验证'),
              ),
            ],
          ),
          for (final r in recipients.entries)
            CheckboxListTile(
              value: selected == r.key,
              onChanged: busy
                  ? null
                  : (v) => setState(() => selected = v! ? r.key : null),
              title: Text(
                LocalIdentity.displayName(
                  Map<String, Object?>.from((r.value as Map)['public'] as Map),
                ),
              ),
              subtitle: Text(r.key),
            ),
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
                    if (record is LifeCard && level == VisibilityLevel.original)
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
            onPressed: busy || selected == null || levels.isEmpty
                ? null
                : () => run(export),
            child: const Text('核对本次范围并导出交接包'),
          ),
        ],
      ),
    );
  }
}
