/// Overview pane: core state, quick actions and system proxy shortcuts.
library;

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import '../../service/system_proxy.dart';
import '../../term/keys.dart';
import '../../term/style.dart';
import '../../term/width.dart';
import '../../util/format.dart';
import '../../util/proxy_chain.dart';
import '../../util/traffic.dart';
import '../app_context.dart';
import '../list_state.dart';
import '../overlay.dart';
import '../painter.dart';
import 'view.dart';

class DashboardView extends View {
  final ListState _list = ListState();

  @override
  String get label => '概览';

  @override
  String get title => '概览';

  @override
  List<KeyHint> hints(AppContext app) => const [
        KeyHint('上下', '选择操作'),
        KeyHint('Enter', '执行'),
        KeyHint('s', '启动/停止'),
        KeyHint('R', '重启'),
        KeyHint('r', '重载配置'),
      ];

  List<_Action> _actions(AppContext app) {
    final status = app.coreStatus;
    final running = status?.running ?? false;
    final online = app.apiOnline;
    final mode = app.apiConfig?.mode ?? app.activeInfo?.mode;
    final allowLan = app.apiConfig?.allowLan;
    return [
      _Action(
        running ? '停止核心' : '启动核心',
        enabled: status?.binaryPath != null,
        hint: running ? '结束 mihomo 进程' : '以当前配置在后台启动 mihomo',
        run: () async {
          if (running) {
            await app.stopCore();
          } else {
            await app.startCore();
          }
        },
      ),
      _Action(
        '重启核心',
        enabled: running,
        hint: '重新加载配置并重启进程',
        run: app.restartCore,
      ),
      _Action(
        '重新加载配置',
        enabled: online,
        hint: '让运行中的 mihomo 热重载 config.yaml',
        run: app.reloadConfig,
      ),
      for (final item in const ['rule', 'global', 'direct'])
        _Action(
          '切换模式：$item',
          enabled: online,
          hint: mode == item ? '当前模式' : '通过控制器切换',
          marker: mode == item ? '当前' : null,
          run: () async => app.setMode(item),
        ),
      _Action(
        '编辑生效配置',
        enabled: File(app.paths.mihomoConfigFile).existsSync(),
        hint: '用编辑器打开核心正在读取的 config.yaml',
        run: app.editActiveConfig,
      ),
      _Action(
        '局域网代理',
        enabled: online,
        hint: '允许局域网内其它设备使用本机代理（allow-lan）',
        marker: allowLan == null ? null : (allowLan ? '已开启' : '已关闭'),
        markerActive: allowLan == true,
        run: app.toggleAllowLan,
      ),
      _Action(
        '切换系统代理',
        enabled: app.activeInfo?.preferredProxyPort != null,
        hint: '一键写入/撤销 GNOME 或 Windows 系统代理',
        marker: switch (app.systemProxyState) {
          SystemProxyState.enabled => '已开启',
          SystemProxyState.disabled => '已关闭',
          _ => null,
        },
        markerActive: app.systemProxyState == SystemProxyState.enabled,
        run: app.toggleSystemProxy,
      ),
      _Action(
        '打开控制面板',
        enabled: online,
        hint: '在浏览器中打开 metacubexd 面板',
        run: () async {
          final url = app.activeInfo?.panelUrl;
          if (url == null) {
            app.toast('当前配置没有 external-controller，无法打开面板',
                level: ToastLevel.warning);
            return;
          }
          app.openUrl(url);
        },
      ),
      _Action(
        '复制代理环境变量',
        enabled: app.activeInfo?.preferredProxyPort != null,
        hint: '把 export 命令复制到剪贴板',
        run: () async {
          final port = app.activeInfo?.preferredProxyPort;
          if (port == null) return;
          final text = [
            'export http_proxy=http://127.0.0.1:$port',
            'export https_proxy=http://127.0.0.1:$port',
            'export all_proxy=socks5://127.0.0.1:$port',
          ].join('\n');
          if (app.copyToClipboard(text)) {
            app.toast('环境变量已复制到剪贴板', level: ToastLevel.success);
          } else {
            app.toast('未找到剪贴板工具，请手动复制环境变量', level: ToastLevel.warning);
          }
        },
      ),
      _Action(
        '刷新状态',
        hint: '重新探测进程与控制器',
        run: app.refresh,
      ),
    ];
  }

