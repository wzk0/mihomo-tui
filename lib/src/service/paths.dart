/// Filesystem locations used by mihomo-tui.
library;

import 'dart:io';

class AppPaths {
  AppPaths({
    required this.configDir,
    required this.mihomoHome,
    required this.mihomoBin,
    required this.editor,
  });

  /// Application data directory (profiles, settings, logs).
  final String configDir;

  /// Directory mihomo uses as its working directory (`mihomo -d <home>`).
  final String mihomoHome;

  final String? mihomoBin;
  final String editor;

  String get profilesDir => _join(configDir, 'profiles');
  String get logsDir => _join(configDir, 'logs');
  String get runDir => _join(configDir, 'run');
  String get settingsFile => _join(configDir, 'settings.json');
  String get dataFile => _join(configDir, 'data.json');
  String get logFile => _join(logsDir, 'mihomo.log');
  String get pidFile => _join(runDir, 'mihomo.pid');
  String get mihomoConfigFile => _join(mihomoHome, 'config.yaml');

  static String _join(String a, String b) => a.endsWith('/') || a.endsWith(r'\')
      ? '$a$b'
      : '$a${Platform.pathSeparator}$b';

  static String get homeDir {
    final env = Platform.environment;
    if (Platform.isWindows) {
      final profile = env['USERPROFILE'];
      if (profile != null && profile.isNotEmpty) return profile;
    }
    final home = env['HOME'];
    if (home != null && home.isNotEmpty) return home;
    return Directory.current.path;
  }

  /// `~/.config` equivalent on the current platform.
  static String get baseConfigDir {
    final env = Platform.environment;
    if (Platform.isWindows) {
      final appData = env['APPDATA'];
      if (appData != null && appData.isNotEmpty) return appData;
      return _join(homeDir, 'AppData${Platform.pathSeparator}Roaming');
    }
    if (Platform.isMacOS) {
      return _join(
          homeDir, 'Library${Platform.pathSeparator}Application Support');
    }
    final xdg = env['XDG_CONFIG_HOME'];
    if (xdg != null && xdg.isNotEmpty) return xdg;
    return _join(homeDir, '.config');
  }

  static String get defaultConfigDir => _join(baseConfigDir, 'mihomo-tui');

  /// mihomo itself resolves its home to `~/.config/mihomo` (or `MIHOMO_HOME`).
  static String get defaultMihomoHome {
    final env = Platform.environment['MIHOMO_HOME'];
    if (env != null && env.isNotEmpty) return env;
    return _join(homeDir, '.config${Platform.pathSeparator}mihomo');
  }

  static String get defaultEditor {
    final env = Platform.environment;
    for (final key in ['VISUAL', 'EDITOR']) {
      final value = env[key];
      if (value != null && value.trim().isNotEmpty) return value.trim();
    }
    if (Platform.isWindows) return 'notepad';
    return 'vi';
  }

  /// Best effort interpreter/editor availability check.
  static bool canRun(String command) {
    final first = command.split(' ').first;
    if (first.isEmpty) return false;
    final pathSeparator = Platform.pathSeparator;
    if (first.contains(pathSeparator) || first.contains('/')) {
      return File(first).existsSync();
    }
    final pathEnv = Platform.environment['PATH'] ?? '';
    final extensions = Platform.isWindows
        ? (Platform.environment['PATHEXT'] ?? '.EXE;.BAT;.CMD')
            .split(';')
            .where((e) => e.isNotEmpty)
            .toList()
        : [''];
    for (final dir in pathEnv.split(Platform.isWindows ? ';' : ':')) {
      if (dir.isEmpty) continue;
      for (final ext in extensions) {
        final candidate = _join(dir, '$first${ext.toLowerCase()}');
        if (File(candidate).existsSync()) return true;
        final upper = _join(dir, '$first${ext.toUpperCase()}');
        if (File(upper).existsSync()) return true;
      }
    }
    return false;
  }
}
