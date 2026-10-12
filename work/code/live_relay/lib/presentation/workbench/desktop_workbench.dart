import '../widgets/liverelay_logo.dart';

import 'dart:async';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';

import '../controllers/app_controller.dart';
import '../../application/app_preferences.dart';
import 'state/card_edit_sessions.dart';
import 'state/workbench_layout.dart';
import 'state/extension_registry.dart';
import '../../core/domain/entities.dart';
import '../controllers/agent_conversation.dart';
import 'conversation_view.dart';
import '../pages/profile_page.dart';
import '../pages/passwords_page.dart';
import '../pages/handoff_page.dart';
import '../pages/speech_input_page.dart';
import '../pages/recycle_page.dart';
import 'dock_surface.dart';
import 'workbench_card_editor.dart';
import 'review_source_view.dart';
import 'relations_view.dart';
import 'extensions_view.dart';
import 'workbench_runtime.dart';

class DesktopWorkbench extends StatefulWidget {
  const DesktopWorkbench({super.key});
  @override
  State<DesktopWorkbench> createState() => _DesktopWorkbenchState();
}

class _DesktopWorkbenchState extends State<DesktopWorkbench> {
  late final AppController _controller;
  late final WorkbenchRuntime _runtime;
  WorkbenchLayout get _layout => _runtime.layout;
  CardEditSessions get _edits => _runtime.edits;
  ExtensionRegistry get _extensions => _runtime.extensions;
  AgentConversation get _conversation => _runtime.conversation;
  late final AppLifecycleListener _lifecycle;
  final _dragging = ValueNotifier<String?>(null);
  final _search = TextEditingController();
  final _selected = <String>{};
  bool get _loaded => _runtime.loaded;
  String? get _layoutError => _runtime.layoutError;
  int _tabSerial = DateTime.now().microsecondsSinceEpoch;
  static const _views = [
    'cards',
    'agent',
    'relations',
    'changes',
    'originals',
    'speech',
    'passwords',
    'handoff',
    'settings',
    'recycle',
    'extensions',
  ];
  @override
  void initState() {
    super.initState();
    _controller = context.read<AppController>();
    _runtime = WorkbenchRuntime(_controller);
    _runtime.addListener(_runtimeChanged);
    _lifecycle = AppLifecycleListener(onExitRequested: _requestExit);
    _controller.addListener(_controllerChanged);
    unawaited(
      _runtime.load(preset: context.read<AppPreferences?>()?.desktopPreset),
    );
  }

  void _runtimeChanged() {
    if (mounted) setState(() {});
  }

  void _controllerChanged() {
    if (!_controller.isUnlocked) _selected.clear();
  }

  Future<void> _persistLayout() => _runtime.persistLayout();

  @override
  void dispose() {
    _controller.removeListener(_controllerChanged);
    _runtime.removeListener(_runtimeChanged);
    _runtime.dispose();
    _lifecycle.dispose();
    _dragging.dispose();
    _search.dispose();
    super.dispose();
  }

