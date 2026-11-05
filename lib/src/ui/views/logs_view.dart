/// Core log viewer with level colouring, three density modes and follow.
library;

import 'dart:async';

import '../../term/keys.dart';
import '../../term/style.dart';
import '../../term/width.dart';
import '../../util/log_entry.dart';
import '../app_context.dart';
import '../overlay.dart';
import '../painter.dart';
import '../theme.dart';
import 'view.dart';

/// How much of each log line is rendered.
enum LogMode {
  /// `HH:MM:SS LEVEL message`
  standard('标准'),

  /// `LEVEL message`
  compact('精简'),

  /// `message` only, debug/trace entries hidden.
  minimal('极简');

  const LogMode(this.label);

  final String label;

  LogMode get next => LogMode.values[(index + 1) % LogMode.values.length];
}

class LogsView extends View {
  List<LogEntry> _entries = const [];
  List<LogEntry> _visible = const [];
  LogMode _mode = LogMode.standard;
  int _scroll = 0;
  bool _follow = true;
  DateTime _lastLoad = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  String get label => '日志';

  @override
  String get title => '核心日志';

  @override
  List<KeyHint> hints(AppContext app) => [
        KeyHint('s', '视图：${_mode.label}'),
        KeyHint('f', _follow ? '停止跟随' : '跟随'),
        KeyHint('r', '刷新'),
        KeyHint('c', '清空'),
      ];

  @override
  void onTick(AppContext app) {
    if (DateTime.now().difference(_lastLoad) <
        const Duration(milliseconds: 900)) {
      return;
    }
    _lastLoad = DateTime.now();
    final raw = app.core.readLogTail(lines: 800);
    if (!_sameEntries(raw)) {
      _entries = raw.map(LogEntry.parse).toList(growable: false);
      _rebuildVisible();
      if (_follow) _scroll = _visible.length;
      app.requestFrame();
    }
  }

  bool _sameEntries(List<String> raw) {
    if (raw.length != _entries.length) return false;
    if (raw.isEmpty) return true;
    return raw.last == _entries.last.raw && raw.first == _entries.first.raw;
  }

  void _rebuildVisible() {
    _visible = _mode == LogMode.minimal
        ? _entries
            .where((entry) => entry.level != 'debug' && entry.level != 'trace')
            .toList(growable: false)
        : _entries;
  }

  @override
  void draw(
    AppContext app,
    Painter painter,
    Rect area, {
    required bool focused,
  }) {
    final theme = app.theme;
    final rect = Rect(area.x, area.y, area.width, area.height);
    final status = _follow ? '跟随中' : '已暂停';
    final inner = Rect(rect.x + 1, rect.y + 1, rect.width - 2, rect.height - 2);
    if (_visible.isEmpty) {
      final hints = app.core.hasLogFile
          ? ['日志文件为空，启动核心后会有输出。']
          : [
              '还没有日志文件：${app.paths.logFile}',
              '启动一次核心（概览 右 s）即可生成。',
            ];
      var y = inner.y;
      for (final line in hints) {
        painter.text(inner.x, y++, truncate(line, inner.width),
            Style(fg: theme.muted, bg: theme.panel));
      }
      painter.drawBox(
        rect,
        focused: focused,
        title: '${app.paths.logFile} | ${_mode.label} | $status',
      );
      return;
    }

    final total = _visible.length;
    final visible = inner.height;
    final maxScroll = total > visible ? total - visible : 0;
    if (_follow) _scroll = maxScroll;
    if (_scroll > maxScroll) _scroll = maxScroll;
    if (_scroll < 0) _scroll = 0;

    for (var row = 0; row < visible; row++) {
      final index = _scroll + row;
      if (index >= total) break;
      _drawEntry(painter, theme, _visible[index], inner, row);
    }

    painter.hit(inner, id: 'logs', onWheel: (delta) {
      _follow = false;
      _scroll += delta * 3;
    });

    // Borders are painted last so content can never punch a hole in them.
    painter.drawBox(
      rect,
      focused: focused,
      title: '${app.paths.logFile} | ${_mode.label} | $status',
    );

    // The scrollbar lives on the border column itself (colour only), which
    // keeps a single clean vertical line.
    if (maxScroll > 0 && inner.height > 2) {
      final barHeight = ((visible / total) * visible).round().clamp(1, visible);
      final barTop = ((_scroll / maxScroll) * (visible - barHeight)).round();
      for (var row = 0; row < visible; row++) {
        final inBar = row >= barTop && row < barTop + barHeight;
        if (!inBar) continue;
        painter.text(
          rect.right - 1,
          inner.y + row,
          '│',
          Style(fg: theme.accent, bold: true),
        );
      }
    }
  }

