/// mihomo binary resolution and lifecycle management.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'launcher.dart';
import 'paths.dart';

class CoreStatus {
  const CoreStatus({
    this.binaryPath,
    this.binaryError,
    this.version,
    this.running = false,
    this.pid,
    this.pidFromFile = false,
    this.logFileError,
  });

  final String? binaryPath;
  final String? binaryError;
  final String? version;
  final bool running;
  final int? pid;
  final bool pidFromFile;
  final String? logFileError;

  CoreStatus copyWith({
    String? binaryPath,
    String? binaryError,
    String? version,
    bool? running,
    int? pid,
    bool? pidFromFile,
  }) {
    return CoreStatus(
      binaryPath: binaryPath ?? this.binaryPath,
      binaryError: binaryError ?? this.binaryError,
      version: version ?? this.version,
      running: running ?? this.running,
      pid: pid ?? this.pid,
      pidFromFile: pidFromFile ?? this.pidFromFile,
      logFileError: logFileError,
    );
  }
}

class MihomoCore {
  MihomoCore({required this.paths, this.binaryOverride});

  final AppPaths paths;

  /// From settings; when null detection falls back to PATH and common paths.
  final String? binaryOverride;

  final ProcessLauncher _launcher = createLauncher();
  final Map<String, String?> _versionCache = {};
  int? _scannedPid;
  DateTime _scannedAt = DateTime.fromMillisecondsSinceEpoch(0);
  final Map<String, DateTime> _versionCacheTime = {};

  static const _binaryNames = [
    'mihomo',
    'mihomo.exe',
    'mihomo-meta',
    'clash-meta',
    'clash-meta.exe',
    'clash',
    'clash.exe',
  ];

  List<String> get searchLocations {
    final locations = <String>[];
    final env = Platform.environment['MIHOMO_BIN'];
    if (env != null && env.trim().isNotEmpty) locations.add(env.trim());
    if (binaryOverride != null && binaryOverride!.trim().isNotEmpty) {
      locations.add(binaryOverride!.trim());
    }
    final scriptDir = File(Platform.resolvedExecutable).parent.path;
    for (final name in _binaryNames) {
      locations.add('$scriptDir${Platform.pathSeparator}$name');
    }
    // Bundled cores, e.g. <app>/mihomo/mihomo-linux-amd64-compatible
    for (final root in {scriptDir, Directory.current.path}) {
      for (final sub in const ['mihomo', 'core', 'resources', 'bin']) {
        final directory = Directory('$root${Platform.pathSeparator}$sub');
        if (!directory.existsSync()) continue;
        try {
          for (final entry in directory.listSync(followLinks: false)) {
            if (entry is! File) continue;
            final base = entry.uri.pathSegments.last.toLowerCase();
            if (base.startsWith('mihomo') || base.startsWith('clash-meta')) {
              locations.add(entry.path);
            }
          }
        } catch (_) {
          // Unreadable directory, skip.
        }
      }
    }
    for (final dir in [
      Directory.current.path,
      paths.mihomoHome,
      paths.configDir,
    ]) {
      for (final name in _binaryNames) {
        locations.add('$dir${Platform.pathSeparator}$name');
      }
    }
    final pathEnv = Platform.environment['PATH'] ?? '';
    for (final dir in pathEnv.split(Platform.isWindows ? ';' : ':')) {
      if (dir.isEmpty) continue;
      for (final name in _binaryNames) {
        locations.add('$dir${Platform.pathSeparator}$name');
      }
    }
    if (Platform.isWindows) {
      final localAppData = Platform.environment['LOCALAPPDATA'];
      if (localAppData != null && localAppData.isNotEmpty) {
        for (final name in _binaryNames) {
          locations.add('$localAppData\\mihomo-tui\\$name');
        }
      }
    }
    for (final dir in [
      '${AppPaths.homeDir}${Platform.pathSeparator}.local${Platform.pathSeparator}bin',
      if (!Platform.isWindows) '/usr/local/bin',
      if (!Platform.isWindows) '/usr/bin',
    ]) {
      for (final name in _binaryNames) {
        locations.add('$dir${Platform.pathSeparator}$name');
      }
    }
    return locations;
  }

