/// Subscription list: add, update, rename, delete, activate.
library;

import 'dart:async';
import 'dart:math' as math;

import '../../model/profile.dart';
import '../../term/keys.dart';
import '../../term/style.dart';
import '../../term/width.dart';
import '../../util/format.dart';
import '../../util/traffic.dart';
import '../app_context.dart';
import '../list_state.dart';
import '../overlay.dart';
import '../painter.dart';
import '../theme.dart';
import 'view.dart';

class ProfilesView extends View {
  final ListState _list = ListState();
  DateTime? _lastClickAt;
  int? _lastClickIndex;

  @override
  String get label => '订阅';

  @override
  String get title => '订阅配置';

  @override
  List<KeyHint> hints(AppContext app) => const [
        KeyHint('Enter', '启用'),
        KeyHint('a', '添加'),
        KeyHint('u', '更新'),
        KeyHint('r', '重命名'),
        KeyHint('d', '删除'),
        KeyHint('e', '订阅信息'),
        KeyHint('E', '编辑 YAML'),
      ];

  @override
  void draw(
    AppContext app,
    Painter painter,
    Rect area, {
    required bool focused,
  }) {
    final theme = app.theme;
    final profiles = app.repo.profiles;
    if (profiles.isEmpty) {
      _drawEmpty(app, painter, area);
      return;
    }

    if (area.height < 4 || area.width < 20) return;

    // Two independent cards: the list fills the space, the details card is
    // minimal and pinned to the bottom (same arrangement as the overview).
    _list.bind(total: profiles.length, visible: 1);
    final detailRows = _detailRows(app, profiles[_list.selected]);
    final detailHeight = detailRows.length + 2;
    const gap = 1;
    final showDetail = area.height >= detailHeight + gap + 6;
    final listHeight =
        showDetail ? area.height - detailHeight - gap : area.height;
    final listRect = Rect(area.x, area.y, area.width, listHeight);
    final listInner = Rect(
      listRect.x + 1,
      listRect.y + 1,
      listRect.width - 2,
      listRect.height - 2,
    );
    const headerRows = 2; // labels + separator
    final maxRows = math.max(1, listInner.height - headerRows);
    _list.bind(total: profiles.length, visible: maxRows);
    _list.ensureVisible();

    // Column layout: marker | name | nodes | ports | updated | url
    final nameWidth = (listInner.width * 0.2).round().clamp(10, 20);
    const nodesWidth = 5;
    var portsWidth = listInner.width > 92 ? 16 : 12;
    const trafficWidth = 13;
    const updatedWidth = 11;
    var urlWidth = listInner.width -
        (9 +
            nameWidth +
            nodesWidth +
            portsWidth +
            trafficWidth +
            updatedWidth) -
        1;
    if (urlWidth < 12) {
      portsWidth = listInner.width > 70 ? 8 : 6;
      urlWidth = listInner.width -
          (9 +
              nameWidth +
              nodesWidth +
              portsWidth +
              trafficWidth +
              updatedWidth) -
          1;
    }

    final headerStyle = Style(fg: theme.muted, bg: theme.panel, bold: true);
    final headerY = listInner.y;
    var x = listInner.x + 2;
    painter.text(x, headerY, padRight('名称', nameWidth), headerStyle);
    x += nameWidth + 1;
    painter.text(x, headerY, padLeft('节点', nodesWidth), headerStyle);
    x += nodesWidth + 1;
    painter.text(x, headerY, padRight('端口', portsWidth), headerStyle);
    x += portsWidth + 1;
    painter.text(x, headerY, padRight('流量', trafficWidth), headerStyle);
    x += trafficWidth + 1;
    painter.text(x, headerY, padRight('更新', updatedWidth), headerStyle);
    x += updatedWidth + 1;
    painter.text(x, headerY, truncate('订阅地址', urlWidth), headerStyle);
    painter.text(
      listInner.x,
      headerY + 1,
      '─' * listInner.width,
      Style(fg: theme.border, bg: theme.panel),
    );

    final visible = math.min(maxRows, profiles.length - _list.scroll);
    for (var row = 0; row < visible; row++) {
      final index = _list.scroll + row;
      final profile = profiles[index];
      final selected = index == _list.selected;
      final active = profile.name == app.repo.activeName;
      final rowY = listInner.y + headerRows + row;
      final rowRect = Rect(listInner.x, rowY, listInner.width, 1);
      final info = app.repo.cachedInfo(profile.name);

      var columnX = listInner.x;
      painter.text(
        columnX,
        rowY,
        selected ? '>' : ' ',
        Style(fg: theme.accent, bg: theme.panel, bold: selected),
      );
      columnX += 2;
      final nameStyle = Style(
        fg: active ? theme.green : (selected ? theme.text : theme.muted),
        bg: theme.panel,
        bold: active || selected,
      );
      painter.text(
        columnX,
        rowY,
        padRight(active ? '${profile.name} *' : profile.name, nameWidth),
        nameStyle,
      );
      columnX += nameWidth + 1;
      final nodes = info?.nodeCount;
      painter.text(
        columnX,
        rowY,
        padLeft(nodes == null ? '-' : '$nodes', nodesWidth),
        Style(fg: theme.muted, bg: theme.panel),
      );
      columnX += nodesWidth + 1;
      final ports = info == null || info.portSummary.isEmpty
          ? '-'
          : info.portSummary.first;
      painter.text(
        columnX,
        rowY,
        padRight(truncate(ports, portsWidth - 1), portsWidth),
        Style(fg: theme.accentSoft, bg: theme.panel),
      );
      columnX += portsWidth + 1;
      painter.text(
        columnX,
        rowY,
        padRight(_trafficCell(profile), trafficWidth),
        Style(fg: theme.accentSoft, bg: theme.panel),
      );
      columnX += trafficWidth + 1;
      final updated =
          profile.updatedAt == null ? '-' : formatRelative(profile.updatedAt!);
      painter.text(
        columnX,
        rowY,
        padRight(truncate(updated, updatedWidth - 1), updatedWidth),
        Style(fg: theme.muted, bg: theme.panel),
      );
      columnX += updatedWidth + 1;
      painter.text(
        columnX,
        rowY,
        truncate(profile.url, urlWidth),
        Style(fg: theme.muted, bg: theme.panel),
      );

      painter.hit(
        rowRect,
        id: 'profile$index',
        onHover: () => _list.select(index),
        onPress: () => _onRowPress(app, index),
        onWheel: _list.wheel,
      );
    }

    // Frames last: content can never punch through the borders.
    painter.drawBox(
      listRect,
      focused: focused,
      title: '订阅配置 (${profiles.length})',
    );
    if (showDetail) {
      final detailRect = Rect(
        area.x,
        area.bottom - detailHeight,
        area.width,
        detailHeight,
      );
      _drawDetailCard(
          app, painter, detailRect, profiles[_list.selected], detailRows,
          focused: focused);
    }
  }

