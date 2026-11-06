/// The application shell: layout, input dispatch, state and background work.
library;

import 'dart:async';
import 'dart:io';

import '../model/profile.dart';
import '../model/profile_info.dart';
import '../model/settings.dart';
import '../service/autostart.dart';
import '../service/core_updater.dart';
import '../service/exporter.dart';
import '../service/mihomo_api.dart';
import '../service/mihomo_core.dart';
import '../service/paths.dart';
import '../service/profile_repo.dart';
import '../service/runtime.dart';
import '../service/system_proxy.dart';
import '../term/keys.dart';
import '../term/screen.dart';
import '../term/style.dart';
import '../term/terminal.dart';
import '../term/width.dart';
import '../util/clipboard.dart';
import '../util/format.dart';
import '../util/shell.dart';
import '../version.dart';
import 'app_context.dart';
import 'overlay.dart';
import 'painter.dart';
import 'theme.dart';
import 'views/dashboard_view.dart';
import 'views/logs_view.dart';
import 'views/profiles_view.dart';
import 'views/proxies_view.dart';
import 'views/settings_view.dart';
import 'views/view.dart';

class App implements AppContext {
  App({
    required this.terminal,
    required Settings settings,
    String? configDir,
    String? mihomoHome,
    String? binaryOverride,
    String? editorOverride,
  })  : _settings = settings,
        _configDirOverride = configDir,
        _mihomoHomeOverride = mihomoHome,
        _binaryOverride = binaryOverride,
        _editorOverride = editorOverride {
    _initServices(settings);
  }

  @override
  final TerminalBackend terminal;

  final String? _configDirOverride;
  final String? _mihomoHomeOverride;
  final String? _binaryOverride;
  final String? _editorOverride;

  Theme _theme = Theme.dark;
  bool? _lightBackground;
  int? _terminalBackground;
  String? _hoverId;

  @override
  Theme get theme => _theme;

  @override
  String? get hoverId => _hoverId;

  @override
  late AppPaths paths;

  @override
  late ProfileRepository repo;

  @override
  late MihomoCore core;

  Settings _settings;

  @override
  Settings get settings => _settings;

  late Screen _screen;
  final ScreenRenderer _renderer = ScreenRenderer();
  List<Hit> _hits = const [];
  bool _dirty = true;
  bool _exiting = false;

  Timer? _frameTimer;
  Timer? _tickTimer;
  final Completer<void> _quitCompleter = Completer<void>();
  StreamSubscription<TermEvent>? _eventSubscription;
  final List<StreamSubscription<ProcessSignal>> _signalSubscriptions = [];

  final View dashboard = DashboardView();
  final View profiles = ProfilesView();
  final View proxies = ProxiesView();
  final View logs = LogsView();
  final View settingsView = SettingsView();
  late final List<View> views = [
    dashboard,
    profiles,
    proxies,
    logs,
    settingsView
  ];
  int _viewIndex = 0;
  bool _sidebarFocused = false;

  final List<Overlay> _overlays = [];

  String? _toastMessage;
  ToastLevel _toastLevel = ToastLevel.info;
  DateTime? _toastUntil;

  bool _busy = false;
  String? _busyLabel;
  int _spinnerFrame = 0;
  DateTime _lastSpinner = DateTime.fromMillisecondsSinceEpoch(0);

  CoreStatus? _coreStatus;
  DateTime? _coreStartedAt;
  AutostartState _autostartState = AutostartState.unknown;
  DateTime _autostartChecked = DateTime.fromMillisecondsSinceEpoch(0);
  SystemProxyState _systemProxyState = SystemProxyState.unknown;
  DateTime _systemProxyChecked = DateTime.fromMillisecondsSinceEpoch(0);
  String? _lanAddress;
  DateTime _lanAddressChecked = DateTime.fromMillisecondsSinceEpoch(0);
  final Map<String, MirrorProbe> _mirrorProbes = {};
  final Set<String> _mirrorProbing = {};
  CoreRelease? _releaseCache;
  DateTime _releaseCachedAt = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _mirrorProbedAt = DateTime.fromMillisecondsSinceEpoch(0);

  MihomoApi? _api;
  String? _apiKey;
  bool _apiOnline = false;
  String? _apiVersion;
  ApiConfig? _apiConfig;
  ProxySnapshot? _proxySnapshot;
  ConnectionsInfo? _connections;
  ProfileInfo? _activeInfo;
  String? _activeInfoKey;

  bool _refreshing = false;
  DateTime _lastProxyFetch = DateTime.fromMillisecondsSinceEpoch(0);

  // ---------------------------------------------------------------- lifecycle

  void _initServices(Settings settings) {
    final runtime = Runtime.build(
      settings: settings,
      configDir: _configDirOverride,
      mihomoHome: _mihomoHomeOverride,
      binaryOverride: _binaryOverride,
      editorOverride: _editorOverride,
    );
    paths = runtime.paths;
    repo = runtime.repo;
    core = runtime.core;
    repo.ensureLayout();
  }

  @override
  CoreStatus? get coreStatus => _coreStatus;

  @override
  MihomoApi? get apiRef => _apiOnline ? _api : null;

  @override
  AutostartState get autostartState => _autostartState;

  @override
  SystemProxyState get systemProxyState => _systemProxyState;

  @override
  String? get lanAddress => _lanAddress;

  @override
  bool get apiOnline => _apiOnline;

  @override
  String? get apiVersion => _apiVersion;

  @override
  ApiConfig? get apiConfig => _apiConfig;

  @override
  ProxySnapshot? get proxySnapshot => _proxySnapshot;

  @override
  ConnectionsInfo? get connections => _connections;

  @override
  ProfileInfo? get activeInfo => _activeInfo;

  @override
  DateTime? get coreStartedAt => _coreStartedAt;

  @override
  bool get busy => _busy;

  @override
  String? get busyLabel => _busyLabel;

  Future<void> run() async {
    _screen = Screen(terminal.size.columns, terminal.size.rows);
    _renderer
      ..trueColor = terminal.supportsTrueColor
      ..refreshColorMode();
    terminal.start();
    terminal.setTitle('$appName $appVersion');
    _eventSubscription = terminal.events.listen(_onEvent);
    _watchSignals();
    _terminalBackground =
        await terminal.probeBackgroundColor() ?? _backgroundFromEnv();
    _lightBackground = _terminalBackground == null
        ? null
        : Theme.luminance(_terminalBackground!) > 0.55;
    _rebuildTheme();
    await _refreshServices();
    _dirty = true;
    _render();
    _frameTimer =
        Timer.periodic(const Duration(milliseconds: 16), (_) => _onFrame());
    _tickTimer = Timer.periodic(const Duration(milliseconds: 1000), (_) {
      unawaited(_onTick());
    });
    await _quitCompleter.future;
    _frameTimer?.cancel();
    _tickTimer?.cancel();
    await _eventSubscription?.cancel();
    for (final subscription in _signalSubscriptions) {
      await subscription.cancel();
    }
    _api?.dispose();
    terminal.stop();
    final farewell = _farewell;
    if (farewell != null) {
      stdout.writeln(farewell);
      await stdout.flush();
    }
  }