  Future<AppExitResponse> _requestExit() async {
    final response = await _runtime.requestExit();
    if (mounted && _runtime.exitError != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(_runtime.exitError!)));
    }
    return response;
  }

  Future<void> _action(Future<void> Function() operation) async {
    try {
      await operation();
    } on Object catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e is FormatException
                  ? e.message
                  : _controller.lastError ?? '操作失败，请重试',
            ),
          ),
        );
      }
    }
  }

  Future<void> _preset(String preset) => _action(
    () => _runtime.resetLayout(preset, () async {
      if (mounted) {
        await context.read<AppPreferences?>()?.setDesktopPreset(preset);
      }
    }),
  );
  Future<void> _commands() async {
    final entries = [
      for (final view in _views)
        (id: 'core.open.$view', title: '打开${_label(view)}', view: view),
      (id: 'core.layout.reset', title: '恢复默认布局', view: '#reset'),
      ..._extensions.commands,
    ];
    var query = '';
    final selected = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, refresh) => Dialog(
          child: SizedBox(
            width: 560,
            height: 400,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: TextField(
                    autofocus: true,
                    decoration: const InputDecoration(
                      hintText: '搜索命令',
                      prefixIcon: Icon(Icons.search),
                    ),
                    onChanged: (v) => refresh(() => query = v.toLowerCase()),
                  ),
                ),
                Expanded(
                  child: ListView(
                    children: [
                      for (final entry in entries.where(
                        (e) => e.title.toLowerCase().contains(query),
                      ))
                        ListTile(
                          title: Text(entry.title),

                          onTap: () => Navigator.pop(context, entry.view),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (selected == null || !mounted) return;
    if (selected == '#reset') {
      await _preset(_layout.assistant ? 'assistant' : 'library');
    } else {
      _layout.open(selected);
    }
  }

  String _cardId(String view) => view.split('/')[1];
  String _label(String view) => switch (view) {
    'cards' => '我的资料',
    'agent' => '助手',
    'relations' => '关系',
    'changes' => '变更',
    'originals' => '原始资料',
    'speech' => '语音输入',
    'passwords' => '密码库',
    'handoff' => '交接',
    'settings' => '设置',
    'recycle' => '回收区',
    'extensions' => '扩展',
    _ =>
      _extensions.views[view]?.title ??
          (view.startsWith('card/')
              ? _controller.cards
                        .where((c) => c.id == _cardId(view))
                        .firstOrNull
                        ?.title ??
                    '卡片'
              : view.startsWith('source/')
              ? '来源'
              : view.startsWith('review/')
              ? '确认来源'
              : '修订历史'),
  };
  IconData _icon(String view) => switch (view) {
    'cards' => Icons.dashboard_outlined,
    'agent' => Icons.auto_awesome_outlined,
    'relations' => Icons.hub_outlined,
    'changes' => Icons.history,
    'originals' => Icons.perm_media_outlined,
    'speech' => Icons.mic_none,
    'passwords' => Icons.key_outlined,
    'handoff' => Icons.how_to_reg_outlined,
    'settings' => Icons.settings_outlined,
    'recycle' => Icons.delete_outline,
    'extensions' => Icons.extension_outlined,
    _ => Icons.description_outlined,
  };
  void _openCard(String id, {String? group}) =>
      _layout.open('card/$id/${_tabSerial++}', groupId: group);
  Future<void> _newCard(String group) => _action(() async {
    final existing = _controller.cards.map((c) => c.id).toSet();
    await _controller.createCard(
      const CardDraft(
        title: '新卡片',
        content: '在这里填写总结',
        status: CardStatus.draft,
      ),
    );
    _openCard(
      _controller.cards.firstWhere((c) => !existing.contains(c.id)).id,
      group: group,
    );
  });
  Future<void> _import(String group) => _action(() async {
    final files = await FilePicker.pickFiles(dialogTitle: '添加本地资料');
    for (final file in files) {
      if (!_controller.isUnlocked) return;
      final extension = file.name.split('.').last.toLowerCase();
      final kind = {'jpg', 'jpeg', 'png', 'webp', 'heic'}.contains(extension)
          ? BlobMediaKind.image
          : {'wav', 'mp3', 'm4a', 'aac', 'ogg'}.contains(extension)
          ? BlobMediaKind.audio
          : {'mp4', 'mov', 'webm', 'mkv'}.contains(extension)
          ? BlobMediaKind.video
          : BlobMediaKind.document;
      final mime = switch (extension) {
        'png' => 'image/png',
        'jpg' || 'jpeg' => 'image/jpeg',
        'txt' || 'md' => 'text/plain',
        'pdf' => 'application/pdf',
        'wav' => 'audio/wav',
        'mp4' => 'video/mp4',
        _ => 'application/octet-stream',
      };
      final card = await _controller.importOriginal(
        bytes: await file.readAsBytes(),
        originalName: file.name,
        mimeType: mime,
        mediaKind: kind,
      );
      _openCard(card.id, group: group);
    }
  });
  Future<void> _delete(List<LifeCard> cards) async {
    CardDeletionPreview? preview;
    await _action(() async {
      await _edits.flush();
      if (_edits.hasUnsaved) throw const FormatException('请先处理未保存的修改');
      preview = await _controller.previewCardDeletion(
        cards.map((c) => c.id).toList(),
      );
    });
    if (preview == null || !mounted) return;
    var recycleOriginals = false;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, refresh) => AlertDialog(
          title: Text('删除 ${cards.length} 张卡片？'),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final card in cards) Text('• ${card.title}'),
                  const SizedBox(height: 12),
                  const Text('卡片移入回收区，历史保留，可恢复。'),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: recycleOriginals,
                    title: Text(
                      '同时回收 ${preview!.recyclableOriginals.length} 个未共享原件',
                    ),
                    subtitle: const Text('原件保留，可随卡片恢复；其他卡片及其历史引用的原件受保护'),
                    onChanged: preview!.recyclableOriginals.isEmpty
                        ? null
                        : (v) => refresh(() => recycleOriginals = v ?? false),
                  ),
                  for (final blob in preview!.recyclableOriginals)
                    Text('可回收：${blob.originalName}'),
                  for (final blob in preview!.protectedOriginals)
                    Text('共享/历史保护：${blob.originalName}'),
                ],
              ),
            ),
          ),
          actions: [
            if (_controller.isBusy)
              const Padding(
                padding: EdgeInsets.all(14),
                child: SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('移入回收区'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) return;
    await _action(() async {
      await _edits.flush();
      if (_edits.hasUnsaved) throw const FormatException('请先处理未保存的修改');
      await _controller.trashCards(
        cards.map((c) => c.id).toList(),
        recycleUnsharedOriginals: recycleOriginals,
      );
      _selected.removeAll(cards.map((c) => c.id));
      if (mounted) setState(() {});
    });
  }

  Widget _recycle() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (_controller.recycledBlobIds.isNotEmpty)
        SizedBox(
          height: 170,
          child: ListView(
            padding: const EdgeInsets.all(12),
            children: [
              const Text('回收原件（历史与加密文件保留）'),
              for (final blob in _controller.blobs.where(
                (b) => _controller.recycledBlobIds.contains(b.id),
              ))
                ListTile(
                  title: Text(blob.originalName),
                  trailing: IconButton(
                    tooltip: '恢复原件',
                    icon: const Icon(Icons.restore),
                    onPressed: _controller.isBusy
                        ? null
                        : () => _action(
                            () => _controller.restoreOriginal(blob.id),
                          ),
                  ),
                ),
            ],
          ),
        ),
      const Expanded(child: RecyclePage()),
    ],
  );
  WorkbenchCardEditor _editor(LifeCard card, String group) =>
      WorkbenchCardEditor(
        key: ValueKey(card.id),
        card: card,
        controller: _controller,
        edits: _edits,
        onNewTab: () => _openCard(card.id, group: group),
        onHistory: () => _layout.open('history/${card.id}', groupId: group),
        onReviewSource: () => _layout.open('review/${card.id}', groupId: group),
        onSource: (id) => _layout.open('source/$id', groupId: group),
        onCard: (id) => _openCard(id, group: group),
        onDelete: () => _delete([card]),
      );
  Widget _library(String group) {
    final cards = _controller.findCards(_search.text);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              TextField(
                controller: _search,
                decoration: const InputDecoration(
                  hintText: '搜索资料',
                  prefixIcon: Icon(Icons.search),
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  FilledButton.tonalIcon(
                    onPressed: _controller.isBusy
                        ? null
                        : () => _newCard(group),
                    icon: const Icon(Icons.add),
                    label: const Text('新建卡片'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _controller.isBusy ? null : () => _import(group),
                    icon: const Icon(Icons.attach_file),
                    label: const Text('添加资料'),
                  ),
                  if (_selected.isNotEmpty)
                    TextButton.icon(
                      onPressed: () => _delete(
                        _controller.cards
                            .where((c) => _selected.contains(c.id))
                            .toList(),
                      ),
                      icon: const Icon(Icons.delete_outline),
                      label: Text('删除 ${_selected.length} 张'),
                    ),
                  Text('${cards.length} 张卡片'),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            itemCount: cards.length,
            itemBuilder: (context, index) {
              final card = cards[index];
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Checkbox(
                            value: _selected.contains(card.id),
                            onChanged: (v) => setState(() {
                              if (v == true) {
                                _selected.add(card.id);
                              } else {
                                _selected.remove(card.id);
                              }
                            }),
                          ),
                          const Text('选择卡片'),
                        ],
                      ),
                      _editor(card, group),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _history(String id) => FutureBuilder<List<CardRevision>>(
    future: _controller.cardHistory(id),
    builder: (context, snapshot) {
      if (snapshot.hasError) return const Center(child: Text('历史读取失败'));
      if (!snapshot.hasData) {
        return const Center(child: CircularProgressIndicator());
      }
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          for (final r in snapshot.data!)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('修订 ${r.number} · ${r.changeNote}'),
                    Text(r.createdAt.toLocal().toString()),
                    Text(
                      r.title,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    SelectableText(r.content),
                    TextButton(
                      onPressed: _controller.isBusy
                          ? null
                          : () => _action(() async {
                              await _edits.flush();
                              if (_edits.hasUnsaved) {
                                throw const FormatException('请先处理未保存的修改');
                              }
                              final card = _controller.cards
                                  .where((c) => c.id == id)
                                  .firstOrNull;
                              if (card == null) {
                                throw const FormatException('卡片已移入回收区');
                              }
                              await _controller.restoreCardRevision(
                                id,
                                r.number,
                              );
                            }),
                      child: const Text('恢复为新修订'),
                    ),
                  ],
                ),
              ),
            ),
        ],
      );
    },
  );
  Widget _view(String view, String group) {
    if (view.startsWith('extension/')) {
      return ContributedCardsView(
        registry: _extensions,
        viewId: view,
        controller: _controller,
        onOpen: (id) => _openCard(id, group: group),
      );
    }
    if (view.startsWith('card/')) {
      final card = _controller.cards
          .where((c) => c.id == _cardId(view))
          .firstOrNull;
      return card == null
          ? const Center(child: Text('卡片已移入回收区'))
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [_editor(card, group)],
            );
    }
    if (view.startsWith('history/')) return _history(_cardId(view));
    if (view.startsWith('review/')) {
      return ReviewSourceView(
        key: ValueKey(view),
        session: _controller,
        loadSource: _controller.cardReviewSource,
        cardTitle: (id) =>
            _controller.cards.where((c) => c.id == id).firstOrNull?.title ??
            '目标已失效',
        cardId: _cardId(view),
        onCard: (id) => _openCard(id, group: group),
        onOriginal: (id) => _layout.open('source/$id', groupId: group),
      );
    }
    if (view.startsWith('source/')) {
      return ListView(
        padding: const EdgeInsets.all(20),
        children: [
          InlineOriginal(controller: _controller, blobId: _cardId(view)),
        ],
      );
    }
    return switch (view) {
      'cards' => _library(group),
      'agent' => ConversationView(
        conversation: _conversation,
        openManual: () => _layout.open('cards'),
        openSpeech: () => _layout.open('speech'),
      ),
      'settings' => const ProfilePage(),
      'passwords' => const PasswordsPage(active: true),
      'handoff' => const HandoffPage(),
      'speech' => SpeechInputPage(
        onTranscript: (text) {
          _conversation.updateDraft(
            _conversation.draft.isEmpty
                ? text
                : '${_conversation.draft}\n$text',
          );
          _layout.open('agent');
        },
      ),
      'recycle' => _recycle(),
      'extensions' => ExtensionsView(
        registry: _extensions,
        onOpen: (view) => _layout.open(view, groupId: group),
      ),
      'originals' => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          for (final b in _controller.blobs.where(
            (b) => !_controller.recycledBlobIds.contains(b.id),
          ))
            ListTile(
              leading: Icon(_icon(view)),
              title: Text(b.originalName),
              subtitle: Text('${b.byteLength} 字节'),
              onTap: () => _layout.open('source/${b.id}', groupId: group),
            ),
        ],
      ),
      'changes' => ListView(
        children: [
          for (final c in _controller.cards)
            ListTile(
              title: Text(c.title),
              subtitle: Text(
                '修订 ${c.revisionNumber} · ${c.updatedAt.toLocal()}',
              ),
              trailing: const Icon(Icons.history),
              onTap: () => _layout.open('history/${c.id}', groupId: group),
            ),
        ],
      ),
      'relations' => RelationsView(
        controller: _controller,
        onCard: (id) => _openCard(id, group: group),
        onSource: (id) => _layout.open('source/$id', groupId: group),
      ),
      _ => const Center(child: Text('视图不可用')),
    };
  }

  @override
  Widget build(BuildContext context) {
    context.watch<AppController>();
    final preferences = context.watch<AppPreferences?>();
    if (!_loaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (preferences != null && preferences.desktopPreset == null) {
      return Scaffold(
        body: Center(
          child: SizedBox(
            width: 600,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '选择你的工作台',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 12),
                const Text('两种布局使用同一份资料，随时可以切换或重新选择。'),
                const SizedBox(height: 24),
                ListTile(
                  leading: const Icon(Icons.dashboard_outlined),
                  title: const Text('资料工作台'),
                  subtitle: const Text('以卡片、来源和关系为中心'),
                  onTap: () => _preset('library'),
                ),
                ListTile(
                  leading: const Icon(Icons.auto_awesome_outlined),
                  title: const Text('助手工作台'),
                  subtitle: const Text('从对话开始，整理资料并核对建议'),
                  onTap: () => _preset('assistant'),
                ),
              ],
            ),
          ),
        ),
      );
    }
    final surface = DockSurface(
      layout: _layout,
      dragging: _dragging,
      builder: _view,
      label: _label,
      icon: _icon,
    );
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(
          LogicalKeyboardKey.keyP,
          control: true,
          shift: true,
        ): _commands,
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          appBar: AppBar(
            leading: const Center(child: LiveRelayLogo(size: 28)),
            title: const Text('留灯 · 工作台'),
            toolbarHeight: 48,
            actions: [
              IconButton(
                tooltip: '命令面板 · Ctrl+Shift+P',
                onPressed: _commands,
                icon: const Icon(Icons.terminal),
              ),
              TextButton(
                onPressed: () => _preset('library'),
                child: const Text('资料'),
              ),
              TextButton(
                onPressed: () => _preset('assistant'),
                child: const Text('助手'),
              ),
              PopupMenuButton<String>(
                tooltip: '工作台布局',
                onSelected: (v) => _action(() async {
                  if (v == 'choose') {
                    await preferences?.setDesktopPreset(null);
                  } else {
                    await _preset(preferences?.desktopPreset ?? 'library');
                  }
                }),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'reset', child: Text('恢复默认布局')),
                  PopupMenuItem(value: 'choose', child: Text('重新选择起始工作台')),
                ],
              ),
              IconButton(
                tooltip: '保存并锁定',
                icon: const Icon(Icons.lock_outline),
                onPressed: _controller.isBusy
                    ? null
                    : () => _action(() async {
                        await _runtime.saveAndLock();
                      }),
              ),
            ],
          ),
          body: Column(
            children: [
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      width: 52,
                      child: SingleChildScrollView(
                        child: Column(
                          children: [
                            for (final view in [
                              ..._views,
                              ..._extensions.views.keys,
                            ])
                              surface.draggable(
                                view,
                                IconButton(
                                  tooltip: _label(view),
                                  icon: Icon(_icon(view)),
                                  onPressed: () => _layout.open(view),
                                ),
                              ),
                            DragTarget<String>(
                              onAcceptWithDetails: (d) => _layout.move(
                                d.data,
                                '',
                                DockPlacement.floating,
                              ),
                              builder: (context, candidates, _) => Container(
                                color: candidates.isNotEmpty
                                    ? Theme.of(context)
                                          .colorScheme
                                          .primaryContainer
                                    : null,
                                child: const Padding(
                                  padding: EdgeInsets.all(12),
                                  child: Tooltip(
                                    message: '拖到这里在工作台内浮动',
                                    child: Icon(Icons.picture_in_picture_alt),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const VerticalDivider(width: 1),
                    Expanded(child: surface),
                  ],
                ),
              ),
              Container(
                height: 28,
                color: Theme.of(context).colorScheme.surfaceContainerLow,
                child: Row(
                  children: [
                    const SizedBox(width: 12),
                    const Icon(Icons.lock, size: 13),
                    const SizedBox(width: 6),
                    const Text('本地加密资料库', style: TextStyle(fontSize: 11)),
                    const Spacer(),
                    if (_layoutError != null)
                      TextButton(
                        onPressed: _persistLayout,
                        child: Text(
                          _layoutError!,
                          style: const TextStyle(fontSize: 11),
                        ),
                      ),
                    ListenableBuilder(
                      listenable: _edits,
                      builder: (context, _) => Text(
                        _edits.hasUnsaved ? '有修改正在保存或需要处理' : '修改已保存',
                        style: const TextStyle(fontSize: 11),
                      ),
                    ),
                    const SizedBox(width: 12),
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
