import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:record/record.dart';

import '../../application/app_controller.dart';
import '../../core/domain/entities.dart';
import '../design_system/atoms.dart';
import '../dialogs/card_dialogs.dart';
import '../dialogs/ai_privacy_dialogs.dart';
import '../dialogs/media_viewer.dart';
import '../widgets/life_card_tile.dart';

class CapturePage extends StatelessWidget {
  const CapturePage({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    final recent = controller.cards.take(5).toList();
    return RefreshIndicator(
      onRefresh: controller.refresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 104),
        children: [
          Card(
            color: Theme.of(context).colorScheme.primaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.lightbulb_rounded,
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '先留下，再慢慢整理',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '手动输入会保留为本人来源。还没确认的内容可以先存草稿。',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.icon(
                        onPressed: () => showCardEditor(context, controller),
                        icon: const Icon(Icons.add),
                        label: const Text('写一条记录'),
                      ),
                      FilledButton.tonalIcon(
                        onPressed: controller.isBusy
                            ? null
                            : () => _pickOriginal(
                                context,
                                controller,
                                BlobMediaKind.image,
                              ),
                        icon: const Icon(Icons.add_photo_alternate_outlined),
                        label: const Text('导入照片'),
                      ),
                      FilledButton.tonalIcon(
                        onPressed: controller.isBusy
                            ? null
                            : () => _pickOriginal(
                                context,
                                controller,
                                BlobMediaKind.audio,
                              ),
                        icon: const Icon(Icons.audio_file_outlined),
                        label: const Text('导入录音'),
                      ),
                      FilledButton.tonalIcon(
                        onPressed: controller.isBusy
                            ? null
                            : () => _pickOriginal(
                                context,
                                controller,
                                BlobMediaKind.video,
                              ),
                        icon: const Icon(Icons.video_file_outlined),
                        label: const Text('导入录像'),
                      ),
                      OutlinedButton.icon(
                        onPressed: controller.isBusy
                            ? null
                            : () => _captureCamera(
                                context,
                                controller,
                                BlobMediaKind.image,
                              ),
                        icon: const Icon(Icons.photo_camera_outlined),
                        label: const Text('拍照'),
                      ),
                      OutlinedButton.icon(
                        onPressed: controller.isBusy
                            ? null
                            : () => _captureCamera(
                                context,
                                controller,
                                BlobMediaKind.video,
                              ),
                        icon: const Icon(Icons.videocam_outlined),
                        label: const Text('录像'),
                      ),
                      OutlinedButton.icon(
                        onPressed: controller.isBusy
                            ? null
                            : () => _recordAudio(context, controller),
                        icon: const Icon(Icons.mic_outlined),
                        label: const Text('录音'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          if (controller.blobs.isNotEmpty) ...[
            PageSection(
              title: '加密原始资料',
              subtitle: '${controller.blobs.length} 个文件；磁盘只保存随机 ID 密文',
              child: Column(
                children: [
                  for (final blob in controller.blobs.take(4))
                    ListTile(
                      onTap: () =>
                          showEncryptedOriginal(context, controller, blob),
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(_iconFor(blob.mediaKind)),
                      title: Text(
                        blob.originalName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        '${blob.mimeType} · ${_readableBytes(blob.byteLength)}'
                        '${blob.ocrText == null ? '' : ' · OCR 已完成'}',
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (blob.mediaKind == BlobMediaKind.image)
                            IconButton(
                              tooltip: '本地 OCR',
                              onPressed: controller.isBusy
                                  ? null
                                  : () => _runOcr(context, controller, blob),
                              icon: Icon(
                                blob.ocrText == null
                                    ? Icons.document_scanner_outlined
                                    : Icons.fact_check_outlined,
                              ),
                            ),
                          if (blob.ocrText != null)
                            IconButton(
                              tooltip: 'AI Privacy 标记与整理',
                              onPressed: controller.isBusy
                                  ? null
                                  : () => showAiPrivacyWorkspace(
                                      context,
                                      controller,
                                      blob,
                                    ),
                              icon: Icon(
                                blob.sensitiveMarks.isEmpty
                                    ? Icons.privacy_tip_outlined
                                    : Icons.privacy_tip,
                              ),
                            ),
                          const Icon(Icons.lock_outline),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 24),
          ],
          PageSection(
            title: '整理概览',
            subtitle: '只做确定性统计，不让 AI 冒充事实',
            child: Row(
              children: [
                Expanded(
                  child: MetricTile(
                    label: '全部卡片',
                    value: '${controller.insights.totalCards}',
                    icon: Icons.view_agenda_outlined,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: MetricTile(
                    label: '待确认',
                    value: '${controller.insights.drafts}',
                    icon: Icons.fact_check_outlined,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: MetricTile(
                    label: '密码条目',
                    value: '${controller.insights.credentials}',
                    icon: Icons.key_outlined,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          PageSection(
            title: '最近记录',
            subtitle: '正式卡片与待确认草稿按最近修改排序',
            child: recent.isEmpty
                ? const EmptyState(
                    icon: Icons.inbox_outlined,
                    title: '还没有记录',
                    message: '从一条此刻最重要的信息开始。',
                  )
                : Column(
                    children: [
                      for (final card in recent) ...[
                        LifeCardTile(
                          card: card,
                          onTap: () =>
                              showCardDetails(context, controller, card),
                        ),
                        const SizedBox(height: 10),
                      ],
                    ],
                  ),
          ),
          if (controller.insights.stale > 0) ...[
            const SizedBox(height: 16),
            ListTile(
              tileColor: Theme.of(context).colorScheme.tertiaryContainer,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              leading: const Icon(Icons.update),
              title: Text('${controller.insights.stale} 张卡片超过半年未确认'),
              subtitle: const Text('“最近”不是可信度，旧来源不会被自动覆盖。'),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _pickOriginal(
    BuildContext context,
    AppController controller,
    BlobMediaKind kind,
  ) async {
    final type = switch (kind) {
      BlobMediaKind.image => FileType.image,
      BlobMediaKind.audio => FileType.audio,
      BlobMediaKind.video => FileType.video,
      BlobMediaKind.document || BlobMediaKind.other => FileType.any,
    };
    final picked = await FilePicker.pickFile(type: type);
    if (picked == null) return;
    try {
      final mimeType = picked.xFile.mimeType ?? _mimeTypeFor(picked.name, kind);
      await controller.importOriginal(
        bytes: await picked.readAsBytes(),
        originalName: picked.name,
        mimeType: mimeType,
        mediaKind: kind,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('原始资料已加密保存，并建立来源卡片')));
      }
    } on Object {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(controller.lastError ?? '导入失败')));
      }
    } finally {
      try {
        await FilePicker.clearTemporaryFiles();
      } on Object {
        // Unsupported on a few desktop implementations. Mobile picker cache
        // cleanup is best-effort here and repeated on the next app start.
      }
    }
  }

  Future<void> _runOcr(
    BuildContext context,
    AppController controller,
    VaultBlob blob,
  ) async {
    try {
      await controller.runOcr(blob.id);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('本地 OCR 已生成待确认草稿，可继续编辑或拆分')),
        );
      }
    } on Object {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(controller.lastError ?? 'OCR 失败')),
        );
      }
    }
  }

  Future<void> _captureCamera(
    BuildContext context,
    AppController controller,
    BlobMediaKind kind,
  ) async {
    final picker = ImagePicker();
    final captured = kind == BlobMediaKind.image
        ? await picker.pickImage(
            source: ImageSource.camera,
            imageQuality: 100,
            requestFullMetadata: false,
          )
        : await picker.pickVideo(
            source: ImageSource.camera,
            maxDuration: const Duration(minutes: 5),
          );
    if (captured == null) return;
    try {
      final rawExtension = path.extension(captured.name).replaceFirst('.', '');
      final extension = rawExtension.isEmpty
          ? (kind == BlobMediaKind.image ? 'jpg' : 'mp4')
          : rawExtension;
      final displayName = kind == BlobMediaKind.image
          ? '照片-${_captureStamp()}.$extension'
          : '录像-${_captureStamp()}.$extension';
      await controller.importOriginal(
        bytes: await captured.readAsBytes(),
        originalName: displayName,
        mimeType: captured.mimeType ?? _mimeTypeFor(captured.name, kind),
        mediaKind: kind,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('现场采集已加密保存，并建立来源卡片')));
      }
    } on Object {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(controller.lastError ?? '采集失败')));
      }
    } finally {
      final temporary = File(captured.path);
      if (await temporary.exists()) await temporary.delete();
    }
  }

  Future<void> _recordAudio(
    BuildContext context,
    AppController controller,
  ) async {
    final recordedPath = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      isDismissible: false,
      enableDrag: false,
      builder: (_) => const _AudioRecorderSheet(),
    );
    if (recordedPath == null) return;
    final file = File(recordedPath);
    try {
      await controller.importOriginal(
        bytes: await file.readAsBytes(),
        originalName: '录音-${_captureStamp()}.m4a',
        mimeType: 'audio/mp4',
        mediaKind: BlobMediaKind.audio,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('录音已加密保存，并建立来源卡片')));
      }
    } on Object {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(controller.lastError ?? '录音保存失败')),
        );
      }
    } finally {
      if (await file.exists()) await file.delete();
    }
  }

  String _captureStamp() => DateTime.now()
      .toIso8601String()
      .substring(0, 19)
      .replaceAll(RegExp(r'[:T]'), '-');

  String _mimeTypeFor(String name, BlobMediaKind kind) {
    final extension = name.split('.').last.toLowerCase();
    const known = <String, String>{
      'jpg': 'image/jpeg',
      'jpeg': 'image/jpeg',
      'png': 'image/png',
      'webp': 'image/webp',
      'heic': 'image/heic',
      'mp3': 'audio/mpeg',
      'm4a': 'audio/mp4',
      'wav': 'audio/wav',
      'aac': 'audio/aac',
      'mp4': 'video/mp4',
      'mov': 'video/quicktime',
      'webm': 'video/webm',
    };
    return known[extension] ??
        switch (kind) {
          BlobMediaKind.image => 'image/*',
          BlobMediaKind.audio => 'audio/*',
          BlobMediaKind.video => 'video/*',
          BlobMediaKind.document ||
          BlobMediaKind.other => 'application/octet-stream',
        };
  }

  IconData _iconFor(BlobMediaKind kind) => switch (kind) {
    BlobMediaKind.image => Icons.image_outlined,
    BlobMediaKind.audio => Icons.audio_file_outlined,
    BlobMediaKind.video => Icons.video_file_outlined,
    BlobMediaKind.document => Icons.description_outlined,
    BlobMediaKind.other => Icons.insert_drive_file_outlined,
  };

  String _readableBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

