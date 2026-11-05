/// Toggling the operating system proxy (GNOME / Windows Internet Settings).
library;

import 'dart:ffi';
import 'dart:io';

class SystemProxyResult {
  const SystemProxyResult(this.ok, this.message);

  final bool ok;
  final String message;
}

enum SystemProxyState { enabled, disabled, unsupported, unknown }

class SystemProxy {
  static const String _host = '127.0.0.1';

  static Future<bool> isSupported() async {
    if (Platform.isWindows) return true;
    if (Platform.isLinux) return _gnomeAvailable();
    return false;
  }

  static Future<SystemProxyState> currentState() async {
    if (Platform.isWindows) return _windowsState();
    if (Platform.isLinux && await _gnomeAvailable()) {
      final result = await _run('gsettings', [
        'get',
        'org.gnome.system.proxy',
        'mode',
      ]);
      if (result == null) return SystemProxyState.unknown;
      final value = result.trim().replaceAll("'", '');
      return value == 'none'
          ? SystemProxyState.disabled
          : SystemProxyState.enabled;
    }
    return SystemProxyState.unsupported;
  }

  static Future<SystemProxyResult> enable({
    required int httpPort,
    int? socksPort,
  }) async {
    if (Platform.isWindows) {
      return _windowsEnable(httpPort);
    }
    if (Platform.isLinux) {
      if (!await _gnomeAvailable()) {
        return const SystemProxyResult(
          false,
          '没有检测到 GNOME 的代理设置（gsettings），请手动配置系统代理',
        );
      }
      final socks = socksPort ?? httpPort;
      final commands = <List<String>>[
        ['set', 'org.gnome.system.proxy', 'mode', 'manual'],
        ['set', 'org.gnome.system.proxy.http', 'host', _host],
        ['set', 'org.gnome.system.proxy.http', 'port', '$httpPort'],
        ['set', 'org.gnome.system.proxy.https', 'host', _host],
        ['set', 'org.gnome.system.proxy.https', 'port', '$httpPort'],
        ['set', 'org.gnome.system.proxy.socks', 'host', _host],
        ['set', 'org.gnome.system.proxy.socks', 'port', '$socks'],
        ['set', 'org.gnome.system.proxy', 'use-same-proxy', 'true'],
      ];
      for (final command in commands) {
        final result = await _run('gsettings', command);
        if (result == null) {
          return const SystemProxyResult(false, 'gsettings 执行失败');
        }
      }
      return SystemProxyResult(
        true,
        '已开启 GNOME 系统代理 | http/https $_host:$httpPort | socks $_host:$socks',
      );
    }
    return const SystemProxyResult(
      false,
      '当前平台暂不支持一键设置系统代理，请手动配置',
    );
  }

  static Future<SystemProxyResult> disable() async {
    if (Platform.isWindows) {
      final enable = await _run('reg', [
        'add',
        r'HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings',
        '/v',
        'ProxyEnable',
        '/t',
        'REG_DWORD',
        '/d',
        '0',
        '/f',
      ]);
      if (enable == null) {
        return const SystemProxyResult(false, '写入注册表失败');
      }
      _refreshWindowsProxy();
      return const SystemProxyResult(true, '已关闭 Windows 系统代理');
    }
    if (Platform.isLinux) {
      if (!await _gnomeAvailable()) {
        return const SystemProxyResult(
          false,
          '没有检测到 GNOME 的代理设置（gsettings），请手动配置系统代理',
        );
      }
      final result = await _run('gsettings', [
        'set',
        'org.gnome.system.proxy',
        'mode',
        'none',
      ]);
      if (result == null) {
        return const SystemProxyResult(false, 'gsettings 执行失败');
      }
      return const SystemProxyResult(true, '已关闭 GNOME 系统代理');
    }
    return const SystemProxyResult(
      false,
      '当前平台暂不支持一键设置系统代理，请手动配置',
    );
  }

  // ---------------------------------------------------------------- Linux

  static bool? _gnomeCached;

  static Future<bool> _gnomeAvailable() async {
    if (_gnomeCached != null) return _gnomeCached!;
    if (!Platform.isLinux) return _gnomeCached = false;
    final result = await _run('gsettings', [
      'get',
      'org.gnome.system.proxy',
      'mode',
    ]);
    return _gnomeCached = result != null;
  }

  static Future<String?> _run(String executable, List<String> arguments) async {
    try {
      final result = await Process.run(executable, arguments);
      if (result.exitCode != 0) return null;
      return '${result.stdout}';
    } on ProcessException {
      return null;
    }
  }

  // -------------------------------------------------------------- Windows

  static const String _windowsKey =
      r'HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings';

  static Future<SystemProxyState> _windowsState() async {
    try {
      final result = await Process.run(
        'reg',
        ['query', _windowsKey, '/v', 'ProxyEnable'],
      );
      if (result.exitCode != 0) return SystemProxyState.unknown;
      final text = '${result.stdout}';
      return text.contains('0x1')
          ? SystemProxyState.enabled
          : SystemProxyState.disabled;
    } on ProcessException {
      return SystemProxyState.unknown;
    }
  }

  static Future<SystemProxyResult> _windowsEnable(int port) async {
    final server = '$_host:$port';
    for (final args in [
      [
        'add',
        _windowsKey,
        '/v',
        'ProxyEnable',
        '/t',
        'REG_DWORD',
        '/d',
        '1',
        '/f',
      ],
      [
        'add',
        _windowsKey,
        '/v',
        'ProxyServer',
        '/t',
        'REG_SZ',
        '/d',
        server,
        '/f',
      ],
    ]) {
      final result = await _run('reg', args);
      if (result == null) {
        return const SystemProxyResult(false, '写入注册表失败');
      }
    }
    _refreshWindowsProxy();
    return SystemProxyResult(true, '已开启 Windows 系统代理 | $server');
  }

  /// Windows caches proxy settings; WinINet needs a nudge to reload them.
  static void _refreshWindowsProxy() {
    if (!Platform.isWindows) return;
    try {
      final lib = DynamicLibrary.open('wininet.dll');
      final setOption = lib.lookupFunction<
          Int32 Function(IntPtr, Uint32, Pointer<Void>, Uint32),
          int Function(int, int, Pointer<Void>, int)>('InternetSetOptionW');
      setOption(0, 39, nullptr, 0); // INTERNET_OPTION_SETTINGS_CHANGED
      setOption(0, 37, nullptr, 0); // INTERNET_OPTION_REFRESH
    } catch (_) {
      // Best effort.
    }
  }
}
