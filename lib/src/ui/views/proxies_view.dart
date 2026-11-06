/// Proxy groups / nodes pane backed by mihomo's RESTful controller.
library;

import 'dart:async';
import 'dart:math' as math;

import '../../service/mihomo_api.dart';
import '../../util/node_sort.dart';
import '../../term/keys.dart';
import '../../term/style.dart';
import '../../term/width.dart';
import '../app_context.dart';
import '../list_state.dart';
import '../overlay.dart';
import '../painter.dart';
import 'view.dart';

class ProxiesView extends View {
  final ListState _groupList = ListState();
  final ListState _nodeList = ListState();
  int _pane = 0; // 0 = groups, 1 = nodes
  final Map<String, int?> _delays = {};
  final Set<String> _testing = {};
  NodeSortMode _sort = NodeSortMode.original;
  bool _testingAll = false;
  bool _cancelTestAll = false;
  int _testDone = 0;
  int _testTotal = 0;

  @override
  String get label => '代理';

  @override
  String get title => '代理组';

  @override
  List<KeyHint> hints(AppContext app) => [
        const KeyHint('上下', '移动'),
        const KeyHint('Tab', '切换列'),
        const KeyHint('Enter', '选择节点'),
        const KeyHint('t', '测延迟'),
        const KeyHint('T', '测速全部'),
        KeyHint('s', '排序：${_sort.label}'),
        const KeyHint('r', '刷新'),
      ];

  @override
  void onTick(AppContext app) {}

  /// Node names of [group] in the currently selected order.
  List<String> _orderedNames(ProxySnapshot snapshot, ProxyNode group) =>
      orderNodeNames(
        names: group.all,
        mode: _sort,
        nodes: snapshot.nodes,
        delays: _delays,
      );

  @override
  void draw(
    AppContext app,
    Painter painter,
    Rect area, {
    required bool focused,
  }) {
    final theme = app.theme;
    final snapshot = app.proxySnapshot;
    if (!app.apiOnline) {
      _drawNotice(
        app,
        painter,
        area,
        '控制器未连接',
        [
          '请先在「概览」中启动核心，并确认配置里的 external-controller 可访问。',
          if (app.activeInfo?.externalController == null)
            '当前配置没有设置 external-controller。',
        ],
      );
      return;
    }
    if (snapshot == null || snapshot.groups.isEmpty) {
      _drawNotice(
          app, painter, area, '没有可用的代理组', ['控制器已连接，但配置中没有 proxy-groups。']);
      return;
    }

    _groupList.bind(total: snapshot.groups.length, visible: _groupList.visible);
    final group = snapshot.groups[_groupList.selected];
    final nodes = _orderedNames(snapshot, group);

    final leftWidth = (area.width * 0.28).round().clamp(18, 34);
    final leftRect = Rect(area.x, area.y, leftWidth, area.height);
    final rightRect = Rect(
      area.x + leftWidth + 1,
      area.y,
      area.width - leftWidth - 1,
      area.height,
    );

    final sortLabel = _sort == NodeSortMode.original ? '' : ' | ${_sort.label}';
    final rightTitle = _testingAll
        ? '${group.name} | 测速中 $_testDone/$_testTotal（Esc 取消）'
        : '${group.name} | ${group.type} | ${nodes.length} 节点$sortLabel';

    final listHeight = leftRect.height - 2;
    _groupList.bind(total: snapshot.groups.length, visible: listHeight);
    _groupList.ensureVisible();
    final visibleGroups =
        math.min(listHeight, snapshot.groups.length - _groupList.scroll);
    for (var row = 0; row < visibleGroups; row++) {
      final index = _groupList.scroll + row;
      final item = snapshot.groups[index];
      final isActiveGroup = index == _groupList.selected;
      final rowRect =
          Rect(leftRect.x + 1, leftRect.y + 1 + row, leftRect.width - 2, 1);
      final style = Style(
        fg: isActiveGroup ? theme.text : theme.muted,
        bg: theme.panel,
        bold: isActiveGroup,
      );
      // The `>` marker tracks the group currently shown on the right, so the
      // cursor stays visible while the node column is focused.
      painter.text(
        rowRect.x,
        rowRect.y,
        isActiveGroup ? '>' : ' ',
        Style(fg: theme.accent, bg: theme.panel, bold: isActiveGroup),
      );
      painter.text(
        rowRect.x + 2,
        rowRect.y,
        truncate(item.name, rowRect.width - 4),
        style,
      );
      painter.hit(
        rowRect,
        id: 'group$index',
        onHover: () {
          if (_groupList.selected != index) {
            _groupList.select(index);
            _nodeList.reset();
          }
          _pane = 0;
        },
        onPress: () {
          _groupList.select(index);
          _nodeList.reset();
          _pane = 0;
        },
        onWheel: _groupList.wheel,
      );
    }

    final innerRight = Rect(
      rightRect.x + 1,
      rightRect.y + 1,
      rightRect.width - 2,
      rightRect.height - 2,
    );
    final nodeRows = innerRight.height;
    _nodeList.bind(total: nodes.length, visible: nodeRows);
    _nodeList.ensureVisible();
    final visibleNodes = math.min(nodeRows, nodes.length - _nodeList.scroll);
    final delayWidth = 9;
    for (var row = 0; row < visibleNodes; row++) {
      final index = _nodeList.scroll + row;
      final name = nodes[index];
      final node = snapshot.nodes[name];
      final isNow = group.now == name;
      final selected = index == _nodeList.selected;
      final rowRect =
          Rect(innerRight.x, innerRight.y + row, innerRight.width, 1);
      final style = selected
          ? theme.selectionStyle()
          : Style(fg: theme.text, bg: theme.panel);
      painter.text(
        rowRect.x,
        rowRect.y,
        selected ? '>' : ' ',
        Style(fg: theme.accent, bg: theme.panel),
      );
      painter.text(
        rowRect.x + 2,
        rowRect.y,
        isNow ? '*' : ' ',
        Style(fg: theme.green, bg: style.bg, bold: true),
      );
      painter.text(
        rowRect.x + 4,
        rowRect.y,
        truncate(name, rowRect.width - delayWidth - 7),
        Style(
          fg: isNow ? theme.green : (selected ? theme.text : theme.muted),
          bg: style.bg,
          bold: isNow || selected,
        ),
      );
      final delay = _delays.containsKey(name) ? _delays[name] : node?.delay;
      final delayText = _testing.contains(name)
          ? '测试中'
          : delay == null
              ? (node?.alive == false ? '失效' : '-')
              : delay == 0
                  ? '超时'
                  : '${delay}ms';
      final delayColor = _testing.contains(name)
          ? theme.yellow
          : delay == null
              ? theme.muted
              : delay == 0
                  ? theme.red
                  : delay < 200
                      ? theme.green
                      : delay < 500
                          ? theme.yellow
                          : theme.red;
      painter.text(
        rowRect.right - delayWidth,
        rowRect.y,
        padLeft(delayText, delayWidth - 1),
        Style(fg: delayColor, bg: style.bg),
      );
      painter.hit(
        rowRect,
        id: 'node$index',
        onHover: () {
          _nodeList.select(index);
          _pane = 1;
        },
        onPress: () {
          _nodeList.select(index);
          _pane = 1;
          // Clicking a node switches to it directly.
          unawaited(_select(app, group.name, name));
        },
        onWheel: _nodeList.wheel,
      );
    }

    if (nodes.isEmpty) {
      painter.text(
        innerRight.x + 1,
        innerRight.y,
        '该代理组没有节点',
        Style(fg: theme.muted),
      );
    }
    if (rightRect.height > 4) {
      painter.text(
        innerRight.x,
        rightRect.bottom - 2,
        truncate(
          'Enter 选择 | t 测延迟 | T 测速全部 | Tab 切换列',
          innerRight.width,
        ),
        Style(fg: theme.muted),
      );
    }
    // Frames last: rows can never punch through the borders.
    painter.drawBox(
      leftRect,
      focused: focused && _pane == 0,
      title: '代理组 (${snapshot.groups.length})',
    );
    painter.drawBox(
      rightRect,
      focused: focused && _pane == 1,
      title: rightTitle,
    );
  }

