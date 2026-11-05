/// Login/boot autostart for the mihomo core.
///
/// Linux uses a systemd *user* unit (no root required): it starts with the
/// user session. Windows uses the per-user Run registry key.
library;

import 'dart:io';

import 'paths.dart';

enum AutostartState { enabled, disabled, unsupported, unknown }

class AutostartResult {
  const AutostartResult(this.ok, this.message);

  final bool ok;
  final String message;
}

class Autostart {
  Autostart({required this.paths, required this.binary});

  final AppPaths paths;

  /// Absolute path of the mihomo binary to launch.
  final String binary;

  static const String unitName = 'mihomo-tui-core.service';
  static const String _runValueName = 'mihomo-tui-core';

  static bool get supported => Platform.isLinux || Platform.isWindows;

  String get unitPath => '${AppPaths.homeDir}/.config/systemd/user/$unitName';

  String get _execStart => '"$binary" -d "${paths.mihomoHome}"';

  Future<AutostartState> state() async {
    if (Platform.isWindows) {
      final result = await _run('reg', [
        'query',
        r'HKCU\Software\Microsoft\Windows\CurrentVersion\Run',
        '/v',
        _runValueName,
      ]);
      if (result == null) return AutostartState.disabled;
      return AutostartState.enabled;
    }
    if (!Platform.isLinux) return AutostartState.unsupported;
    if (!File(unitPath).existsSync()) return AutostartState.disabled;
    final result = await _run('systemctl', [
      '--user',
      'is-enabled',
      unitName,
    ]);
    if (result == null) return AutostartState.disabled;
    return AutostartState.enabled;
  }

  Future<AutostartResult> enable() async {
    if (Platform.isWindows) {
      final result = await _run('reg', [
        'add',
        r'HKCU\Software\Microsoft\Windows\CurrentVersion\Run',
        '/v',
        _runValueName,
        '/t',
        'REG_SZ',
        '/d',
        _execStart,
        '/f',
      ]);
      return result == null
          ? const AutostartResult(false, '写入注册表失败')
          : const AutostartResult(true, '已加入 Windows 开机启动（登录时运行 mihomo）');
    }
    if (!Platform.isLinux) {
      return const AutostartResult(false, '当前平台暂不支持开机自启');
    }
    final file = File(unitPath);
    file.parent.createSync(recursive: true);
    file.writeAsStringSync('''
[Unit]
Description=mihomo core (managed by mihomo-tui)
Documentation=https://github.com/MetaCubeX/mihomo
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=$_execStart
Restart=on-failure
RestartSec=3
LimitNOFILE=65535

[Install]
WantedBy=default.target
''');
    if (await _run('systemctl', ['--user', 'daemon-reload']) == null) {
      return const AutostartResult(false, 'systemctl --user 不可用');
    }
    final enabled = await _run('systemctl', [
      '--user',
      'enable',
      '--now',
      unitName,
    ]);
    if (enabled == null) {
      return AutostartResult(
        false,
        '安装 systemd 用户服务失败，可手动执行：systemctl --user enable --now $unitName',
      );
    }
    return AutostartResult(
      true,
      '已启用 systemd 用户服务 $unitName（登录时自动启动 mihomo）',
    );
  }

  Future<AutostartResult> disable() async {
    if (Platform.isWindows) {
      final result = await _run('reg', [
        'delete',
        r'HKCU\Software\Microsoft\Windows\CurrentVersion\Run',
        '/v',
        _runValueName,
        '/f',
      ]);
      return result == null
          ? const AutostartResult(false, '删除注册表项失败')
          : const AutostartResult(true, '已移除 Windows 开机启动');
    }
    if (!Platform.isLinux) {
      return const AutostartResult(false, '当前平台暂不支持开机自启');
    }
    await _run('systemctl', ['--user', 'disable', '--now', unitName]);
    final file = File(unitPath);
    if (file.existsSync()) file.deleteSync();
    await _run('systemctl', ['--user', 'daemon-reload']);
    return AutostartResult(true, '已关闭开机自启（$unitName）');
  }

  static Future<String?> _run(String executable, List<String> args) async {
    try {
      final result = await Process.run(executable, args);
      if (result.exitCode != 0) return null;
      return '${result.stdout}';
    } on ProcessException {
      return null;
    }
  }
}