  void _watchSignals() {
    for (final signal in [
      ProcessSignal.sigint,
      ProcessSignal.sigterm,
      ProcessSignal.sighup,
    ]) {
      try {
        _signalSubscriptions.add(signal.watch().listen((_) {
          quit();
        }));
      } catch (_) {
        // Signals are not supported on all platforms.
      }
    }
  }

  String? _farewell;

  void quit() {
    if (_exiting) return;
    _exiting = true;
    if (!_quitCompleter.isCompleted) _quitCompleter.complete();
  }

  @override
  void hideToBackground() {
    final pid = _coreStatus?.pid;
    _farewell = '$appName 已转入后台'
        '${pid == null ? '' : '，mihomo 继续运行（pid $pid）'}'
        '。再次运行 $appName 即可回到面板。';
    quit();
  }

  void _rebuildTheme() {
    final light = switch (_colorMode()) {
      'light' => true,
      'dark' => false,
      _ => _lightBackground ?? false,
    };
    _theme = Theme.build(
      light: light,
      accent: _settings.accent ?? 'blue',
    );
    _dirty = true;
  }

  String _colorMode() => _settings.colorMode ?? 'auto';

  /// Fallback for terminals that do not answer OSC 11 but export COLORFGBG
  /// (e.g. `15;0` for white on black).
  int? _backgroundFromEnv() {
    final raw = Platform.environment['COLORFGBG'];
    if (raw == null || raw.trim().isEmpty) return null;
    final index = int.tryParse(raw.split(';').last.trim());
    if (index == null || index < 0 || index >= Theme.ansiPalette.length) {
      return null;
    }
    return Theme.ansiPalette[index];
  }

  // ------------------------------------------------------------------ drawing

  void _onFrame() {
    final now = DateTime.now();
    if (_busy && now.difference(_lastSpinner).inMilliseconds > 90) {
      _lastSpinner = now;
      _spinnerFrame = (_spinnerFrame + 1) % 8;
      _dirty = true;
    }
    if (_toastUntil != null && now.isAfter(_toastUntil!)) {
      _toastUntil = null;
      _toastMessage = null;
      _dirty = true;
    }
    if (_dirty) _render();
  }

  void _render() {
    _dirty = false;
    _screen.clear();
    final p = Painter(_screen, theme);
    final width = _screen.width;
    final height = _screen.height;
    _screen.fillRect(0, 0, width, height, Style(bg: theme.background));
    if (width < 40 || height < 10) {
      p.text(1, 1, '窗口太小（至少 40x10）', Style(fg: theme.red));
      _hits = List<Hit>.unmodifiable(p.hits);
      terminal.write(_renderer.render(_screen));
      return;
    }

    _drawTopBar(p, width);
    final sidebarWidth = width < 100 ? 20 : 24;
    final sidebarRect = Rect(1, 1, sidebarWidth, height - 2);
    final contentRect = Rect(
      sidebarWidth + 2,
      1,
      width - sidebarWidth - 3,
      height - 2,
    );
    _drawSidebar(p, sidebarRect);
    _drawContent(p, contentRect);
    _drawBottomBar(p, width, height);

    _overlays.removeWhere((overlay) => overlay.isDismissed);
    for (final overlay in _overlays) {
      overlay.draw(p);
    }

    _hits = List<Hit>.unmodifiable(p.hits);
    terminal.write(_renderer.render(_screen));
  }

  void _drawTopBar(Painter p, int width) {
    p.fill(Rect(0, 0, width, 1), Style(bg: theme.header));
    var x = 1;
    x += p.text(
        x, 0, appName, Style(fg: theme.accent, bg: theme.header, bold: true));
    x += p.text(
        x + 1, 0, 'v$appVersion', Style(fg: theme.muted, bg: theme.header));
    x += 6;

    final right = <(String, Style)>[];
    if (_busy) {
      const frames = ['⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧'];
      right.add((
        '${frames[_spinnerFrame]} ${_busyLabel ?? '处理中'}',
        Style(fg: theme.yellow, bg: theme.header),
      ));
      right.add(('  ', Style(bg: theme.header)));
    }
    right.add((
      _statusText(),
      Style(fg: _statusColor(), bg: theme.header, bold: true),
    ));
    right.add(('  ', Style(bg: theme.header)));
    if (repo.activeName != null) {
      right.add((
        repo.activeName!,
        Style(fg: theme.accentSoft, bg: theme.header),
      ));
      right.add(('  ', Style(bg: theme.header)));
    }
    var rightX = width - 1;
    for (final item in right.reversed) {
      final valueWidth = textWidth(item.$1);
      rightX -= valueWidth;
      if (rightX < x) break;
      p.text(rightX, 0, item.$1, item.$2);
    }
  }

  String _statusText() {
    final status = _coreStatus;
    if (status == null) return '检测中';
    if (!status.running) return '未运行';
    final version = status.version == null ? '' : ' ${status.version}';
    return '运行中$version';
  }

  int _statusColor() {
    final status = _coreStatus;
    if (status == null) return theme.muted;
    if (!status.running) return theme.red;
    if (!_apiOnline) return theme.yellow;
    return theme.green;
  }

  void _drawSidebar(Painter p, Rect rect) {
    p.drawBox(rect, focused: _sidebarFocused, title: '导航');
    final innerX = rect.x + 2;
    final innerWidth = rect.width - 4;
    var y = rect.y + 1;
    for (var index = 0; index < views.length; index++) {
      final view = views[index];
      final selected = index == _viewIndex;
      final rowRect = Rect(rect.x + 1, y, rect.width - 2, 1);
      final hoveringNav = _hoverId != null && _hoverId!.startsWith('nav');
      final hovered = _hoverId == 'nav$index';
      final style = Style(
        fg: selected ? theme.accentSoft : (hovered ? theme.text : theme.muted),
        bg: theme.panel,
        bold: selected || hovered,
      );
      // The '>' marker follows the mouse while hovering the sidebar, but the
      // displayed page only changes on click.
      final cursor = hoveringNav ? hovered : selected;
      if (cursor) {
        p.text(rect.x + 1, y, '>', Style(fg: theme.accent, bg: theme.panel));
      }
      p.text(innerX + 1, y, truncate(view.label, innerWidth), style);
      p.text(
        rect.right - 3,
        y,
        '${index + 1}',
        Style(fg: selected ? theme.muted : theme.border, bg: style.bg),
      );
      p.hit(
        rowRect,
        id: 'nav$index',
        // Hover only highlights the entry; it must not switch pages.
        onHover: () {},
        onPress: () {
          _viewIndex = index;
          _sidebarFocused = false;
          _syncView();
        },
      );
      y++;
    }

    // Bottom summary: core and profile state.
    final summary = <(String, String, Style)>[
      (
        '状态',
        _coreStatus?.running == true ? '运行中' : '未运行',
        Style(fg: _statusColor(), bg: theme.panel, bold: true),
      ),
      (
        '版本',
        _coreStatus?.version ?? '-',
        Style(fg: theme.muted, bg: theme.panel)
      ),
      (
        '配置',
        repo.activeName ?? '未选择',
        Style(fg: theme.accentSoft, bg: theme.panel)
      ),
      (
        '控制器',
        _apiOnline
            ? '已连接'
            : (_activeInfo?.externalController == null ? '-' : '未连接'),
        Style(fg: _apiOnline ? theme.green : theme.muted, bg: theme.panel),
      ),
    ];
    var summaryY = rect.bottom - 1 - summary.length;
    if (summaryY > y + 1) {
      p.text(rect.x + 1, summaryY - 1, '─' * (rect.width - 2),
          Style(fg: theme.border, bg: theme.panel));
      for (final item in summary) {
        if (summaryY >= rect.bottom - 1) break;
        p.text(rect.x + 2, summaryY, item.$1,
            Style(fg: theme.muted, bg: theme.panel));
        p.text(
          rect.x + 10,
          summaryY,
          truncate(item.$2, rect.width - 12),
          item.$3,
        );
        summaryY++;
      }
    }
  }