  void _drawEntry(
    Painter painter,
    Theme theme,
    LogEntry entry,
    Rect inner,
    int row,
  ) {
    final y = inner.y + row;
    final levelColor = _levelColor(theme, entry.level);
    final background = Style(bg: theme.panel);
    var x = inner.x;
    if (_mode == LogMode.standard && entry.time != null) {
      x += painter.text(
        x,
        y,
        '${entry.time!} ',
        Style(fg: theme.muted, bg: theme.panel),
      );
    }
    if (_mode == LogMode.minimal) {
      // Only the message survives; the level is conveyed by colour.
      painter.text(
        x,
        y,
        truncate(entry.message, inner.right - x - 1),
        Style(fg: levelColor == theme.accent ? theme.text : levelColor),
      );
      return;
    }
    x += painter.text(
      x,
      y,
      '${entry.tag} ',
      Style(fg: levelColor, bg: theme.panel, bold: true),
    );
    // Leave one column before the border so a trailing wide glyph can never
    // touch (and visually eat) the frame line.
    final remaining = inner.right - x - 1;
    if (remaining > 0) {
      painter.text(
        x,
        y,
        truncate(entry.message, remaining),
        background.copyWith(
          fg: entry.level == 'error' ? theme.red : theme.text,
        ),
      );
    }
  }

  int _levelColor(Theme theme, String level) => switch (level) {
        'error' || 'fatal' => theme.red,
        'warning' || 'warn' => theme.yellow,
        'debug' || 'trace' => theme.muted,
        _ => theme.accent,
      };

  @override
  bool onKey(AppContext app, KeyEvent event) {
    if (event.kind == KeyKind.down || event.isChar('j')) {
      _follow = false;
      _scroll++;
      return true;
    }
    if (event.kind == KeyKind.up || event.isChar('k')) {
      _follow = false;
      _scroll--;
      return true;
    }
    if (event.kind == KeyKind.pageUp) {
      _follow = false;
      _scroll -= 15;
      return true;
    }
    if (event.kind == KeyKind.pageDown) {
      _follow = false;
      _scroll += 15;
      return true;
    }
    if (event.kind == KeyKind.home || event.isCharExact('g')) {
      _follow = false;
      _scroll = 0;
      return true;
    }
    if (event.kind == KeyKind.end || event.isCharExact('G')) {
      _follow = true;
      return true;
    }
    if (event.isChar('f')) {
      _follow = !_follow;
      return true;
    }
    if (event.isChar('s')) {
      _mode = _mode.next;
      _rebuildVisible();
      if (_follow) _scroll = _visible.length;
      return true;
    }
    if (event.isChar('r')) {
      unawaited(_reload(app));
      return true;
    }
    if (event.isChar('c')) {
      app.confirm(
        title: '清空日志',
        message: '确定清空 ${app.paths.logFile} 吗？',
        confirmLabel: '清空',
        danger: true,
        onConfirm: () {
          app.core.clearLog();
          _entries = const [];
          _visible = const [];
          app.toast('日志已清空', level: ToastLevel.success);
        },
      );
      return true;
    }
    return false;
  }

  @override
  bool onWheel(AppContext app, int delta) {
    _follow = false;
    _scroll += delta * 3;
    return true;
  }

  Future<void> _reload(AppContext app) async {
    _lastLoad = DateTime.fromMillisecondsSinceEpoch(0);
    onTick(app);
    app.requestFrame();
  }
}
