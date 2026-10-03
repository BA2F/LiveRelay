import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../core/ports/agent_command_provider.dart';

/// Linux only. Refuses to run if namespaces or required tools are unavailable.
/// Host user directories, environment, network and process tree are not mounted.
class LinuxBashCommandProvider implements AgentCommandProvider {
  LinuxBashCommandProvider({required this.resolveDirectory});
  final Future<Directory> Function() resolveDirectory;
  Future<void> cleanStaleInputs() async {
    if (!Platform.isLinux) return;
    final root = await resolveDirectory();
    if (!await root.exists()) return;
    await for (final entity in root.list(followLinks: false)) {
      if (entity is Directory &&
          entity.path.split('/').last.startsWith('request-')) {
        await entity.delete(recursive: true);
      }
    }
  }

  @override
  Future<bool> available() async {
    if (!Platform.isLinux) return false;
    AgentCommandSession? session;
    try {
      session = await open('probe');
      final result = await session.run(
        'test ! -e /home && test ! -e /etc && test ! -e /run && printf sandbox-ready',
      );
      return result.exitCode == 0 && result.stdout == 'sandbox-ready';
    } on Object {
      return false;
    } finally {
      await session?.close();
    }
  }

  @override
  Future<AgentCommandSession> open(
    String redactedText, {
    Future<void>? whenCancelled,
  }) async {
    if (!Platform.isLinux || utf8.encode(redactedText).length > 64 * 1024) {
      throw const FormatException('当前设备尚未支持隔离命令，或资料过长');
    }
    for (final tool in [
      '/usr/bin/bwrap',
      '/usr/bin/bash',
      '/usr/bin/prlimit',
    ]) {
      if (!await File(tool).exists()) {
        throw const FormatException('需要可用的 bubblewrap、Bash 和 prlimit');
      }
    }
    final root = await resolveDirectory();
    await root.create(recursive: true);
    final directory = await root.createTemp('request-');
    try {
      await File('${directory.path}/input.txt')
          .writeAsString(redactedText, flush: true);
      final arguments = <String>[
        '--unshare-all',
        '--unshare-user',
        '--disable-userns',
        '--die-with-parent',
        '--new-session',
        '--cap-drop',
        'ALL',
        '--ro-bind',
        '/usr/bin',
        '/usr/bin',
        '--ro-bind',
        '/usr/lib',
        '/usr/lib',
      ];
      // Support both merged /usr distributions and separate loader directories.
      for (final alias in ['/bin', '/lib', '/lib64', '/usr/lib64']) {
        if (await FileSystemEntity.isLink(alias)) {
          final target = await Link(alias).target();
          final resolved = await Directory(alias).resolveSymbolicLinks();
          if (!resolved.startsWith('/usr/bin') &&
              !resolved.startsWith('/usr/lib')) {
            throw const FormatException('此系统的命令运行库布局尚未支持');
          }
          arguments.addAll(['--symlink', target, alias]);
        } else if (await Directory(alias).exists()) {
          arguments.addAll(['--ro-bind', alias, alias]);
        }
      }
      arguments.addAll([
        '--proc',
        '/proc',
        '--dev',
        '/dev',
        '--size',
        '16777216',
        '--tmpfs',
        '/tmp',
        '--size',
        '16777216',
        '--tmpfs',
        '/work',
        '--ro-bind',
        directory.path,
        '/input',
        '--chdir',
        '/work',
        '--clearenv',
        '--setenv',
        'PATH',
        '/usr/bin',
        '--setenv',
        'LANG',
        'C.UTF-8',
        '--setenv',
        'HOME',
        '/work',
        '--setenv',
        'TMPDIR',
        '/tmp',
        '--',
        '/usr/bin/prlimit',
        '--as=536870912',
        '--cpu=5',
        '--fsize=16777216',
        '--nofile=64',
        '--nproc=256',
        '--',
        '/usr/bin/bash',
        '--noprofile',
        '--norc',
        '-c',
      ]);
      final session = _LinuxCommandSession(directory, arguments);
      if (whenCancelled != null) {
        unawaited(whenCancelled.then((_) => session.close()));
      }
      return session;
    } on Object {
      await directory.delete(recursive: true);
      rethrow;
    }
  }
}

class _LinuxCommandSession implements AgentCommandSession {
  _LinuxCommandSession(this.directory, this.arguments);
  final Directory directory;
  final List<String> arguments;
  final _history = <AgentCommandResult>[];
  Process? _active;
  bool _closed = false;
  bool _starting = false;
  @override
  List<AgentCommandResult> get history => List.unmodifiable(_history);

  @override
  Future<AgentCommandResult> run(String command) async {
    if (_closed ||
        _starting ||
        _active != null ||
        command.trim().isEmpty ||
        utf8.encode(command).length > 4096 ||
        _history.length >= 6) {
      throw const FormatException('隔离命令已关闭、正忙或超出限制');
    }
    _starting = true;
    late final Process process;
    try {
      process = await Process.start(
        '/usr/bin/bwrap',
        [...arguments, command],
        environment: const {},
        includeParentEnvironment: false,
        workingDirectory: directory.path,
      );
    } finally {
      _starting = false;
    }
    if (_closed) {
      process.kill(ProcessSignal.sigkill);
      await process.exitCode;
      throw const FormatException('隔离命令已取消');
    }
    _active = process;
    var timedOut = false;
    var overflow = false;
    var received = 0;
    final out = <int>[], err = <int>[];
    final timer = Timer(const Duration(seconds: 10), () {
      timedOut = true;
      process.kill(ProcessSignal.sigkill);
    });
    Future<void> collect(Stream<List<int>> stream, List<int> target) async {
      await for (final chunk in stream) {
        received += chunk.length;
        if (received > 64 * 1024) {
          overflow = true;
          process.kill(ProcessSignal.sigkill);
        } else {
          target.addAll(chunk);
        }
      }
    }

    try {
      await process.stdin.close();
      final reading = Future.wait([
        collect(process.stdout, out),
        collect(process.stderr, err),
      ]);
      final code = await process.exitCode;
      await reading;
      if (_closed) throw const FormatException('隔离命令已取消');
      if (timedOut) throw const FormatException('隔离命令超过 10 秒');
      if (overflow) throw const FormatException('隔离命令输出超出 64 KB');
      final result = AgentCommandResult(
        command: command,
        exitCode: code,
        stdout: utf8.decode(out, allowMalformed: true),
        stderr: utf8.decode(err, allowMalformed: true),
      );
      _history.add(result);
      return result;
    } finally {
      timer.cancel();
      process.kill(ProcessSignal.sigkill);
      _active = null;
    }
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    final process = _active;
    process?.kill(ProcessSignal.sigkill);
    if (process != null) {
      try {
        await process.exitCode.timeout(const Duration(seconds: 2));
      } on Object {
        /* Continue cleanup. */
      }
    }
    try {
      if (await directory.exists()) await directory.delete(recursive: true);
    } on FileSystemException {
      /* Startup cleans stale input directories under our dedicated app directory. */
    }
  }
}