  List<(String, String, int?)> _detailRows(AppContext app, Profile profile) {
    final theme = app.theme;
    final info = app.repo.cachedInfo(profile.name);
    final error = app.repo.cachedError(profile.name);
    final isActive = profile.name == app.repo.activeName;
    final rows = <(String, String, int?)>[];
    rows.add((
      '状态',
      isActive ? '当前使用' : '未启用',
      isActive ? theme.green : theme.muted,
    ));
    if (error != null) {
      rows.add(('解析', error, theme.red));
    } else if (info != null) {
      rows.add((
        '节点',
        '${info.nodeCount} 个节点 | ${info.groupCount} 个代理组 | ${info.ruleCount} 条规则'
            '${info.providerCount > 0 ? ' | ${info.providerCount} 个 provider' : ''}',
        null,
      ));
      rows.add((
        '端口',
        info.portSummary.isEmpty ? '未定义' : info.portSummary.join(' | '),
        theme.accentSoft,
      ));
      rows.add(_trafficRow(profile, app.theme) ?? ('流量', '-', null));
      rows.add((
        '控制器',
        '${info.controllerAddress ?? '未定义'} | 模式 ${info.mode}'
            '${info.allowLan ? ' | 允许局域网' : ''}'
            '${info.ipv6 ? ' | IPv6' : ''}',
        null,
      ));
    }
    rows.add((
      '文件',
      '${app.repo.profileFile(profile.name)}'
          '${profile.size == null ? '' : ' | ${formatBytes(profile.size!)}'}',
      theme.muted,
    ));
    rows.add((
      '更新',
      profile.updatedAt == null ? '从未更新' : formatDateTime(profile.updatedAt!),
      theme.muted,
    ));
    rows.add(('地址', profile.url, theme.muted));
    return rows;
  }