  void _drawNotice(
    AppContext app,
    Painter painter,
    Rect area,
    String title,
    List<String> lines,
  ) {
    final theme = app.theme;
    final height = (lines.length + 4).clamp(5, area.height);
    final box = Rect(area.x, area.y, area.width, height);
    var y = box.y + 2;
    for (final line in lines) {
      if (y >= box.bottom - 1) break;
      painter.text(
        box.x + 3,
        y++,
        truncate(line, box.width - 6),
        Style(fg: theme.muted),
      );
    }
    painter.drawBox(box, title: title);
  }

  @override
  bool onKey(AppContext app, KeyEvent event) {
    final snapshot = app.proxySnapshot;
    if (snapshot == null || snapshot.groups.isEmpty) return false;
    _groupList.bind(total: snapshot.groups.length, visible: _groupList.visible);
    final group = snapshot.groups[_groupList.selected];
    final ordered = _orderedNames(snapshot, group);
    _nodeList.bind(total: ordered.length, visible: _nodeList.visible);
    if (event.kind == KeyKind.tab || event.kind == KeyKind.right) {
      _pane = _pane == 0 ? 1 : 0;
      if (event.kind == KeyKind.right) _pane = 1;
      return true;
    }
    if (event.kind == KeyKind.left) {
      _pane = 0;
      return true;
    }
    if (event.isChar('r')) {
      unawaited(app.refresh());
      return true;
    }
    if (event.kind == KeyKind.down || event.isChar('j')) {
      if (_pane == 0) {
        _groupList.moveBy(1);
        _nodeList.reset();
      } else {
        _nodeList.moveBy(1);
      }
      return true;
    }
    if (event.kind == KeyKind.up || event.isChar('k')) {
      if (_pane == 0) {
        _groupList.moveBy(-1);
        _nodeList.reset();
      } else {
        _nodeList.moveBy(-1);
      }
      return true;
    }
    if (event.kind == KeyKind.home || event.isCharExact('g')) {
      if (_pane == 0) {
        _groupList.select(0);
      } else {
        _nodeList.select(0);
      }
      return true;
    }
    if (event.kind == KeyKind.end || event.isCharExact('G')) {
      if (_pane == 0) {
        _groupList.select(snapshot.groups.length - 1);
      } else {
        _nodeList.select(ordered.length - 1);
      }
      return true;
    }
    if (event.kind == KeyKind.pageDown) {
      if (_pane == 0) {
        _groupList.wheel(_groupList.visible - 1);
      } else {
        _nodeList.wheel(_nodeList.visible - 1);
      }
      return true;
    }
    if (event.kind == KeyKind.pageUp) {
      if (_pane == 0) {
        _groupList.wheel(-(_groupList.visible - 1));
      } else {
        _nodeList.wheel(-(_nodeList.visible - 1));
      }
      return true;
    }
    if (event.kind == KeyKind.enter) {
      if (_pane == 0) {
        _pane = 1;
        return true;
      }
      if (ordered.isEmpty) return true;
      final name = ordered[_nodeList.selected];
      unawaited(_select(app, group.name, name));
      return true;
    }
    if (event.isChar('s')) {
      _sort = _sort.next;
      _nodeList.reset();
      app.toast('节点排序：${_sort.label}');
      return true;
    }
    if (event.isCharExact('T')) {
      unawaited(_testAll(app));
      return true;
    }
    if (event.kind == KeyKind.escape && _testingAll) {
      _cancelTestAll = true;
      return true;
    }
    if (event.isCharExact('t')) {
      if (_pane == 0) {
        _pane = 1;
        return true;
      }
      if (ordered.isEmpty) return true;
      unawaited(_testDelay(app, ordered[_nodeList.selected]));
      return true;
    }
    return false;
  }

