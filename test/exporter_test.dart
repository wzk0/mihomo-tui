import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:mihomo_tui/src/model/profile.dart';
import 'package:mihomo_tui/src/model/settings.dart';
import 'package:mihomo_tui/src/service/exporter.dart';
import 'package:mihomo_tui/src/service/paths.dart';
import 'package:mihomo_tui/src/service/store.dart';
import 'package:test/test.dart';

void main() {
  late Directory temp;
  late AppPaths paths;
  late DataExporter exporter;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('mihomo-tui-export');
    paths = AppPaths(
      configDir: '${temp.path}/data',
      mihomoHome: '${temp.path}/home',
      mihomoBin: null,
      editor: 'vi',
    );
    Directory(paths.profilesDir).createSync(recursive: true);
    Directory(paths.mihomoHome).createSync(recursive: true);
    const settings = Settings(
      mihomoBin: '/usr/bin/mihomo',
      accent: 'violet',
      colorMode: 'light',
    );
    exporter = DataExporter(paths: paths, settings: settings);
  });

  tearDown(() {
    if (temp.existsSync()) temp.deleteSync(recursive: true);
  });

  test('exports settings, index, profiles and active config', () async {
    const settings = Settings(accent: 'violet', colorMode: 'light');
    settings.save(paths.settingsFile);
    DataStore(paths.dataFile).save(AppData(
      profiles: [
        const Profile(name: 'a', url: 'https://example.com/a'),
        const Profile(name: 'b', url: 'https://example.com/b'),
      ],
      active: 'a',
    ));
    File('${paths.profilesDir}/a.yaml').writeAsStringSync('mixed-port: 7890\n');
    File('${paths.profilesDir}/b.yaml').writeAsStringSync('mixed-port: 7891\n');
    File(paths.mihomoConfigFile).writeAsStringSync('mixed-port: 7890\n');

    final destination = File('${temp.path}/export.zip');
    final result = await exporter.export(destination: destination);

    expect(result.file.existsSync(), isTrue);
    expect(result.bytes, greaterThan(0));
    expect(
      result.entries,
      containsAll([
        'manifest.json',
        'settings.json',
        'data.json',
        'profiles/a.yaml',
        'profiles/b.yaml',
        'mihomo/config.yaml',
        'README.txt',
      ]),
    );

    final archive = ZipDecoder().decodeBytes(destination.readAsBytesSync());
    final names = archive.files.map((file) => file.name).toSet();
    expect(names.contains('manifest.json'), isTrue);

    final manifest = jsonDecode(
      utf8.decode(archive.findFile('manifest.json')!.content as List<int>),
    ) as Map<String, Object?>;
    expect(manifest['activeProfile'], 'a');
    expect(manifest['profileCount'], 2);
    expect((manifest['theme'] as Map)['accent'], 'violet');

    final exportedSettings = jsonDecode(
      utf8.decode(archive.findFile('settings.json')!.content as List<int>),
    ) as Map<String, Object?>;
    expect(exportedSettings['colorMode'], 'light');

    final profileA = utf8.decode(
      archive.findFile('profiles/a.yaml')!.content as List<int>,
    );
    expect(profileA, contains('mixed-port: 7890'));
  });

  test('works with an empty data directory and default destination', () async {
    Directory(paths.profilesDir).createSync(recursive: true);
    final result = await exporter.export();
    expect(result.file.existsSync(), isTrue);
    final archive = ZipDecoder().decodeBytes(result.file.readAsBytesSync());
    final names = archive.files.map((file) => file.name).toSet();
    expect(names, contains('manifest.json'));
    expect(names, contains('settings.json'));
    expect(names, isNot(contains('data.json')));
    expect(names, isNot(contains('mihomo/config.yaml')));
    // Cleanup the home directory export.
    result.file.deleteSync();
  });

  test('file name is timestamped', () {
    final name = DataExporter.defaultFileName(
      now: DateTime(2026, 1, 2, 3, 4, 5),
    );
    expect(name, 'mihomo-tui-export-20260102-030405.zip');
  });
}
