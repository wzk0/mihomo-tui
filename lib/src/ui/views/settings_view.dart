/// Settings pane: paths, editor, download proxy.
library;

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import '../../model/settings.dart';
import '../../service/autostart.dart';
import '../../service/core_updater.dart';
import '../../service/downloader.dart';
import '../../util/format.dart';
import '../../service/paths.dart';
import '../../term/keys.dart';
import '../../term/style.dart';
import '../../term/width.dart';
import '../../version.dart';
import '../theme.dart';
import '../app_context.dart';
import '../list_state.dart';
import '../overlay.dart';
import '../painter.dart';
import 'view.dart';

class SettingsView extends View {
  final ListState _list = ListState();

  @override
  String get label => '设置';

  @override
  String get title => '设置';

  @override
  List<KeyHint> hints(AppContext app) => const [
        KeyHint('上下', '选择'),
        KeyHint('Enter', '编辑'),
        KeyHint('d', '自动检测核心'),
        KeyHint('i', '关于'),
      ];

  List<_Row> _rows(AppContext app) {
    final settings = app.settings;
    return [
      _Row(
        'mihomo 可执行文件',
        settings.mihomoBin ?? '自动检测',
        '留空则从 PATH / 程序目录 / 常见路径自动查找',
        editable: true,
        onEdit: (value) => _apply(
            app,
            settings.copyWith(
              mihomoBin: value,
              clearMihomoBin: value.isEmpty,
            )),
      ),
      _Row(
        'mihomo 配置目录',
        settings.mihomoHome ?? app.paths.mihomoHome,
        '启动核心时使用 -d 指定的目录，config.yaml 会写在这里',
        editable: true,
        onEdit: (value) => _apply(
            app,
            settings.copyWith(
              mihomoHome: value,
              clearMihomoHome: value.isEmpty,
            )),
      ),
      _Row(
        '编辑器',
        settings.editor ?? AppPaths.defaultEditor,
        '编辑订阅时使用，支持带参数（如 "code -w"）',
        editable: true,
        onEdit: (value) => _apply(
            app,
            settings.copyWith(
              editor: value,
              clearEditor: value.isEmpty,
            )),
      ),
      _Row(
        '更新内核',
        app.coreStatus?.version ?? '未安装',
        '从 GitHub 官方获取与当前平台/架构匹配的内核（${CoreUpdater.platformLabel}）',
        action: true,
        onActivate: () => unawaited(app.updateCore()),
      ),
      _Row(
        '下载镜像',
        _mirrorValue(app),
        '选择更新内核的下载源，打开后可看到各镜像的连通性',
        action: true,
        onActivate: app.showMirrorPicker,
      ),
      _Row(
        '下载代理',
        settings.downloadProxy ?? _defaultProxy(),
        '留空则使用环境变量 http_proxy/https_proxy',
        editable: true,
        onEdit: (value) => _apply(
            app,
            settings.copyWith(
              downloadProxy: value,
              clearDownloadProxy: value.isEmpty,
            )),
      ),
      _Row(
        '主题色',
        Theme.accentLabel(settings.accent ?? 'blue'),
        '回车切换强调色（蓝 / 紫 / 绿 / 橙 / 青 / 玫红）',
        action: true,
        onActivate: () => unawaited(app.cycleThemeAccent()),
      ),
      _Row(
        '明暗模式',
        switch (settings.colorMode ?? 'auto') {
          'light' => '亮色',
          'dark' => '暗色',
          _ => '跟随终端',
        },
        '终端深浅色不同，可强制指定；自动模式读取 OSC 11 / COLORFGBG',
        action: true,
        onActivate: () => unawaited(app.cycleColorMode()),
      ),
      _Row(
        '开机自启',
        _autostartLabel(app),
        '随登录自动启动 mihomo（Linux: systemd 用户服务；Windows: 注册表 Run）',
        action: true,
        onActivate: () => unawaited(app.toggleAutostart()),
      ),
      _Row(
        '导出数据',
        '导出为 zip',
        '设置 + 订阅索引 + 所有配置文件，导出到主目录',
        action: true,
        onActivate: () => app.confirm(
          title: '导出数据',
          message: '将设置、订阅索引（data.json）与全部配置文件打包为 zip。',
          detail: const ['默认保存在主目录，文件名带时间戳。'],
          confirmLabel: '导出',
          onConfirm: () => unawaited(app.exportData()),
        ),
      ),
      _Row('数据目录', app.paths.configDir, '订阅配置、日志与运行状态',
          action: true, onActivate: () => _openPath(app, app.paths.configDir)),
      _Row('订阅目录', app.paths.profilesDir, '每个订阅保存为 <名称>.yaml',
          action: true,
          onActivate: () => _openPath(app, app.paths.profilesDir)),
      _Row('日志文件', app.paths.logFile, 'mihomo 的 stdout/stderr 输出',
          action: true,
          onActivate: () => _openPath(app,
              app.core.hasLogFile ? app.paths.logFile : app.paths.logsDir)),
      _Row(
        '检测核心',
        app.coreStatus?.binaryPath == null
            ? '未找到'
            : app.coreStatus!.binaryPath!,
        '重新扫描 mihomo 可执行文件',
        action: true,
        onActivate: () => unawaited(app.refresh()),
      ),
      _Row('关于', '$appName $appVersion', '终端界面 | 鼠标与键盘均可操作',
          action: true, onActivate: () => _about(app)),
    ];
  }

  String _mirrorValue(AppContext app) {
    final current = mirrorById(app.settings.mirror);
    if (app.isMirrorProbing(current.id)) return '${current.label}（检测中~）';
    final probe = app.mirrorProbes[current.id];
    if (probe == null) return current.label;
    return '${current.label}（${probe.label}）';
  }

