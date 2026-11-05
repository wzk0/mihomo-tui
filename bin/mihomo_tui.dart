import 'dart:convert';
import 'dart:io';

import 'package:mihomo_tui/src/model/profile_info.dart';
import 'package:mihomo_tui/src/model/settings.dart';
import 'package:mihomo_tui/src/service/core_updater.dart';
import 'package:mihomo_tui/src/service/exporter.dart';
import 'package:mihomo_tui/src/service/mihomo_api.dart';
import 'package:mihomo_tui/src/service/paths.dart';
import 'package:mihomo_tui/src/service/runtime.dart';
import 'package:mihomo_tui/src/term/terminal.dart';
import 'package:mihomo_tui/src/util/format.dart';
import 'package:mihomo_tui/src/ui/app.dart';
import 'package:mihomo_tui/src/version.dart';
import 'package:yaml/yaml.dart';

Future<void> main(List<String> arguments) async {
  final options = _CliOptions.parse(arguments);
  if (options.error != null) {
    stderr.writeln('参数错误：${options.error}');
    stderr.writeln(_usage);
    exitCode = 64;
    return;
  }
  if (options.help) {
    stdout.writeln(_usage);
    return;
  }
  if (options.version) {
    stdout.writeln('$appName $appVersion');
    return;
  }

  final settings = Settings.load(
    '${options.dataDir ?? AppPaths.defaultConfigDir}'
    '${Platform.pathSeparator}settings.json',
  );
  final runtime = Runtime.build(
    settings: settings,
    configDir: options.dataDir,
    mihomoHome: options.home,
    binaryOverride: options.binary,
    editorOverride: options.editor,
  );

  if (options.selfTest) {
    exitCode = await _selfTest(runtime);
    return;
  }

  if (options.status) {
    exitCode = await _printStatus(runtime, json: options.json);
    return;
  }
  if (options.list) {
    runtime.repo.ensureLayout();
    _printList(runtime);
    return;
  }
  final infoName = options.info;
  if (infoName != null) {
    runtime.repo.ensureLayout();
    exitCode = _printInfo(runtime, infoName);
    return;
  }
  if (options.updateCore) {
    exitCode = await _updateCore(runtime, options);
    return;
  }

  final exportPath = options.exportPath;
  if (exportPath != null) {
    runtime.repo.ensureLayout();
    final exporter = DataExporter(paths: runtime.paths, settings: settings);
    try {
      final result = await exporter.export(
        destination: exportPath.isEmpty ? null : File(exportPath),
      );
      stdout.writeln('已导出 ${result.entries.length} 项到 ${result.file.path}');
      stdout.writeln('  ${result.entries.join('\n  ')}');
      exitCode = 0;
    } catch (error) {
      stderr.writeln('导出失败：$error');
      exitCode = 1;
    }
    return;
  }
  final legacyDir = options.importLegacy;
  if (legacyDir != null) {
    runtime.repo.ensureLayout();
    final imported = runtime.repo.importLegacy(legacyDir);
    stdout.writeln(imported == 0
        ? '没有从 $legacyDir 导入任何订阅'
        : '已导入 $imported 个订阅到 ${runtime.paths.profilesDir}');
    exitCode = imported == 0 ? 1 : 0;
    return;
  }
  if (options.start || options.stop || options.restart) {
    runtime.repo.ensureLayout();
    exitCode = await _control(
      runtime,
      start: options.start,
      stop: options.stop,
      restart: options.restart,
    );
    return;
  }

  final terminal = createTerminal();
  if (!terminal.isInteractive) {
    stderr.writeln('$appName 需要交互式终端。');
    stderr.writeln('纯命令行用法请见 $appName --help');
    exitCode = 2;
    return;
  }
  final app = App(
    terminal: terminal,
    settings: settings,
    configDir: options.dataDir,
    mihomoHome: options.home,
    binaryOverride: options.binary,
    editorOverride: options.editor,
  );
  await app.run();
  await stdout.flush();
}

