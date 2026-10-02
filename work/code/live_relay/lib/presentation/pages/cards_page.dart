import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../application/app_controller.dart';
import '../../core/domain/entities.dart';
import '../design_system/atoms.dart';
import '../dialogs/card_dialogs.dart';
import '../model_labels.dart';
import '../widgets/life_card_tile.dart';

class CardsPage extends StatefulWidget {
  const CardsPage({super.key, this.initialStatus});
  final CardStatus? initialStatus;
  @override
  State<CardsPage> createState() => _CardsPageState();
}

class _CardsPageState extends State<CardsPage> {
  final _search = TextEditingController();
  late CardStatus? _status = widget.initialStatus;
  CardKind? _kind;
  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    final visible = controller.findCards(
      _search.text,
      kind: _kind,
      status: _status,
    );
    final searching = _search.text.trim().isNotEmpty;
    final filtered = _kind != null || _status != null;
    return RefreshIndicator(
      onRefresh: () => runUiAction(context, controller.refresh),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 104),
        children: [
          Semantics(
            label: '搜索卡片',
            child: SearchField(
              controller: _search,
              hintText: '搜索标题、内容或标签',
              leading: const Icon(Icons.search),
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => setState(() {}),
              trailing: [
                if (_search.text.isNotEmpty)
                  IconButton(
                    tooltip: '清除搜索',
                    onPressed: () => setState(_search.clear),
                    icon: const Icon(Icons.clear),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Wrap(
              spacing: 8,
              children: [
                FilterChip(
                  label: const Text('全部类型'),
                  selected: _kind == null,
                  onSelected: (_) => setState(() => _kind = null),
                ),
                for (final kind in CardKind.values)
                  FilterChip(
                    label: Text(kind.label),
                    selected: _kind == kind,
                    onSelected: (_) => setState(() => _kind = kind),
                  ),
              ],
            ),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              FilterChip(
                label: const Text('全部状态'),
                selected: _status == null,
                onSelected: (_) => setState(() => _status = null),
              ),
              for (final status in [CardStatus.draft, CardStatus.confirmed])
                FilterChip(
                  label: Text(status.label),
                  selected: _status == status,
                  onSelected: (_) => setState(() => _status = status),
                ),
              PopupMenuButton<CardStatus>(
                tooltip: '历史状态筛选',
                onSelected: (s) => setState(() => _status = s),
                itemBuilder: (_) => [
                  for (final s in [CardStatus.split, CardStatus.archived])
                    PopupMenuItem(value: s, child: Text(s.label)),
                ],
                child: const Padding(
                  padding: EdgeInsets.all(14),
                  child: Text('历史状态 ▾'),
                ),
              ),
              if (controller.cards.length >= 2)
                OutlinedButton.icon(
                  onPressed: () => showCombineCardsDialog(context, controller),
                  icon: const Icon(Icons.dashboard_customize_outlined),
                  label: const Text('组合'),
                ),
            ],
          ),
          if (_status == CardStatus.split || _status == CardStatus.archived)
            Text('正在查看：${_status!.label}'),
          const SizedBox(height: 8),
          if (controller.lastError != null) ...[
            ErrorBanner(controller.lastError!),
            TextButton(
              onPressed: () => runUiAction(context, controller.refresh),
              child: const Text('重试加载'),
            ),
          ],
          if (visible.isEmpty)
            EmptyState(
              icon: searching ? Icons.search_off : Icons.inbox_outlined,
              title: controller.cards.isEmpty
                  ? '还没有卡片'
                  : searching
                  ? '没有匹配的卡片'
                  : '此筛选下没有卡片',
              message: controller.cards.isEmpty
                  ? '先记下重要的信息，再按自己的节奏整理。'
                  : searching
                  ? '试试其他关键词。首页最近内容不受搜索影响。'
                  : '调整类型或状态，查看其他内容。',
              action: searching || filtered
                  ? TextButton(
                      onPressed: () => setState(() {
                        _search.clear();
                        _status = null;
                        _kind = null;
                      }),
                      child: const Text('清除搜索与筛选'),
                    )
                  : FilledButton(
                      onPressed: () => showCardEditor(context, controller),
                      child: const Text('记一条'),
                    ),
            ),
          for (final card in visible) ...[
            LifeCardTile(
              card: card,
              onTap: () => showCardDetails(context, controller, card),
            ),
            const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}