  String _autostartLabel(AppContext app) => switch (app.autostartState) {
        AutostartState.enabled => '已启用',
        AutostartState.disabled => '未启用',
        AutostartState.unsupported => '当前平台不支持 / 未找到内核',
        AutostartState.unknown => '检测中~',
      };

  String _defaultProxy() {
    final proxy = Downloader.envProxy();
    return proxy ?? '未设置（走直连）';
  }

  @override
  void draw(
    AppContext app,
    Painter painter,
    Rect area, {
    required bool focused,
  }) {
    final theme = app.theme;
    final rows = _rows(app);
    final inner = Rect(area.x + 1, area.y + 1, area.width - 2, area.height - 2);
    final labelWidth = (inner.width * 0.28).round().clamp(14, 30);

    // Rows take two lines plus a separating blank line; compute capacity from
    // the real height so the list never leaves a blank row behind.
    var capacity = 0;
    var used = 0;
    while (used + (capacity == 0 ? 2 : 3) <= inner.height) {
      used += capacity == 0 ? 2 : 3;
      capacity++;
    }
    if (capacity < 1) capacity = 1;
    _list.bind(total: rows.length, visible: capacity);
    _list.ensureVisible();

    var y = inner.y;
    final visible = math.min(capacity, rows.length - _list.scroll);
    for (var row = 0; row < visible; row++) {
      final index = _list.scroll + row;
      final entry = rows[index];
      final selected = index == _list.selected;
      const rowHeight = 2;
      final rowStyle = selected
          ? theme.selectionStyle()
          : Style(fg: theme.muted, bg: theme.panel);
      painter.text(
        inner.x,
        y,
        selected ? '>' : ' ',
        Style(fg: theme.accent, bg: rowStyle.bg),
      );
      painter.text(
        inner.x + 2,
        y,
        truncate(entry.label, labelWidth),
        Style(
            fg: selected ? theme.text : theme.muted,
            bg: rowStyle.bg,
            bold: selected),
      );
      final valueStyle = Style(
        fg: entry.editable
            ? theme.accentSoft
            : (selected ? theme.text : theme.muted),
        bg: rowStyle.bg,
      );
      painter.text(
        inner.x + 2 + labelWidth,
        y,
        truncate(entry.value, inner.width - labelWidth - 4),
        valueStyle,
      );
      painter.text(
        inner.x + 2 + labelWidth,
        y + 1,
        truncate(entry.description, inner.width - labelWidth - 4),
        Style(fg: theme.muted, bg: rowStyle.bg),
      );
      painter.hit(
        Rect(inner.x, y, inner.width, rowHeight + 1),
        id: 'setting$index',
        onHover: () => _list.select(index),
        onWheel: _list.wheel,
        onPress: () {
          _list.select(index);
          if (entry.onActivate != null) {
            entry.onActivate!();
          } else {
            _edit(app, entry);
          }
        },
      );
      y += rowHeight + 1;
    }
    // Painted last so stray text can never break the frame.
    painter.drawBox(area, focused: focused, title: '设置');
  }

  void _edit(AppContext app, _Row row) {
    if (row.onEdit == null) return;
    app.showOverlay(
      FormOverlay(
        onChanged: app.requestFrame,
        title: row.label,
        description: [row.description],
        fields: [
          FormFieldSpec(
            key: 'value',
            label: '新的值',
            hint: row.label.contains('可执行文件') ? '留空则自动检测' : row.value,
            initial: row.value == '自动检测' ? '' : row.value,
          ),
        ],
        onSubmit: (values) => row.onEdit!(values['value']?.trim() ?? ''),
      ),
    );
  }

  Future<void> _apply(AppContext app, Settings next) async {
    await app.applySettings(next);
    app.toast('设置已保存', level: ToastLevel.success);
  }

  void _openPath(AppContext app, String path) {
    final directory = Directory(path);
    final target = directory.existsSync() ? path : File(path).parent.path;
    app.openUrl(target);
  }

  void _about(AppContext app) {
    app.showOverlay(
      InfoOverlay(
        title: '关于 $appName',
        lines: [
          '$appName $appVersion',
          appDescription,
          '',
          '平台      ${platformLabel()}',
          'Dart      ${Platform.version.split(' ').first}',
          '数据目录  ${app.paths.configDir}',
          '配置目录  ${app.paths.mihomoHome}',
          '核心      ${app.coreStatus?.binaryPath ?? '未找到'}',
          '版本      ${app.coreStatus?.version ?? '未知'}',
          '',
          '操作提示',
          '  | 鼠标点击即可选中条目，滚轮可滚动列表',
          '  | Tab 在侧栏与内容区之间切换焦点',
          '  | ? 打开快捷键帮助',
          '',
          'mihomo-tui 是原 clash_tui（python）的 Dart 重写版，',
          '核心改用 mihomo（Clash.Meta），并新增了控制器集成、',
          '鼠标操作与日志查看。',
        ],
      ),
    );
  }

  @override
  bool onKey(AppContext app, KeyEvent event) {
    final rows = _rows(app);
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
      _list.select(rows.length - 1);
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
      final row = rows[_list.selected];
      if (row.onActivate != null) {
        row.onActivate!();
      } else {
        _edit(app, row);
      }
      return true;
    }
    if (event.isChar('d')) {
      unawaited(app.refresh());
      return true;
    }
    if (event.isChar('i')) {
      _about(app);
      return true;
    }
    return false;
  }
}

class _Row {
  _Row(
    this.label,
    this.value,
    this.description, {
    this.editable = false,
    this.action = false,
    this.onEdit,
    this.onActivate,
  });

  final String label;
  final String value;
  final String description;
  final bool editable;
  final bool action;
  final void Function(String value)? onEdit;
  final void Function()? onActivate;
}
