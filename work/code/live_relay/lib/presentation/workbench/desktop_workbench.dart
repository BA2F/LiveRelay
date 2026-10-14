import 'dart:async';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';

import '../controllers/app_controller.dart';
import 'state/card_edit_sessions.dart';
import 'state/workbench_tabs.dart';
import 'state/extension_registry.dart';
import 'workbench_right_panel.dart';
import '../../core/domain/entities.dart';
import '../controllers/agent_conversation.dart';
import '../model_labels.dart';
import '../dialogs/card_dialogs.dart';
import '../dialogs/credential_dialogs.dart';
import '../widgets/credential_secret_actions.dart';
import '../widgets/liverelay_logo.dart';
import '../pages/handoff_page.dart';
import '../pages/identity_page.dart';
import '../pages/profile_page.dart';
import '../pages/speech_input_page.dart';
import 'conversation_view.dart';
import 'extensions_view.dart';
import 'relations_view.dart';
import 'review_source_view.dart';
import 'workbench_card_editor.dart';
import 'workbench_runtime.dart';
import 'workbench_sidebar.dart';
import 'workbench_tab_strip.dart';

class DesktopWorkbench extends StatefulWidget {
  const DesktopWorkbench({super.key});
  @override
  State<DesktopWorkbench> createState() => _DesktopWorkbenchState();
}

class _DesktopWorkbenchState extends State<DesktopWorkbench> {
  late final AppController _controller;
  late final WorkbenchRuntime _runtime;
  WorkbenchTabs get _tabs => _runtime.tabs;
  CardEditSessions get _edits => _runtime.edits;
  ExtensionRegistry get _extensions => _runtime.extensions;
  AgentConversation get _conversation => _runtime.conversation;
  late final AppLifecycleListener _lifecycle;
  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  bool get _loaded => _runtime.loaded;

  @override
  void initState() {
    super.initState();
    _controller = context.read<AppController>();
    _runtime = WorkbenchRuntime(_controller);
    _runtime.addListener(_runtimeChanged);
    _lifecycle = AppLifecycleListener(onExitRequested: _requestExit);
    unawaited(_runtime.load());
  }

  void _runtimeChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _runtime.removeListener(_runtimeChanged);
    _runtime.dispose();
    _lifecycle.dispose();
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  // ---- 通用动作 ----

