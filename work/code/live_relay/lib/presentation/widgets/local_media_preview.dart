import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path/path.dart' as path;

import '../../application/preview_session.dart';
import '../../infrastructure/private_cache.dart';

/// Linux-only renderer. It never opens network URLs or starts playback itself.
class LocalMediaPreview extends StatefulWidget {
  const LocalMediaPreview({
    super.key,
    required this.controller,
    required this.name,
    required this.video,
    required this.readBytes,
    this.compact = false,
  });
  final PreviewSession controller;
  final String name;
  final bool video, compact;
  final Future<Uint8List> Function() readBytes;
  @override
  State<LocalMediaPreview> createState() => LocalMediaPreviewState();
}

class LocalMediaPreviewState extends State<LocalMediaPreview> {
  Player? _player;
  VideoController? _video;
  File? _file;
  StreamSubscription<String>? _errors;
  bool _closed = false, _ready = false, _disposing = false;
  String? _error;
  Future<void>? _opening, _closing, _releasing;
  Player? get player => _player;
  File? get temporaryFile => _file;
  bool get isReady => _ready && !_closed && _player != null;
  Future<List<({int milliseconds, Uint8List bytes})>> sampleFrames() async {
    final player = _player;
    if (player == null || !_ready || _closed || !widget.video) {
      throw const FormatException('请先等待视频加载完成');
    }
    final frames = <({int milliseconds, Uint8List bytes})>[];
    try {
      await player.pause();
      final duration = player.state.duration.inMilliseconds;
      if (duration <= 0 || duration > 10 * 60 * 1000) {
        throw const FormatException('视频需在10分钟以内');
      }
      for (final fraction in [0.05, 0.35, 0.65, 0.95]) {
        await player.seek(
          Duration(milliseconds: (duration * fraction).round()),
        );
        await Future<void>.delayed(const Duration(milliseconds: 200));
        if (_closed || !mounted || !widget.controller.isUnlocked) {
          throw const FormatException('视频预览已关闭');
        }
        final bytes = await player.screenshot();
        if (bytes == null || bytes.length > 256 * 1024) {
          bytes?.fillRange(0, bytes.length, 0);
          throw const FormatException('无法生成适合发送的视频帧');
        }
        frames.add((
          milliseconds: player.state.position.inMilliseconds,
          bytes: bytes,
        ));
      }
      return frames;
    } on Object {
      for (final f in frames) {
        f.bytes.fillRange(0, f.bytes.length, 0);
      }
      rethrow;
    }
  }

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_sessionChanged);
    widget.controller.registerPreviewCleanup(closePreview);
    _opening = _open();
  }

  void _sessionChanged() {
    if (!widget.controller.isUnlocked && !_closed) {
      unawaited(closePreview());
    }
  }

  Future<void> _open() async {
    Uint8List? bytes;
    try {
      if (!Platform.isLinux) throw const FormatException('此预览使用Linux播放后端');
      bytes = await widget.readBytes();
      if (_closed || !mounted || !widget.controller.isUnlocked) return;
      final cache = await privateCacheDirectory();
      if (_closed || !mounted) return;
      final extension = path.extension(widget.name).toLowerCase();
      final safeExtension = RegExp(r'^\.[a-z0-9]{1,8}$').hasMatch(extension)
          ? extension
          : widget.video
          ? '.mp4'
          : '.wav';
      final file = File(
        '${cache.path}/view-${DateTime.now().microsecondsSinceEpoch}$safeExtension',
      );
      _file = file;
      await file.writeAsBytes(bytes, flush: true);
      if (_closed || !mounted) {
        if (await file.exists()) await file.delete();
        await _release();
        return;
      }
      MediaKit.ensureInitialized();
      final player = Player(
        configuration: const PlayerConfiguration(
          title: 'LiveRelay 本地资料',
          protocolWhitelist: ['file', 'data'],
          bufferSize: 8 * 1024 * 1024,
        ),
      );
      _player = player;
      if (widget.video) _video = VideoController(player);
      _errors = player.stream.error.listen((_) {
        if (mounted && !_closed) setState(() => _error = '文件无法播放，请检查格式或本机解码器');
      });
      await player.open(Media(file.uri.toString()), play: false);
      if (player.state.duration <= Duration.zero) {
        await player.stream.duration
            .firstWhere((d) => d > Duration.zero)
            .timeout(const Duration(seconds: 5));
      }
      if (_closed || !mounted) {
        await _release();
        return;
      }
      _ready = true;
    } on Object {
      if (!_closed) _error = '媒体无法打开，请检查文件和Linux播放依赖';
      await _release();
    } finally {
      bytes?.fillRange(0, bytes.length, 0);
      if (mounted) setState(() {});
    }
  }

  Future<void> closePreview() {
    if (_closing != null) return _closing!;
    _closed = true;
    if (mounted && !_disposing) setState(() {});
    return _closing = _finishClosing();
  }

  Future<void> _finishClosing() async {
    await _opening;
    await _release();
  }

  Future<void> _release() {
    if (_releasing != null) return _releasing!;
    final work = _releaseResources();
    _releasing = work;
    return work.whenComplete(() => _releasing = null);
  }

  Future<void> _releaseResources() async {
    await _errors?.cancel();
    _errors = null;
    final player = _player;
    _player = null;
    final file = _file;
    _file = null;
    try {
      await player?.dispose();
    } finally {
      if (file != null && await file.exists()) await file.delete();
    }
  }

  @override
  void dispose() {
    _disposing = true;
    _closed = true;
    widget.controller.removeListener(_sessionChanged);
    unawaited(
      closePreview().whenComplete(
        () => widget.controller.unregisterPreviewCleanup(closePreview),
      ),
    );
    super.dispose();
  }

  String _clock(Duration d) =>
      '${d.inMinutes.toString().padLeft(2, '0')}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';
  @override
  Widget build(BuildContext context) {
    final player = _player;
    if (_closed) return const Text('预览已关闭，播放已停止');
    if (_error != null) return Text(_error!);
    if (!_ready || player == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(widget.name, maxLines: 2, overflow: TextOverflow.ellipsis),
        if (widget.video && _video != null)
          SizedBox(
            height: widget.compact ? 220 : 360,
            child: Video(controller: _video!, controls: NoVideoControls),
          ),
        StreamBuilder<Duration>(
          stream: player.stream.position,
          initialData: player.state.position,
          builder: (context, s) {
            final duration = player.state.duration;
            final position = s.data ?? Duration.zero;
            final maximum = duration.inMilliseconds.toDouble();
            return Column(
              children: [
                Slider(
                  key: const ValueKey('local-media-seek'),
                  value: position.inMilliseconds.toDouble().clamp(
                    0.0,
                    maximum > 0 ? maximum : 1.0,
                  ),
                  max: maximum > 0 ? maximum : 1.0,
                  onChanged: maximum <= 0
                      ? null
                      : (v) => player.seek(Duration(milliseconds: v.round())),
                ),
                Text('${_clock(position)} / ${_clock(duration)}'),
              ],
            );
          },
        ),
        StreamBuilder<bool>(
          stream: player.stream.playing,
          initialData: player.state.playing,
          builder: (context, s) => FilledButton.icon(
            key: const ValueKey('local-media-play'),
            onPressed: () async {
              if (player.state.completed) await player.seek(Duration.zero);
              await player.playOrPause();
            },
            icon: Icon(s.data == true ? Icons.pause : Icons.play_arrow),
            label: Text(s.data == true ? '暂停' : '播放'),
          ),
        ),
      ],
    );
  }
}
