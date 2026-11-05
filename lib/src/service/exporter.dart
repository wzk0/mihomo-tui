/// One-click export of the app data into a zip archive.
library;

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';

import '../model/settings.dart';
import '../version.dart';
import 'paths.dart';

class ExportResult {
  const ExportResult({
    required this.file,
    required this.entries,
    required this.bytes,
  });

  final File file;
  final List<String> entries;
  final int bytes;
}

class DataExporter {
  DataExporter({required this.paths, required this.settings});

  final AppPaths paths;
  final Settings settings;

  static String defaultFileName({DateTime? now}) {
    final stamp = now ?? DateTime.now();
    String two(int value) => value.toString().padLeft(2, '0');
    return 'mihomo-tui-export-${stamp.year}${two(stamp.month)}${two(stamp.day)}'
        '-${two(stamp.hour)}${two(stamp.minute)}${two(stamp.second)}.zip';
  }

  /// Default location: `~/mihomo-tui-export-<timestamp>.zip`.
  File defaultDestination({DateTime? now}) {
    final home = AppPaths.homeDir;
    final separator = Platform.pathSeparator;
    return File('$home$separator${defaultFileName(now: now)}');
  }

  /// Collects settings, subscription index, every profile and the currently
  /// activated mihomo config into a single zip archive.
  Future<ExportResult> export({File? destination}) async {
    final target = destination ?? defaultDestination();
    final archive = Archive();
    final entries = <String>[];

    void addText(String name, String content) {
      final bytes = utf8.encode(content);
      archive.addFile(ArchiveFile(name, bytes.length, bytes));
      entries.add(name);
    }

    final dataFile = File(paths.dataFile);
    final settingsFile = File(paths.settingsFile);
    final profilesDir = Directory(paths.profilesDir);

    final manifest = <String, Object?>{
      'app': appName,
      'version': appVersion,
      'exportedAt': DateTime.now().toIso8601String(),
      'platform': Platform.operatingSystem,
      'dataDir': paths.configDir,
      'mihomoHome': paths.mihomoHome,
      'activeProfile':
          profilesDir.existsSync() ? _activeProfileName(dataFile) : null,
      'profileCount': profilesDir.existsSync()
          ? profilesDir
              .listSync()
              .whereType<File>()
              .where((file) => file.path.endsWith('.yaml'))
              .length
          : 0,
      'theme': {'accent': settings.accent, 'colorMode': settings.colorMode},
    };
    addText('manifest.json', _prettyJson(manifest));

    addText(
      'settings.json',
      settingsFile.existsSync()
          ? settingsFile.readAsStringSync()
          : _prettyJson(settings.toJson()),
    );
    if (dataFile.existsSync()) {
      addText('data.json', dataFile.readAsStringSync());
    }
    if (profilesDir.existsSync()) {
      final files = profilesDir
          .listSync()
          .whereType<File>()
          .where((file) => file.path.endsWith('.yaml'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
      for (final file in files) {
        final name = file.uri.pathSegments.last;
        archive.addFile(
          ArchiveFile(
            'profiles/$name',
            file.lengthSync(),
            file.readAsBytesSync(),
          ),
        );
        entries.add('profiles/$name');
      }
    }
    final activeConfig = File(paths.mihomoConfigFile);
    if (activeConfig.existsSync()) {
      archive.addFile(
        ArchiveFile(
          'mihomo/config.yaml',
          activeConfig.lengthSync(),
          activeConfig.readAsBytesSync(),
        ),
      );
      entries.add('mihomo/config.yaml');
    }

    addText(
      'README.txt',
      [
        '$appName $appVersion 数据导出',
        '导出时间：${DateTime.now()}',
        '',
        '内容：',
        '  manifest.json        导出信息（版本、平台、路径、当前订阅）',
        '  settings.json        应用设置（内核路径、编辑器、主题等）',
        '  data.json            订阅索引（名称、地址、更新时间、当前启用项）',
        '  profiles/*.yaml      每个订阅的原始配置',
        '  mihomo/config.yaml   正在使用的核心配置（如果存在）',
        '',
        '恢复：把 profiles/*.yaml 与 data.json 放回数据目录，',
        '或把某一份 yaml 直接当作 mihomo 的 config.yaml 使用。',
      ].join('\n'),
    );

    final List<int>? encoded;
    try {
      encoded = ZipEncoder().encode(archive);
    } catch (error) {
      throw StateError('压缩失败：$error');
    }

    target.parent.createSync(recursive: true);
    await target.writeAsBytes(encoded, flush: true);
    return ExportResult(
      file: target,
      entries: entries,
      bytes: encoded.length,
    );
  }

  String? _activeProfileName(File dataFile) {
    if (!dataFile.existsSync()) return null;
    try {
      final decoded = jsonDecode(dataFile.readAsStringSync());
      if (decoded is Map && decoded['active'] is String) {
        return decoded['active'] as String;
      }
    } catch (_) {}
    return null;
  }

  String _prettyJson(Object? value) =>
      const JsonEncoder.withIndent('  ').convert(value);
}