  void _snack(String message) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message)));

  Future<void> _action(Future<void> Function() operation) async {
    try {
      await operation();
    } on Object catch (e) {
      if (mounted) {
        _snack(
          e is FormatException
              ? e.message
              : _controller.lastError ?? '操作失败，请重试',
        );
      }
    }
  }

  Future<AppExitResponse> _requestExit() async {
    final response = await _runtime.requestExit();
    if (mounted && _runtime.exitError != null) _snack(_runtime.exitError!);
    return response;
  }

  Future<String?> _menuAt(Offset position, List<(String, String)> entries) async {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        position & const Size(1, 1),
        Offset.zero & overlay.size,
      ),
      items: [
        for (final entry in entries)
          PopupMenuItem(value: entry.$1, child: Text(entry.$2)),
      ],
    );
    if (!mounted) return null;
    return selected;
  }

  // ---- 打开与创建 ----

  void _open(String view) => _tabs.open(view);
  void _openCard(String id) => _tabs.open('card/$id');
  static String _segment(String view) => view.split('/')[1];
  LifeCard? _card(String id) =>
      _controller.cards.where((c) => c.id == id).firstOrNull;

  Future<void> _newCard() => _action(() async {
    final existing = _controller.cards.map((c) => c.id).toSet();
    await _controller.createCard(
      const CardDraft(
        title: '新卡片',
        content: '在这里填写总结',
        status: CardStatus.draft,
      ),
    );
    _openCard(_controller.cards.firstWhere((c) => !existing.contains(c.id)).id);
  });

  Future<void> _import() => _action(() async {
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
      _openCard(card.id);
    }
  });

  // ---- 移入回收与恢复 ----

  /// 移入回收区是可撤销动作：直接做，给撤销，不弹确认框。
  /// 原件不随卡片走：卡片移入回收区只影响卡片本身。
  Future<void> _deleteCards(List<LifeCard> cards) => _action(() async {
    await _edits.flush();
    if (_edits.hasUnsaved) throw const FormatException('请先处理未保存的修改');
    await _controller.trashCards(cards.map((c) => c.id).toList());
    for (final card in cards) {
      _tabs.close('card/${card.id}');
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          cards.length == 1
              ? '已移入回收区：${cards.single.title}'
              : '已把 ${cards.length} 张卡片移入回收区',
        ),
        action: SnackBarAction(
          label: '撤销',
          onPressed: () => unawaited(
            _action(() async {
              for (final card in cards) {
                await _controller.restoreCard(card.id);
              }
              if (mounted) _snack('已撤销，卡片已恢复');
            }),
          ),
        ),
      ),
    );
  });

  Future<void> _trashCredential(CredentialEntry entry) => _action(() async {
    await _controller.trashCredential(entry.id);
    _tabs.close('credential/${entry.id}');
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已移入回收区：${entry.title}'),
        action: SnackBarAction(
          label: '撤销',
          onPressed: () =>
              unawaited(_action(() => _controller.restoreCredential(entry.id))),
        ),
      ),
    );
  });

  // ---- 标签操作 ----

  Future<void> _closeTab(String view) async {
    final session = view.startsWith('card/')
        ? _edits.values
              .where((s) => s.card.id == _segment(view))
              .firstOrNull
        : null;
    if (session != null && session.state != CardSaveState.saved) {
      await _action(() => _edits.flush());
      if (!mounted) return;
      if (session.state != CardSaveState.saved) {
        _snack('还有修改没有保存，标签保持打开');
        return;
      }
    }
    _tabs.close(view);
  }

  Future<void> _closeAllTabs({String? except}) async {
    if (_edits.hasUnsaved) {
      await _action(() => _edits.flush());
      if (!mounted || _edits.hasUnsaved) {
        _snack('还有修改没有保存，标签保持打开');
        return;
      }
    }
    if (except == null) {
      _tabs.closeAll();
    } else {
      _tabs.closeOthers(except);
    }
  }

  Future<void> _tabMenu(String view, Offset position) async {
    final selection = await _menuAt(position, const [
      ('close', '关闭标签'),
      ('others', '关闭其他标签'),
      ('all', '关闭全部标签'),
    ]);
    switch (selection) {
      case 'close':
        await _closeTab(view);
      case 'others':
        await _closeAllTabs(except: view);
      case 'all':
        await _closeAllTabs();
    }
  }

  // ---- 右键菜单 ----

  Future<void> _rowMenu(
    WorkbenchRowKind kind,
    String id,
    Offset position,
  ) async {
    final card = _card(id);
    final selection = await _menuAt(position, switch (kind) {
      WorkbenchRowKind.card => [
        ('open', '打开'),
        if (card?.status == CardStatus.draft) ('confirm', '确认卡片'),
        ('trash', '移入回收区'),
      ],
      WorkbenchRowKind.original => [
        ('open', '查看原件'),
        ('copy-name', '复制文件名'),
      ],
      WorkbenchRowKind.credential => [('open', '打开'), ('trash', '移入回收区')],
      WorkbenchRowKind.recycledCard => [
        ('details', '查看详情'),
        ('restore', '恢复卡片'),
      ],
      WorkbenchRowKind.recycledCredential => [
        ('details', '查看详情'),
        ('restore', '恢复密码'),
      ],
    });
    if (selection == null || !mounted) return;
    switch (selection) {
      case 'open':
        switch (kind) {
          case WorkbenchRowKind.card:
            _openCard(id);
          case WorkbenchRowKind.original:
            _open('source/$id');
          case WorkbenchRowKind.credential:
            _open('credential/$id');
          case WorkbenchRowKind.recycledCard:
          case WorkbenchRowKind.recycledCredential:
            break;
        }
      case 'copy-name':
        final name = _controller.blobs
            .where((b) => b.id == id)
            .firstOrNull
            ?.originalName;
        if (name != null) {
          await Clipboard.setData(ClipboardData(text: name));
          if (mounted) _snack('已复制文件名');
        }
      case 'confirm':
        await _action(() => _controller.confirmCard(id));
      case 'trash':
        switch (kind) {
          case WorkbenchRowKind.card:
            if (card != null) await _deleteCards([card]);
          case WorkbenchRowKind.credential:
            final entry = _controller.credentials
                .where((c) => c.id == id)
                .firstOrNull;
            if (entry != null) await _trashCredential(entry);
          case WorkbenchRowKind.original:
          case WorkbenchRowKind.recycledCard:
          case WorkbenchRowKind.recycledCredential:
            break;
        }
      case 'restore':
        switch (kind) {
          case WorkbenchRowKind.recycledCard:
            await _action(() => _controller.restoreCard(id));
            if (mounted) _snack('已恢复卡片');
          case WorkbenchRowKind.recycledCredential:
            await _action(() => _controller.restoreCredential(id));
            if (mounted) _snack('已恢复密码');
          case WorkbenchRowKind.card:
          case WorkbenchRowKind.original:
          case WorkbenchRowKind.credential:
            break;
        }
      case 'details':
        if (!mounted) return;
        switch (kind) {
          case WorkbenchRowKind.recycledCard:
            final recycled = _controller.recycledCards
                .where((c) => c.id == id)
                .firstOrNull;
            if (recycled != null) {
              await showCardDetails(context, _controller, recycled);
            }
          case WorkbenchRowKind.recycledCredential:
            final recycled = _controller.recycledCredentials
                .where((c) => c.id == id)
                .firstOrNull;
            if (recycled != null) {
              await showCredentialDetails(context, _controller, recycled);
            }
          case WorkbenchRowKind.card:
          case WorkbenchRowKind.original:
          case WorkbenchRowKind.credential:
            break;
        }
    }
  }

  Future<void> _editorMenu(LifeCard card, Offset position) async {
    final selection = await _menuAt(position, const [
      ('save', '立即保存 (Ctrl+S)'),
      ('history', '修订历史'),
      ('relations', '关系图'),
      ('trash', '移入回收区'),
    ]);
    switch (selection) {
      case 'save':
        await _action(() => _edits.flush());
        if (mounted && !_edits.hasUnsaved) _snack('修改已保存');
      case 'history':
        _open('history/${card.id}');
      case 'relations':
        _open('relations');
      case 'trash':
        await _deleteCards([card]);
    }
  }

  // ---- 快捷键与快速打开 ----

  Future<void> _saveNow() => _action(() async {
    final had = _edits.hasUnsaved;
    await _runtime.flush();
    if (mounted && had) _snack('修改已保存');
  });

  void _toggleSidebar() => _tabs.setCollapsed(!_tabs.collapsed);

  void _toggleRightPanel() =>
      _tabs.setRightCollapsed(!_tabs.rightCollapsed);

  void _focusSearch() {
    if (_tabs.collapsed) _tabs.setCollapsed(false);
    _search.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _search.text.length,
    );
    _searchFocus.requestFocus();
  }

  Future<void> _quickOpen() async {
    final selected = await showDialog<String>(
      context: context,
      builder: (dialogContext) =>
          _QuickOpenDialog(cards: (query) => _controller.findCards(query)),
    );
    if (selected != null && mounted) _openCard(selected);
  }

  // ---- 视图 ----

  String _label(String view) {
    if (view.startsWith('extension/')) {
      return _extensions.views[view]?.title ?? '扩展视图';
    }
    if (view.startsWith('card/') ||
        view.startsWith('history/') ||
        view.startsWith('review/')) {
      final title = _card(_segment(view))?.title ?? '卡片';
      return switch (view.split('/').first) {
        'history' => '修订历史 · $title',
        'review' => '确认来源 · $title',
        _ => title,
      };
    }
    if (view.startsWith('source/')) {
      return _controller.blobs
              .where((b) => b.id == _segment(view))
              .firstOrNull
              ?.originalName ??
          '原件';
    }
    if (view.startsWith('credential/')) {
      return _controller.credentials
              .where((c) => c.id == _segment(view))
              .firstOrNull
              ?.title ??
          '密码';
    }
    return switch (view) {
      'agent' => '助手',
      'speech' => '语音输入',
      'settings' => '设置',
      'handoff' => '交接准备',
      'relations' => '关系图',
      'extensions' => '扩展',
      _ => '标签页',
    };
  }

  IconData _icon(String view) => switch (view.split('/').first) {
    'card' => Icons.description_outlined,
    'history' => Icons.history,
    'review' => Icons.fact_check_outlined,
    'source' => Icons.attach_file,
    'credential' => Icons.key_outlined,
    'extension' => Icons.extension_outlined,
    _ => switch (view) {
      'agent' => Icons.auto_awesome_outlined,
      'speech' => Icons.mic_none,
      'settings' => Icons.settings_outlined,
      'handoff' => Icons.how_to_reg_outlined,
      'relations' => Icons.hub_outlined,
      'extensions' => Icons.extension_outlined,
      _ => Icons.tab,
    },
  };

  Widget _missing(String message) => Center(child: Text(message));

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
                              if (_card(id) == null) {
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

  Widget _editor(LifeCard card) => WorkbenchCardEditor(
    key: ValueKey(card.id),
    card: card,
    controller: _controller,
    edits: _edits,
    onHistory: () => _open('history/${card.id}'),
    onReviewSource: () => _open('review/${card.id}'),
    onRelations: () => _open('relations'),
    onSource: (id) => _open('source/$id'),
    onCard: _openCard,
    onDelete: () => _deleteCards([card]),
  );

  Widget _view(String view) {
    if (view.startsWith('extension/')) {
      return ContributedCardsView(
        registry: _extensions,
        viewId: view,
        controller: _controller,
        onOpen: _openCard,
      );
    }
    if (view.startsWith('card/')) {
      final card = _card(_segment(view));
      if (card == null) return _missing('卡片已移入回收区');
      return GestureDetector(
        onSecondaryTapDown: (details) =>
            _editorMenu(card, details.globalPosition),
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [_editor(card)],
        ),
      );
    }
    if (view.startsWith('history/')) return _history(_segment(view));
    if (view.startsWith('review/')) {
      return ReviewSourceView(
        key: ValueKey(view),
        session: _controller,
        loadSource: _controller.cardReviewSource,
        cardTitle: (id) => _card(id)?.title ?? '目标已失效',
        cardId: _segment(view),
        onCard: _openCard,
        onOriginal: (id) => _open('source/$id'),
      );
    }
    if (view.startsWith('source/')) {
      return ListView(
        padding: const EdgeInsets.all(20),
        children: [
          InlineOriginal(controller: _controller, blobId: _segment(view)),
        ],
      );
    }
    if (view.startsWith('credential/')) {
      final entry = _controller.credentials
          .where((c) => c.id == _segment(view))
          .firstOrNull;
      if (entry == null) return _missing('密码已移入回收区');
      return _CredentialTab(
        controller: _controller,
        entry: entry,
        onTrash: () => _trashCredential(entry),
      );
    }
    return switch (view) {
      'agent' => ConversationView(
        conversation: _conversation,
        openManual: () => unawaited(_newCard()),
        openSpeech: () => _open('speech'),
      ),
      'speech' => SpeechInputPage(
        onTranscript: (text) {
          _conversation.updateDraft(
            _conversation.draft.isEmpty
                ? text
                : '${_conversation.draft}\n$text',
          );
          _open('agent');
        },
      ),
      'settings' => ProfilePage(onOpenExtensions: () => _open('extensions')),
      'handoff' => const HandoffPage(),
      'relations' => RelationsView(
        controller: _controller,
        onCard: _openCard,
        onSource: (id) => _open('source/$id'),
      ),
      'extensions' => ExtensionsView(registry: _extensions, onOpen: _open),
      _ => _missing('视图不可用'),
    };
  }

  // ---- 框架 ----

  Widget _emptyTabs() => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.tab_outlined,
          size: 40,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        const SizedBox(height: 12),
        Text('没有打开的标签', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 6),
        Text(
          '从左侧选择内容，或用 Ctrl+P 按标题打开卡片',
          style: TextStyle(
            fontSize: 13,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    ),
  );

  Widget _saveStatus() {
    final states = _edits.values.map((s) => s.state).toSet();
    if (states.contains(CardSaveState.failed)) {
      return TextButton(
        onPressed: () => _action(() => _edits.flush()),
        child: const Text('保存失败，点击重试', style: TextStyle(fontSize: 11)),
      );
    }
    final label = states.contains(CardSaveState.saving)
        ? '正在保存…'
        : states.contains(CardSaveState.pending)
        ? '待保存…'
        : '修改已保存';
    return Text(label, style: const TextStyle(fontSize: 11));
  }

  Widget _statusBar() => Container(
    height: 28,
    color: Theme.of(context).colorScheme.surfaceContainerLow,
    padding: const EdgeInsets.only(left: 12, right: 4),
    child: Row(
      children: [
        const Icon(Icons.lock, size: 13),
        const SizedBox(width: 6),
        const Text('本地加密资料库', style: TextStyle(fontSize: 11)),
        const Spacer(),
        if (_runtime.notice != null)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Text(
              _runtime.notice!,
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        if (_runtime.persistError != null)
          TextButton(
            onPressed: () => _action(() => _runtime.persistTabs()),
            child: Text(
              _runtime.persistError!,
              style: const TextStyle(fontSize: 11),
            ),
          ),
        ListenableBuilder(
          listenable: _edits,
          builder: (context, _) => _saveStatus(),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    context.watch<AppController>();
    if (!_loaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final tabs = _tabs;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyN, control: true):
            () => unawaited(_newCard()),
        const SingleActivator(LogicalKeyboardKey.keyF, control: true):
            _focusSearch,
        const SingleActivator(LogicalKeyboardKey.keyP, control: true):
            () => unawaited(_quickOpen()),
        const SingleActivator(LogicalKeyboardKey.keyS, control: true):
            () => unawaited(_saveNow()),
        const SingleActivator(LogicalKeyboardKey.keyW, control: true): () {
          final active = tabs.active;
          if (active != null) unawaited(_closeTab(active));
        },
        const SingleActivator(LogicalKeyboardKey.keyL, control: true):
            () => unawaited(_action(() => _runtime.saveAndLock())),
        const SingleActivator(LogicalKeyboardKey.keyB, control: true):
            _toggleSidebar,
        const SingleActivator(LogicalKeyboardKey.keyJ, control: true):
            _toggleRightPanel,
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          appBar: AppBar(
            leading: IconButton(
              tooltip: tabs.collapsed ? '展开左栏 (Ctrl+B)' : '收起左栏 (Ctrl+B)',
              icon: Icon(tabs.collapsed ? Icons.menu : Icons.menu_open),
              onPressed: _toggleSidebar,
            ),
            title: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const LiveRelayLogo(size: 24),
                const SizedBox(width: 8),
                Text('留灯 · 工作台', style: Theme.of(context).textTheme.titleSmall),
              ],
            ),
            toolbarHeight: 44,
            actions: [
              IconButton(
                tooltip: '保存并锁定 (Ctrl+L)',
                icon: const Icon(Icons.lock_outline),
                onPressed: _controller.isBusy
                    ? null
                    : () => _action(() => _runtime.saveAndLock()),
              ),
              IconButton(
                tooltip: tabs.rightCollapsed
                    ? '展开右栏 (Ctrl+J)'
                    : '收起右栏 (Ctrl+J)',
                icon: Icon(
                  tabs.rightCollapsed
                      ? Icons.view_sidebar_outlined
                      : Icons.vertical_split_outlined,
                ),
                onPressed: _toggleRightPanel,
              ),
              PopupMenuButton<String>(
                tooltip: '更多',
                onSelected: (value) => switch (value) {
                  'handoff' => _open('handoff'),
                  'identity' => Navigator.of(context).push<void>(
                    MaterialPageRoute(builder: (_) => const IdentityPage()),
                  ),
                  'settings' => _open('settings'),
                  _ => null,
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'handoff', child: Text('交接准备')),
                  PopupMenuItem(value: 'identity', child: Text('身份与接收者')),
                  PopupMenuItem(value: 'settings', child: Text('设置')),
                ],
              ),
            ],
          ),
          body: Column(
            children: [
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (!tabs.collapsed) ...[
                      SizedBox(
                        width: 288,
                        child: WorkbenchSidebar(
                          controller: _controller,
                          section: tabs.section,
                          search: _search,
                          searchFocus: _searchFocus,
                          activeView: tabs.active,
                          onSection: tabs.selectSection,
                          onOpenView: _open,
                          onNewCard: () => unawaited(_newCard()),
                          onNewCredential: () =>
                              showCredentialEditor(context, _controller),
                          onImport: () => unawaited(_import()),
                          onRowMenu: _rowMenu,
                          onRecycledCard: (card) =>
                              showCardDetails(context, _controller, card),
                          onRecycledCredential: (entry) =>
                              showCredentialDetails(context, _controller, entry),
                        ),
                      ),
                      const VerticalDivider(width: 1),
                    ],
                    Expanded(
                      child: Column(
                        children: [
                          WorkbenchTabStrip(
                            tabs: tabs.tabs,
                            active: tabs.active,
                            label: _label,
                            icon: _icon,
                            onActivate: tabs.activate,
                            onClose: (view) => unawaited(_closeTab(view)),
                            onMove: tabs.move,
                            onMenu: (view, position) =>
                                unawaited(_tabMenu(view, position)),
                          ),
                          Expanded(
                            child: tabs.active == null
                                ? _emptyTabs()
                                : _view(tabs.active!),
                          ),
                        ],
                      ),
                    ),
                    if (!tabs.rightCollapsed) ...[
                      const VerticalDivider(width: 1),
                      SizedBox(
                        width: WorkbenchRightPanel.width,
                        child: WorkbenchRightPanel(
                          controller: _controller,
                          activeView: tabs.active,
                          onOpen: _open,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              _statusBar(),
            ],
          ),
        ),
      ),
    );
  }
}

