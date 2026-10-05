import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../application/app_controller.dart';
import '../../application/workbench/card_edit_sessions.dart';
import '../../core/domain/entities.dart';
import '../dialogs/media_viewer.dart';
import '../widgets/local_media_preview.dart';
import 'reference_panel.dart';

class WorkbenchCardEditor extends StatefulWidget {
  const WorkbenchCardEditor({
    super.key,
    required this.card,
    required this.edits,
    required this.controller,
    required this.onHistory,
    required this.onSource,
    required this.onDelete,
    required this.onNewTab,
    required this.onCard,
    this.onReviewSource,
  });
  final LifeCard card;
  final CardEditSessions edits;
  final AppController controller;
  final VoidCallback onHistory, onNewTab, onDelete;
  final ValueChanged<String> onSource;
  final ValueChanged<String> onCard;
  final VoidCallback? onReviewSource;
  @override
  State<WorkbenchCardEditor> createState() => _WorkbenchCardEditorState();
}

class _WorkbenchCardEditorState extends State<WorkbenchCardEditor> {
  final _title = TextEditingController(),
      _content = TextEditingController(),
      _tags = TextEditingController();
  late CardEditSession _session;
  late Future<List<CardSource>> _sources;
  int? _revision;
  @override
  void initState() {
    super.initState();
    _session = widget.edits.session(widget.card);
    _sync();
    widget.edits.addListener(_sync);
    _loadSources();
  }

  void _loadSources() {
    _revision = widget.card.revisionNumber;
    _sources = widget.controller.currentCardSources(widget.card.id);
  }

  @override
  void didUpdateWidget(covariant WorkbenchCardEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_revision != widget.card.revisionNumber) _loadSources();
  }

  void _set(TextEditingController c, String value) {
    if (c.text == value) return;
    c.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(
        offset: c.selection.extentOffset.clamp(0, value.length),
      ),
    );
  }

  void _sync() {
    _set(_title, _session.title);
    _set(_content, _session.content);
    _set(_tags, _session.tags);
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.edits.removeListener(_sync);
    _title.dispose();
    _content.dispose();
    _tags.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    await widget.edits.flush();
    if (_session.state != CardSaveState.saved || !mounted) return;
    try {
      await widget.controller.confirmCard(widget.card.id);
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(widget.controller.lastError ?? '确认失败')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(_session.card.isDraft ? '待确认 · ' : '已确认 · '),
          Text(
            switch (_session.state) {
              CardSaveState.saved => '已保存',
              CardSaveState.pending => '等待保存',
              CardSaveState.saving => '正在保存…',
              CardSaveState.failed => '保存失败',
            },
            style: TextStyle(
              fontSize: 12,
              color: _session.state == CardSaveState.failed
                  ? Theme.of(context).colorScheme.error
                  : Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          if (_session.state == CardSaveState.failed)
            IconButton(
              tooltip: '重试保存',
              onPressed: () => widget.edits.flush(),
              icon: const Icon(Icons.refresh, size: 18),
            ),
          IconButton(
            tooltip: '在新标签编辑',
            onPressed: widget.onNewTab,
            icon: const Icon(Icons.open_in_new, size: 18),
          ),
          IconButton(
            tooltip: '修订历史',
            onPressed: widget.onHistory,
            icon: const Icon(Icons.history, size: 18),
          ),
          if (widget.onReviewSource != null)
            IconButton(
              tooltip: '查看确认来源',
              onPressed: widget.onReviewSource,
              icon: const Icon(Icons.fact_check_outlined, size: 18),
            ),
          if (_session.card.isDraft)
            IconButton(
              tooltip: '确认当前卡片',
              onPressed: widget.controller.isBusy ? null : _confirm,
              icon: const Icon(Icons.check, size: 20),
            ),
          IconButton(
            tooltip: '删除当前卡片',
            onPressed: widget.controller.isBusy ? null : widget.onDelete,
            icon: const Icon(Icons.close, size: 20),
          ),
        ],
      ),
      TextField(
        controller: _title,
        decoration: const InputDecoration(
          labelText: '标题',
          border: InputBorder.none,
        ),
        style: Theme.of(context).textTheme.titleLarge,
        onChanged: (v) => widget.edits.edit(_session, title: v),
      ),
      TextField(
        controller: _content,
        minLines: 2,
        maxLines: null,
        decoration: const InputDecoration(
          labelText: '总结',
          border: InputBorder.none,
          alignLabelWithHint: true,
        ),
        onChanged: (v) => widget.edits.edit(_session, content: v),
      ),
      TextField(
        controller: _tags,
        decoration: const InputDecoration(
          labelText: '标签（用逗号分隔）',
          border: InputBorder.none,
        ),
        onChanged: (v) => widget.edits.edit(_session, tags: v),
      ),
      if (_session.error != null)
        Text(
          _session.error!,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      ReferencePanel(
        controller: widget.controller,
        cardId: widget.card.id,
        onOpen: widget.onCard,
      ),
      FutureBuilder<List<CardSource>>(
        future: _sources,
        builder: (context, snapshot) {
          if (snapshot.hasError) return const Text('来源读取失败');
          final sources = snapshot.data ?? [];
          final linked = sources
              .where((s) => s.blobId != null)
              .map((s) => s.blobId!)
              .toSet();
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ExpansionTile(
                title: const Text('管理原件引用'),
                tilePadding: EdgeInsets.zero,
                children: [
                  for (final blob in widget.controller.blobs)
                    CheckboxListTile(
                      title: Text(blob.originalName),
                      subtitle:
                          widget.controller.recycledBlobIds.contains(blob.id)
                          ? const Text('引用后恢复此原件')
                          : null,
                      value: linked.contains(blob.id),
                      onChanged: widget.controller.isBusy
                          ? null
                          : (value) async {
                              final selected = Set<String>.of(linked);
                              if (value == true) {
                                selected.add(blob.id);
                              } else {
                                selected.remove(blob.id);
                              }
                              await widget.edits.flush();
                              if (widget.edits.hasUnsaved) return;
                              try {
                                await widget.controller.setCardOriginals(
                                  widget.card.id,
                                  selected.toList(),
                                );
                              } on Object {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        widget.controller.lastError ?? '引用保存失败',
                                      ),
                                    ),
                                  );
                                }
                              }
                            },
                    ),
                ],
              ),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: Text('原始资料与来源 · ${sources.length}'),
                children: [
                  for (final source in sources)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  source.label,
                                  style: Theme.of(context).textTheme.labelLarge,
                                ),
                              ),
                              if (source.blobId != null)
                                TextButton(
                                  onPressed: () =>
                                      widget.onSource(source.blobId!),
                                  child: const Text('来源标签'),
                                ),
                            ],
                          ),
                          if (source.blobId != null)
                            InlineOriginal(
                              controller: widget.controller,
                              blobId: source.blobId!,
                            )
                          else
                            SelectableText(source.excerpt),
                        ],
                      ),
                    ),
                ],
              ),
            ],
          );
        },
      ),
    ],
  );
}