class _AudioRecorderSheet extends StatefulWidget {
  const _AudioRecorderSheet();

  @override
  State<_AudioRecorderSheet> createState() => _AudioRecorderSheetState();
}

class _AudioRecorderSheetState extends State<_AudioRecorderSheet> {
  final _recorder = AudioRecorder();
  Timer? _timer;
  Duration _elapsed = Duration.zero;
  bool _recording = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _timer?.cancel();
    if (_recording) unawaited(_recorder.cancel());
    unawaited(_recorder.dispose());
    super.dispose();
  }

  Future<void> _start() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (!await _recorder.hasPermission()) {
        throw const FormatException('未获得麦克风权限');
      }
      final directory = await getTemporaryDirectory();
      final output = path.join(
        directory.path,
        'recording-${DateTime.now().microsecondsSinceEpoch}.m4a',
      );
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 128000,
          sampleRate: 44100,
        ),
        path: output,
      );
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() => _elapsed += const Duration(seconds: 1));
      });
      if (mounted) setState(() => _recording = true);
    } on Object catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _finish() async {
    setState(() => _busy = true);
    _timer?.cancel();
    final recordedPath = await _recorder.stop();
    _recording = false;
    if (mounted) Navigator.pop(context, recordedPath);
  }

  Future<void> _cancel() async {
    setState(() => _busy = true);
    _timer?.cancel();
    if (_recording) await _recorder.cancel();
    _recording = false;
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final minutes = _elapsed.inMinutes.toString().padLeft(2, '0');
    final seconds = (_elapsed.inSeconds % 60).toString().padLeft(2, '0');
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _recording ? Icons.mic : Icons.mic_none,
            size: 56,
            color: _recording ? Theme.of(context).colorScheme.error : null,
          ),
          const SizedBox(height: 12),
          Text(
            _recording ? '$minutes:$seconds' : '录制一段原始语音',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          const Text('停止后立即进入加密 Blob；MVP 暂不自动转写。'),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _busy ? null : _cancel,
                  child: const Text('取消'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _busy ? null : (_recording ? _finish : _start),
                  icon: Icon(
                    _recording ? Icons.stop : Icons.fiber_manual_record,
                  ),
                  label: Text(_recording ? '停止并保存' : '开始录音'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
