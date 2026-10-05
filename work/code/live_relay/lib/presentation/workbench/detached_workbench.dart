import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import '../../infrastructure/desktop_window_channel.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:window_manager/window_manager.dart';

import '../../application/workbench/window_projection.dart';

/// Called before constructing any vault services. No AppController, repository,
/// secure storage, vault paths or cryptographic keys exist in this engine.
Future<bool> runDetachedWorkbench(List<String> arguments) async {
  if (!Platform.isLinux || arguments.firstOrNull != '--liverelay-workbench') {
    return false;
  }
  final args = jsonDecode(arguments[1]) as Map;
  if (args['type'] != 'liverelay.workbench' ||
      args['version'] != 1 ||
      args['socket'] is! String ||
      args['nonce'] is! String) {
    throw const FormatException('窗口配置无效');
  }
  final channel = await LocalWindowChannel.connect(args);
  await windowManager.ensureInitialized();
  await windowManager.setTitle('LiveRelay · 独立工作台');
  await windowManager.setMinimumSize(const Size(400, 280));
  final b = windowBounds(args['bounds']);
  if (b != null) {
    await windowManager.setBounds(
      Rect.fromLTWH(b['x']!, b['y']!, b['width']!, b['height']!),
    );
  } else {
    await windowManager.setSize(const Size(800, 650));
  }
  await windowManager.setPreventClose(true);
  runApp(
    DetachedWorkbench(
      channel: channel,
      diagnostics: kDebugMode && args['diagnostics'] == true,
    ),
  );
  return true;
}

class DetachedWorkbench extends StatefulWidget {
  const DetachedWorkbench({
    super.key,
    required this.channel,
    this.diagnostics = false,
  });
  final LocalWindowChannel channel;
  final bool diagnostics;
  @override
  State<DetachedWorkbench> createState() => _DetachedWorkbenchState();
}

