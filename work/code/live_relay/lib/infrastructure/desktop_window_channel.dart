import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

/// Local Unix socket protocol, one paired presentation process. Bounded frames
/// and private directory/nonce; no listening network port or vault credentials.
class LocalWindowChannel {
  LocalWindowChannel(this.socket) {
    socket.listen(_receive, onError: (_) => _closed(), onDone: _closed);
  }
  final Socket socket;
  Future<dynamic> Function(MethodCall)? _handler;
  final _pending = <int, Completer<dynamic>>{};
  var _serial = 0, _headerOffset = 0, _bodyOffset = 0;
  final _header = Uint8List(4);
  Uint8List? _body;
  bool _isClosed = false;
  Future<void> _outgoing = Future.value();
  int _queuedBytes = 0;
  static const maxFrame = 16 * 1024 * 1024;
  Future<void> setMethodCallHandler(
    Future<dynamic> Function(MethodCall)? handler,
  ) async {
    _handler = handler;
  }

  static dynamic _encode(dynamic value) {
    if (value is Uint8List) return {'__bytes': base64Encode(value)};
    if (value is Map) {
      return {
        for (final e in value.entries) e.key.toString(): _encode(e.value),
      };
    }
    if (value is Iterable) return [for (final v in value) _encode(v)];
    return value;
  }

  static dynamic _decode(dynamic value) {
    if (value is Map) {
      if (value.length == 1 && value['__bytes'] is String) {
        return base64Decode(value['__bytes'] as String);
      }
      return {for (final e in value.entries) e.key: _decode(e.value)};
    }
    if (value is List) return [for (final v in value) _decode(v)];
    return value;
  }

  // Reply buffers are owned by this channel. _send synchronously serializes
  // them, and the queued serialized frame has its own existing wipe lifecycle.
  static void _wipeReply(dynamic value) {
    if (value is Uint8List) {
      value.fillRange(0, value.length, 0);
    } else if (value is Map) {
      for (final child in value.values) {
        _wipeReply(child);
      }
    } else if (value is List) {
      for (final child in value) {
        _wipeReply(child);
      }
    }
  }

  void _send(Map value) {
    if (_isClosed) throw const SocketException('窗口连接已关闭');
    final body = Uint8List.fromList(utf8.encode(jsonEncode(_encode(value))));
    if (body.length > maxFrame) {
      body.fillRange(0, body.length, 0);
      throw const FormatException('窗口数据超过允许大小');
    }
    final header = ByteData(4)..setUint32(0, body.length);
    _queuedBytes += body.length;
    if (_queuedBytes > 2 * maxFrame) {
      body.fillRange(0, body.length, 0);
      close();
      throw const FormatException('窗口发送队列已满');
    }
    _outgoing = _outgoing.then((_) async {
      try {
        if (!_isClosed) {
          socket.add(header.buffer.asUint8List());
          socket.add(body);
          await socket.flush();
        }
      } on Object {
        close();
      } finally {
        body.fillRange(0, body.length, 0);
        _queuedBytes -= body.length;
      }
    });
  }

  Future<T?> invokeMethod<T>(String method, [dynamic args]) async {
    final id = ++_serial, reply = Completer<dynamic>();
    _pending[id] = reply;
    try {
      _send({'id': id, 'method': method, 'args': args});
      return await reply.future.timeout(const Duration(minutes: 2)) as T?;
    } finally {
      _pending.remove(id);
    }
  }

  void _receive(Uint8List chunk) {
    var offset = 0;
    try {
      while (offset < chunk.length) {
        if (_body == null) {
          final count = (4 - _headerOffset).clamp(0, chunk.length - offset);
          _header.setRange(_headerOffset, _headerOffset + count, chunk, offset);
          offset += count;
          _headerOffset += count;
          if (_headerOffset < 4) continue;
          final length = ByteData.sublistView(_header).getUint32(0);
          if (length < 2 || length > maxFrame) {
            throw const FormatException('窗口数据帧无效');
          }
          _body = Uint8List(length);
          _bodyOffset = 0;
          _headerOffset = 0;
        }
        final body = _body!;
        final count = (body.length - _bodyOffset).clamp(
          0,
          chunk.length - offset,
        );
        body.setRange(_bodyOffset, _bodyOffset + count, chunk, offset);
        offset += count;
        _bodyOffset += count;
        if (_bodyOffset == body.length) {
          final value = _decode(jsonDecode(utf8.decode(body))) as Map;
          body.fillRange(0, body.length, 0);
          _body = null;
          unawaited(_dispatch(value));
        }
      }
    } on Object {
      socket.destroy();
      _closed();
    }
  }