/// 按标题快速打开卡片（Ctrl+P）。控制器随对话框生命周期释放。
class _QuickOpenDialog extends StatefulWidget {
  const _QuickOpenDialog({required this.cards});
  final List<LifeCard> Function(String query) cards;
  @override
  State<_QuickOpenDialog> createState() => _QuickOpenDialogState();
}

class _QuickOpenDialogState extends State<_QuickOpenDialog> {
  final _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final matches = widget.cards(_query.text).take(50).toList();
    return Dialog(
      child: SizedBox(
        width: 520,
        height: 420,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: TextField(
                controller: _query,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: '按标题打开卡片',
                  prefixIcon: Icon(Icons.search),
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => Navigator.pop(
                  context,
                  matches.isEmpty ? null : matches.first.id,
                ),
              ),
            ),
            Expanded(
              child: matches.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('没有匹配的卡片'),
                    )
                  : ListView(
                      children: [
                        for (final card in matches)
                          ListTile(
                            dense: true,
                            leading: Icon(card.kind.icon, size: 18),
                            title: Text(card.title),
                            subtitle: Text(card.status.label),
                            onTap: () => Navigator.pop(context, card.id),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CredentialTab extends StatelessWidget {
  const _CredentialTab({
    required this.controller,
    required this.entry,
    required this.onTrash,
  });
  final AppController controller;
  final CredentialEntry entry;
  final VoidCallback onTrash;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      Row(
        children: [
          Expanded(
            child: Text(
              entry.title,
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          IconButton(
            tooltip: '编辑密码条目',
            icon: const Icon(Icons.edit_outlined),
            onPressed: controller.isBusy
                ? null
                : () => showCredentialEditor(context, controller, entry: entry),
          ),
          IconButton(
            tooltip: '移入回收区',
            icon: const Icon(Icons.delete_outline),
            onPressed: controller.isBusy ? null : onTrash,
          ),
        ],
      ),
      const SizedBox(height: 8),
      if (entry.username.isNotEmpty) Text('账号：${entry.username}'),
      if (entry.website.isNotEmpty) Text('网址：${entry.website}'),
      if (entry.tags.isNotEmpty) Text('标签：${entry.tags.join('、')}'),
      const SizedBox(height: 12),
      Text('密码', style: Theme.of(context).textTheme.titleSmall),
      CredentialSecretActions(secret: entry.secret),
      if (entry.notes.isNotEmpty) ...[
        const SizedBox(height: 12),
        Text('备注', style: Theme.of(context).textTheme.titleSmall),
        SelectableText(entry.notes),
      ],
      const SizedBox(height: 12),
      Text(
        '修订 ${entry.revisionNumber} · ${entry.updatedAt.toLocal()}',
        style: TextStyle(
          fontSize: 12,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    ],
  );
}