  void _drawContent(Painter p, Rect rect) {
    final view = views[_viewIndex];
    // Views draw their own top-level borders so that nesting never produces
    // doubled border columns.
    view.draw(this, p, rect, focused: !_sidebarFocused);
  }

  void _drawBottomBar(Painter p, int width, int height) {
    final y = height - 1;
    p.fill(Rect(0, y, width, 1), Style(bg: theme.header));
    var x = 1;
    final message = _toastMessage;
    if (message != null) {
      final color = switch (_toastLevel) {
        ToastLevel.info => theme.accent,
        ToastLevel.success => theme.green,
        ToastLevel.warning => theme.yellow,
        ToastLevel.error => theme.red,
      };
      p.text(x, y, truncate(message, width - 28),
          Style(fg: color, bg: theme.header, bold: true));
      final rightText =
          _sidebarFocused ? 'Tab 内容区 | ? 帮助 | q 退出' : 'Esc 侧栏 | ? 帮助 | q 退出';
      final rightWidth = textWidth(rightText);
      if (width - rightWidth - 2 > 0) {
        p.text(width - rightWidth - 1, y, rightText,
            Style(fg: theme.muted, bg: theme.header));
      }
      return;
    }
    final view = views[_viewIndex];
    final hints = _sidebarFocused
        ? const [
            KeyHint('上下', '选择'),
            KeyHint('Enter', '打开'),
            KeyHint('Tab', '内容区'),
          ]
        : view.hints(this);
    for (final hint in hints) {
      if (x + textWidth(hint.keys) + textWidth(hint.label) + 5 > width - 26) {
        break;
      }
      final keyStyle = Style(fg: theme.chipText, bg: theme.muted, bold: true);
      x += p.text(x, y, ' ${hint.keys} ', keyStyle);
      x += p.text(
          x + 1, y, hint.label, Style(fg: theme.muted, bg: theme.header));
      x += 2;
    }
    final rightText =
        _sidebarFocused ? 'Tab 内容区 | ? 帮助 | q 退出' : 'Esc 侧栏 | ? 帮助 | q 退出';
    final rightWidth = textWidth(rightText);
    if (width - rightWidth - 2 > x) {
      p.text(width - rightWidth - 1, y, rightText,
          Style(fg: theme.muted, bg: theme.header));
    }
  }

  // ------------------------------------------------------------------- events

  void _onEvent(TermEvent event) {
    switch (event) {
      case ResizeEvent(:final columns, :final rows):
        _screen.resize(columns, rows);
        _renderer.invalidate();
        _dirty = true;
      case KeyEvent():
        _handleKey(event);
      case MouseEvent():
        _handleMouse(event);
      case ColorReportEvent(
          red: final red,
          green: final green,
          blue: final blue,
          isBackground: true
        ):
        _terminalBackground = (red << 16) | (green << 8) | blue;
        _lightBackground = Theme.luminance(_terminalBackground!) > 0.55;
        _rebuildTheme();
      case ColorReportEvent():
        break;
    }
  }

  void _handleKey(KeyEvent event) {
    if (_overlays.isNotEmpty) {
      _overlays.last.handleKey(event);
      _dirty = true;
      return;
    }
    if (event.isCtrl('c')) {
      quit();
      return;
    }
    if (event.isChar('q')) {
      quit();
      return;
    }
    if (event.isChar('?')) {
      _showHelp();
      return;
    }
    if (event.isChar('h') && !_sidebarFocused) {
      hideToBackground();
      return;
    }
    if (event.kind == KeyKind.char &&
        !event.ctrl &&
        !event.alt &&
        event.char != null &&
        '12345'.contains(event.char!)) {
      _viewIndex = int.parse(event.char!) - 1;
      _sidebarFocused = false;
      _syncView();
      return;
    }
    if (_sidebarFocused) {
      if (event.kind == KeyKind.down || event.isChar('j')) {
        _viewIndex = (_viewIndex + 1) % views.length;
        _syncView();
        return;
      }
      if (event.kind == KeyKind.up || event.isChar('k')) {
        _viewIndex = (_viewIndex - 1 + views.length) % views.length;
        _syncView();
        return;
      }
      if (event.kind == KeyKind.enter ||
          event.kind == KeyKind.right ||
          event.kind == KeyKind.tab) {
        _sidebarFocused = false;
        _dirty = true;
        return;
      }
      return;
    }
    final view = views[_viewIndex];
    if (view.onKey(this, event)) {
      _dirty = true;
      return;
    }
    if (event.kind == KeyKind.escape ||
        event.kind == KeyKind.tab ||
        event.kind == KeyKind.left) {
      _sidebarFocused = true;
      _dirty = true;
    }
  }

  void _handleMouse(MouseEvent event) {
    for (final overlay in _overlays.reversed) {
      if (overlay.handleMouse(event)) {
        _dirty = true;
        return;
      }
    }
    if (_overlays.isNotEmpty) return;

    if (event.kind == MouseKind.move) {
      _handleHover(event);
      return;
    }

    if (event.kind == MouseKind.wheel) {
      for (final hit in _hits.reversed) {
        if (hit.onWheel != null && hit.rect.contains(event.x, event.y)) {
          hit.onWheel!(event.wheelDelta);
          _dirty = true;
          return;
        }
      }
      views[_viewIndex].onWheel(this, event.wheelDelta);
      _dirty = true;
      return;
    }
    if (event.kind == MouseKind.press && event.button == MouseButton.left) {
      for (final hit in _hits.reversed) {
        if (hit.rect.contains(event.x, event.y)) {
          hit.onPress?.call();
          _dirty = true;
          return;
        }
      }
    }
  }