  @override
  void draw(
    AppContext app,
    Painter painter,
    Rect area, {
    required bool focused,
  }) {
    final theme = app.theme;
    final actions = _actions(app);

    final statusRows = _statusRows(app);
    var y = area.y;

    final statusHeight = statusRows.length + 2;
    if (statusHeight <= area.bottom - y) {
      final statusCard = Rect(area.x, y, area.width, statusHeight);
      var rowY = statusCard.y + 1;
      for (final row in statusRows) {
        final rowRect = Rect(statusCard.x + 1, rowY, statusCard.width - 2, 1);
        final clickable = row.onPress != null;
        painter.text(
          statusCard.x + 2,
          rowY,
          row.label,
          Style(fg: theme.muted, bg: theme.panel),
        );
        painter.text(
          statusCard.x + 2 + 11,
          rowY,
          truncate(row.value, statusCard.width - 16),
          Style(
            fg: row.color ?? theme.text,
            bold: row.bold,
            underline: clickable && app.hoverId == 'status-${row.label}',
          ),
        );
        if (clickable) {
          painter.hit(
            rowRect,
            id: 'status-${row.label}',
            onPress: row.onPress,
          );
        }
        rowY++;
      }
      painter.drawBox(statusCard, focused: false, title: '核心状态');
      y += statusHeight + 1;
    }

    final available = area.bottom - y;
    if (available >= 4) {
      final maxRows = available - 2;
      _list.bind(total: actions.length, visible: maxRows);
      _list.ensureVisible();

      final visible = math.min(maxRows, actions.length - _list.scroll);
      final cardHeight = visible + 2;
      final card = Rect(area.x, y, area.width, cardHeight);
      for (var row = 0; row < visible; row++) {
        final index = _list.scroll + row;
        final action = actions[index];
        final selected = index == _list.selected;
        final rowRect = Rect(card.x + 1, card.y + 1 + row, card.width - 2, 1);
        final baseStyle = selected
            ? theme.selectionStyle()
            : Style(fg: theme.muted, bg: theme.panel);
        painter.text(
          rowRect.x + 1,
          rowRect.y,
          selected ? '>' : ' ',
          Style(fg: theme.accent, bg: baseStyle.bg, bold: selected),
        );
        painter.text(
          rowRect.x + 3,
          rowRect.y,
          truncate(action.label, rowRect.width - 12),
          baseStyle,
        );
        if (action.marker != null) {
          painter.text(
            rowRect.right - textWidth(action.marker!) - 2,
            rowRect.y,
            action.marker!,
            Style(
              fg: action.markerActive ? theme.green : theme.muted,
              bg: baseStyle.bg,
              bold: action.markerActive,
            ),
          );
        }
        final hint = action.hint;
        if (hint != null && rowRect.width > 50) {
          painter.text(
            rowRect.x + 26,
            rowRect.y,
            truncate(hint, rowRect.right - (rowRect.x + 26) - 2),
            Style(fg: theme.muted, bg: baseStyle.bg),
          );
        }
        painter.hit(
          rowRect,
          id: 'action$index',
          onHover: () => _list.select(index),
          onPress: () {
            _list.select(index);
            if (action.enabled) {
              action.run();
            } else {
              app.toast(
                _disabledReason(app, action.label),
                level: ToastLevel.warning,
              );
            }
          },
          onWheel: _list.wheel,
        );
      }
      painter.drawBox(
        card,
        focused: focused,
        title: '快捷操作',
        borderStyle: Style(
          fg: focused ? theme.borderFocus : theme.border,
          bg: theme.panel,
        ),
      );
    }
  }

