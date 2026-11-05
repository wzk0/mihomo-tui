import 'dart:convert';
import 'dart:io';

import 'package:mihomo_tui/src/model/profile.dart';
import 'package:mihomo_tui/src/model/settings.dart';
import 'package:mihomo_tui/src/service/store.dart';
import 'package:test/test.dart';

void main() {
  late Directory temp;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('mihomo-tui-store');
  });

  tearDown(() {
    if (temp.existsSync()) temp.deleteSync(recursive: true);
  });

  test('parses the legacy bare-list data.json', () {
    final data = AppData.fromJson([
      {'name': 'a', 'url': 'https://example.com/a'},
      {'name': 'b', 'url': 'https://example.com/b'},
    ]);
    expect(data.profiles.map((p) => p.name), ['a', 'b']);
    expect(data.active, isNull);
  });

  test('parses the new object format', () {
    final data = AppData.fromJson({
      'version': 1,
      'active': 'a',
      'profiles': [
        {'name': 'a', 'url': 'https://example.com/a'},
      ],
    });
    expect(data.profiles.single.name, 'a');
    expect(data.active, 'a');
    expect(data.activeProfile?.name, 'a');
  });

  test('ignores malformed entries', () {
    final data = AppData.fromJson({
      'profiles': [
        {'name': 'a', 'url': 'u'},
        'junk',
        {'url': 'no-name'},
      ],
    });
    expect(data.profiles.length, 1);
  });

  test('saves and loads through DataStore', () {
    final path = '${temp.path}${Platform.pathSeparator}data.json';
    final store = DataStore(path);
    final data = AppData(
      profiles: [
        Profile(
          name: 'pm',
          url: 'https://example.com/sub',
          updatedAt: DateTime.utc(2026, 5, 6),
        ),
      ],
      active: 'pm',
    );
    store.save(data);
    final loaded = store.load();
    expect(loaded.profiles.single.name, 'pm');
    expect(loaded.active, 'pm');
    expect(loaded.profiles.single.updatedAt, DateTime.utc(2026, 5, 6));
    // Ensure the file is valid JSON with the documented shape.
    final decoded = jsonDecode(File(path).readAsStringSync());
    expect(decoded, isA<Map<String, Object?>>());
  });

  test('missing or corrupt data.json yields an empty store', () {
    final path = '${temp.path}${Platform.pathSeparator}data.json';
    expect(DataStore(path).load().profiles, isEmpty);
    File(path).writeAsStringSync('{not json');
    expect(DataStore(path).load().profiles, isEmpty);
  });

  test('copyWith keeps theme fields', () {
    const settings = Settings(
      accent: 'violet',
      colorMode: 'light',
      editor: 'vi',
    );
    final next = settings.copyWith(accent: 'green');
    expect(next.accent, 'green');
    expect(next.colorMode, 'light');
    expect(next.editor, 'vi');
    expect(settings.copyWith(clearColorMode: true).colorMode, isNull);
    expect(settings.copyWith(clearAccent: true).accent, isNull);
  });

  test('settings round trip and defaults', () {
    final path = '${temp.path}${Platform.pathSeparator}settings.json';
    const settings = Settings(
      mihomoBin: '/opt/mihomo',
      editor: 'nano',
      downloadProxy: 'http://127.0.0.1:7890',
    );
    settings.save(path);
    final loaded = Settings.load(path);
    expect(loaded.mihomoBin, '/opt/mihomo');
    expect(loaded.editor, 'nano');
    expect(loaded.downloadProxy, 'http://127.0.0.1:7890');
    expect(loaded.mihomoHome, isNull);
    expect(loaded.accent, isNull);

    File(path).writeAsStringSync('{"editor": ""}');
    expect(Settings.load(path).editor, isNull);
    expect(Settings.load('${temp.path}/missing.json').mihomoBin, isNull);
  });
}
