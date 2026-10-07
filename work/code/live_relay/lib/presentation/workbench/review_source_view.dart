import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../application/preview_session.dart';
import '../../core/ai/conversation_attachment.dart';
import '../../core/ai/review_source.dart';
import '../widgets/local_media_preview.dart';
import '../widgets/local_pdf_preview.dart';
import 'review_actions_editor.dart';

class ReviewSourceView extends StatefulWidget {
  const ReviewSourceView({
    super.key,
    required this.session,
    required this.loadSource,
    required this.cardTitle,
    required this.cardId,
    required this.onCard,
    required this.onOriginal,
  });
  final PreviewSession session;
  final Future<ReviewSource?> Function(String) loadSource;
  final String Function(String) cardTitle;
  final String cardId;
  final ValueChanged<String> onCard, onOriginal;
  @override
  State<ReviewSourceView> createState() => ReviewSourceViewState();
}

class ReviewSourceViewState extends State<ReviewSourceView> {
  ReviewSource? _source;
  String? _error;
  bool _loading = true;
  int _generation = 0;
  final _pendingReads = <Future<void>>{};
  String? get reviewId => _source?.reviewId;
  bool get isLoading => _loading;
  String? get loadError => _error;
  int get inputCount => _source?.inputs.length ?? 0;
  int get attachmentCount =>
      _source?.inputs.fold<int>(
        0,
        (n, input) => n + input.attachments.length,
      ) ??
      0;
  @override
  void initState() {
    super.initState();
    widget.session.addListener(_sessionChanged);
    widget.session.registerPreviewCleanup(_cleanup);
    _reload();
  }

  void _sessionChanged() {
    if (widget.session.isUnlocked) return;
    _generation++;
    _clear();
    if (mounted) setState(() => _loading = false);
  }

  void _clear() {
    final source = _source;
    _source = null;
    if (source == null) return;
    for (final input in source.inputs) {
      for (final a in input.attachments) {
        if (a.kind == ConversationAttachmentKind.image) {
          unawaited(MemoryImage(a.bytes).evict());
        }
        for (final frame in a.frames) {
          unawaited(MemoryImage(frame.bytes).evict());
        }
      }
    }
    source.wipe();
  }

  void _reload() {
    final task = _load();
    _pendingReads.add(task);
    unawaited(task.whenComplete(() => _pendingReads.remove(task)));
  }

  Future<void> _cleanup() async {
    _generation++;
    _clear();
    await Future.wait(List.of(_pendingReads));
  }

  Future<void> _load() async {
    final generation = ++_generation;
    try {
      final source = await widget.loadSource(widget.cardId);
      if (!mounted || generation != _generation || !widget.session.isUnlocked) {
        source?.wipe();
        return;
      }
      _clear();
      setState(() {
        _source = source;
        _loading = false;
        _error = null;
      });
    } on Object {
      if (mounted && generation == _generation) {
        setState(() {
          _loading = false;
          _error = '确认来源无法读取；记录保留，可重试。';
        });
      }
    }
  }