  void _drawDetailCard(
    AppContext app,
    Painter painter,
    Rect rect,
    Profile profile,
    List<(String, String, int?)> rows, {
    required bool focused,
  }) {
    final theme = app.theme;
    var y = rect.y + 1;
    for (final row in rows) {
      if (y >= rect.bottom - 1) break;
      painter.text(
        rect.x + 2,
        y,
        row.$1,
        Style(fg: theme.muted, bg: theme.panel),
      );
      painter.text(
        rect.x + 2 + 8,
        y,
        truncate(row.$2, rect.width - 12),
        Style(fg: row.$3 ?? theme.text, bg: theme.panel),
      );
      y++;
    }
    painter.hit(
      Rect(rect.x + 1, rect.y + 1, rect.width - 2, rect.height - 2),
      id: 'detail',
      onPress: () => openProfileInfo(app, profile),
    );
    painter.drawBox(
      rect,
      focused: focused,
      title: '详情 | ${profile.name} | 点击查看全部',
    );
  }

  /// Compact `used/total` text for the table column.
  String _trafficCell(Profile profile) {
    final used = profile.trafficUsed;
    final total = profile.trafficTotal;
    if (used == null && total == null) return '-';
    if (used != null && total != null && total > 0) {
      return '${formatBytesShort(used)}/${formatBytesShort(total)}';
    }
    if (used != null) return formatBytesShort(used);
    return '-';
  }

  /// Detail row with an ASCII progress bar (hidden when the provider does not
  /// report traffic).
  (String, String, int?)? _trafficRow(Profile profile, Theme theme) {
    final summary = summarizeTraffic(
      used: profile.trafficUsed,
      total: profile.trafficTotal,
      expire: profile.trafficExpireAt,
    );
    if (summary == null) return null;
    final fraction = summary.fraction;
    final color = fraction == null
        ? theme.accentSoft
        : fraction >= 0.9
            ? theme.red
            : fraction >= 0.7
                ? theme.yellow
                : theme.green;
    return ('流量', summary.display, color);
  }

  void _drawEmpty(AppContext app, Painter painter, Rect area) {
    final theme = app.theme;
    final box = Rect(area.x, area.y, area.width, area.height);
    painter.text(
      box.x + 3,
      box.y + 2,
      '按 a 添加第一个订阅，或 u 更新已有订阅。',
      Style(fg: theme.text),
    );
    painter.text(
      box.x + 3,
      box.y + 3,
      '订阅会保存到 ${app.paths.profilesDir}',
      Style(fg: theme.muted),
    );
    painter.text(
      box.x + 3,
      box.y + 4,
      '启用后复制为 ${app.paths.mihomoConfigFile}',
      Style(fg: theme.muted),
    );
    painter.hit(
      Rect(box.x + 1, box.y + 1, box.width - 2, math.min(5, box.height - 2)),
      id: 'add',
      onPress: () => unawaited(app.addProfileInteractive()),
    );
    painter.drawBox(box, title: '订阅配置 | 还没有订阅');
  }

  void _onRowPress(AppContext app, int index) {
    final now = DateTime.now();
    final doubleClick = _lastClickIndex == index &&
        _lastClickAt != null &&
        now.difference(_lastClickAt!) < const Duration(milliseconds: 450);
    _lastClickAt = now;
    _lastClickIndex = index;
    _list.select(index);
    if (doubleClick) {
      final profiles = app.repo.profiles;
      if (index < profiles.length) {
        unawaited(app.activateProfile(profiles[index]));
      }
    }
  }