  @override
  bool onWheel(AppContext app, int delta) {
    _list.wheel(delta);
    return true;
  }

  String _disabledReason(AppContext app, String label) {
    if (label.contains('核心') && app.coreStatus?.binaryPath == null) {
      return '未找到 mihomo 可执行文件，请在设置中指定';
    }
    if (app.coreStatus?.running != true) return '核心未运行';
    if (!app.apiOnline) return '控制器不可用（请检查 external-controller）';
    return '当前不可用';
  }

  /// Resolves the default group down to the actually selected (leaf) node.
  _CurrentNode? _currentNode(AppContext app) {
    final snapshot = app.proxySnapshot;
    if (snapshot == null) return null;
    final group = defaultGroup(snapshot, app.activeInfo?.finalMatchTarget);
    if (group == null || !group.isGroup) return null;
    final leaf = resolveSelectedNode(snapshot, group);
    return _CurrentNode(group.name, leaf?.name ?? group.now ?? '-');
  }

  List<_StatusRow> _statusRows(AppContext app) {
    final theme = app.theme;
    final status = app.coreStatus;
    final info = app.activeInfo;
    final running = status?.running ?? false;
    final pid = status?.pid;
    final uptime = app.coreStartedAt == null
        ? null
        : DateTime.now().difference(app.coreStartedAt!);
    final rows = <_StatusRow>[];

    rows.add(_StatusRow(
      '二进制',
      status?.binaryPath ?? '未找到 mihomo（设置中可指定路径）',
      color: status?.binaryPath == null ? theme.red : null,
    ));
    rows.add(_StatusRow('版本', status?.version ?? '未知'));
    rows.add(_StatusRow(
      '进程',
      running
          ? '运行中${status?.pidFromFile == false ? '（外部进程）' : ''}'
              ' | pid ${pid ?? '?'}'
              '${uptime == null ? '' : ' | 已运行 ${formatDuration(uptime)}'}'
          : '未运行',
      color: running
          ? (status?.pidFromFile == false ? theme.yellow : theme.green)
          : theme.red,
      bold: true,
    ));
    rows.add(_StatusRow(
      '配置',
      app.repo.activeName ?? '未选择',
      color: app.repo.activeName == null ? theme.yellow : null,
    ));
    final ports = info?.portSummary ?? const <String>[];
    rows.add(_StatusRow('端口', ports.isEmpty ? '-' : ports.join(' | ')));
    final controller = info?.controllerAddress;
    rows.add(_StatusRow(
      '控制器',
      controller == null
          ? '-'
          : '$controller ${app.apiOnline ? '| 已连接 ${app.apiVersion ?? ''}' : '| 未连接'}'
              .trim(),
      color: controller == null
          ? theme.muted
          : app.apiOnline
              ? theme.green
              : theme.yellow,
    ));
    final mode = app.apiConfig?.mode ?? info?.mode;
    rows.add(_StatusRow('模式', mode ?? '-'));

    final node = _currentNode(app);
    rows.add(_StatusRow(
      '当前节点',
      node == null ? (app.apiOnline ? '读取中~' : '-') : node.name,
      color: node == null ? theme.muted : theme.accentSoft,
      onPress: () => app.openView(2),
    ));

    final panel = info?.panelUrl;
    rows.add(_StatusRow(
      '控制面板',
      panel ?? (controller == null ? '未配置 external-controller' : '-'),
      color: panel == null ? theme.muted : theme.accent,
      onPress: panel == null ? null : () => app.openUrl(panel),
    ));

    if (app.apiConfig?.allowLan == true) {
      final port = info?.mixedPort ??
          info?.port ??
          info?.socksPort ??
          app.activeInfo?.preferredProxyPort;
      final address = app.lanAddress;
      if (address != null) {
        rows.add(_StatusRow(
          '局域网代理',
          port == null ? address : '$address:$port',
          color: theme.accentSoft,
        ));
      }
    }

    final profile = app.repo.activeProfile;
    if (profile != null) {
      final summary = summarizeTraffic(
        used: profile.trafficUsed,
        total: profile.trafficTotal,
        expire: profile.trafficExpireAt,
      );
      if (summary != null) {
        final fraction = summary.fraction;
        rows.add(_StatusRow(
          '套餐',
          summary.display,
          color: fraction == null
              ? theme.accentSoft
              : fraction >= 0.9
                  ? theme.red
                  : fraction >= 0.7
                      ? theme.yellow
                      : theme.green,
        ));
      }
    }

    final connections = app.connections;
    rows.add(_StatusRow(
      '连接',
      connections == null ? '-' : '${connections.count} 个',
    ));
    rows.add(_StatusRow(
      '流量',
      connections == null
          ? '-'
          : '上行 ${formatBytes(connections.uploadTotal)}'
              ' | 下行 ${formatBytes(connections.downloadTotal)}'
              '（自核心启动）',
      color: connections == null ? null : theme.accentSoft,
    ));
    return rows;
  }

