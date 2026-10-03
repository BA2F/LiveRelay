import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

import '../../application/app_controller.dart';
import '../../application/device_capabilities.dart';
import '../../core/domain/entities.dart';
import 'capability_dialog.dart';

Future<void> showEncryptedOriginal(
  BuildContext context,
  AppController controller,
  VaultBlob blob,
) async {
  final feature = switch (blob.mediaKind) {
    BlobMediaKind.audio || BlobMediaKind.video => AppFeature.mediaPlayback,
    BlobMediaKind.document || BlobMediaKind.other => AppFeature.documentPreview,
    BlobMediaKind.image => null,
  };
  if (feature != null && !controller.capability(feature).isAvailable) {
    await showCapabilityMessage(
      context,
      '查看原件',
      controller.capability(feature),
    );
    return;
  }
  Uint8List? clearBytes;
  try {
    clearBytes = await controller.readOriginal(blob.id);
    if (!context.mounted) return;
    switch (blob.mediaKind) {
      case BlobMediaKind.image:
        await showDialog<void>(
          context: context,
          builder: (_) =>
              _ImageViewer(name: blob.originalName, bytes: clearBytes!),
        );
      case BlobMediaKind.audio:
        await _showAudio(context, blob, clearBytes);
      case BlobMediaKind.video:
        await _showVideo(context, blob, clearBytes);
      case BlobMediaKind.document:
      case BlobMediaKind.other:
        throw const FormatException('此文件类型暂不支持预览');
    }
  } on Object catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('打开原件失败：$error')));
    }
  } finally {
    clearBytes?.fillRange(0, clearBytes.length, 0);
  }
}

Future<void> _showAudio(
  BuildContext context,
  VaultBlob blob,
  Uint8List clearBytes,
) async {
  if (!Platform.isAndroid && !Platform.isIOS && !Platform.isMacOS) {
    throw UnsupportedError('此设备暂不支持音频播放');
  }
  final temporary = await _writeTemporaryMedia(blob, clearBytes, '.m4a');
  try {
    if (!context.mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (_) => _AudioViewer(name: blob.originalName, file: temporary),
    );
  } finally {
    if (await temporary.exists()) await temporary.delete();
  }
}

Future<void> _showVideo(
  BuildContext context,
  VaultBlob blob,
  Uint8List clearBytes,
) async {
  if (!Platform.isAndroid && !Platform.isIOS && !Platform.isMacOS) {
    throw UnsupportedError('此设备暂不支持视频播放');
  }
  final temporary = await _writeTemporaryMedia(blob, clearBytes, '.mp4');
  try {
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => _VideoViewer(name: blob.originalName, file: temporary),
    );
  } finally {
    if (await temporary.exists()) await temporary.delete();
  }
}

Future<File> _writeTemporaryMedia(
  VaultBlob blob,
  Uint8List clearBytes,
  String fallbackExtension,
) async {
  final cache = await getTemporaryDirectory();
  final candidate = path.extension(blob.originalName).toLowerCase();
  final extension = RegExp(r'^\.[a-z0-9]{1,8}$').hasMatch(candidate)
      ? candidate
      : fallbackExtension;
  final temporary = File(
    path.join(
      cache.path,
      'view-${DateTime.now().microsecondsSinceEpoch}$extension',
    ),
  );
  try {
    await temporary.writeAsBytes(clearBytes, flush: true);
    return temporary;
  } on Object {
    if (await temporary.exists()) await temporary.delete();
    rethrow;
  } finally {
    clearBytes.fillRange(0, clearBytes.length, 0);
  }
}

class _ImageViewer extends StatelessWidget {
  const _ImageViewer({required this.name, required this.bytes});

  final String name;
  final Uint8List bytes;

  @override
  Widget build(BuildContext context) => Dialog.fullscreen(
    child: Scaffold(
      appBar: AppBar(
        title: Text(name, overflow: TextOverflow.ellipsis),
        leading: IconButton(
          tooltip: '关闭',
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.close),
        ),
      ),
      body: ColoredBox(
        color: Colors.black,
        child: Center(
          child: InteractiveViewer(
            minScale: 0.5,
            maxScale: 6,
            child: Image.memory(
              bytes,
              fit: BoxFit.contain,
              gaplessPlayback: true,
            ),
          ),
        ),
      ),
    ),
  );
}