  Future<void> _dispatch(Map message) async {
    if (message['reply'] is int) {
      final pending = _pending[message['reply']];
      if (pending == null || pending.isCompleted) {
        _wipeReply(message['result']);
        return;
      }
      if (message['error'] != null) {
        pending.completeError(
          PlatformException(code: message['error'] as String),
        );
      } else {
        pending.complete(message['result']);
      }
      return;
    }
    if (message['id'] is! int || message['method'] is! String) {
      close();
      return;
    }
    dynamic result;
    try {
      final handler = _handler;
      if (handler == null) throw PlatformException(code: 'NO_HANDLER');
      result = await handler(
        MethodCall(message['method'] as String, message['args']),
      );
      _send({'reply': message['id'], 'result': result});
    } on Object catch (e) {
      if (!_isClosed) {
        _send({
          'reply': message['id'],
          'error': e is PlatformException ? e.code : 'COMMAND_FAILED',
        });
      }
    } finally {
      _wipeReply(result);
      _wipeReply(message['args']);
    }
  }

  void _closed() {
    if (_isClosed) return;
    _isClosed = true;
    _handler = null;
    _body?.fillRange(0, _body!.length, 0);
    _body = null;
    for (final pending in _pending.values) {
      if (!pending.isCompleted) {
        pending.completeError(const SocketException('窗口连接已关闭'));
      }
    }
    _pending.clear();
  }

  void close() {
    socket.destroy();
    _closed();
  }

  static Future<LocalWindowChannel> connect(Map args) async {
    final socket = await Socket.connect(
      InternetAddress(args['socket'] as String, type: InternetAddressType.unix),
      0,
    );
    final channel = LocalWindowChannel(socket);
    final accepted = await channel
        .invokeMethod<bool>('hello', {'nonce': args['nonce']})
        .timeout(const Duration(seconds: 5));
    if (accepted != true) {
      channel.close();
      throw const FormatException('窗口连接未获授权');
    }
    return channel;
  }
}

class PresentationWindow {
  PresentationWindow._(
    this.process,
    this.channel,
    this.arguments,
    this.directory,
  ) {
    process.exitCode.then((_) async {
      exited = true;
      channel.close();
      if (await directory.exists()) await directory.delete(recursive: true);
    });
  }
  final Process process;
  final LocalWindowChannel channel;
  final String arguments;
  final Directory directory;
  bool exited = false;
  String get windowId => process.pid.toString();
  Future<void> show() async {
    for (var i = 0; i < 300 && !exited; i++) {
      try {
        await channel.invokeMethod('show');
        return;
      } on PlatformException catch (e) {
        if (e.code != 'NO_HANDLER') rethrow;
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    throw const FormatException('子窗口启动失败');
  }

  Future<void> hide() => channel.invokeMethod<void>('hide');
  Future<void> stop() async {
    if (exited) return;
    try {
      await process.exitCode.timeout(const Duration(seconds: 3));
    } on TimeoutException {
      process.kill();
      await process.exitCode;
    }
  }

  static Future<PresentationWindow> create({
    required Future<dynamic> Function(MethodCall) handler,
    Map<String, double>? bounds,
    bool diagnostics = false,
  }) async {
    final dir = await Directory.systemTemp.createTemp('liverelay-window-');
    final chmod = await Process.run('chmod', ['700', dir.path]);
    if (chmod.exitCode != 0) throw const FileSystemException('无法保护窗口通信目录');
    final path = '${dir.path}/view.sock';
    final nonce = const Uuid().v4();
    final server = await ServerSocket.bind(
      InternetAddress(path, type: InternetAddressType.unix),
      0,
    );
    final socketMode = await Process.run('chmod', ['600', path]);
    if (socketMode.exitCode != 0) {
      await server.close();
      await dir.delete(recursive: true);
      throw const FileSystemException('无法保护窗口通信端点');
    }
    final ready = Completer<LocalWindowChannel>();
    server.listen((socket) {
      final channel = LocalWindowChannel(socket);
      var authorized = false;
      channel.setMethodCallHandler((call) async {
        if (!authorized) {
          if (call.method != 'hello' ||
              (call.arguments as Map?)?['nonce'] != nonce ||
              ready.isCompleted) {
            channel.close();
            throw PlatformException(code: 'DENIED');
          }
          authorized = true;
          ready.complete(channel);
          unawaited(server.close());
          return true;
        }
        return handler(call);
      });
    });
    final arguments = jsonEncode({
      'type': 'liverelay.workbench',
      'version': 1,
      'socket': path,
      'nonce': nonce,
      'bounds': bounds,
      'diagnostics': diagnostics,
    });
    final environment = Map<String, String>.of(Platform.environment)
      ..removeWhere(
        (k, _) =>
            k.startsWith('FLUTTER_ENGINE_SWITCH_') || k == 'DART_VM_OPTIONS',
      );
    Process? process;
    try {
      process = await Process.start(
        Platform.resolvedExecutable,
        ['--liverelay-workbench', arguments],
        environment: environment,
        includeParentEnvironment: false,
      );
      process.stdout.drain<void>();
      process.stderr.drain<void>();
      final channel = await ready.future.timeout(const Duration(seconds: 10));
      return PresentationWindow._(process, channel, arguments, dir);
    } on Object {
      process?.kill();
      await server.close();
      if (await dir.exists()) await dir.delete(recursive: true);
      rethrow;
    }
  }
}
