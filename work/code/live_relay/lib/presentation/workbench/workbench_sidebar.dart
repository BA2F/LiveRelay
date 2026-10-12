import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../controllers/app_controller.dart';
import '../../core/domain/entities.dart';
import '../model_labels.dart';

/// 左栏只管浏览：一行是标题、状态、时间，点开才在标签里编辑。
enum WorkbenchRowKind { card, original, credential, recycledCard, recycledCredential }

class WorkbenchSidebar extends StatelessWidget {
  const WorkbenchSidebar({
    super.key,
    required this.controller,
    required this.section,
    required this.search,
    required this.searchFocus,
    required this.activeView,
    required this.onSection,
    required this.onOpenView,
    required this.onNewCard,
    required this.onNewCredential,
    required this.onImport,
    required this.onRowMenu,
    required this.onRecycledCard,
    required this.onRecycledCredential,
  });
  final AppController controller;
  final String section;
  final TextEditingController search;
  final FocusNode searchFocus;
  final String? activeView;
  final ValueChanged<String> onSection;
  final ValueChanged<String> onOpenView;
  final VoidCallback onNewCard, onNewCredential, onImport;
  final Future<void> Function(
    WorkbenchRowKind kind,
    String id,
    Offset globalPosition,
  )
  onRowMenu;
  final ValueChanged<LifeCard> onRecycledCard;
  final ValueChanged<CredentialEntry> onRecycledCredential;

  static const _sections = [
    ('inbox', '待整理', Icons.inbox_outlined),
    ('cards', '全部卡片', Icons.view_agenda_outlined),
    ('originals', '原件', Icons.perm_media_outlined),
    ('passwords', '密码', Icons.key_outlined),
    ('recycle', '回收', Icons.delete_outline),
  ];

