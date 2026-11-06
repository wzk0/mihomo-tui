/// Core log viewer: level colouring, two densities, hover + detail popup.
library;

import 'dart:async';

import '../../term/keys.dart';
import '../../term/style.dart';
import '../../term/width.dart';
import '../../util/log_entry.dart';
import '../app_context.dart';
import '../list_state.dart';
import '../overlay.dart';
import '../painter.dart';
import '../theme.dart';
import 'view.dart';

/// How much of each log line is rendered.
enum LogMode {
  /// `HH:MM:SS LEVEL message`
  standard('标准'),

  /// `LEVEL message`
  compact('精简');

  const LogMode(this.label);

  final String label;

  LogMode get next => LogMode.values[(index + 1) % LogMode.values.length];
}

class LogsView extends View {
  List<LogEntry> _entries = const [];
  LogMode _mode = LogMode.standard;
  final ListState _list = ListState();
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
        KeyHint('Enter', '详情'),
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
      if (_follow) _list.selected = _entries.isEmpty ? 0 : _entries.length - 1;
      app.requestFrame();
    }
  }

  bool _sameEntries(List<String> raw) {
    if (raw.length != _entries.length) return false;
    if (raw.isEmpty) return true;
    return raw.last == _entries.last.raw && raw.first == _entries.first.raw;
  }

  @override
  void draw(
    AppContext app,
    Painter painter,
    Rect area, {
    required bool focused,
  }) {
    final theme = app.theme;
    final status = _follow ? '跟随中' : '已暂停';
    final inner = Rect(area.x + 1, area.y + 1, area.width - 2, area.height - 2);
    if (_entries.isEmpty) {
      final hints = app.core.hasLogFile
          ? ['日志文件为空，启动核心后会有输出。']
          : [
              '还没有日志文件：${app.paths.logFile}',
              '启动一次核心（概览 -> s）即可生成。',
            ];
      var y = inner.y;
      for (final line in hints) {
        painter.text(
          inner.x,
          y++,
          truncate(line, inner.width),
          Style(fg: theme.muted, bg: theme.panel),
        );
      }
      painter.drawBox(
        area,
        focused: focused,
        title: '${app.paths.logFile} | ${_mode.label} | $status',
      );
      return;
    }

    // While following, the cursor column is hidden (the view is a live tail).
    final showCursor = !_follow;
    final textOffset = showCursor ? 2 : 0;
    final total = _entries.length;
    final rows = inner.height;
    _list.bind(total: total, visible: rows);
    if (_follow) {
      _list.selected = total - 1;
      _list.ensureVisible();
    } else {
      _list.ensureVisible();
    }

    final visible = total < rows ? total : rows;
    for (var row = 0; row < visible; row++) {
      final index = _list.scroll + row;
      if (index >= total) break;
      final entry = _entries[index];
      final selected = index == _list.selected;
      final y = inner.y + row;
      final rowRect = Rect(inner.x, y, inner.width, 1);
      if (selected) {
        painter.text(
          inner.x,
          y,
          showCursor ? '>' : ' ',
          Style(fg: theme.accent, bg: theme.panel, bold: true),
        );
      }
      _drawEntry(
        painter,
        theme,
        entry,
        inner.x + textOffset,
        y,
        inner.right - (inner.x + textOffset),
        bold: selected,
      );
      painter.hit(
        rowRect,
        id: 'log$index',
        onHover: () => _list.select(index),
        onPress: () => _showDetail(app, index),
        onWheel: (delta) {
          _follow = false;
          _list.wheel(delta);
        },
      );
    }

    painter.text(
      inner.x,
      inner.y,
      '',
      Style(bg: theme.panel),
    );

    // Scrollbar drawn on the border column, colour only.
    final maxScroll = total > rows ? total - rows : 0;
    painter.drawBox(
      area,
      focused: focused,
      title: '${app.paths.logFile} | ${_mode.label} | $status',
    );
    if (maxScroll > 0 && rows > 2) {
      final barHeight = ((rows / total) * rows).round().clamp(1, rows);
      final barTop =
          ((_list.scroll / maxScroll) * (rows - barHeight)).round().clamp(
                0,
                rows - barHeight,
              );
      for (var i = 0; i < barHeight; i++) {
        painter.text(
          area.right - 1,
          inner.y + barTop + i,
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
    int x,
    int y,
    int width, {
    required bool bold,
  }) {
    if (width <= 0) return;
    final levelColor = _levelColor(theme, entry.level);
    var cursor = x;
    if (_mode == LogMode.standard && entry.time != null) {
      cursor += painter.text(
        cursor,
        y,
        '${entry.time!} ',
        Style(fg: theme.muted, bg: theme.panel),
      );
    }
    cursor += painter.text(
      cursor,
      y,
      '${entry.tag} ',
      Style(fg: levelColor, bg: theme.panel, bold: true),
    );
    final remaining = width - (cursor - x);
    if (remaining <= 1) return;
    final messageColor = switch (entry.level) {
      'error' || 'fatal' => theme.red,
      'warning' || 'warn' => theme.yellow,
      'debug' || 'trace' => theme.muted,
      _ => theme.text,
    };
    painter.text(
      cursor,
      y,
      truncate(entry.message, remaining - 1),
      Style(fg: messageColor, bg: theme.panel, bold: bold),
    );
  }

  int _levelColor(Theme theme, String level) => switch (level) {
        'error' || 'fatal' => theme.red,
        'warning' || 'warn' => theme.yellow,
        'debug' || 'trace' => theme.muted,
        _ => theme.accent,
      };

  void _showDetail(AppContext app, int index) {
    if (index < 0 || index >= _entries.length) return;
    final entry = _entries[index];
    app.showOverlay(InfoOverlay(
      title: '日志详情',
      lines: [
        '时间    ${entry.time ?? '-'}',
        '级别    ${entry.level}',
        '',
        '内容',
        ...wrapText(entry.message, 78),
        '',
        '原始行',
        ...wrapText(entry.raw, 78),
      ],
    ));
  }

  @override
  bool onKey(AppContext app, KeyEvent event) {
    if (event.kind == KeyKind.down || event.isChar('j')) {
      _follow = false;
      _list.moveBy(1);
      return true;
    }
    if (event.kind == KeyKind.up || event.isChar('k')) {
      _follow = false;
      _list.moveBy(-1);
      return true;
    }
    if (event.kind == KeyKind.pageUp) {
      _follow = false;
      _list.wheel(-15);
      return true;
    }
    if (event.kind == KeyKind.pageDown) {
      _follow = false;
      _list.wheel(15);
      return true;
    }
    if (event.kind == KeyKind.home || event.isCharExact('g')) {
      _follow = false;
      _list.select(0);
      return true;
    }
    if (event.kind == KeyKind.end || event.isCharExact('G')) {
      _follow = true;
      return true;
    }
    if (event.kind == KeyKind.enter) {
      _showDetail(app, _list.selected);
      return true;
    }
    if (event.isChar('f')) {
      _follow = !_follow;
      if (_follow) _list.select(_entries.isEmpty ? 0 : _entries.length - 1);
      return true;
    }
    if (event.isChar('s')) {
      _mode = _mode.next;
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
    _list.wheel(delta);
    return true;
  }

  Future<void> _reload(AppContext app) async {
    _lastLoad = DateTime.fromMillisecondsSinceEpoch(0);
    onTick(app);
    app.requestFrame();
  }

  @override
  void reset() => _list.reset();
}
