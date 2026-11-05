/// Platform specific detached process launching / inspection.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../term/win32.dart';

class LaunchResult {
  const LaunchResult({this.pid, this.error});

  final int? pid;
  final String? error;

  bool get isSuccess => pid != null;
}

abstract class ProcessLauncher {
  Future<LaunchResult> launchDetached({
    required String executable,
    required List<String> arguments,
    required String logPath,
    String? workingDirectory,
  });

  bool isAlive(int pid);

  /// Terminates [pid] and waits up to [grace] before forcing it.
  Future<bool> terminate(int pid,
      {Duration grace = const Duration(seconds: 4)});

  /// Best effort process lookup by executable base name.
  List<int> findProcessIds(String name);
}

ProcessLauncher createLauncher() {
  if (Platform.isWindows) return WindowsLauncher();
  return PosixLauncher();
}

class PosixLauncher implements ProcessLauncher {
  @override
  Future<LaunchResult> launchDetached({
    required String executable,
    required List<String> arguments,
    required String logPath,
    String? workingDirectory,
  }) async {
    // nohup + stdin from /dev/null keeps mihomo alive after the TUI exits.
    const script = r'''
log="$1"; shift
mkdir -p "$(dirname "$log")" || exit 3
nohup "$@" >> "$log" 2>&1 < /dev/null &
echo $!
''';
    try {
      final result = await Process.start(
        '/bin/sh',
        ['-c', script, 'sh', logPath, executable, ...arguments],
        workingDirectory: workingDirectory,
      ).timeout(const Duration(seconds: 10));
      final stdoutFuture = result.stdout.transform(utf8.decoder).join();
      final stderrFuture = result.stderr.transform(utf8.decoder).join();
      final pidText = (await stdoutFuture).trim();
      final stderrText = (await stderrFuture).trim();
      final pid = int.tryParse(pidText.split('\n').last.trim());
      if (pid == null) {
        return LaunchResult(
          error: stderrText.isEmpty ? '无法解析 mihomo 进程号' : stderrText,
        );
      }
      return LaunchResult(pid: pid);
    } on TimeoutException {
      return const LaunchResult(error: '启动 mihomo 超时');
    } on ProcessException catch (error) {
      return LaunchResult(error: error.message);
    }
  }

  @override
  bool isAlive(int pid) {
    if (pid <= 0) return false;
    if (Directory('/proc/$pid').existsSync()) {
      try {
        final stat = File('/proc/$pid/stat').readAsStringSync();
        // Zombie processes are not "alive" for our purposes.
        final close = stat.lastIndexOf(')');
        if (close > 0 && close + 2 < stat.length) {
          final state = stat[close + 2];
          if (state == 'Z' || state == 'X') return false;
        }
        return true;
      } catch (_) {
        return true;
      }
    }
    return false;
  }

  @override
  Future<bool> terminate(
    int pid, {
    Duration grace = const Duration(seconds: 4),
  }) async {
    if (!isAlive(pid)) return true;
    Process.killPid(pid, ProcessSignal.sigterm);
    final deadline = DateTime.now().add(grace);
    while (DateTime.now().isBefore(deadline)) {
      if (!isAlive(pid)) return true;
      await Future<void>.delayed(const Duration(milliseconds: 120));
    }
    Process.killPid(pid, ProcessSignal.sigkill);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    return !isAlive(pid);
  }

  @override
  List<int> findProcessIds(String name) {
    final target = name.toLowerCase();
    final result = <int>[];
    final proc = Directory('/proc');
    if (!proc.existsSync()) return result;
    for (final entry in proc.listSync(followLinks: false)) {
      final pid = int.tryParse(entry.path.split(Platform.pathSeparator).last);
      if (pid == null) continue;
      try {
        final comm = File('/proc/$pid/comm').readAsStringSync().trim();
        if (comm.toLowerCase() == target) result.add(pid);
      } catch (_) {
        // Process disappeared.
      }
    }
    return result;
  }
}

class WindowsLauncher implements ProcessLauncher {
  @override
  Future<LaunchResult> launchDetached({
    required String executable,
    required List<String> arguments,
    required String logPath,
    String? workingDirectory,
  }) async {
    final log = File(logPath);
    log.parent.createSync(recursive: true);
    final pid = Win32.instance.startDetachedWithLog(
      exe: executable,
      arguments: arguments,
      logPath: logPath,
      workingDirectory: workingDirectory,
    );
    if (pid == null) {
      return const LaunchResult(error: 'CreateProcess 调用失败');
    }
    return LaunchResult(pid: pid);
  }

  @override
  bool isAlive(int pid) => Win32.instance.isProcessAlive(pid);

  @override
  Future<bool> terminate(
    int pid, {
    Duration grace = const Duration(seconds: 4),
  }) async {
    if (!isAlive(pid)) return true;
    Win32.instance.terminate(pid);
    final deadline = DateTime.now().add(grace);
    while (DateTime.now().isBefore(deadline)) {
      if (!isAlive(pid)) return true;
      await Future<void>.delayed(const Duration(milliseconds: 120));
    }
    return !isAlive(pid);
  }

  @override
  List<int> findProcessIds(String name) {
    try {
      final result = Process.runSync(
        'tasklist',
        ['/FI', 'IMAGENAME eq $name.exe', '/FO', 'CSV', '/NH'],
      );
      final output = result.stdout.toString();
      final pids = <int>[];
      for (final line in output.split('\n')) {
        final match = RegExp(r'"([^"]*\.exe)","(\d+)"').firstMatch(line);
        if (match != null) pids.add(int.parse(match.group(2)!));
      }
      return pids;
    } catch (_) {
      return const [];
    }
  }
}