class _DetachedWorkbenchState extends State<DetachedWorkbench>
    with WindowListener {
  Map _data = {};
  String? _error;
  bool _revoked = false, _closing = false;
  int _request = 0, _applied = -1, _pending = 0;
  Timer? _geometryTimer, _heartbeat;
  Future<void> _commands = Future.value();
  final _boundary = GlobalKey();
  BuildContext? _dialogContext;
  List<Map> get _cards => (_data['cards'] as List? ?? []).cast<Map>();
  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    try {
      await widget.channel.setMethodCallHandler((call) async {
        switch (call.method) {
          case 'show':
            await windowManager.show();
            return true;
          case 'hide':
            await windowManager.hide();
            return true;
          case 'invalidate':
            if (_pending == 0) unawaited(_pull());
            return true;
          case 'revoke':
            if (_closing) return true;
            _closing = true;
            _clear();
            unawaited(
              Future<void>.delayed(
                const Duration(milliseconds: 100),
                () => exit(0),
              ),
            );
            return true;
          case 'prepareClose':
            await _commands;
            if (!_revoked) {
              await widget.channel.invokeMethod('geometry', await _bounds());
            }
            return true;
          case 'inspect':
            if (!widget.diagnostics) throw StateError('诊断未启用');
            return {
              'view': _data['view'],
              'cards': _cards,
              'revoked': _revoked,
              'bounds': await _bounds(),
              'vaultOwner': false,
            };
          case 'diagnosticCommand':
            if (!widget.diagnostics) throw StateError('诊断未启用');
            final args = call.arguments as Map;
            await _act(
              args['method'] as String,
              Map<String, Object?>.from(args['arguments'] as Map),
            );
            return true;
          case 'diagnosticMove':
            if (!widget.diagnostics) throw StateError('诊断未启用');
            final b = windowBounds(call.arguments)!;
            await windowManager.setBounds(
              Rect.fromLTWH(b['x']!, b['y']!, b['width']!, b['height']!),
            );
            return true;
          case 'diagnosticClose':
            if (!widget.diagnostics) throw StateError('诊断未启用');
            unawaited(
              Future<void>.delayed(
                const Duration(milliseconds: 100),
                () => windowManager.close(),
              ),
            );
            return true;
          case 'capture':
            if (!widget.diagnostics || _revoked) throw StateError('诊断未启用');
            WidgetsBinding.instance.scheduleFrame();
            await WidgetsBinding.instance.endOfFrame;
            await WidgetsBinding.instance.endOfFrame;
            final render =
                _boundary.currentContext!.findRenderObject()
                    as RenderRepaintBoundary;
            final image = await render.toImage();
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            image.dispose();
            return bytes!.buffer.asUint8List();
          default:
            throw StateError('不支持的窗口命令');
        }
      });
      await _pull();
      _heartbeat = Timer.periodic(const Duration(seconds: 2), (_) async {
        try {
          await widget.channel
              .invokeMethod('health')
              .timeout(const Duration(seconds: 2));
        } on Object {
          _clear();
        }
      });
    } on Object {
      _clear();
    }
  }

  void _wipeBytes() {
    final bytes = _data['sourceBytes'];
    if (bytes is Uint8List) bytes.fillRange(0, bytes.length, 0);
  }

  void _clear() {
    _heartbeat?.cancel();
    _geometryTimer?.cancel();
    _wipeBytes();
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
    _data = {};
    _revoked = true;
    _request++;
    if (mounted) setState(() {});
  }

  Future<void> _pull() async {
    if (_revoked || !mounted) return;
    final request = ++_request;
    try {
      final data = await widget.channel.invokeMethod<Map>('snapshot');
      if (!mounted ||
          _revoked ||
          _pending > 0 ||
          request < _applied ||
          data == null) {
        final bytes = data?['sourceBytes'];
        if (bytes is Uint8List) bytes.fillRange(0, bytes.length, 0);
        return;
      }
      _applied = request;
      _wipeBytes();
      setState(() => _data = data);
    } on Object {
      _clear();
    }
  }

  Future<void> _act(String method, [Map<String, Object?> args = const {}]) {
    if (_revoked) return Future.value();
    _pending++;
    final next = _commands.then((_) async {
      if (_revoked || !mounted) return;
      try {
        await widget.channel.invokeMethod(method, args);
        if (mounted && !_revoked) setState(() => _error = null);
      } on Object {
        if (mounted && !_revoked) setState(() => _error = '操作未完成，请重试；修改不会自动确认');
      }
    });
    _commands = next.whenComplete(() async {
      _pending--;
      if (_pending == 0) await _pull();
    });
    return _commands;
  }

  Future<Map<String, double>> _bounds() async {
    final b = await windowManager.getBounds();
    return {'x': b.left, 'y': b.top, 'width': b.width, 'height': b.height};
  }

  void _geometry() {
    if (_revoked) return;
    _geometryTimer?.cancel();
    _geometryTimer = Timer(const Duration(milliseconds: 400), () async {
      if (!_revoked) await _act('geometry', await _bounds());
    });
  }

  @override
  void onWindowMove() => _geometry();
  @override
  void onWindowResize() => _geometry();
  @override
  void onWindowClose() => unawaited(_close());
  Future<void> _close() async {
    if (_closing) return;
    _closing = true;
    try {
      if (!_revoked) {
        await _commands;
        await widget.channel.invokeMethod('geometry', await _bounds());
        await widget.channel.invokeMethod('close');
      }
      _clear();
      exit(0);
    } on Object {
      _closing = false;
      if (mounted) setState(() => _error = '关闭已取消，请保存成功后重试');
    }
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    _heartbeat?.cancel();
    _geometryTimer?.cancel();
    _wipeBytes();
    unawaited(widget.channel.setMethodCallHandler(null));
    super.dispose();
  }

  void _navigate(String view) => unawaited(_act('navigate', {'view': view}));
  Future<void> _delete(Map card) async {
    final allowed = await showDialog<bool>(
      context: _dialogContext!,
      builder: (context) => AlertDialog(
        title: const Text('回收当前卡片？'),
        content: Text('“${card['title']}”将进入回收站。原件和修订保留。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确认回收'),
          ),
        ],
      ),
    );
    if (allowed == true) await _act('delete', {'id': card['id']});
  }

  Widget _field(
    String key,
    String value,
    String label,
    ValueChanged<String> changed, {
    bool multiline = false,
  }) => _RemoteTextField(
    key: ValueKey(key),
    value: value,
    label: label,
    onChanged: changed,
    multiline: multiline,
  );
  Widget _editor(Map c) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                '${c['status'] == 'draft' ? '待确认' : '已确认'} · ${switch (c['saveState']) {
                  'pending' => '等待保存',
                  'saving' => '正在保存',
                  'failed' => '保存失败',
                  _ => '已保存',
                }}',
              ),
              if (c['status'] == 'draft')
                IconButton(
                  tooltip: '确认当前卡片',
                  icon: const Icon(Icons.check),
                  onPressed: () => _act('confirm', {'id': c['id']}),
                ),
              IconButton(
                tooltip: '删除当前卡片',
                icon: const Icon(Icons.close),
                onPressed: () => _delete(c),
              ),
              IconButton(
                tooltip: '修订历史',
                icon: const Icon(Icons.history),
                onPressed: () => _navigate('history/${c['id']}'),
              ),
              TextButton(
                onPressed: () => _act('flush'),
                child: const Text('重试保存'),
              ),
            ],
          ),
          for (final f in ['title', 'content', 'tags'])
            _field(
              '${c['id']}/$f',
              c[f] as String,
              {'title': '标题', 'content': '总结', 'tags': '标签'}[f]!,
              (v) => _act('edit', {'id': c['id'], 'field': f, 'text': v}),
              multiline: f == 'content',
            ),
          const SizedBox(height: 12),
          const Text('来源'),
          for (final s
              in (_data['sources'] as Map? ?? {})[c['id']] as List? ?? [])
            s['id'] != null
                ? TextButton(
                    onPressed: () => _navigate('source/${s['id']}'),
                    child: Text(s['label'] as String),
                  )
                : SelectableText(s['text'] as String),
          const SizedBox(height: 12),
          const Text('出链 / 入链'),
          for (final r in (_data['references'] as List? ?? []))
            if (r['from'] == c['id'] || r['to'] == c['id'])
              TextButton(
                onPressed: () => _navigate(
                  'card/${r['from'] == c['id'] ? r['to'] : r['from']}',
                ),
                child: Text(
                  '${r['from'] == c['id'] ? '引用' : '被引用'}：${(_data['titles'] as Map)[r['from'] == c['id'] ? r['to'] : r['from']]}',
                ),
              ),
        ],
      ),
    ),
  );
  Widget _agent() => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      Text('${_data['model']} · 与主工作台共享会话'),
      for (final m in _data['messages'] as List? ?? []) ...[
        Text(
          m['role'] == 'user' ? '我' : '助手',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        SelectableText(m['text'] as String),
        for (var i = 0; i < (m['suggestions'] as List).length; i++) ...[
          for (final f in ['title', 'content'])
            _field(
              '${m['reviewId']}/$i/$f',
              m['suggestions'][i][f] as String,
              f == 'title' ? '建议标题' : '建议总结',
              (v) => _act('editSuggestion', {
                'reviewId': m['reviewId'],
                'index': i,
                'field': f,
                'text': v,
              }),
              multiline: f == 'content',
            ),
        ],
        if ((m['suggestions'] as List).isNotEmpty)
          FilledButton(
            onPressed: m['accepted'] == true || _data['working'] == true
                ? null
                : () => _act('accept', {'reviewId': m['reviewId']}),
            child: Text(m['accepted'] == true ? '已确认保存' : '确认建议并保存'),
          ),
        const Divider(),
      ],
      _field(
        'agent/draft',
        _data['draft'] as String? ?? '',
        '给助手的消息',
        (v) => _act('draft', {'text': v}),
        multiline: true,
      ),
      FilledButton(
        onPressed: _data['working'] == true ? null : () => _act('send'),
        child: const Text('发送（主窗口核对范围）'),
      ),
      if (_data['error'] != null) Text(_data['error'] as String),
    ],
  );
  Widget _body() {
    final view = _data['view'] as String? ?? '';
    if (view == 'agent') return _agent();
    if (view == 'originals') {
      return ListView(
        children: [
          for (final b in _data['originals'] as List? ?? [])
            ListTile(
              title: Text(b['name'] as String),
              subtitle: Text('${b['size']} 字节'),
              onTap: () => _navigate('source/${b['id']}'),
            ),
        ],
      );
    }
    if (view.startsWith('source/')) {
      final source = _data['source'] as Map?;
      if (source == null) return const Center(child: Text('原件已回收或不存在'));
      final bytes = _data['sourceBytes'];
      return ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(source['name'] as String),
          if (bytes is Uint8List && source['kind'] == 'image')
            Image.memory(bytes)
          else if (bytes is Uint8List &&
              source['mime']?.startsWith('text/') == true)
            SelectableText(utf8.decode(bytes, allowMalformed: true))
          else
            const Text('此媒体请合并回主工作台播放或查看。'),
        ],
      );
    }
    if (view.startsWith('history/')) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          for (final r in _data['history'] as List? ?? [])
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('修订 ${r['number']} · ${r['title']}'),
                    SelectableText(r['content'] as String),
                    Text(r['note'] as String),
                    TextButton(
                      onPressed: () => _act('restoreRevision', {
                        'id': _cards.first['id'],
                        'number': r['number'],
                      }),
                      child: const Text('恢复为新修订'),
                    ),
                  ],
                ),
              ),
            ),
        ],
      );
    }
    if (view == 'changes') {
      return ListView(
        children: [
          for (final c in _cards)
            ListTile(
              title: Text(c['title'] as String),
              subtitle: Text('修订 ${c['revision']}'),
              onTap: () => _navigate('history/${c['id']}'),
            ),
        ],
      );
    }
    if (view == 'relations') {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('真实引用与来源关系'),
          for (final r in _data['references'] as List? ?? [])
            ListTile(
              title: Text(
                '${(_data['titles'] as Map)[r['from']]} → ${(_data['titles'] as Map)[r['to']]}',
              ),
              onTap: () => _navigate('card/${r['to']}'),
            ),
          for (final c in _cards)
            for (final s in (_data['sources'] as Map)[c['id']] as List)
              if (s['id'] != null)
                ListTile(
                  title: Text('${c['title']} → ${s['label']}'),
                  onTap: () => _navigate('source/${s['id']}'),
                ),
        ],
      );
    }
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [for (final c in _cards) _editor(c)],
    );
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    theme: ThemeData(
      useMaterial3: true,
      colorSchemeSeed: const Color(0xff7655aa),
    ),
    home: Builder(
      builder: (context) {
        _dialogContext = context;
        return Scaffold(
          appBar: AppBar(
            title: const Text('LiveRelay · 独立工作台'),
            actions: [
              if (!_revoked)
                TextButton(onPressed: _close, child: const Text('合并回主工作台')),
            ],
          ),
          body: RepaintBoundary(
            key: _boundary,
            child: ColoredBox(
              color: Colors.white,
              child: _revoked
                  ? const Center(child: Text('资料库已锁定或主窗口不可用'))
                  : _data.isEmpty
                  ? const Center(child: CircularProgressIndicator())
                  : Column(
                      children: [
                        if (_error != null)
                          Text(
                            _error!,
                            style: const TextStyle(color: Colors.red),
                          ),
                        Expanded(child: _body()),
                      ],
                    ),
            ),
          ),
        );
      },
    ),
  );
}

class _RemoteTextField extends StatefulWidget {
  const _RemoteTextField({
    super.key,
    required this.value,
    required this.label,
    required this.onChanged,
    this.multiline = false,
  });
  final String value, label;
  final ValueChanged<String> onChanged;
  final bool multiline;
  @override
  State<_RemoteTextField> createState() => _RemoteTextFieldState();
}

class _RemoteTextFieldState extends State<_RemoteTextField> {
  late final TextEditingController _text;
  @override
  void initState() {
    super.initState();
    _text = TextEditingController(text: widget.value);
  }

  @override
  void didUpdateWidget(covariant _RemoteTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_text.text != widget.value) {
      _text.value = TextEditingValue(
        text: widget.value,
        selection: TextSelection.collapsed(
          offset: _text.selection.extentOffset.clamp(0, widget.value.length),
        ),
      );
    }
  }

  @override
  void dispose() {
    _text.clear();
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: TextField(
      controller: _text,
      decoration: InputDecoration(labelText: widget.label),
      minLines: widget.multiline ? 3 : 1,
      maxLines: widget.multiline ? null : 1,
      onChanged: widget.onChanged,
    ),
  );
}
