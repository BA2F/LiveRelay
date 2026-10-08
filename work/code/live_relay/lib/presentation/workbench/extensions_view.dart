import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controllers/app_controller.dart';
import '../../application/card_summary.dart';
import 'state/extension_registry.dart';
import '../dialogs/local_file_dialogs.dart';

class ExtensionsView extends StatefulWidget {
  const ExtensionsView({
    super.key,
    required this.registry,
    required this.onOpen,
  });
  final ExtensionAccess registry;
  final ValueChanged<String> onOpen;
  @override
  State<ExtensionsView> createState() => _ExtensionsViewState();
}

class _ExtensionsViewState extends State<ExtensionsView> {
  late final Future<ExtensionManifest> _sample = rootBundle
      .loadString('assets/extensions/draft-review.lrext.json')
      .then(
        (v) => ExtensionManifest.parse(jsonDecode(v) as Map<String, dynamic>),
      );
  String? _error;
  bool _working = false;
  Future<void> _run(Future<void> Function() operation) async {
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      await operation();
    } on Object catch (e) {
      _error = e is FormatException ? e.message : '扩展配置保存失败，请重试';
    }
    if (mounted) setState(() => _working = false);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.registry,
    builder: (context, _) => ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('扩展', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        const Text('安装资料视图、命令和设置扩展。扩展使用已解锁的卡片摘要；不会获得密码、密钥、整库、文件或网络访问。'),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          icon: const Icon(Icons.install_desktop),
          label: const Text('从本地安装扩展描述'),
          onPressed: _working
              ? null
              : () => _run(() async {
                  final raw = await pickLocalJson(title: '选择 LiveRelay 扩展描述');
                  if (raw != null) {
                    await widget.registry.install(
                      ExtensionManifest.parse(Map<String, dynamic>.from(raw)),
                    );
                  }
                }),
        ),
        if (_working) const LinearProgressIndicator(),
        if (_error != null)
          Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        const SizedBox(height: 16),
        Text(
          '已安装 · ${widget.registry.installed.length}',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        for (final item in widget.registry.installed.values)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(item.manifest.name),
                    subtitle: Text(
                      '${item.manifest.id} · ${item.manifest.version}',
                    ),
                    value: item.enabled,
                    onChanged: _working
                        ? null
                        : (v) => _run(
                            () =>
                                widget.registry.setEnabled(item.manifest.id, v),
                          ),
                  ),
                  Text(item.manifest.description),
                  for (final setting in item.manifest.settings)
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(setting.title),
                      value: item.setting(setting.id),
                      onChanged: _working || !item.enabled
                          ? null
                          : (v) => _run(
                              () => widget.registry.setSetting(
                                item.manifest.id,
                                setting.id,
                                v,
                              ),
                            ),
                    ),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final view in item.manifest.views)
                        TextButton(
                          onPressed: item.enabled
                              ? () => widget.onOpen(
                                  'extension/${item.manifest.id}/${view.id}',
                                )
                              : null,
                          child: Text('打开${view.title}'),
                        ),
                      TextButton(
                        onPressed: _working
                            ? null
                            : () => _run(
                                () => widget.registry.remove(item.manifest.id),
                              ),
                        child: const Text('移除扩展'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 16),
        Text('可发现的扩展', style: Theme.of(context).textTheme.titleMedium),
        FutureBuilder<ExtensionManifest>(
          future: _sample,
          builder: (context, snapshot) {
            if (snapshot.hasError) return const Text('内置扩展描述读取失败');
            if (!snapshot.hasData) return const LinearProgressIndicator();
            final sample = snapshot.data!;
            return Card(
              child: ListTile(
                title: Text('${sample.name} · ${sample.version}'),
                subtitle: Text(sample.description),
                trailing: FilledButton.tonal(
                  onPressed:
                      _working ||
                          widget.registry.installed.containsKey(sample.id)
                      ? null
                      : () => _run(() => widget.registry.install(sample)),
                  child: Text(
                    widget.registry.installed.containsKey(sample.id)
                        ? '已安装'
                        : '安装',
                  ),
                ),
              ),
            );
          },
        ),
      ],
    ),
  );
}

class ContributedCardsView extends StatefulWidget {
  const ContributedCardsView({
    super.key,
    required this.registry,
    required this.viewId,
    required this.controller,
    required this.onOpen,
  });
  final ExtensionRegistry registry;
  final String viewId;
  final AppController controller;
  final ValueChanged<String> onOpen;
  @override
  State<ContributedCardsView> createState() => _ContributedCardsViewState();
}

class _ContributedCardsViewState extends State<ContributedCardsView> {
  late Future<Set<String>> _sourced;
  String _signature = '';
  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void didUpdateWidget(covariant ContributedCardsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    _reload();
  }

  void _reload() {
    final signature = widget.controller.cards
        .map((c) => '${c.id}:${c.revisionNumber}')
        .join(',');
    if (_signature == signature && signature.isNotEmpty) return;
    _signature = signature;
    _sourced = Future.wait([
      for (final c in widget.controller.cards)
        widget.controller
            .currentCardSources(c.id)
            .then(
              (sources) => sources.any((s) => s.blobId != null) ? c.id : null,
            ),
    ]).then((ids) => ids.whereType<String>().toSet());
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Set<String>>(
    future: _sourced,
    builder: (context, snapshot) {
      if (snapshot.hasError) return const Center(child: Text('卡片来源读取失败'));
      if (!snapshot.hasData) {
        return const Center(child: CircularProgressIndicator());
      }
      final cards = widget.registry.filter(
        widget.viewId,
        widget.controller.findInformationCards(''),
        snapshot.data!,
      );
      return ContributedCardList(cards: cards, onOpen: widget.onOpen);
    },
  );
}

class ContributedCardList extends StatelessWidget {
  const ContributedCardList({
    super.key,
    required this.cards,
    required this.onOpen,
  });
  final List<CardSummary> cards;
  final ValueChanged<String> onOpen;
  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('${cards.length} 张卡片'),
        for (final card in cards)
          Card(
            child: ListTile(
              title: Text(card.title),
              subtitle: Text(card.preview),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => onOpen(card.recordId),
            ),
          ),
        if (cards.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Text('没有符合此扩展筛选条件的卡片'),
          ),
      ],
    );
  }
}