  @override
  Widget build(BuildContext context) {
    final cards = controller.findCards(search.text);
    final drafts = controller.findCards(search.text, status: CardStatus.draft);
    final originals = controller.blobs
        .where((b) => !controller.recycledBlobIds.contains(b.id))
        .where(
          (b) =>
              search.text.trim().isEmpty ||
              b.originalName.toLowerCase().contains(
                search.text.trim().toLowerCase(),
              ),
        )
        .toList();
    final credentials = controller.findCredentials(search.text);
    final query = search.text.trim().toLowerCase();
    bool matches(String title) =>
        query.isEmpty || title.toLowerCase().contains(query);
    final recycledCards = controller.recycledCards
        .where((c) => matches(c.title))
        .toList();
    final recycledCredentials = controller.recycledCredentials
        .where((c) => matches(c.title))
        .toList();
    final counts = {
      'inbox': controller.cards
          .where((c) => c.status == CardStatus.draft)
          .length,
      'cards': controller.cards.length,
      'originals': controller.blobs
          .where((b) => !controller.recycledBlobIds.contains(b.id))
          .length,
      'passwords': controller.credentials.length,
      'recycle':
          controller.recycledCards.length +
          controller.recycledCredentials.length,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 6, 6),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: search,
                  focusNode: searchFocus,
                  decoration: const InputDecoration(
                    hintText: '搜索',
                    prefixIcon: Icon(Icons.search, size: 18),
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  style: const TextStyle(fontSize: 13),
                ),
              ),
              PopupMenuButton<String>(
                tooltip: '新建 (Ctrl+N)',
                icon: const Icon(Icons.add, size: 20),
                onSelected: (value) => switch (value) {
                  'card' => onNewCard(),
                  'credential' => onNewCredential(),
                  'import' => onImport(),
                  _ => onOpenView(value),
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'card', child: Text('信息卡片')),
                  PopupMenuItem(value: 'credential', child: Text('密码')),
                  PopupMenuItem(value: 'import', child: Text('导入原件')),
                  PopupMenuDivider(),
                  PopupMenuItem(value: 'speech', child: Text('语音输入')),
                  PopupMenuItem(value: 'agent', child: Text('助手对话')),
                ],
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        for (final entry in _sections)
          _SectionTile(
            icon: entry.$3,
            label: entry.$2,
            count: counts[entry.$1] ?? 0,
            selected: section == entry.$1,
            onTap: () => onSection(entry.$1),
          ),
        const Divider(height: 1),
        Expanded(
          child: switch (section) {
            'inbox' => _rows(
              context,
              drafts.isEmpty
                  ? (controller.cards.isEmpty ? '还没有内容' : '没有待整理的内容')
                  : null,
              [
                for (final card in drafts)
                  _cardRow(context, card, '待整理'),
              ],
            ),
            'cards' => _rows(
              context,
              cards.isEmpty
                  ? (controller.cards.isEmpty ? '还没有卡片' : '没有匹配的卡片')
                  : null,
              [
                for (final card in cards)
                  _cardRow(context, card, card.status.label),
              ],
            ),
            'originals' => _rows(
              context,
              originals.isEmpty
                  ? (controller.blobs.isEmpty ? '还没有原件' : '没有匹配的原件')
                  : null,
              [
                for (final blob in originals)
                  _SidebarRow(
                    icon: switch (blob.mediaKind) {
                      BlobMediaKind.image => Icons.image_outlined,
                      BlobMediaKind.audio => Icons.audiotrack_outlined,
                      BlobMediaKind.video => Icons.movie_outlined,
                      BlobMediaKind.document => Icons.description_outlined,
                      _ => Icons.attach_file,
                    },
                    title: blob.originalName,
                    meta: '${_size(blob.byteLength)} · ${_time(blob.createdAt)}',
                    selected: activeView == 'source/${blob.id}',
                    onTap: () => onOpenView('source/${blob.id}'),
                    onMenu: (position) =>
                        onRowMenu(WorkbenchRowKind.original, blob.id, position),
                  ),
              ],
            ),
            'passwords' => _rows(
              context,
              credentials.isEmpty
                  ? (controller.credentials.isEmpty ? '密码库还是空的' : '没有匹配的账号')
                  : null,
              [
                for (final entry in credentials)
                  _SidebarRow(
                    icon: Icons.key_outlined,
                    title: entry.title,
                    meta:
                        '${entry.username.isEmpty ? '密码' : entry.username} · ${_time(entry.updatedAt)}',
                    selected: activeView == 'credential/${entry.id}',
                    onTap: () => onOpenView('credential/${entry.id}'),
                    onMenu: (position) => onRowMenu(
                      WorkbenchRowKind.credential,
                      entry.id,
                      position,
                    ),
                  ),
              ],
            ),
            'recycle' => _rows(
              context,
              recycledCards.isEmpty && recycledCredentials.isEmpty
                  ? '回收区是空的'
                  : null,
              [
                for (final card in recycledCards)
                  _SidebarRow(
                    icon: Icons.delete_outline,
                    title: card.title,
                    meta: '卡片 · ${_time(card.updatedAt)}',
                    onTap: () => onRecycledCard(card),
                    onMenu: (position) => onRowMenu(
                      WorkbenchRowKind.recycledCard,
                      card.id,
                      position,
                    ),
                  ),
                for (final entry in recycledCredentials)
                  _SidebarRow(
                    icon: Icons.delete_outline,
                    title: entry.title,
                    meta: '密码 · ${_time(entry.updatedAt)}',
                    onTap: () => onRecycledCredential(entry),
                    onMenu: (position) => onRowMenu(
                      WorkbenchRowKind.recycledCredential,
                      entry.id,
                      position,
                    ),
                  ),
              ],
            ),
            _ => const SizedBox.shrink(),
          },
        ),
      ],
    );
  }

  Widget _cardRow(BuildContext context, LifeCard card, String status) =>
      _SidebarRow(
        icon: card.kind.icon,
        title: card.title,
        meta: '$status · ${_time(card.updatedAt)}',
        selected: activeView == 'card/${card.id}',
        onTap: () => onOpenView('card/${card.id}'),
        onMenu: (position) =>
            onRowMenu(WorkbenchRowKind.card, card.id, position),
      );

  Widget _rows(BuildContext context, String? empty, List<Widget> rows) =>
      rows.isEmpty && empty != null
          ? Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                empty,
                style: TextStyle(
                  fontSize: 13,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            )
          : ListView(padding: const EdgeInsets.symmetric(vertical: 4), children: rows);

  static String _time(DateTime value) =>
      DateFormat('MM-dd HH:mm').format(value.toLocal());

  static String _size(int bytes) => bytes >= 1024 * 1024
      ? '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB'
      : '${(bytes / 1024).ceil()} KB';
}

class _SectionTile extends StatelessWidget {
  const _SectionTile({
    required this.icon,
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      child: Container(
        height: 34,
        color: selected ? scheme.secondaryContainer : null,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Row(
          children: [
            Icon(icon, size: 17),
            const SizedBox(width: 8),
            Expanded(
              child: Text(label, style: const TextStyle(fontSize: 13)),
            ),
            Text(
              '$count',
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _SidebarRow extends StatelessWidget {
  const _SidebarRow({
    required this.icon,
    required this.title,
    required this.meta,
    required this.onTap,
    required this.onMenu,
    this.selected = false,
  });
  final IconData icon;
  final String title;
  final String meta;
  final bool selected;
  final VoidCallback onTap;
  final ValueChanged<Offset> onMenu;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onSecondaryTapDown: (details) => onMenu(details.globalPosition),
      child: InkWell(
        onTap: onTap,
        child: Container(
          color: selected ? scheme.secondaryContainer : null,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Icon(icon, size: 15),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13),
                    ),
                    Text(
                      meta,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