const String _usage = '''
$appName $appVersion — $appDescription

用法:
  $appName [选项]

通用选项:
  -h, --help            显示本帮助
  -V, --version         显示版本号
      --data <目录>     覆盖数据目录（默认 ${'~/.config/mihomo-tui'}）
      --home <目录>     覆盖 mihomo 配置目录（默认 ~/.config/mihomo）
      --bin <路径>      指定 mihomo 可执行文件
      --editor <命令>   指定编辑订阅用的编辑器

无界面命令（不需要 TTY）:
      --status          输出核心与配置状态，退出码 0=运行中 1=未运行
      --json            与 --status 合用，输出 JSON
      --list            列出全部订阅
      --info [名称]     输出订阅详情（缺省为当前启用的订阅）
      --start           启动核心
      --stop            停止核心
      --restart         重启核心
      --selftest        运行内置自检
      --update-core     从 GitHub 下载/更新 mihomo 内核（自动识别平台与架构）
      --mirror <id>     配合 --update-core 选择下载镜像：
                        direct / ghproxy / gh-proxy / akams
      --export [路径]   把设置与全部订阅配置打包成 zip（缺省写到主目录）
      --import-legacy <目录>
                        导入旧 clash_tui 的数据目录（含 data.json 与 config/）

交互界面快捷键:
  Tab 切换侧栏/内容   ↑↓ 移动    Enter 确认    ? 帮助    q 退出
  1-5 直接切换页面    鼠标点击/滚轮同样可用
''';

class _CliOptions {
  _CliOptions();

  bool help = false;
  bool version = false;
  bool status = false;
  bool json = false;
  bool list = false;
  bool selfTest = false;
  bool start = false;
  bool stop = false;
  bool restart = false;
  String? info;
  String? importLegacy;
  String? exportPath;
  bool updateCore = false;
  String? mirror;
  String? binary;
  String? home;
  String? dataDir;
  String? editor;
  String? error;

  static _CliOptions parse(List<String> arguments) {
    final options = _CliOptions();
    String? nextValue(int index) =>
        index + 1 < arguments.length ? arguments[index + 1] : null;

    for (var index = 0; index < arguments.length; index++) {
      final arg = arguments[index];
      switch (arg) {
        case '-h':
        case '--help':
          options.help = true;
        case '-V':
        case '--version':
          options.version = true;
        case '--status':
          options.status = true;
        case '--json':
          options.json = true;
        case '--list':
          options.list = true;
        case '--selftest':
          options.selfTest = true;
        case '--update-core':
          options.updateCore = true;
        case '--mirror':
          options.mirror = nextValue(index);
          if (options.mirror == null) {
            options.error = '--mirror 需要一个镜像 id';
          } else {
            index++;
          }
        case '--export':
          final value = nextValue(index);
          if (value != null && !value.startsWith('-')) {
            options.exportPath = value;
            index++;
          } else {
            options.exportPath = '';
          }
        case '--import-legacy':
          options.importLegacy = nextValue(index);
          if (options.importLegacy == null) {
            options.error = '--import-legacy 需要一个目录';
          } else {
            index++;
          }
        case '--start':
          options.start = true;
        case '--stop':
          options.stop = true;
        case '--restart':
          options.restart = true;
        case '--bin':
          options.binary = nextValue(index);
          if (options.binary == null) {
            options.error = '--bin 需要一个路径';
          } else {
            index++;
          }
        case '--home':
          options.home = nextValue(index);
          if (options.home == null) {
            options.error = '--home 需要一个目录';
          } else {
            index++;
          }
        case '--data':
          options.dataDir = nextValue(index);
          if (options.dataDir == null) {
            options.error = '--data 需要一个目录';
          } else {
            index++;
          }
        case '--editor':
          options.editor = nextValue(index);
          if (options.editor == null) {
            options.error = '--editor 需要一个命令';
          } else {
            index++;
          }
        case '--info':
          final value = nextValue(index);
          if (value != null && !value.startsWith('-')) {
            options.info = value;
            index++;
          } else {
            options.info = '';
          }
        default:
          options.error ??= '未知参数 $arg';
      }
    }
    return options;
  }
}

Future<int> _printStatus(Runtime runtime, {required bool json}) async {
  final status = await runtime.core.status();
  final profile = runtime.repo.activeProfile;
  final configFile = File(runtime.paths.mihomoConfigFile);
  ProfileInfo? info;
  if (configFile.existsSync()) {
    try {
      info = ProfileInfo.parse(configFile.readAsStringSync());
    } catch (_) {
      info = null;
    }
  }
  var apiOnline = false;
  String? apiVersion;
  if (info?.apiBase != null) {
    final api = MihomoApi(baseUrl: info!.apiBase!, secret: info.secret);
    try {
      apiVersion = await api.version();
      apiOnline = apiVersion != null;
    } on ApiException {
      apiOnline = false;
    } finally {
      api.dispose();
    }
  }
  if (json) {
    stdout.writeln(const JsonEncoder.withIndent('  ').convert({
      'app': appName,
      'version': appVersion,
      'platform': Platform.operatingSystem,
      'arch': _arch,
      'binary': status.binaryPath,
      'coreVersion': status.version,
      'running': status.running,
      'pid': status.pid,
      'profile': runtime.repo.activeName,
      'configFile': runtime.paths.mihomoConfigFile,
      'api': info?.controllerAddress,
      'apiOnline': apiOnline,
      'apiVersion': apiVersion,
    }));
  } else {
    stdout.writeln('$appName $appVersion (${Platform.operatingSystem} $_arch)');
    stdout.writeln('  二进制    ${status.binaryPath ?? '未找到'}');
    stdout.writeln('  核心版本  ${status.version ?? '未知'}');
    stdout.writeln('  状态      ${status.running ? '运行中' : '未运行'}'
        '${status.pid == null ? '' : '（pid ${status.pid}）'}');
    stdout.writeln(
      '  订阅      ${runtime.repo.activeName ?? '未选择'}'
      '${profile?.updatedAt == null ? '' : '（更新于 ${formatDateTime(profile!.updatedAt!)}）'}',
    );
    stdout.writeln('  配置      ${runtime.paths.mihomoConfigFile}');
    stdout.writeln(
      '  控制器    ${info?.controllerAddress ?? '未配置'}'
      '${apiOnline ? ' · 已连接 ${apiVersion ?? ''}' : ''}',
    );
    stdout.writeln('  数据目录  ${runtime.paths.configDir}');
  }
  return status.running ? 0 : 1;
}