  void _handleHover(MouseEvent event) {
    Hit? target;
    for (final hit in _hits.reversed) {
      if (hit.onHover != null && hit.rect.contains(event.x, event.y)) {
        target = hit;
        break;
      }
    }
    if (target?.id == _hoverId) return;
    _hoverId = target?.id;
    target?.onHover?.call();
    _dirty = true;
  }

  /// Terminals can report a stale size right after a resize (or miss the
  /// signal entirely); re-checking keeps the frame in sync with the window,
  /// otherwise long lines wrap and look like broken borders.
  void _syncTerminalSize() {
    final size = terminal.size;
    if (size.columns == _screen.width && size.rows == _screen.height) return;
    _screen.resize(size.columns, size.rows);
    _renderer.invalidate();
    _dirty = true;
  }

  void _syncView() {
    _dirty = true;
    unawaited(_refreshServices());
  }

  void _showHelp() {
    final view = views[_viewIndex];
    showOverlay(HelpOverlay([
      (
        '全局',
        const [
          KeyHint('Tab', '在侧栏与内容区之间切换'),
          KeyHint('1-5', '直接跳转到对应页面'),
          KeyHint('?', '打开/关闭本帮助'),
          KeyHint('h', '隐藏面板（核心继续后台运行）'),
          KeyHint('q', '退出程序'),
          KeyHint('上下 / 滚轮', '移动或滚动'),
          KeyHint('Enter', '确认 / 执行'),
          KeyHint('Esc', '取消 / 返回'),
          KeyHint('Ctrl+C / V', '文本框中复制 / 粘贴'),
          KeyHint('Ctrl+A / X', '全选 / 剪切'),
          KeyHint('Shift+方向键', '在文本框中选中文本'),
        ],
      ),
      ('当前页面 | ${view.label}', view.hints(this)),
      (
        '订阅',
        const [
          KeyHint('a', '添加订阅（输入地址与名称）'),
          KeyHint('Enter', '启用订阅（复制为 config.yaml）'),
          KeyHint('u / U', '更新选中 / 全部订阅'),
          KeyHint('r', '重命名'),
          KeyHint('d', '删除'),
          KeyHint('e', '编辑订阅信息（名称 / 订阅地址）'),
          KeyHint('E', '编辑订阅配置文件（profiles/<名称>.yaml）'),
          KeyHint('i', '查看配置详情'),
          KeyHint('双击', '启用订阅'),
        ],
      ),
      (
        '代理',
        const [
          KeyHint('Tab / 左右', '切换代理组与节点列'),
          KeyHint('Enter', '选择节点'),
          KeyHint('t', '测试当前节点延迟'),
          KeyHint('T', '测速当前代理组全部节点（Esc 取消）'),
        ],
      ),
      (
        '概览',
        const [
          KeyHint('s', '启动 / 停止核心'),
          KeyHint('R', '重启核心'),
          KeyHint('r', '热重载配置'),
          KeyHint('m', '循环切换模式'),
          KeyHint('o', '打开控制面板'),
          KeyHint('p', '一键切换系统代理'),
        ],
      ),
      (
        '日志',
        const [
          KeyHint('s', '循环视图：标准 / 精简'),
          KeyHint('Enter', '查看选中日志的详情'),
          KeyHint('f', '跟随开关（跟随时不显示 > 列）'),
          KeyHint('r', '重新读取'),
          KeyHint('c', '清空日志'),
          KeyHint('g / G', '跳到开头 / 结尾'),
        ],
      ),
      (
        '设置',
        const [
          KeyHint('Enter', '编辑条目 / 切换主题色 / 明暗模式'),
          KeyHint('d', '重新检测核心'),
          KeyHint('i', '关于'),
        ],
      ),
    ]));
  }

  // ------------------------------------------------------------------ actions

  @override
  void requestFrame() {
    _dirty = true;
  }

  @override
  void openView(int index) {
    if (index < 0 || index >= views.length) return;
    _viewIndex = index;
    _sidebarFocused = false;
    _syncView();
  }

  @override
  void showOverlay(Overlay overlay) {
    _overlays.add(overlay);
    _dirty = true;
  }

  @override
  void toast(String message, {ToastLevel level = ToastLevel.info}) {
    _toastMessage = message;
    _toastLevel = level;
    _toastUntil = DateTime.now().add(const Duration(seconds: 5));
    _dirty = true;
  }

  @override
  void confirm({
    required String title,
    required String message,
    List<String> detail = const [],
    String confirmLabel = '确认',
    bool danger = false,
    required void Function() onConfirm,
  }) {
    showOverlay(ConfirmOverlay(
      title: title,
      message: message,
      detail: detail,
      confirmLabel: confirmLabel,
      danger: danger,
      onConfirm: onConfirm,
    ));
  }

  Future<void> _runBusy(
    String label,
    Future<void> Function() action,
  ) async {
    _busy = true;
    _busyLabel = label;
    _dirty = true;
    try {
      await action();
    } catch (error) {
      toast('$error', level: ToastLevel.error);
    } finally {
      _busy = false;
      _busyLabel = null;
      _dirty = true;
    }
  }

  @override
  Future<void> refresh() async {
    await _refreshServices();
    _dirty = true;
  }

  Future<void> _refreshServices() async {
    if (_refreshing) return;
    _refreshing = true;
    try {
      final status = await core.status();
      _coreStatus = status;
      _coreStartedAt = null;
      if (status.running) {
        final pidFile = File(paths.pidFile);
        if (pidFile.existsSync()) {
          try {
            _coreStartedAt = pidFile.statSync().modified;
          } catch (_) {}
        }
      }

      await _refreshActiveInfo();
      await _refreshApi();
      await _refreshAutostart();
      await _refreshSystemProxy();
      await _refreshLanAddress();
    } finally {
      _refreshing = false;
      _dirty = true;
    }
  }

  Autostart? _autostartOrNull() {
    final binary = core.resolveBinary();
    if (binary == null) return null;
    return Autostart(paths: paths, binary: binary);
  }

  Future<void> _refreshSystemProxy({bool force = false}) async {
    if (!force &&
        DateTime.now().difference(_systemProxyChecked) <
            const Duration(seconds: 10)) {
      return;
    }
    _systemProxyChecked = DateTime.now();
    _systemProxyState = await SystemProxy.currentState();
  }

