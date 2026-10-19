import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/app_controller.dart';
import '../../application/release_preview.dart';
import '../../core/domain/entities.dart';
import '../design_system/atoms.dart';
import '../dialogs/card_dialogs.dart';
import '../model_labels.dart';
import '../widgets/release_preview_panel.dart';
import 'manual_handoff_page.dart';

ReleasePolicy _policy(AppController c, String type, String id) =>
    c.releasePolicies
        .where((p) => p.recordType == type && p.recordId == id)
        .firstOrNull ??
    ReleasePolicy(recordType: type, recordId: id);
bool _authorized(ReleasePolicy p) =>
    p.incapacitated != VisibilityLevel.hidden ||
    p.deceased != VisibilityLevel.hidden;

class HandoffPage extends StatelessWidget {
  const HandoffPage({super.key});
  @override
  Widget build(BuildContext context) {
    final c = context.watch<AppController>();
    final total = c.cards.length + c.credentials.length;
    final authorized =
        c.cards.where((v) => _authorized(_policy(c, 'card', v.id))).length +
        c.credentials
            .where((v) => _authorized(_policy(c, 'credential', v.id)))
            .length;
    Widget tile(String type, String id, String title) {
      final p = _policy(c, type, id);
      return ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(title),
        subtitle: Text('临时失能：${p.incapacitated.label}\n身故：${p.deceased.label}'),
        trailing: const Icon(Icons.chevron_right),
        onTap: c.isBusy
            ? null
            : () => showReleasePolicyDialog(
                context,
                c,
                recordType: type,
                recordId: id,
                recordTitle: title,
              ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        if (c.handoff != null)
          ListTile(
            leading: const Icon(Icons.send_outlined),
            title: const Text('真实限定范围交接'),
            subtitle: const Text('本人选择本次交付内容；接收者验证通过后即可取走'),
            trailing: const Icon(Icons.chevron_right),
            onTap: c.isBusy
                ? null
                : () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const ManualHandoffPage(),
                    ),
                  ),
          ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '已设置授权 $authorized 条',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                Text('预览不包含回收区内容'),
                const SizedBox(height: 12),
                FilledButton.icon(
                  icon: const Icon(Icons.visibility_outlined),
                  label: const Text('预览对方能看到什么'),
                  onPressed: () => Navigator.of(context).push<void>(
                    MaterialPageRoute(
                      builder: (_) => const RecipientPreviewPage(),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        Text('已授权的内容', style: Theme.of(context).textTheme.titleLarge),
        if (authorized == 0) const Text('尚未授权。打开一条信息，选择情境并核对精确输出。'),
        for (final card in c.cards.where(
          (v) => _authorized(_policy(c, 'card', v.id)),
        ))
          tile('card', card.id, card.title),
        for (final entry in c.credentials.where(
          (v) => _authorized(_policy(c, 'credential', v.id)),
        ))
          tile('credential', entry.id, entry.title),
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: Text('保持私密的内容 · ${total - authorized} 条'),
          children: [
            for (final card in c.cards.where(
              (v) => !_authorized(_policy(c, 'card', v.id)),
            ))
              tile('card', card.id, card.title),
            for (final entry in c.credentials.where(
              (v) => !_authorized(_policy(c, 'credential', v.id)),
            ))
              tile('credential', entry.id, entry.title),
          ],
        ),
      ],
    );
  }
}

class RecipientPreviewPage extends StatefulWidget {
  const RecipientPreviewPage({super.key});
  @override
  State<RecipientPreviewPage> createState() => _RecipientPreviewPageState();
}

class _RecipientPreviewPageState extends State<RecipientPreviewPage> {
  LifeState _scene = LifeState.incapacitated;
  @override
  Widget build(BuildContext context) {
    final c = context.watch<AppController>();
    return Scaffold(
      appBar: AppBar(title: const Text('接收者预览')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('切换情境只用于核对各状态下对方能看到的内容。'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final scene in LifeState.values)
                ChoiceChip(
                  label: Text(scene.label),
                  selected: _scene == scene,
                  onSelected: (_) => setState(() => _scene = scene),
                ),
            ],
          ),
          const SizedBox(height: 16),
          ReleasedContents(controller: c, scene: _scene),
        ],
      ),
    );
  }
}

/// 按情境列出会被释放的内容；交接预览与独立演示共用。
class ReleasedContents extends StatelessWidget {
  const ReleasedContents({
    super.key,
    required this.controller,
    required this.scene,
  });
  final AppController controller;
  final LifeState scene;
  @override
  Widget build(BuildContext context) {
    final cards = controller.cards
        .where(
          (v) =>
              _policy(controller, 'card', v.id).visibleAt(scene) !=
              VisibilityLevel.hidden,
        )
        .toList();
    final credentials = controller.credentials
        .where(
          (v) =>
              _policy(controller, 'credential', v.id).visibleAt(scene) !=
              VisibilityLevel.hidden,
        )
        .toList();
    if (cards.isEmpty && credentials.isEmpty) {
      return const EmptyState(
        icon: Icons.visibility_off_outlined,
        title: '此情境下没有被授权的信息',
        message: '未设置的条目保持私密；健康状态不释放任何信息。',
      );
    }
    return Column(
      children: [
        for (final card in cards) ...[
          ReleasePreviewPanel(
            preview: ReleasePreview.card(
              card,
              _policy(controller, 'card', card.id).visibleAt(scene),
            ),
          ),
          const SizedBox(height: 12),
        ],
        for (final entry in credentials) ...[
          ReleasePreviewPanel(
            preview: ReleasePreview.credential(
              entry,
              _policy(controller, 'credential', entry.id).visibleAt(scene),
            ),
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}