  /// Path explicitly provided through settings or the MIHOMO_BIN env var.
  String? get explicitBinaryPath {
    final env = Platform.environment['MIHOMO_BIN'];
    if (env != null && env.trim().isNotEmpty) return env.trim();
    if (binaryOverride != null && binaryOverride!.trim().isNotEmpty) {
      return binaryOverride!.trim();
    }
    return null;
  }

  static bool _isExecutable(File file) {
    if (Platform.isWindows) return file.existsSync();
    try {
      return file.statSync().mode & 0x49 != 0;
    } catch (_) {
      return false;
    }
  }

  String? resolveBinary() {
    final explicit = explicitBinaryPath;
    if (explicit != null) {
      final file = File(explicit);
      if (file.existsSync() && _isExecutable(file)) return file.absolute.path;
      return null;
    }
    for (final candidate in searchLocations) {
      final file = File(candidate);
      if (file.existsSync() && _isExecutable(file)) {
        return file.absolute.path;
      }
    }
    return null;
  }

  String get binaryError {
    final explicit = explicitBinaryPath;
    if (explicit != null) return '指定的 mihomo 路径不可执行：$explicit';
    return '未找到 mihomo 可执行文件';
  }

  Future<String?> version({bool refresh = false}) async {
    final binary = resolveBinary();
    if (binary == null) return null;
    final stamp = File(binary).statSync().modified;
    if (!refresh &&
        _versionCache.containsKey(binary) &&
        _versionCacheTime[binary] == stamp) {
      return _versionCache[binary];
    }
    String? version;
    try {
      final result = await Process.run(
        binary,
        ['-v'],
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      ).timeout(const Duration(seconds: 10));
      final output = '${result.stdout}\n${result.stderr}';
      final match = RegExp(r'v?\d+\.\d+\.\d+[\w.\-+]*').firstMatch(output);
      if (match != null) {
        version = match.group(0);
      } else if (output.trim().isNotEmpty) {
        version = output.trim().split('\n').first;
      }
    } catch (_) {
      version = null;
    }
    _versionCache[binary] = version;
    _versionCacheTime[binary] = stamp;
    return version;
  }

  int? readPidFile() {
    final file = File(paths.pidFile);
    if (!file.existsSync()) return null;
    try {
      return int.tryParse(file.readAsStringSync().trim());
    } catch (_) {
      return null;
    }
  }

  void writePidFile(int pid) {
    final file = File(paths.pidFile);
    file.parent.createSync(recursive: true);
    file.writeAsStringSync('$pid\n');
  }

  void clearPidFile() {
    final file = File(paths.pidFile);
    if (file.existsSync()) {
      try {
        file.deleteSync();
      } catch (_) {}
    }
  }

  /// Detects the running pid from the pid file, falling back to a process scan.
  ///
  /// [fromFile] is false when the process was started outside of mihomo-tui,
  /// which the UI surfaces as "外部进程" so that stopping it stays explicit.
  ({int? pid, bool fromFile}) detectProcess({bool allowScan = true}) {
    final stored = readPidFile();
    if (stored != null) {
      if (_launcher.isAlive(stored)) return (pid: stored, fromFile: true);
      clearPidFile();
    }
    if (!allowScan) return (pid: null, fromFile: false);
    final cached = _scannedPid;
    if (cached != null && _launcher.isAlive(cached)) {
      return (pid: cached, fromFile: false);
    }
    final now = DateTime.now();
    if (cached == null &&
        now.difference(_scannedAt) < const Duration(seconds: 3)) {
      return (pid: null, fromFile: false);
    }
    _scannedAt = now;
    _scannedPid = null;
    final binary = resolveBinary();
    final name = binary == null
        ? 'mihomo'
        : File(binary).uri.pathSegments.last.replaceAll('.exe', '');
    for (final pid in _launcher.findProcessIds(name)) {
      if (_launcher.isAlive(pid)) {
        _scannedPid = pid;
        return (pid: pid, fromFile: false);
      }
    }
    return (pid: null, fromFile: false);
  }

