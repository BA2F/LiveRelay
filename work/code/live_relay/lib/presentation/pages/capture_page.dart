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
import '../../application/device_capabilities.dart';
import '../../core/domain/entities.dart';
import '../design_system/atoms.dart';
import '../dialogs/card_dialogs.dart';
import '../dialogs/capability_dialog.dart';
import '../widgets/life_card_tile.dart';
import 'cards_page.dart';
import 'originals_page.dart';

class CapturePage extends StatelessWidget {
  const CapturePage({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    final recent = controller.cards.take(5).toList();
    return RefreshIndicator(
      onRefresh: () => runUiAction(context, controller.refresh),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Text('先记下来', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 6),
          Text(recent.isEmpty ? '例如：备用钥匙放在哪里。重要的事，之后再慢慢整理。' : '重要的事，之后再慢慢整理。'),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: controller.isBusy
                ? null
                : () => showCardEditor(context, controller),
            icon: const Icon(Icons.add),
            label: const Text('记一条'),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
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
                    : () => _recordAudio(context, controller),
                icon: const Icon(Icons.mic_outlined),
                label: const Text('录音'),
              ),
              OutlinedButton.icon(
                onPressed: controller.isBusy
                    ? null
                    : () => showCapabilityMessage(
                        context,
                        '语音输入',
                        controller.capability(AppFeature.speechInput),
                      ),
                icon: const Icon(Icons.keyboard_voice_outlined),
                label: const Text('语音输入'),
              ),
              OutlinedButton.icon(
                onPressed: controller.isBusy
                    ? null
                    : () => _showMore(context, controller),
                icon: const Icon(Icons.more_horiz),
                label: const Text('更多'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Card(
            child: ListTile(
              leading: const Icon(Icons.fact_check_outlined),
              title: Text('待整理 · ${controller.insights.drafts} 条'),
              subtitle: const Text('核对草稿、补充信息，再由本人确认'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push<void>(
                MaterialPageRoute(
                  builder: (_) => Scaffold(
                    appBar: AppBar(title: const Text('待整理')),
                    body: const CardsPage(initialStatus: CardStatus.draft),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          if (controller.lastError != null) ErrorBanner(controller.lastError!),
          PageSection(
            title: '最近记录',
            subtitle: '已加密保存在本机 · 按最近修改排序',
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
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => Navigator.of(context).push<void>(
              MaterialPageRoute(builder: (_) => const OriginalsPage()),
            ),
            icon: const Icon(Icons.folder_open),
            label: Text('全部原件 · ${controller.blobs.length} 个'),
          ),
          if (controller.insights.stale > 0)
            ListTile(
              leading: const Icon(Icons.update),
              title: Text('${controller.insights.stale} 张卡片超过半年未确认'),
              subtitle: const Text('打开卡片核对，旧来源和历史会保留。'),
            ),
        ],
      ),
    );
  }

  Future<void> _showMore(BuildContext context, AppController controller) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (c) => SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final item in [
              ('image', '导入照片', Icons.add_photo_alternate_outlined),
              ('audio', '导入录音', Icons.audio_file_outlined),
              ('video', '导入录像', Icons.video_file_outlined),
              ('camera', '现场录像', Icons.videocam_outlined),
            ])
              ListTile(
                leading: Icon(item.$3),
                title: Text(item.$2),
                onTap: () => Navigator.pop(c, item.$1),
              ),
          ],
        ),
      ),
    );
    if (!context.mounted) return;
    switch (action) {
      case 'image':
        await _pickOriginal(context, controller, BlobMediaKind.image);
      case 'audio':
        await _pickOriginal(context, controller, BlobMediaKind.audio);
      case 'video':
        await _pickOriginal(context, controller, BlobMediaKind.video);
      case 'camera':
        await _captureCamera(context, controller, BlobMediaKind.video);
    }
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

  Future<void> _captureCamera(
    BuildContext context,
    AppController controller,
    BlobMediaKind kind,
  ) async {
    final capability = controller.capability(AppFeature.camera);
    if (!capability.isAvailable) {
      await showCapabilityMessage(
        context,
        kind == BlobMediaKind.image ? '拍照' : '录像',
        capability,
      );
      return;
    }
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
          const Text('录音会加密保存，暂不自动转写。'),
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