  Future<void> _select(AppContext app, String group, String node) async {
    final api = app.apiRef;
    if (api == null) return;
    try {
      await api.select(group, node);
      app.toast('已切换到 $node', level: ToastLevel.success);
      await app.refresh();
    } on ApiException catch (error) {
      app.toast('切换失败：${error.message}', level: ToastLevel.error);
    }
  }

  Future<void> _testDelay(AppContext app, String name) async {
    final api = app.apiRef;
    if (api == null) return;
    _testing.add(name);
    app.requestFrame();
    try {
      final delay = await api.delay(name);
      _delays[name] = delay ?? 0;
      app.toast(
        delay == null ? '$name 延迟测试超时' : '$name | ${delay}ms',
        level: delay == null ? ToastLevel.warning : ToastLevel.success,
      );
    } on ApiException catch (error) {
      app.toast('测试失败：${error.message}', level: ToastLevel.error);
    } finally {
      _testing.remove(name);
      app.requestFrame();
    }
  }

  Future<void> _testAll(AppContext app) async {
    final snapshot = app.proxySnapshot;
    final api = app.apiRef;
    if (snapshot == null || api == null) {
      app.toast('控制器未连接，无法测速', level: ToastLevel.warning);
      return;
    }
    if (_testingAll) {
      _cancelTestAll = true;
      return;
    }
    final group = snapshot.groups[_groupList.selected];
    final names = _orderedNames(snapshot, group)
        .where((name) => snapshot.nodes[name]?.isGroup != true)
        .toList();
    if (names.isEmpty) {
      app.toast('该代理组没有可测速的节点', level: ToastLevel.warning);
      return;
    }
    _testingAll = true;
    _cancelTestAll = false;
    _testDone = 0;
    _testTotal = names.length;
    var index = 0;

    Future<void> worker() async {
      while (true) {
        if (_cancelTestAll) return;
        final current = index++;
        if (current >= names.length) return;
        final name = names[current];
        try {
          final delay = await api.delay(name, timeoutMs: 3000);
          _delays[name] = delay ?? 0;
        } on ApiException {
          _delays[name] = 0;
        }
        _testing.add(name);
        _testing.remove(name);
        _testDone++;
        app.requestFrame();
      }
    }

    await Future.wait([
      for (var i = 0; i < 6; i++) worker(),
    ]);
    final cancelled = _cancelTestAll || _testDone < names.length;
    _testingAll = false;
    _cancelTestAll = false;
    final ok = names.where((name) => (_delays[name] ?? 0) > 0).length;
    app.toast(
      cancelled
          ? '测速已取消（$_testDone/$_testTotal）'
          : '测速完成：$ok/${names.length} 个节点可用',
      level: cancelled ? ToastLevel.warning : ToastLevel.success,
    );
    app.requestFrame();
  }

  @override
  bool onWheel(AppContext app, int delta) {
    if (_pane == 0) {
      _groupList.wheel(delta);
    } else {
      _nodeList.wheel(delta);
    }
    return true;
  }

  @override
  void reset() {
    _groupList.reset();
    _nodeList.reset();
    _pane = 0;
  }
}