  int? detectPid({bool allowScan = true}) =>
      detectProcess(allowScan: allowScan).pid;

  Future<CoreStatus> status({bool refreshVersion = false}) async {
    final binary = resolveBinary();
    final detected = detectProcess();
    final version = await this.version(refresh: refreshVersion);
    return CoreStatus(
      binaryPath: binary,
      binaryError: binary == null ? binaryError : null,
      version: version,
      running: detected.pid != null,
      pid: detected.pid,
      pidFromFile: detected.fromFile,
    );
  }

  void _rotateLogIfNeeded() {
    final log = File(paths.logFile);
    if (!log.existsSync()) return;
    try {
      if (log.lengthSync() > 5 * 1024 * 1024) {
        final old = File('${log.path}.1');
        if (old.existsSync()) old.deleteSync();
        log.renameSync(old.path);
      }
    } catch (_) {}
  }

  Future<LaunchResult> start() async {
    final binary = resolveBinary();
    if (binary == null) {
      return LaunchResult(error: '$binaryError，请在「设置」中指定路径');
    }
    if (!Directory(paths.mihomoHome).existsSync()) {
      Directory(paths.mihomoHome).createSync(recursive: true);
    }
    final config = File(paths.mihomoConfigFile);
    if (!config.existsSync()) {
      return LaunchResult(
        error: '配置文件不存在：${config.path}，请先选择一个订阅',
      );
    }
    _rotateLogIfNeeded();
    var logOffset = 0;
    try {
      if (File(paths.logFile).existsSync()) {
        logOffset = File(paths.logFile).lengthSync();
      }
    } catch (_) {}
    final result = await _launcher.launchDetached(
      executable: binary,
      arguments: ['-d', paths.mihomoHome],
      logPath: paths.logFile,
      workingDirectory: paths.mihomoHome,
    );
    if (!result.isSuccess) {
      return LaunchResult(error: result.error ?? '启动失败');
    }
    writePidFile(result.pid!);
    // Give the process a moment, then verify it did not exit immediately.
    await Future<void>.delayed(const Duration(milliseconds: 700));
    if (!_launcher.isAlive(result.pid!)) {
      clearPidFile();
      final tail = readLogTail(lines: 8, fromOffset: logOffset);
      return LaunchResult(
        error: tail.isEmpty ? 'mihomo 启动后立即退出' : tail.join('\n'),
      );
    }
    return result;
  }

  Future<bool> stop() async {
    final pid = detectPid();
    if (pid == null) {
      clearPidFile();
      return false;
    }
    final ok = await _launcher.terminate(pid);
    clearPidFile();
    return ok;
  }

  Future<bool> restart() async {
    await stop();
    await Future<void>.delayed(const Duration(milliseconds: 400));
    final result = await start();
    return result.isSuccess;
  }

  List<String> readLogTail({int lines = 200, int? fromOffset}) {
    final file = File(paths.logFile);
    if (!file.existsSync()) return const [];
    try {
      final length = file.lengthSync();
      const maxBytes = 256 * 1024;
      var start = length > maxBytes ? length - maxBytes : 0;
      if (fromOffset != null && fromOffset > start && fromOffset < length) {
        start = fromOffset;
      }
      final raf = file.openSync();
      try {
        raf.setPositionSync(start);
        final bytes = raf.readSync(length - start);
        final text = utf8.decode(bytes, allowMalformed: true);
        final all = text.split('\n');
        if (start > 0 && all.length > 1) all.removeAt(0);
        final tail = all.length > lines ? all.sublist(all.length - lines) : all;
        return tail.where((line) => line.trim().isNotEmpty).toList();
      } finally {
        raf.closeSync();
      }
    } catch (_) {
      return const [];
    }
  }

  bool get hasLogFile => File(paths.logFile).existsSync();

  void clearLog() {
    final file = File(paths.logFile);
    if (file.existsSync()) {
      try {
        file.writeAsStringSync('');
      } catch (_) {}
    }
  }
}
