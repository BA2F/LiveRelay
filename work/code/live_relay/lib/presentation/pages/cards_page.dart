import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../application/app_controller.dart';
import '../../core/domain/entities.dart';
import '../design_system/atoms.dart';
import '../dialogs/card_dialogs.dart';
import '../model_labels.dart';
import '../widgets/life_card_tile.dart';

class CardsPage extends StatefulWidget {
  const CardsPage({super.key});

  @override
  State<CardsPage> createState() => _CardsPageState();
}

class _CardsPageState extends State<CardsPage> {
  final _search = TextEditingController();
  CardStatus? _status;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _runSearch(AppController controller) =>
      controller.refresh(cardQuery: _search.text);

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    final visible = _status == null
        ? controller.cards
        : controller.cards.where((card) => card.status == _status).toList();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
          child: Column(
            children: [
              SearchBar(
                controller: _search,
                hintText: '搜索标题、内容或标签',
                leading: const Icon(Icons.search),
                trailing: [
                  if (_search.text.isNotEmpty)
                    IconButton(
                      onPressed: () {
                        _search.clear();
                        _runSearch(controller);
                        setState(() {});
                      },
                      icon: const Icon(Icons.clear),
                    ),
                ],
                onSubmitted: (_) => _runSearch(controller),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Wrap(
                        spacing: 8,
                        children: [
                          FilterChip(
                            label: const Text('全部'),
                            selected: _status == null,
                            onSelected: (_) => setState(() => _status = null),
                          ),
                          for (final status in CardStatus.values)
                            FilterChip(
                              label: Text(status.label),
                              selected: _status == status,
                              onSelected: (_) =>
                                  setState(() => _status = status),
                            ),
                        ],
                      ),
                    ),
                  ),
                  IconButton.filledTonal(
                    tooltip: '创建组合卡片',
                    onPressed: controller.cards.length < 2
                        ? null
                        : () => showCombineCardsDialog(context, controller),
                    icon: const Icon(Icons.dashboard_customize_outlined),
                  ),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: visible.isEmpty
              ? const EmptyState(
                  icon: Icons.search_off,
                  title: '没有匹配的卡片',
                  message: '换个关键词，或新建一条记录。',
                )
              : RefreshIndicator(
                  onRefresh: () => _runSearch(controller),
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 104),
                    itemCount: visible.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final card = visible[index];
                      return LifeCardTile(
                        card: card,
                        onTap: () => showCardDetails(context, controller, card),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }
}