class InlineOriginal extends StatefulWidget {
  const InlineOriginal({
    super.key,
    required this.controller,
    required this.blobId,
  });
  final AppController controller;
  final String blobId;
  @override
  State<InlineOriginal> createState() => _InlineOriginalState();
}

class _InlineOriginalState extends State<InlineOriginal> {
  Uint8List? _bytes;
  String? _error;
  bool _loading = false;
  bool _playInline = false;
  VaultBlob? get _blob =>
      widget.controller.blobs.where((b) => b.id == widget.blobId).firstOrNull;
  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final bytes = await widget.controller.readOriginal(widget.blobId);
      if (!mounted) {
        bytes.fillRange(0, bytes.length, 0);
        return;
      }
      _bytes?.fillRange(0, _bytes!.length, 0);
      _bytes = bytes;
    } on Object {
      _error = '原件无法读取，请检查原件补充包';
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  void dispose() {
    _bytes?.fillRange(0, _bytes!.length, 0);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final blob = _blob;
    if (blob == null) return const Text('原件不存在或尚未补齐');
    final image = blob.mediaKind == BlobMediaKind.image;
    final text =
        blob.mimeType.startsWith('text/') ||
        blob.originalName.toLowerCase().endsWith('.txt');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          leading: Icon(image ? Icons.image_outlined : Icons.attach_file),
          title: Text(blob.originalName),
          subtitle: Text('${blob.byteLength} 字节'),
          trailing: TextButton(
            onPressed: _loading
                ? null
                : image || text
                ? _load
                : Platform.isLinux &&
                      {
                        BlobMediaKind.audio,
                        BlobMediaKind.video,
                      }.contains(blob.mediaKind)
                ? () => setState(() => _playInline = !_playInline)
                : () => showEncryptedOriginal(context, widget.controller, blob),
            child: const Text('查看原件'),
          ),
        ),
        if (_playInline)
          LocalMediaPreview(
            key: ValueKey(widget.blobId),
            controller: widget.controller,
            name: blob.originalName,
            video: blob.mediaKind == BlobMediaKind.video,
            compact: true,
            readBytes: () => widget.controller.readOriginal(widget.blobId),
          ),
        if (_loading) const LinearProgressIndicator(),
        if (_error != null) Text(_error!),
        if (_bytes != null && image)
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 320),
            child: Image.memory(_bytes!, fit: BoxFit.contain),
          ),
        if (_bytes != null && text)
          SelectableText(
            utf8.decode(
              _bytes!.take(256 * 1024).toList(),
              allowMalformed: true,
            ),
          ),
        if (blob.ocrText != null)
          ExpansionTile(
            title: const Text('识别文字'),
            children: [SelectableText(blob.ocrText!)],
          ),
      ],
    );
  }
}