  @override
  bool onKey(AppContext app, KeyEvent event) {
    final actions = _actions(app);
    _list.bind(total: actions.length, visible: _list.visible);
    if (event.kind == KeyKind.down || event.isChar('j')) {
      _list.moveBy(1);
      return true;
    }
    if (event.kind == KeyKind.up || event.isChar('k')) {
      _list.moveBy(-1);
      return true;
    }
    if (event.kind == KeyKind.home || event.isCharExact('g')) {
      _list.select(0);
      return true;
    }
    if (event.kind == KeyKind.end || event.isCharExact('G')) {
      _list.select(actions.length - 1);
      return true;
    }
    if (event.kind == KeyKind.pageDown) {
      _list.wheel(_list.visible - 1);
      return true;
    }
    if (event.kind == KeyKind.pageUp) {
      _list.wheel(-(_list.visible - 1));
      return true;
    }
    if (event.kind == KeyKind.enter) {
      final action = actions[_list.selected];
      if (action.enabled) {
        action.run();
      } else {
        app.toast(_disabledReason(app, action.label),
            level: ToastLevel.warning);
      }
      return true;
    }
    if (event.isChar('s')) {
      if (app.coreStatus?.running ?? false) {
        unawaited(app.stopCore());
      } else {
        unawaited(app.startCore());
      }
      return true;
    }
    if (event.isCharExact('R')) {
      unawaited(app.restartCore());
      return true;
    }
    if (event.isChar('r')) {
      unawaited(app.reloadConfig());
      return true;
    }
    if (event.isChar('m')) {
      final current = app.apiConfig?.mode ?? 'rule';
      const order = ['rule', 'global', 'direct'];
      final next = order[(order.indexOf(current) + 1) % order.length];
      unawaited(app.setMode(next));
      return true;
    }
    if (event.isChar('o')) {
      final url = app.activeInfo?.panelUrl;
      if (url != null) app.openUrl(url);
      return true;
    }
    if (event.isChar('p')) {
      unawaited(app.toggleSystemProxy());
      return true;
    }
    return false;
  }
}

class _Action {
  _Action(
    this.label, {
    required this.run,
    this.enabled = true,
    this.hint,
    this.marker,
    this.markerActive = true,
  });

  final String label;
  final Future<void> Function() run;
  final bool enabled;
  final String? hint;
  final String? marker;
  final bool markerActive;
}

class _StatusRow {
  _StatusRow(
    this.label,
    this.value, {
    this.color,
    this.bold = false,
    this.onPress,
  });

  final String label;
  final String value;
  final int? color;
  final bool bold;
  final void Function()? onPress;
}

class _CurrentNode {
  _CurrentNode(this.group, this.name);
  final String group;
  final String name;
}
