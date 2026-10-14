import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/domain/entities.dart';
import '../controllers/app_controller.dart';
import '../model_labels.dart';

/// 右栏：跟着当前标签走的只读透镜——像 VSCode 的 Timeline / Find-References
/// 一样呈现信息、点击跳转定位；一切写操作留在中央编辑区。
/// 卡片对象（card/、review/、history/）显示来源、历史与引用；
/// 原件（source/）显示基本信息与被引用情况；其余标签显示空态占位。
class WorkbenchRightPanel extends StatelessWidget {
  const WorkbenchRightPanel({
    super.key,
    required this.controller,
    required this.activeView,
    required this.onOpen,
  });

  static const double width = 320;

  final AppController controller;
  final String? activeView;
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context) {
    final view = activeView;
    final segments = view?.split('/') ?? const <String>[];
    if (segments.length > 1) {
      switch (segments.first) {
        case 'card':
        case 'review':
        case 'history':
          return _CardLens(
            key: ValueKey(view),
            controller: controller,
            cardId: segments[1],
            onOpen: onOpen,
          );
      }
    }
    return const _LensEmpty();
  }
}

class _CardLens extends StatefulWidget {
  const _CardLens({
    super.key,
    required this.controller,
    required this.cardId,
    required this.onOpen,
  });

  final AppController controller;
  final String cardId;
  final ValueChanged<String> onOpen;

  @override
  State<_CardLens> createState() => _CardLensState();
}

class _CardLensState extends State<_CardLens> {
  static const _historyPreview = 5;

  int? _loadedRevision;
  List<CardSource>? _sources;
  List<CardRevision>? _history;
  Object? _error;
  var _generation = 0;

  @override
  void initState() {
    super.initState();
    _schedule();
  }

  @override
  void didUpdateWidget(covariant _CardLens oldWidget) {
    super.didUpdateWidget(oldWidget);
    _schedule();
  }

  /// Loads once per card revision: the parent rebuilds on every controller
  /// change, so a changed revision number (autosave) triggers a refresh
  /// without issuing queries from build.
  void _schedule() {
    final revision = _revisionNumber();
    if (_loadedRevision == revision && (_sources != null || _error != null)) {
      return;
    }
    _loadedRevision = revision;
    _load();
  }

  int? _revisionNumber() {
    for (final card in widget.controller.cards) {
      if (card.id == widget.cardId) return card.revisionNumber;
    }
    return null;
  }

  Future<void> _load() async {
    final generation = ++_generation;
    try {
      final sourcesFuture = widget.controller.currentCardSources(
        widget.cardId,
      );
      final historyFuture = widget.controller.cardHistory(widget.cardId);
      final sources = await sourcesFuture;
      final history = await historyFuture;
      if (!mounted ||
          generation != _generation ||
          !widget.controller.isUnlocked) {
        return;
      }
      setState(() {
        _sources = sources;
        _history = history;
        _error = null;
      });
    } on Object catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() => _error = error);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_revisionNumber() == null) {
      // 卡片已被移入回收区或不存在；主区已有对应提示，面板不重复。
      return const _LensEmpty();
    }
    if (_error != null) {
      return _LensError(onRetry: _load);
    }
    final sources = _sources;
    final history = _history;
    if (sources == null || history == null) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: LinearProgressIndicator(),
      );
    }
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        _LensSection(
          title: '来源',
          count: sources.length,
          empty: '这张卡片还没有来源记录',
          rows: [for (final source in sources) _sourceRow(source)],
        ),
        _LensSection(
          title: history.length > _historyPreview
              ? '历史 · 最近 $_historyPreview 条'
              : '历史',
          empty: '还没有修订记录',
          rows: [
            for (final revision in history.take(_historyPreview))
              _LensRow(
                title: '修订 ${revision.number} · ${revision.changeNote}',
                meta: _time(revision.createdAt),
              ),
          ],
          footer: history.length > _historyPreview
              ? TextButton(
                  onPressed: () => widget.onOpen('history/${widget.cardId}'),
                  child: const Text('打开完整历史'),
                )
              : null,
        ),
        _LensSection(
          title: '引用',
          count: _outgoing.length,
          empty: '没有引用其他卡片',
          rows: [for (final card in _outgoing) _referenceRow(card)],
          trailing: _incoming.isEmpty
              ? null
              : _LensSubGroup(
                  title: '被引用 · ${_incoming.length}',
                  rows: [for (final card in _incoming) _referenceRow(card)],
                ),
        ),
      ],
    );
  }

  List<LifeCard> get _outgoing {
    final cards = {for (final card in widget.controller.cards) card.id: card};
    return [
      for (final reference in widget.controller.cardReferences)
        if (reference.from == widget.cardId &&
            cards.containsKey(reference.to))
          cards[reference.to]!,
    ];
  }

  List<LifeCard> get _incoming {
    final cards = {for (final card in widget.controller.cards) card.id: card};
    return [
      for (final reference in widget.controller.cardReferences)
        if (reference.to == widget.cardId &&
            cards.containsKey(reference.from))
          cards[reference.from]!,
    ];
  }

  Widget _sourceRow(CardSource source) {
    final blobId = source.blobId;
    final metaParts = [source.kind.label, _time(source.createdAt)];
    VoidCallback? onTap;
    if (blobId != null) {
      final recycled = widget.controller.recycledBlobIds.contains(blobId);
      final present = widget.controller.blobs.any((b) => b.id == blobId);
      if (recycled) {
        metaParts.add('已移入回收区');
      } else if (!present) {
        metaParts.add('原件已删除');
      } else {
        onTap = () => widget.onOpen('source/$blobId');
      }
    }
    return _LensRow(
      title: source.label,
      meta: metaParts.join(' · '),
      onTap: onTap,
    );
  }

  Widget _referenceRow(LifeCard card) => _LensRow(
    title: card.title,
    meta:
        '${card.status.label} · ${_time(card.updatedAt)}',
    onTap: () => widget.onOpen('card/${card.id}'),
  );
}

class _LensSection extends StatelessWidget {
  const _LensSection({
    required this.title,
    required this.rows,
    this.count,
    this.empty,
    this.footer,
    this.trailing,
  });

  final String title;
  final List<Widget> rows;
  final int? count;
  final String? empty;
  final Widget? footer;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text(
            count == null ? title : '$title · $count',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
        if (rows.isEmpty && empty != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Text(
              empty!,
              style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
            ),
          )
        else
          ...rows,
        ?trailing,
        if (footer != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Align(alignment: Alignment.centerLeft, child: footer),
          ),
      ],
    );
  }
}

class _LensSubGroup extends StatelessWidget {
  const _LensSubGroup({required this.title, required this.rows});

  final String title;
  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Text(
            title,
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
        ),
        ...rows,
      ],
    );
  }
}

class _LensRow extends StatelessWidget {
  const _LensRow({required this.title, required this.meta, this.onTap});

  final String title;
  final String meta;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
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
              style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _LensEmpty extends StatelessWidget {
  const _LensEmpty();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('当前标签没有跟随信息', style: theme.textTheme.bodyMedium),
          const SizedBox(height: 6),
          Text(
            '右栏跟随卡片与原件标签，显示来源、历史与引用。',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _LensError extends StatelessWidget {
  const _LensError({required this.onRetry});

  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('读取失败', style: TextStyle(fontSize: 13)),
          TextButton(onPressed: () => onRetry(), child: const Text('重试')),
        ],
      ),
    );
  }
}

String _time(DateTime value) =>
    DateFormat('MM-dd HH:mm').format(value.toLocal());