void _printList(Runtime runtime) {
  final profiles = runtime.repo.profiles;
  if (profiles.isEmpty) {
    stdout.writeln('（还没有订阅）');
    return;
  }
  stdout.writeln('  名称\t节点\t端口\t更新\t地址');
  for (final profile in profiles) {
    final info = runtime.repo.cachedInfo(profile.name);
    final marker = profile.name == runtime.repo.activeName ? '*' : ' ';
    final ports =
        info == null || info.portSummary.isEmpty ? '-' : info.portSummary.first;
    stdout.writeln(
      '$marker ${profile.name}\t'
      '${info?.nodeCount ?? '?'}\t'
      '$ports\t'
      '${profile.updatedAt == null ? '-' : formatDateTime(profile.updatedAt!)}\t'
      '${profile.url}',
    );
  }
}

int _printInfo(Runtime runtime, String name) {
  final target = name.isEmpty ? runtime.repo.activeName : name;
  if (target == null) {
    stderr.writeln('当前没有启用的订阅，请指定名称：$appName --info <名称>');
    return 1;
  }
  final profile = runtime.repo.byName(target);
  if (profile == null) {
    stderr.writeln('未找到订阅「$target」');
    return 1;
  }
  final info = runtime.repo.cachedInfo(target);
  final error = runtime.repo.cachedError(target);
  stdout.writeln('名称      ${profile.name}');
  stdout.writeln('地址      ${profile.url}');
  stdout.writeln('文件      ${runtime.repo.profileFile(target)}');
  stdout.writeln(
    '更新      ${profile.updatedAt == null ? '从未更新' : formatDateTime(profile.updatedAt!)}',
  );
  stdout.writeln(
      '启用      ${profile.name == runtime.repo.activeName ? '是' : '否'}');
  if (error != null) {
    stdout.writeln('解析失败  $error');
    return 1;
  }
  if (info != null) {
    stdout.writeln('节点      ${info.nodeCount}');
    stdout.writeln('代理组    ${info.groupCount}');
    stdout.writeln('规则      ${info.ruleCount}');
    stdout.writeln('模式      ${info.mode}');
    stdout.writeln(
      '端口      ${info.portSummary.isEmpty ? '未定义' : info.portSummary.join(' · ')}',
    );
    stdout.writeln('控制器    ${info.controllerAddress ?? '未定义'}');
    stdout.writeln('允许局域网 ${info.allowLan ? '是' : '否'}');
    stdout.writeln('IPv6      ${info.ipv6 ? '是' : '否'}');
    stdout.writeln('面板      ${info.panelUrl ?? '无'}');
  }
  return 0;
}

Future<int> _control(
  Runtime runtime, {
  required bool start,
  required bool stop,
  required bool restart,
}) async {
  if (stop || restart) {
    final stopped = await runtime.core.stop();
    stdout.writeln(stopped ? '已停止 mihomo' : '没有运行中的 mihomo 进程');
    if (stop && !restart) return stopped ? 0 : 1;
    await Future<void>.delayed(const Duration(milliseconds: 400));
  }
  if (start || restart) {
    if (runtime.repo.activeName == null &&
        !File(runtime.paths.mihomoConfigFile).existsSync()) {
      stderr.writeln('没有可用的配置，请先在 TUI 中选择订阅');
      return 1;
    }
    final result = await runtime.core.start();
    if (!result.isSuccess) {
      stderr.writeln('启动失败：${result.error}');
      return 1;
    }
    stdout.writeln('mihomo 已启动，pid ${result.pid}');
  }
  return 0;
}

