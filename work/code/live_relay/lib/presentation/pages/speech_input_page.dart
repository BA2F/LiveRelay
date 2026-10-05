import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import '../../infrastructure/private_cache.dart';

import 'package:provider/provider.dart';
import 'package:record/record.dart';

import '../../application/app_controller.dart';
import '../../core/domain/entities.dart';
import '../../infrastructure/speech/local_sense_voice_provider.dart';
import '../dialogs/speech_settings_dialog.dart';

class SpeechInputPage extends StatefulWidget {
  const SpeechInputPage({super.key, this.onTranscript});
  final ValueChanged<String>? onTranscript;
  @override
  State<SpeechInputPage> createState() => _SpeechInputPageState();
}

class _SpeechInputPageState extends State<SpeechInputPage> {
  final _recorder = AudioRecorder();
  final _text = TextEditingController();
  late AppController _controller;
  Timer? _limit, _meterTimer;
  StreamSubscription<Amplitude>? _amplitude;
  final _recordClock = Stopwatch();
  final _levels = <double>[];
  late bool _saveOriginal = widget.onTranscript == null;
  String? _recordPath;
  String? _sourceBlobId;
  int _generation = 0;
  bool _recording = false;
  bool _working = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _controller = context.read<AppController>();
    _controller.addListener(_sessionChanged);
    _controller.exitCleanups.add(_discardRecording);
  }

  void _sessionChanged() {
    if (!_controller.isUnlocked) {
      _generation++;
      _controller.speech?.cancelTranscription();
      _text.clear();
      _sourceBlobId = null;
      if (_recording) unawaited(_discardRecording());
      if (mounted) setState(() {});
    }
  }

  Future<void> _discardRecording() async {
    _limit?.cancel();
    await _stopMeter();
    _recording = false;
    try {
      await _recorder.cancel();
    } on Object {
      /* Cleanup below is retried. */
    }
    await _deleteRecording();
  }

  Future<void> _stopMeter() async {
    _meterTimer?.cancel();
    _recordClock.stop();
    await _amplitude?.cancel();
    _amplitude = null;
  }

  Future<void> _deleteRecording() async {
    final path = _recordPath;
    _recordPath = null;
    if (path != null) {
      try {
        final f = File(path);
        if (await f.exists()) await f.delete();
      } on Object {
        /* Startup also clears known audio cache. */
      }
    }
  }

  @override
  void dispose() {
    _generation++;
    _controller.speech?.cancelTranscription();
    _controller.removeListener(_sessionChanged);
    _controller.exitCleanups.remove(_discardRecording);
    _limit?.cancel();
    unawaited(_discardRecording().whenComplete(_recorder.dispose));
    _text.dispose();
    super.dispose();
  }

  Future<void> _action(Future<void> Function() action) async {
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      await action();
    } on Object catch (e, stack) {
      if (kDebugMode) {
        debugPrintStack(
          label: 'Speech operation failed (${e.runtimeType})',
          stackTrace: stack,
        );
      }
      if (mounted) {
        setState(
          () => _error = e is FormatException
              ? e.message
              : _controller.speech?.error ?? '操作失败，请检查权限或模型',
        );
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _start() async => _action(() async {
    if (!await _recorder.hasPermission()) {
      throw const FormatException('请允许麦克风权限');
    }
    if (!mounted || !_controller.isUnlocked) return;
    final cache = await privateCacheDirectory();
    if (!mounted || !_controller.isUnlocked) return;
    _recordPath =
        '${cache.path}/speech-${DateTime.now().microsecondsSinceEpoch}.wav';
    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.wav,
        sampleRate: 16000,
        numChannels: 1,
      ),
      path: _recordPath!,
    );
    if (!mounted || !_controller.isUnlocked) {
      await _discardRecording();
      return;
    }
    _levels.clear();
    _recordClock.reset();
    _recordClock.start();
    _amplitude = _recorder
        .onAmplitudeChanged(const Duration(milliseconds: 100))
        .listen(
          (value) {
            if (!mounted || !_recording || !value.current.isFinite) return;
            setState(() {
              _levels.add(
                ((value.current.clamp(-60.0, 0.0) + 60) / 60).toDouble(),
              );
              if (_levels.length > 60) _levels.removeAt(0);
            });
          },
          onError: (Object _) {
            if (mounted) setState(() => _error = '无法读取录音音量');
          },
        );
    _meterTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (mounted && _recording) setState(() {});
    });
    setState(() => _recording = true);
    _limit = Timer(const Duration(seconds: 60), () => unawaited(_stop()));
  });
  Future<void> _stop() async {
    if (!_recording) return;
    _limit?.cancel();
    await _stopMeter();
    if (!mounted) return;
    setState(() => _recording = false);
    await _action(() async {
      try {
        final path = await _recorder.stop();
        if (path == null) throw const FormatException('录音未完成');
        await _recognizeFile(File(path));
      } finally {
        await _deleteRecording();
      }
    });
  }

  Future<void> _pick(bool model) async {
    final picked = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: [model ? 'bz2' : 'wav'],
    );
    if (picked == null || !mounted) return;
    await _action(() async {
      try {
        if (model) {
          await _controller.speech!.install(picked.xFile.path);
        } else {
          await _recognizeFile(File(picked.xFile.path));
        }
      } finally {
        try {
          await FilePicker.clearTemporaryFiles();
        } on Object {
          /* Retry at startup. */
        }
      }
    });
  }

  Future<void> _recognizeFile(File file) async {
    final generation = _generation;
    final service = _controller.speech!;
    final remoteGeneration = service.configurationGeneration;
    final remote = service.usingRemote;
    if (!mounted || !_controller.isUnlocked) return;
    if (await file.length() > 2 * 1024 * 1024) {
      throw const FormatException('请选择 60 秒以内的 WAV');
    }
    final bytes = await file.readAsBytes();
    try {
      if (remote) {
        if (!mounted || !_controller.isUnlocked || generation != _generation) {
          return;
        }
        final settings = service.remoteSettings;
        final allowed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('允许上传本次音频？'),
            content: Text(
              '${settings.name} · ${settings.model}\n${Uri.tryParse(settings.endpoint)?.host ?? ""}\n'
              '将上传完整 WAV 音频（${bytes.length} 字节），音频不做敏感内容替换。文字回填不会自动发送给对话服务。',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('允许本次音频上传'),
              ),
            ],
          ),
        );
        if (allowed != true) return;
      }
      if (!mounted ||
          !_controller.isUnlocked ||
          generation != _generation ||
          service.configurationGeneration != remoteGeneration) {
        return;
      }
      String? blobId;
      if (_saveOriginal) {
        final original = await _controller.importOriginal(
          bytes: Uint8List.fromList(bytes),
          originalName: '语音-${DateTime.now().millisecondsSinceEpoch}.wav',
          mimeType: 'audio/wav',
          mediaKind: BlobMediaKind.audio,
        );
        if (!mounted || !_controller.isUnlocked || generation != _generation) {
          return;
        }
        blobId = (await _controller.cardSources(original.id)).first.blobId!;
      }
      final text = await service.transcribe(
        bytes,
        authorizedRemoteGeneration: remote ? remoteGeneration : null,
      );
      if (mounted && _controller.isUnlocked && generation == _generation) {
        _sourceBlobId = blobId;
        _text.text = text;
      }
    } finally {
      bytes.fillRange(0, bytes.length, 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    final service = controller.speech;
    final busy = _working || (service?.busy ?? false);
    return Scaffold(
      appBar: AppBar(
        title: Text(service?.usingRemote == true ? '远程语音输入' : '本地语音输入'),
      ),
      body: !controller.isUnlocked
          ? const Center(child: Text('请先解锁资料库'))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  service?.usingRemote == true
                      ? '音频将发送给独立配置的语音服务，每次上传前确认；最长 60 秒，核对文字后回填或保存。'
                      : widget.onTranscript == null
                      ? '录音原件加密保留，识别在本机完成，不上传音频。每次最长 60 秒，核对文字后保存关联草稿。'
                      : '识别在本机完成，不上传音频。每次最长 60 秒；核对后可填入助手，发送时另行确认。',
                ),
                if (widget.onTranscript != null)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('另存录音原件到资料库'),
                    value: _saveOriginal,
                    onChanged: busy || _recording
                        ? null
                        : (value) =>
                              setState(() => _saveOriginal = value ?? false),
                  ),
                const SizedBox(height: 16),
                if (service == null)
                  const Text('语音服务不可用')
                else ...[
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<bool>(
                          key: ValueKey(service.usingRemote),
                          initialValue: service.usingRemote,
                          decoration: const InputDecoration(
                            labelText: '语音识别提供方',
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: false,
                              child: Text('本地 SenseVoice'),
                            ),
                            DropdownMenuItem(
                              value: true,
                              child: Text('远程语音服务'),
                            ),
                          ],
                          onChanged: busy || _recording
                              ? null
                              : (remote) => _action(
                                  () => service.chooseRemote(remote ?? false),
                                ),
                        ),
                      ),
                      IconButton(
                        tooltip: '远程语音服务设置',
                        onPressed: busy || _recording
                            ? null
                            : () => showDialog<void>(
                                context: context,
                                builder: (_) =>
                                    SpeechSettingsDialog(service: service),
                              ),
                        icon: const Icon(Icons.settings_outlined),
                      ),
                    ],
                  ),
                  if (service.usingRemote)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.cloud_outlined),
                      title: Text(service.remoteSettings.name),
                      subtitle: Text(
                        '${service.remoteSettings.model} · ${Uri.tryParse(service.remoteSettings.endpoint)?.host ?? ""}',
                      ),
                    )
                  else if (!service.supported)
                    const Text('当前平台尚未支持本地语音')
                  else ...[
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.download_for_offline_outlined),
                      title: const Text('SenseVoice 本地模型'),
                      subtitle: Text(
                        service.installed
                            ? '已安装 · 支持中文等多种语言'
                            : '尚未安装 · 下载约 156 MB，安装请预留 1 GB 空间',
                      ),
                    ),
                    if (!service.installed) ...[
                      SelectableText(
                        LocalSenseVoiceProvider.modelUrl,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          FilledButton.icon(
                            onPressed: busy
                                ? null
                                : () => _action(service.download),
                            icon: const Icon(Icons.download),
                            label: const Text('下载并安装模型'),
                          ),
                          OutlinedButton(
                            onPressed: busy ? null : () => _pick(true),
                            child: const Text('导入官方模型包'),
                          ),
                        ],
                      ),
                      if (service.busy) ...[
                        LinearProgressIndicator(
                          value: service.total == null
                              ? null
                              : service.received / service.total!,
                        ),
                        Text(
                          '已下载 ${(service.received / 1024 / 1024).toStringAsFixed(1)} MB；下载完成后安装',
                        ),
                        TextButton(
                          onPressed: service.cancel,
                          child: const Text('取消下载／安装'),
                        ),
                      ],
                    ],
                  ],
                  if (service.ready) ...[
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton.icon(
                          onPressed: _recording
                              ? _stop
                              : busy
                              ? null
                              : _start,
                          icon: Icon(_recording ? Icons.stop : Icons.mic),
                          label: Text(_recording ? '停止并识别' : '开始录音'),
                        ),
                        OutlinedButton(
                          onPressed: busy || _recording
                              ? null
                              : () => _pick(false),
                          child: const Text('识别 WAV 文件'),
                        ),
                        if (!service.usingRemote)
                          TextButton(
                            onPressed: busy || _recording
                                ? null
                                : () => _action(service.remove),
                            child: const Text('移除模型'),
                          ),
                        if (busy && service.usingRemote)
                          TextButton(
                            onPressed: service.cancelTranscription,
                            child: const Text('取消识别'),
                          ),
                      ],
                    ),
                    if (_recording) ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Semantics(
                          label: '实时录音音量',
                          child: SizedBox(
                            height: 48,
                            width: double.infinity,
                            child: CustomPaint(
                              painter: _Waveform(
                                List.of(_levels),
                                Theme.of(context).colorScheme.primary,
                              ),
                            ),
                          ),
                        ),
                      ),
                      Text(
                        '正在录音 ${_recordClock.elapsed.inSeconds.toString().padLeft(2, "0")} / 60 秒',
                      ),
                      TextButton(
                        onPressed: () async {
                          await _discardRecording();
                          if (mounted) setState(() {});
                        },
                        child: const Text('取消录音'),
                      ),
                    ],
                  ],
                  if (service.error != null)
                    Text(
                      service.error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                ],
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                if (_working && (service?.ready ?? false))
                  const LinearProgressIndicator(),
                const SizedBox(height: 20),
                TextField(
                  controller: _text,
                  minLines: 5,
                  maxLines: 12,
                  enabled: !busy && !_recording,
                  maxLength: 32000,
                  decoration: const InputDecoration(
                    labelText: '检查或修改识别文字',
                    alignLabelWithHint: true,
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                if (widget.onTranscript != null)
                  OutlinedButton.icon(
                    onPressed: busy || _recording || _text.text.trim().isEmpty
                        ? null
                        : () => widget.onTranscript!(_text.text.trim()),
                    icon: const Icon(Icons.chat_bubble_outline),
                    label: const Text('填入助手输入'),
                  ),
                FilledButton(
                  onPressed: busy || _recording || _text.text.trim().isEmpty
                      ? null
                      : () => _action(() async {
                          await controller.saveSpeechDraft(
                            _text.text,
                            blobId: _sourceBlobId,
                          );
                          if (mounted && context.mounted) {
                            _text.clear();
                            _sourceBlobId = null;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('已加密保存为待整理草稿')),
                            );
                          }
                        }),
                  child: const Text('已核对，保存文字草稿'),
                ),
              ],
            ),
    );
  }
}

class _Waveform extends CustomPainter {
  _Waveform(this.levels, this.color);
  final List<double> levels;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    final gap = size.width / 60;
    for (var i = 0; i < levels.length; i++) {
      final height = (levels[i] * size.height).clamp(2.0, size.height);
      final x = gap * (60 - levels.length + i + 0.5);
      canvas.drawLine(
        Offset(x, (size.height - height) / 2),
        Offset(x, (size.height + height) / 2),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_Waveform oldDelegate) => true;
}