  @override
  void didUpdateWidget(covariant ReviewSourceView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.cardId != widget.cardId) {
      _clear();
      _loading = true;
      _reload();
    }
  }

  @override
  void dispose() {
    _generation++;
    widget.session.removeListener(_sessionChanged);
    _clear();
    unawaited(
      _cleanup().whenComplete(
        () => widget.session.unregisterPreviewCleanup(_cleanup),
      ),
    );
    super.dispose();
  }

  Widget _attachment(ConversationAttachment a) => Card(
    child: ExpansionTile(
      key: ValueKey('review-attachment-${a.id}'),
      title: Text(a.name),
      subtitle: Text(
        [
          '${a.mimeType} · ${a.bytes.length} 字节',
          if (a.cardRevision != null) '所选卡片第${a.cardRevision}版',
          if (a.frames.isNotEmpty) '发送时已检查${a.frames.length}帧',
        ].join(' · '),
      ),
      childrenPadding: const EdgeInsets.all(12),
      children: [
        if (a.kind == ConversationAttachmentKind.text)
          SelectableText(a.text)
        else if (a.kind == ConversationAttachmentKind.image)
          Image.memory(
            a.bytes,
            height: 320,
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) => const Text('图片无法显示'),
          )
        else if (Platform.isLinux && a.kind == ConversationAttachmentKind.pdf)
          LocalPdfPreview(
            session: widget.session,
            name: a.name,
            compact: true,
            readBytes: () async => Uint8List.fromList(a.bytes),
          )
        else if (Platform.isLinux &&
            {
              ConversationAttachmentKind.audio,
              ConversationAttachmentKind.video,
            }.contains(a.kind))
          LocalMediaPreview(
            controller: widget.session,
            name: a.name,
            video: a.kind == ConversationAttachmentKind.video,
            compact: true,
            readBytes: () async => Uint8List.fromList(a.bytes),
          )
        else
          const Text('完整附件已保存在此加密确认记录中；此格式尚无内嵌预览。'),
        for (final frame in a.frames)
          Column(
            children: [
              Text('发送帧 · ${(frame.milliseconds / 1000).toStringAsFixed(2)}秒'),
              Image.memory(frame.bytes, height: 180, fit: BoxFit.contain),
            ],
          ),
        Wrap(
          children: [
            if (a.cardId != null)
              TextButton(
                onPressed: () => widget.onCard(a.cardId!),
                child: const Text('打开所选卡片当前版本'),
              ),
            if (a.blobId != null)
              TextButton(
                onPressed: () => widget.onOriginal(a.blobId!),
                child: const Text('打开已另存原件'),
              ),
          ],
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!),
            TextButton(onPressed: _reload, child: const Text('重试')),
          ],
        ),
      );
    }
    final source = _source;
    if (source == null || !widget.session.isUnlocked) {
      return const Center(child: Text('此卡片没有独立确认来源记录。早期卡片的来源仍可在卡片和修订历史中查看。'));
    }
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text('确认来源', style: Theme.of(context).textTheme.headlineSmall),
        Text('${source.providerLabel} · ${source.confirmedAt.toLocal()}'),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: Text('保留确认时完整输入和附件，与当前会话独立。此记录仅在本人资料库中保存，交接范围仍需另行明确选择。'),
        ),
        if (source.actions.isNotEmpty) ...[
          Text('确认时的操作', style: Theme.of(context).textTheme.titleMedium),
          for (var i = 0; i < source.actions.length; i++)
            Text(
              '卡片 ${i + 1}：${source.actions[i].bundleId == null ? "独立保存" : "收纳至组合 ${source.actions[i].bundleId}"} · ${source.actions[i].referenceIds.length}项引用 · 失能：${reviewLevelLabel(source.actions[i].incapacitated)} · 身故：${reviewLevelLabel(source.actions[i].deceased)}',
            ),
          const Divider(),
        ],
        if (source.proposals.any((p) => p != null)) ...[
          Text('模型提出的操作草案', style: Theme.of(context).textTheme.titleMedium),
          const Text('模型草案与本人最终保存计划分别保留；实际执行以上方确认时的操作为准。'),
          for (var i = 0; i < source.proposals.length; i++)
            if (source.proposals[i] case final proposal?) ...[
              Text(
                '卡片 ${i + 1}：${reviewPlanSummary(proposal.plan, const [], titleForId: widget.cardTitle)}',
              ),
              if (proposal.reason.isNotEmpty) SelectableText(proposal.reason),
            ],
          const Divider(),
        ],
        for (var i = 0; i < source.inputs.length; i++) ...[
          Text('输入 ${i + 1}', style: Theme.of(context).textTheme.titleMedium),
          SelectableText(source.inputs[i].text),
          for (final a in source.inputs[i].attachments) _attachment(a),
          const Divider(),
        ],
        Text('模型答复', style: Theme.of(context).textTheme.titleMedium),
        SelectableText(source.reply),
      ],
    );
  }
}