Future<int> _selfTest(Runtime runtime) async {
  var failures = 0;
  void check(String label, bool ok, [String? detail]) {
    stdout.writeln(
        '${ok ? 'ok  ' : 'FAIL'} $label${detail == null ? '' : ' · $detail'}');
    if (!ok) failures++;
  }

  stdout.writeln('$appName $appVersion selftest');
  check('platform', Platform.operatingSystem.isNotEmpty,
      '${Platform.operatingSystem} $_arch');
  check(
    'dart runtime',
    Platform.version.isNotEmpty,
    Platform.version.split(' ').first,
  );

  try {
    final temp = Directory.systemTemp.createTempSync('mihomo-tui-selftest');
    final file = File('${temp.path}${Platform.pathSeparator}probe.txt');
    file.writeAsStringSync('probe');
    check('filesystem', file.readAsStringSync() == 'probe', temp.path);
    temp.deleteSync(recursive: true);
  } catch (error) {
    check('filesystem', false, '$error');
  }

  try {
    final parsed = ProfileInfo.parse('''
mixed-port: 7890
mode: rule
external-controller: 127.0.0.1:9090
proxies:
  - {name: a, type: ss, server: 1.1.1.1, port: 80, cipher: aes-128-gcm, password: x}
proxy-groups:
  - {name: g, type: select, proxies: [a]}
rules:
  - DOMAIN-SUFFIX,example.com,DIRECT
''');
    check(
      'config parser',
      parsed.nodeCount == 1 &&
          parsed.mixedPort == 7890 &&
          parsed.mode == 'rule',
      '${parsed.nodeCount} 节点 · 端口 ${parsed.mixedPort}',
    );
  } catch (error) {
    check('config parser', false, '$error');
  }

  try {
    final sample = loadYaml('a: 1');
    check('yaml engine', sample is YamlMap);
  } catch (error) {
    check('yaml engine', false, '$error');
  }

  try {
    final settings = Settings(
      mihomoBin: runtime.paths.mihomoBin,
      editor: 'vi',
    );
    final roundTrip = Settings.fromJson(settings.toJson());
    check('settings roundtrip', roundTrip.editor == 'vi');
  } catch (error) {
    check('settings roundtrip', false, '$error');
  }

  final binary = runtime.core.resolveBinary();
  stdout.writeln(
    'info  mihomo binary · ${binary ?? '未找到（TUI 里可在设置中指定）'}',
  );
  if (binary != null) {
    final version = await runtime.core.version();
    stdout.writeln('info  mihomo version · ${version ?? '无法读取'}');
  }
  stdout.writeln('info  data dir · ${runtime.paths.configDir}');
  stdout.writeln('info  config dir · ${runtime.paths.mihomoHome}');
  stdout.writeln(
      'info  tty · stdin=${stdin.hasTerminal} stdout=${stdout.hasTerminal}');

  return failures == 0 ? 0 : 1;
}

Future<int> _updateCore(Runtime runtime, _CliOptions options) async {
  final mirror = mirrorById(options.mirror);
  final updater = CoreUpdater(mirror: mirror);
  final target = options.binary != null
      ? File(options.binary!).absolute.path
      : runtime.core.resolveBinary() ?? CoreUpdater.defaultInstallPath();
  stdout.writeln('$appName $appVersion');
  stdout.writeln('  平台/架构  ${CoreUpdater.platformLabel}');
  stdout.writeln('  下载源     ${mirror.label}');
  stdout.writeln('  目标路径   $target');
  stdout.writeln('  当前版本   ${await runtime.core.version() ?? '未安装'}');
  try {
    stdout.write('  查询最新版本...');
    final release = await updater.latest();
    stdout.writeln(' ${release.tag}（${release.assetName}）');
    var lastPercent = -1;
    var progressOpen = false;
    final result = await updater.install(
      release,
      targetPath: target,
      onProgress: (received, total) {
        if (total == null) return;
        final percent = (received * 100 / total).floor();
        if (percent < lastPercent + 10) return;
        lastPercent = percent;
        stdout.write(' $percent%');
        progressOpen = percent < 100;
        if (percent >= 100) stdout.writeln();
      },
    );
    if (progressOpen) stdout.writeln();
    stdout.writeln('完成：${result.path}（${result.version}）');
    return 0;
  } on CoreUpdateException catch (error) {
    stderr.writeln('更新失败：${error.message}');
    return 1;
  }
}

String get _arch {
  final version = Platform.version;
  if (version.contains('arm64') || version.contains('aarch64')) return 'arm64';
  if (version.contains('arm')) return 'arm';
  if (version.contains('x64')) return 'x64';
  return 'unknown';
}