  /// First non-loopback IPv4 address, used for the "LAN proxy" summary row.
  Future<void> _refreshLanAddress() async {
    if (DateTime.now().difference(_lanAddressChecked) <
        const Duration(seconds: 30)) {
      return;
    }
    _lanAddressChecked = DateTime.now();
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      _lanAddress = null;
      for (final interface in interfaces) {
        for (final address in interface.addresses) {
          if (address.isLoopback) continue;
          _lanAddress ??= address.address;
        }
      }
    } catch (_) {
      _lanAddress = null;
    }
  }

  @override
  Future<void> toggleAllowLan() async {
    final api = apiRef;
    if (api == null) {
      toast('控制器未连接，无法切换局域网代理', level: ToastLevel.warning);
      return;
    }
    final enabled = _apiConfig?.allowLan ?? false;
    try {
      await api.setAllowLan(!enabled);
      await _refreshServices();
      toast(
        !enabled ? '已开启局域网代理' : '已关闭局域网代理',
        level: ToastLevel.success,
      );
    } on ApiException catch (error) {
      toast('切换失败：${error.message}', level: ToastLevel.error);
    }
  }

  Future<void> _refreshAutostart() async {
    if (DateTime.now().difference(_autostartChecked) <
        const Duration(seconds: 10)) {
      return;
    }
    _autostartChecked = DateTime.now();
    final autostart = _autostartOrNull();
    if (autostart == null) {
      _autostartState = AutostartState.unsupported;
      return;
    }
    _autostartState = await autostart.state();
    if (_autostartState == AutostartState.enabled) {
      // The service started the core for us: adopt its pid so the overview
      // shows a managed process instead of an "external" one.
      final pid = await autostart.mainPid() ?? core.detectPid();
      if (pid != null) core.adoptPid(pid);
    }
  }

  @override
  Future<void> updateCore() async {
    final updater = CoreUpdater(
      mirror: mirrorById(_settings.mirror),
      proxy: _settings.downloadProxy,
    );
    final target = core.resolveBinary() ?? CoreUpdater.defaultInstallPath();
    CoreRelease? release;
    final current = _coreStatus?.version ?? await core.version();
    await _runBusy('检查内核更新', () async {
      try {
        _busyLabel = '查询最新版本~';
        _dirty = true;
        release = await updater.latest();
      } on CoreUpdateException catch (error) {
        toast('检查更新失败：${error.message}', level: ToastLevel.error);
        return;
      }
    });
    final found = release;
    if (found == null) return;
    if (_sameVersion(current, found.tag)) {
      toast('已是最新版 ${found.tag}', level: ToastLevel.success);
      return;
    }
    confirm(
      title: '发现新版本',
      message: '${current ?? '未安装'} → ${found.tag}',
      detail: [
        '平台/架构：${CoreUpdater.platformLabel}',
        '下载源：${updater.mirror.label}',
        '目标路径：$target',
        '原文件会备份为 .bak',
      ],
      confirmLabel: '下载并安装',
      onConfirm: () => unawaited(_runCoreUpdate(updater, target, found)),
    );
  }

  static bool _sameVersion(String? current, String tag) {
    String normalize(String value) =>
        value.replaceFirst(RegExp(r'^[vV]'), '').split(' ').first.trim();
    if (current == null || current.isEmpty) return false;
    return normalize(current) == normalize(tag);
  }

  Future<void> _runCoreUpdate(
    CoreUpdater updater,
    String target,
    CoreRelease release,
  ) async {
    final before = _coreStatus?.version;
    await _runBusy('更新内核', () async {
      try {
        _busyLabel = '下载 ${release.assetName}';
        _dirty = true;
        final result = await updater.install(
          release,
          targetPath: target,
          onProgress: (received, total) {
            _busyLabel = total == null
                ? '下载 ${formatBytes(received)}'
                : '下载 ${formatBytes(received)} / ${formatBytes(total)}';
            _dirty = true;
          },
        );
        await _refreshServices();
        toast(
          '内核已更新：${before ?? '未安装'} -> ${result.version}',
          level: ToastLevel.success,
        );
        if (_coreStatus?.running == true) {
          confirm(
            title: '重启核心',
            message: '内核已更新，是否重启 mihomo 使其生效？',
            confirmLabel: '重启',
            onConfirm: () => unawaited(restartCore()),
          );
        }
      } on CoreUpdateException catch (error) {
        toast('更新失败：${error.message}', level: ToastLevel.error);
      } catch (error) {
        toast('更新失败：$error', level: ToastLevel.error);
      }
    });
  }

  @override
  Map<String, MirrorProbe> get mirrorProbes => _mirrorProbes;

  @override
  bool isMirrorProbing(String id) => _mirrorProbing.contains(id);

  @override
  void showMirrorPicker() {
    showOverlay(MirrorOverlay(
      current: _settings.mirror ?? 'direct',
      probes: _mirrorProbes,
      probing: isMirrorProbing,
      onSelect: (id) {
        unawaited(applySettings(_settings.copyWith(mirror: id)));
        toast('下载镜像：${mirrorById(id).label}', level: ToastLevel.success);
      },
      onRefresh: () => unawaited(_probeMirrors(force: true)),
    ));
    unawaited(_probeMirrors());
  }

  Future<void> _probeMirrors({bool force = false}) async {
    if (_mirrorProbing.isNotEmpty) return;
    if (!force &&
        _mirrorProbes.isNotEmpty &&
        DateTime.now().difference(_mirrorProbedAt) <
            const Duration(minutes: 5)) {
      return;
    }
    final updater = CoreUpdater(mirror: mirrorById(_settings.mirror));
    var release = _releaseCache;
    if (release == null ||
        DateTime.now().difference(_releaseCachedAt) >
            const Duration(minutes: 10)) {
      try {
        release = await updater.latest();
        _releaseCache = release;
        _releaseCachedAt = DateTime.now();
      } on CoreUpdateException catch (error) {
        for (final mirror in coreMirrors) {
          _mirrorProbes[mirror.id] = MirrorProbe.unavailable(error.message);
        }
        _mirrorProbedAt = DateTime.now();
        _dirty = true;
        return;
      }
    }
    final target = release;
    _mirrorProbedAt = DateTime.now();
    await Future.wait(coreMirrors.map((mirror) async {
      _mirrorProbing.add(mirror.id);
      _dirty = true;
      final probe = await CoreUpdater.probe(
        mirror,
        target,
        proxy: _settings.downloadProxy,
      );
      _mirrorProbes[mirror.id] = probe;
      _mirrorProbing.remove(mirror.id);
      _dirty = true;
    }));
  }

  @override
  Future<void> toggleAutostart() async {
    final autostart = _autostartOrNull();
    if (autostart == null) {
      toast('未找到 mihomo 可执行文件，无法创建自启服务', level: ToastLevel.warning);
      return;
    }
    if (_autostartState == AutostartState.enabled) {
      confirm(
        title: '关闭开机自启',
        message: '将停用并删除 mihomo 的自启服务，之后不再随登录自动启动。',
        confirmLabel: '关闭自启',
        danger: true,
        onConfirm: () => unawaited(_applyAutostart(autostart, false)),
      );
      return;
    }
    confirm(
      title: '开启开机自启',
      message: '创建一个随登录启动 mihomo 的服务（Linux 为 systemd 用户服务，Windows 为注册表 Run 项）。',
      detail: const [
        '服务会直接读取当前生效的 config.yaml。',
        '若希望未登录时也启动，可执行：sudo loginctl enable-linger \$USER',
        '开启后请不要在概览里重复手动启动同一个核心。',
      ],
      confirmLabel: '开启自启',
      onConfirm: () => unawaited(_applyAutostart(autostart, true)),
    );
  }

  Future<void> _applyAutostart(Autostart autostart, bool enable) async {
    await _runBusy(enable ? '安装自启服务' : '移除自启服务', () async {
      final result =
          enable ? await autostart.enable() : await autostart.disable();
      _autostartChecked = DateTime.fromMillisecondsSinceEpoch(0);
      await _refreshAutostart();
      await _refreshSystemProxy();
      await _refreshLanAddress();
      toast(
        result.message,
        level: result.ok ? ToastLevel.success : ToastLevel.error,
      );
    });
  }

  Future<void> _refreshActiveInfo() async {
    final file = File(paths.mihomoConfigFile);
    if (!file.existsSync()) {
      _activeInfo = null;
      _activeInfoKey = null;
      return;
    }
    String key;
    try {
      final stat = file.statSync();
      key = '${stat.modified.toIso8601String()}:${stat.size}';
    } catch (_) {
      return;
    }
    if (key == _activeInfoKey) return;
    _activeInfoKey = key;
    try {
      _activeInfo = ProfileInfo.parse(file.readAsStringSync());
    } catch (_) {
      _activeInfo = null;
    }
  }

  Future<void> _refreshApi() async {
    final info = _activeInfo;
    final base = info?.apiBase;
    if (base == null) {
      _apiOnline = false;
      _apiConfig = null;
      _proxySnapshot = null;
      _connections = null;
      return;
    }
    final key = '$base|${info?.secret ?? ''}';
    if (_apiKey != key) {
      _api?.dispose();
      _api = MihomoApi(baseUrl: base, secret: info?.secret);
      _apiKey = key;
      _apiVersion = null;
      _proxySnapshot = null;
    }
    try {
      final api = _api!;
      _apiVersion ??= await api.version();
      _apiConfig = await api.configs();
      _apiOnline = true;
      final needsProxies = (_viewIndex == 0 || _viewIndex == 2) &&
          DateTime.now().difference(_lastProxyFetch) >
              const Duration(milliseconds: 900);
      if (needsProxies) {
        _proxySnapshot = await api.proxies();
        _lastProxyFetch = DateTime.now();
      }
      if (_viewIndex == 0) {
        _connections = await api.connections();
      }
    } on ApiException {
      _apiOnline = false;
      _apiConfig = null;
      _apiVersion = null;
      if (_viewIndex == 2) _proxySnapshot = null;
    }
  }

  Future<void> _onTick() async {
    if (_exiting) return;
    _syncTerminalSize();
    await _refreshServices();
    if (_exiting) return;
    try {
      views[_viewIndex].onTick(this);
    } catch (_) {}
    _dirty = true;
  }

  @override
  Future<void> startCore() async {
    if (core.resolveBinary() == null) {
      toast('未找到 mihomo 可执行文件，请在「设置」中指定路径', level: ToastLevel.error);
      return;
    }
    if (repo.activeName == null && !File(paths.mihomoConfigFile).existsSync()) {
      toast('请先在「订阅」中选择一个配置', level: ToastLevel.warning);
      return;
    }
    final status = _coreStatus;
    if (status?.running == true) {
      final external = status?.pidFromFile == false;
      confirm(
        title: '已有 mihomo 在运行',
        message: '检测到 pid ${status?.pid} 的 mihomo 进程'
            '${external ? '（由其他程序启动）' : ''}，需要先结束它才能启动新的实例。',
        detail: external
            ? const ['如果该进程由 mihomo-party 等工具托管，结束它可能影响那些程序。']
            : const [],
        confirmLabel: '结束并启动',
        danger: true,
        onConfirm: () => unawaited(_startCoreNow(stopFirst: true)),
      );
      return;
    }
    await _startCoreNow();
  }

  Future<void> _startCoreNow({bool stopFirst = false}) async {
    await _runBusy('启动核心', () async {
      if (stopFirst) {
        await core.stop();
        await Future<void>.delayed(const Duration(milliseconds: 300));
      }
      final result = await core.start();
      if (!result.isSuccess) {
        _reportCoreError('启动失败', result.error ?? '未知错误');
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 500));
      await _refreshServices();
      if (_coreStatus?.running == true) {
        toast(
          'mihomo 已启动${_coreStatus?.pid == null ? '' : '，pid ${_coreStatus!.pid}'}',
          level: ToastLevel.success,
        );
      } else {
        toast('mihomo 启动后退出，请查看「日志」', level: ToastLevel.error);
      }
    });
  }

  @override
  Future<void> stopCore() async {
    final status = _coreStatus;
    if (status?.running == true && !status!.pidFromFile) {
      confirm(
        title: '结束外部进程',
        message: 'pid ${status.pid} 的 mihomo 不是由 mihomo-tui 启动的，确定要结束它吗？',
        detail: const ['如果它由 mihomo-party 等工具托管，那些程序会失去代理内核。'],
        confirmLabel: '结束进程',
        danger: true,
        onConfirm: () => unawaited(_stopCoreNow()),
      );
      return;
    }
    await _stopCoreNow();
  }

  Future<void> _stopCoreNow() async {
    await _runBusy('停止核心', () async {
      final stopped = await core.stop();
      await _refreshServices();
      if (stopped) {
        toast('已停止 mihomo', level: ToastLevel.success);
      } else {
        toast('没有找到运行中的 mihomo 进程', level: ToastLevel.warning);
      }
    });
  }

  @override
  Future<void> restartCore() async {
    await _runBusy('重启核心', () async {
      await core.stop();
      await Future<void>.delayed(const Duration(milliseconds: 400));
      final result = await core.start();
      await _refreshServices();
      if (result.isSuccess && _coreStatus?.running == true) {
        toast(
            'mihomo 已重启${_coreStatus?.pid == null ? '' : '，pid ${_coreStatus!.pid}'}',
            level: ToastLevel.success);
      } else {
        _reportCoreError('重启失败', result.error ?? '未知错误');
      }
    });
  }

  void _reportCoreError(String title, String detail) {
    final lines = detail
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    if (lines.length <= 1) {
      toast('$title：${lines.isEmpty ? detail : lines.first}',
          level: ToastLevel.error);
      return;
    }
    showOverlay(InfoOverlay(
      title: title,
      lines: [
        ...lines,
        '',
        '完整日志：${paths.logFile}',
        '可在「设置」中确认 mihomo 可执行文件路径。',
      ],
    ));
  }

  @override
  Future<void> reloadConfig() async {
    final api = apiRef;
    if (api == null) {
      toast('控制器未连接', level: ToastLevel.warning);
      return;
    }
    await _runBusy('重新加载配置', () async {
      try {
        await api.reload();
        toast('配置已重新加载', level: ToastLevel.success);
      } on ApiException catch (error) {
        toast('重新加载失败：${error.message}', level: ToastLevel.error);
      }
      await _refreshServices();
    });
  }

  @override
  Future<void> setMode(String mode) async {
    final api = apiRef;
    if (api == null) {
      toast('控制器未连接', level: ToastLevel.warning);
      return;
    }
    try {
      await api.setMode(mode);
      await _refreshServices();
      toast('模式已切换为 $mode', level: ToastLevel.success);
    } on ApiException catch (error) {
      toast('切换模式失败：${error.message}', level: ToastLevel.error);
    }
  }

  @override
  Future<void> activateProfile(Profile profile) async {
    final running = _coreStatus?.running ?? false;
    if (profile.name == repo.activeName && running) {
      toast('「${profile.name}」已经是当前配置');
      return;
    }
    void apply() {
      try {
        repo.activate(profile);
        _activeInfoKey = null;
        _dirty = true;
        toast('已启用「${profile.name}」', level: ToastLevel.success);
        if (running) {
          confirm(
            title: '重启核心',
            message: '配置已切换为「${profile.name}」，是否立即重启 mihomo 使其生效？',
            confirmLabel: '重启',
            onConfirm: () => unawaited(restartCore()),
          );
        }
        unawaited(refresh());
      } catch (error) {
        toast('启用失败：$error', level: ToastLevel.error);
      }
    }

    if (running) {
      confirm(
        title: '切换配置',
        message: 'mihomo 正在运行，切换配置会覆盖 mihomo 的 config.yaml。',
        detail: [
          '目标文件：${paths.mihomoConfigFile}',
          '切换后需要重启核心才会生效，原配置会备份为 config.yaml.bak。',
        ],
        confirmLabel: '切换',
        onConfirm: apply,
      );
    } else {
      apply();
    }
  }

  @override
  Future<void> updateProfile(Profile profile) async {
    await _runBusy('更新「${profile.name}」', () async {
      try {
        await repo.update(
          profile,
          onProgress: (progress) {
            final percent = progress.fraction;
            _busyLabel = percent == null
                ? '更新「${profile.name}」 ${formatBytes(progress.received)}'
                : '更新「${profile.name}」 ${(percent * 100).round()}%';
            _dirty = true;
          },
        );
        repo.invalidateCache(profile.name);
        _activeInfoKey = null;
        toast('已更新「${profile.name}」', level: ToastLevel.success);
        if (profile.name == repo.activeName &&
            File(paths.mihomoConfigFile).existsSync()) {
          repo.activate(profile);
          _activeInfoKey = null;
        }
        await _refreshServices();
      } on ProfileException catch (error) {
        toast('更新失败：${error.message}', level: ToastLevel.error);
      }
    });
  }

  @override
  Future<void> addProfileInteractive() async {
    showOverlay(FormOverlay(
      onChanged: requestFrame,
      title: '添加订阅',
      description: const [
        '填入 mihomo 订阅地址；下载后会校验 YAML 与节点数量。',
      ],
      fields: [
        FormFieldSpec(
          key: 'url',
          label: '订阅地址',
          hint: 'https://example.com/subscribe?token=...',
          required: true,
          validator: validateSubscriptionUrl,
        ),
        FormFieldSpec(
          key: 'name',
          label: '配置名称',
          hint: '例如 pm',
          required: true,
          validator: validateProfileName,
        ),
        FormFieldSpec(
          key: 'activate',
          label: '添加后立即启用（覆盖 config.yaml）',
          kind: FieldKind.toggle,
          initialToggle: repo.activeName == null,
        ),
        FormFieldSpec(
          key: 'start',
          label: '启用后重启核心',
          kind: FieldKind.toggle,
          initialToggle: false,
        ),
      ],
      submitLabel: '下载',
      onSubmit: (values) {
        final url = values['url']?.trim() ?? '';
        final name = values['name']?.trim() ?? '';
        final activate = values['activate'] == 'true';
        final start = values['start'] == 'true';
        unawaited(_addProfile(url, name, activate, start));
      },
    ));
  }

  Future<void> _addProfile(
    String url,
    String name,
    bool activate,
    bool start,
  ) async {
    await _runBusy('下载订阅', () async {
      try {
        await repo.add(
          name: name,
          url: url,
          onProgress: (progress) {
            final percent = progress.fraction;
            _busyLabel = percent == null
                ? '下载订阅 ${formatBytes(progress.received)}'
                : '下载订阅 ${(percent * 100).round()}% | ${formatBytes(progress.received)}';
            _dirty = true;
          },
        );
        final profile = repo.byName(name);
        if (profile == null) throw ProfileException('保存订阅失败');
        final nodes = repo.cachedInfo(name)?.nodeCount;
        toast(
          nodes == null ? '已添加「$name」' : '已添加「$name」，$nodes 个节点',
          level: ToastLevel.success,
        );
        if (activate) {
          repo.activate(profile);
          _activeInfoKey = null;
          toast('已启用「$name」', level: ToastLevel.success);
          if (start) {
            await restartCore();
          }
        }
        await _refreshServices();
      } on ProfileException catch (error) {
        toast('添加失败：${error.message}', level: ToastLevel.error);
      }
    });
  }

  @override
  Future<void> editActiveConfig() async {
    final file = File(paths.mihomoConfigFile);
    if (!file.existsSync()) {
      toast('还没有 config.yaml，请先启用一个订阅', level: ToastLevel.warning);
      return;
    }
    final edited = await _runEditor(file.path);
    if (edited == null) return;
    if (edited.isNotEmpty) {
      toast(edited, level: ToastLevel.error);
      return;
    }
    String? parseError;
    try {
      ProfileInfo.parse(file.readAsStringSync());
    } on FormatException catch (error) {
      parseError = error.message;
    }
    _activeInfoKey = null;
    await _refreshServices();
    if (parseError != null) {
      toast('config.yaml 解析失败：$parseError', level: ToastLevel.error);
      return;
    }
    toast('已保存 ${paths.mihomoConfigFile}', level: ToastLevel.success);
    if (_apiOnline) {
      confirm(
        title: '重新加载配置',
        message: 'config.yaml 已修改，是否让运行中的 mihomo 立即热重载？',
        confirmLabel: '热重载',
        onConfirm: () => unawaited(reloadConfig()),
      );
    }
  }

  /// Runs the configured editor on [file]. Returns null when nothing was
  /// saved, otherwise an error message (empty string means success).
  Future<String?> _runEditor(String file) async {
    final editor = paths.editor.trim();
    if (editor.isEmpty) {
      toast('未配置编辑器，请在「设置」中填写', level: ToastLevel.warning);
      return null;
    }
    final parts = splitCommand(editor);
    if (parts.isEmpty) {
      toast('编辑器命令为空', level: ToastLevel.warning);
      return null;
    }
    terminal.suspend();
    var failure = '';
    try {
      final process = await Process.start(
        parts.first,
        [...parts.skip(1), file],
        mode: ProcessStartMode.inheritStdio,
      );
      final code = await process.exitCode;
      if (code != 0) failure = '编辑器退出码 $code';
    } on ProcessException catch (error) {
      failure = '无法启动编辑器：${error.message}';
    } finally {
      terminal.resume();
      _renderer.invalidate();
      _dirty = true;
    }
    return failure;
  }

  @override
  Future<void> editProfileMeta(Profile profile) async {
    showOverlay(FormOverlay(
      onChanged: requestFrame,
      title: '编辑订阅信息',
      description: const ['只修改名称与订阅地址，不会改动已下载的配置文件。'],
      fields: [
        FormFieldSpec(
          key: 'name',
          label: '名称',
          initial: profile.name,
          required: true,
          validator: validateProfileName,
        ),
        FormFieldSpec(
          key: 'url',
          label: '订阅地址',
          initial: profile.url,
          hint: 'https://example.com/subscribe?token=...',
          required: true,
          validator: validateSubscriptionUrl,
        ),
        FormFieldSpec(
          key: 'download',
          label: '保存后立即重新下载订阅',
          kind: FieldKind.toggle,
        ),
      ],
      submitLabel: '保存',
      onSubmit: (values) {
        unawaited(_applyProfileMeta(profile, values));
      },
    ));
  }

  Future<void> _applyProfileMeta(
    Profile profile,
    Map<String, String> values,
  ) async {
    final name = values['name']?.trim() ?? '';
    final url = values['url']?.trim() ?? '';
    final download = values['download'] == 'true';
    Profile updated;
    try {
      updated = repo.updateMeta(profile, name: name, url: url);
    } catch (error) {
      toast('保存失败：$error', level: ToastLevel.error);
      return;
    }
    _activeInfoKey = null;
    toast('已更新「${updated.name}」的订阅信息', level: ToastLevel.success);
    if (download) {
      await updateProfile(updated);
    } else {
      await _refreshServices();
    }
  }

  @override
  Future<void> editProfile(Profile profile) async {
    final edited = await _runEditor(repo.profileFile(profile.name));
    if (edited == null) return;
    repo.invalidateCache(profile.name);
    _activeInfoKey = null;
    if (edited.isNotEmpty) {
      toast(edited, level: ToastLevel.error);
      return;
    }
    final error = repo.cachedError(profile.name);
    if (error != null) {
      toast('配置解析失败：$error', level: ToastLevel.error);
      return;
    }
    toast('已保存「${profile.name}」', level: ToastLevel.success);
    if (profile.name == repo.activeName) {
      confirm(
        title: '重新应用配置',
        message: '订阅文件已修改，是否复制为 config.yaml 并重启核心？',
        detail: ['目标文件：${paths.mihomoConfigFile}'],
        confirmLabel: '应用',
        onConfirm: () {
          try {
            repo.activate(profile);
            _activeInfoKey = null;
            unawaited(restartCore());
          } catch (error) {
            toast('应用失败：$error', level: ToastLevel.error);
          }
        },
      );
    }
    await _refreshServices();
  }

  @override
  void openUrl(String url) {
    try {
      final List<String> command;
      if (Platform.isWindows) {
        command = ['cmd', '/c', 'start', '', url];
      } else if (Platform.isMacOS) {
        command = ['open', url];
      } else {
        command = ['xdg-open', url];
      }
      unawaited(Process.start(
        command.first,
        command.skip(1).toList(),
        mode: ProcessStartMode.detached,
      ));
    } catch (error) {
      toast('打开失败：$error', level: ToastLevel.error);
    }
  }

  @override
  bool copyToClipboard(String text) {
    if (!Clipboard.canWrite) return false;
    unawaited(Clipboard.write(text));
    return true;
  }

  @override
  Future<void> applySettings(Settings next) async {
    final previous = _settings;
    _settings = next;
    next.save(paths.settingsFile);
    if (previous.mihomoBin != next.mihomoBin ||
        previous.mihomoHome != next.mihomoHome ||
        previous.editor != next.editor ||
        previous.downloadProxy != next.downloadProxy) {
      _initServices(next);
      _apiKey = null;
      _activeInfoKey = null;
      _apiOnline = false;
      _coreStatus = null;
    }
    _rebuildTheme();
    await _refreshServices();
    _dirty = true;
  }

  @override
  Future<void> cycleThemeAccent() async {
    final order = Theme.accentOrder;
    final current = _settings.accent ?? 'blue';
    final index = order.indexOf(current);
    final next = order[(index + 1) % order.length];
    await applySettings(_settings.copyWith(accent: next));
    toast('主题色：${Theme.accentLabel(next)}', level: ToastLevel.success);
  }

  @override
  Future<void> cycleColorMode() async {
    const modes = ['auto', 'dark', 'light'];
    final current = _colorMode();
    final next = modes[(modes.indexOf(current) + 1) % modes.length];
    if (next == 'auto') {
      _terminalBackground =
          await terminal.probeBackgroundColor() ?? _backgroundFromEnv();
      _lightBackground = _terminalBackground == null
          ? null
          : Theme.luminance(_terminalBackground!) > 0.55;
    }
    await applySettings(_settings.copyWith(colorMode: next));
    toast(
      switch (next) {
        'auto' => '配色：跟随终端（${_theme.isLight ? '亮色' : '暗色'}）',
        'light' => '配色：亮色',
        _ => '配色：暗色',
      },
      level: ToastLevel.success,
    );
  }

  @override
  Future<void> toggleSystemProxy() async {
    final state = await SystemProxy.currentState();
    if (state == SystemProxyState.unsupported) {
      toast('当前环境不支持一键设置系统代理', level: ToastLevel.warning);
      return;
    }
    if (state == SystemProxyState.enabled) {
      await _disableSystemProxy();
      return;
    }
    final info = _activeInfo;
    final port = info?.preferredProxyPort;
    if (port == null) {
      toast('当前配置没有可用的本地代理端口', level: ToastLevel.warning);
      return;
    }
    final result = await SystemProxy.enable(
      httpPort: info?.mixedPort ?? info?.port ?? port,
      socksPort: info?.socksPort ?? port,
    );
    if (result.ok) {
      _systemProxyState = SystemProxyState.enabled;
      _systemProxyChecked = DateTime.now();
      _dirty = true;
    }
    toast(
      result.message,
      level: result.ok ? ToastLevel.success : ToastLevel.error,
    );
    await _refreshSystemProxy(force: true);
    _dirty = true;
  }

  Future<void> _disableSystemProxy() async {
    final result = await SystemProxy.disable();
    if (result.ok) {
      _systemProxyState = SystemProxyState.disabled;
      _systemProxyChecked = DateTime.now();
      _dirty = true;
    }
    toast(
      result.message,
      level: result.ok ? ToastLevel.success : ToastLevel.error,
    );
    await _refreshSystemProxy(force: true);
    _dirty = true;
  }

  @override
  Future<void> exportData() async {
    await _runBusy('导出数据', () async {
      try {
        final exporter = DataExporter(paths: paths, settings: _settings);
        final result = await exporter.export();
        toast(
          '已导出 ${result.entries.length} 项（${formatBytes(result.bytes)}）到 ${result.file.path}',
          level: ToastLevel.success,
        );
      } catch (error) {
        toast('导出失败：$error', level: ToastLevel.error);
      }
    });
  }
}