  @override
  bool onKey(AppContext app, KeyEvent event) {
    final profiles = app.repo.profiles;
    if (profiles.isEmpty) {
      if (event.isChar('a') || event.kind == KeyKind.enter) {
        unawaited(app.addProfileInteractive());
        return true;
      }
      return false;
    }
    _list.bind(total: profiles.length, visible: _list.visible);
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
      _list.select(profiles.length - 1);
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
    final profile = profiles[_list.selected];
    if (event.kind == KeyKind.enter) {
      unawaited(app.activateProfile(profile));
      return true;
    }
    if (event.isChar('a')) {
      unawaited(app.addProfileInteractive());
      return true;
    }
    if (event.isCharExact('u')) {
      unawaited(app.updateProfile(profile));
      return true;
    }
    if (event.isCharExact('U')) {
      unawaited(_updateAll(app));
      return true;
    }
    if (event.isChar('r')) {
      _rename(app, profile);
      return true;
    }
    if (event.isChar('d')) {
      app.confirm(
        title: '删除订阅',
        message: '确定删除「${profile.name}」吗？文件会一并删除。',
        detail: [
          if (profile.name == app.repo.activeName) '这是当前启用的配置，删除后核心配置不会被改动。',
        ],
        confirmLabel: '删除',
        danger: true,
        onConfirm: () {
          try {
            app.repo.delete(profile);
            app.toast('已删除「${profile.name}」', level: ToastLevel.success);
            _list.bind(
              total: app.repo.profiles.length,
              visible: _list.visible,
            );
          } catch (error) {
            app.toast('删除失败：$error', level: ToastLevel.error);
          }
        },
      );
      return true;
    }
    if (event.isCharExact('E')) {
      unawaited(app.editProfile(profile));
      return true;
    }
    if (event.isCharExact('e')) {
      unawaited(app.editProfileMeta(profile));
      return true;
    }
    if (event.isChar('i')) {
      openProfileInfo(app, profile);
      return true;
    }
    return false;
  }

  Future<void> _updateAll(AppContext app) async {
    for (final profile in app.repo.profiles) {
      await app.updateProfile(profile);
    }
  }

  void _rename(AppContext app, Profile profile) {
    app.showOverlay(
      FormOverlay(
        onChanged: app.requestFrame,
        title: '重命名配置',
        fields: [
          FormFieldSpec(
            key: 'name',
            label: '新名称',
            initial: profile.name,
            required: true,
            validator: validateProfileName,
          ),
        ],
        onSubmit: (values) {
          final name = values['name']?.trim() ?? '';
          try {
            app.repo.rename(profile, name);
            app.toast('已重命名为「$name」', level: ToastLevel.success);
          } catch (error) {
            app.toast('重命名失败：$error', level: ToastLevel.error);
          }
        },
      ),
    );
  }

  void openProfileInfo(AppContext app, Profile profile) {
    final info = app.repo.cachedInfo(profile.name);
    final error = app.repo.cachedError(profile.name);
    final lines = <String>[
      '名称      ${profile.name}',
      '状态      ${profile.name == app.repo.activeName ? '当前使用' : '未启用'}',
      '文件      ${app.repo.profileFile(profile.name)}',
      if (profile.size != null) '大小      ${formatBytes(profile.size!)}',
      '更新      ${profile.updatedAt == null ? '从未更新' : formatDateTime(profile.updatedAt!)}',
      '地址      ${profile.url}',
      '',
    ];
    if (error != null) {
      lines.add('解析失败  $error');
    } else if (info != null) {
      lines.addAll([
        '节点      ${info.nodeCount}',
        '代理组    ${info.groupCount}',
        '规则      ${info.ruleCount}',
        'Provider  ${info.providerCount}',
        '模式      ${info.mode}',
        '端口      ${info.portSummary.isEmpty ? '未定义' : info.portSummary.join(' | ')}',
        '控制器    ${info.controllerAddress ?? '未定义'}',
        '密钥      ${info.secret == null ? '未设置' : '已设置'}',
        '允许局域网 ${info.allowLan ? '是' : '否'}',
        'IPv6      ${info.ipv6 ? '是' : '否'}',
        'TUN       ${info.tunEnabled ? '启用' : '未启用'}',
        '日志级别  ${info.logLevel ?? 'info'}',
        '面板      ${info.panelUrl ?? '无'}',
      ]);
    }
    app.showOverlay(InfoOverlay(title: '配置信息 | ${profile.name}', lines: lines));
  }

  @override
  bool onWheel(AppContext app, int delta) {
    _list.wheel(delta);
    return true;
  }

  @override
  void reset() => _list.reset();
}
