import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../application/app_controller.dart';
import '../../application/card_summary.dart';
import '../../core/domain/entities.dart';
import '../design_system/atoms.dart';
import '../dialogs/card_dialogs.dart';
import '../dialogs/credential_dialogs.dart';
import '../model_labels.dart';
import '../widgets/card_browser.dart';
import '../design_system/appearance_tokens.dart';

class CardsPage extends StatefulWidget {
  const CardsPage({
    super.key,
    this.initialStatus,
    this.browserBuilder = defaultCardBrowser,
  });
  final CardStatus? initialStatus;
  final CardBrowserBuilder browserBuilder;
  @override
  State<CardsPage> createState() => _CardsPageState();
}

class _CardsPageState extends State<CardsPage> {
  final _search = TextEditingController();
  late CardStatus? _status = widget.initialStatus;
  CardKind? _kind;
  bool _passwordsOnly = false;

  void _open(AppController controller, CardSummary summary) {
    if (summary.isPassword) {
      final entry = controller.credentials
          .where((c) => c.id == summary.recordId)
          .firstOrNull;
      if (entry != null) showCredentialDetails(context, controller, entry);
    } else {
      final card = controller.cards
          .where((c) => c.id == summary.recordId)
          .firstOrNull;
      if (card != null) showCardDetails(context, controller, card);
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    final visible = controller.findInformationCards(
      _search.text,
      kind: _kind,
      status: _status,
      passwordsOnly: _passwordsOnly,
    );
    final searching = _search.text.trim().isNotEmpty;
    final filtered = _kind != null || _status != null || _passwordsOnly;
    final emptyLibrary =
        controller.cards.isEmpty && controller.credentials.isEmpty;
    final inset = AppearanceTokens.of(context).pageInset;
    return RefreshIndicator(
      onRefresh: () => runUiAction(context, controller.refresh),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(inset, 8, inset, 104),
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
                  selected: _kind == null && !_passwordsOnly,
                  onSelected: (_) => setState(() {
                    _kind = null;
                    _passwordsOnly = false;
                  }),
                ),
                FilterChip(
                  label: const Text('密码'),
                  selected: _passwordsOnly,
                  onSelected: (_) => setState(() {
                    _passwordsOnly = true;
                    _kind = null;
                    _status = null;
                  }),
                ),
                for (final kind in CardKind.values)
                  FilterChip(
                    label: Text(kind.label),
                    selected: _kind == kind,
                    onSelected: (_) => setState(() {
                      _kind = kind;
                      _passwordsOnly = false;
                    }),
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
                  onSelected: (_) => setState(() {
                    _status = status;
                    _passwordsOnly = false;
                  }),
                ),
              PopupMenuButton<CardStatus>(
                tooltip: '历史状态筛选',
                onSelected: (s) => setState(() {
                  _status = s;
                  _passwordsOnly = false;
                }),
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
              title: emptyLibrary
                  ? '还没有卡片'
                  : searching
                  ? '没有匹配的卡片'
                  : '此筛选下没有卡片',
              message: emptyLibrary
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
                        _passwordsOnly = false;
                      }),
                      child: const Text('清除搜索与筛选'),
                    )
                  : FilledButton(
                      onPressed: () => showCardEditor(context, controller),
                      child: const Text('记一条'),
                    ),
            ),
          widget.browserBuilder(
            context,
            visible,
            (card) => _open(controller, card),
          ),
        ],
      ),
    );
  }
}