class _AudioViewer extends StatefulWidget {
  const _AudioViewer({required this.name, required this.file});

  final String name;
  final File file;

  @override
  State<_AudioViewer> createState() => _AudioViewerState();
}

class _AudioViewerState extends State<_AudioViewer> {
  final _player = AudioPlayer();
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      await _player.setFilePath(widget.file.path);
    } on Object catch (error) {
      _error = error.toString();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    unawaited(_player.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            const Icon(Icons.graphic_eq, size: 32),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                widget.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            IconButton(
              tooltip: '关闭',
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close),
            ),
          ],
        ),
        const SizedBox(height: 20),
        if (_loading)
          const Padding(
            padding: EdgeInsets.all(24),
            child: CircularProgressIndicator(),
          )
        else if (_error != null)
          Text('无法播放：$_error')
        else ...[
          StreamBuilder<Duration>(
            stream: _player.positionStream,
            initialData: Duration.zero,
            builder: (context, snapshot) {
              final duration = _player.duration ?? Duration.zero;
              final position = snapshot.data ?? Duration.zero;
              final maximum = duration.inMilliseconds <= 0
                  ? 1.0
                  : duration.inMilliseconds.toDouble();
              final value = position.inMilliseconds
                  .clamp(0, maximum.toInt())
                  .toDouble();
              return Column(
                children: [
                  Slider(
                    value: value,
                    max: maximum,
                    onChanged: (milliseconds) => _player.seek(
                      Duration(milliseconds: milliseconds.round()),
                    ),
                  ),
                  Text('${_clock(position)} / ${_clock(duration)}'),
                ],
              );
            },
          ),
          const SizedBox(height: 8),
          StreamBuilder<PlayerState>(
            stream: _player.playerStateStream,
            builder: (context, snapshot) {
              final state = snapshot.data;
              final playing = state?.playing ?? false;
              return FilledButton.icon(
                onPressed: () async {
                  if (state?.processingState == ProcessingState.completed) {
                    await _player.seek(Duration.zero);
                  }
                  playing ? await _player.pause() : await _player.play();
                },
                icon: Icon(playing ? Icons.pause : Icons.play_arrow),
                label: Text(playing ? '暂停' : '播放'),
              );
            },
          ),
        ],
      ],
    ),
  );

  String _clock(Duration duration) {
    final minutes = duration.inMinutes.toString().padLeft(2, '0');
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}

class _VideoViewer extends StatefulWidget {
  const _VideoViewer({required this.name, required this.file});

  final String name;
  final File file;

  @override
  State<_VideoViewer> createState() => _VideoViewerState();
}

class _VideoViewerState extends State<_VideoViewer> {
  late final VideoPlayerController _controller;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.file(widget.file);
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    try {
      await _controller.initialize();
    } on Object catch (error) {
      _error = error.toString();
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    unawaited(_controller.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Dialog.fullscreen(
    child: Scaffold(
      appBar: AppBar(
        title: Text(widget.name, overflow: TextOverflow.ellipsis),
        leading: IconButton(
          tooltip: '关闭',
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.close),
        ),
      ),
      body: ColoredBox(
        color: Colors.black,
        child: Center(
          child: _error != null
              ? Text(
                  '无法播放：$_error',
                  style: const TextStyle(color: Colors.white),
                )
              : !_controller.value.isInitialized
              ? const CircularProgressIndicator()
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AspectRatio(
                      aspectRatio: _controller.value.aspectRatio,
                      child: VideoPlayer(_controller),
                    ),
                    VideoProgressIndicator(
                      _controller,
                      allowScrubbing: true,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                    ),
                    IconButton.filled(
                      tooltip: _controller.value.isPlaying ? '暂停' : '播放',
                      onPressed: () async {
                        _controller.value.isPlaying
                            ? await _controller.pause()
                            : await _controller.play();
                        if (mounted) setState(() {});
                      },
                      icon: Icon(
                        _controller.value.isPlaying
                            ? Icons.pause
                            : Icons.play_arrow,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    ),
  );
}
