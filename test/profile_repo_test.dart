import 'dart:convert';
import 'dart:io';

import 'package:mihomo_tui/src/model/settings.dart';
import 'package:mihomo_tui/src/service/downloader.dart';
import 'package:mihomo_tui/src/service/paths.dart';
import 'package:mihomo_tui/src/service/profile_repo.dart';
import 'package:test/test.dart';

const _validConfig = '''
mixed-port: 7890
mode: rule
external-controller: 127.0.0.1:9099
proxies:
  - {name: a, type: ss, server: 1.1.1.1, port: 1, cipher: aes-128-gcm, password: x}
proxy-groups:
  - {name: g, type: select, proxies: [a]}
rules:
  - MATCH,g
''';

void main() {
  late Directory temp;
  late HttpServer server;
  late String baseUrl;
  var payload = _validConfig;
  var statusCode = 200;

  setUpAll(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    baseUrl = 'http://127.0.0.1:${server.port}/sub';
    server.listen((request) async {
      request.response.statusCode = statusCode;
      request.response.headers.contentType = ContentType.text;
      request.response.headers.set(
        'subscription-userinfo',
        'upload=1048576; download=2097152; total=1073741824; expire=1893456000',
      );
      request.response.write(payload);
      await request.response.close();
    });
  });

  tearDownAll(() async {
    await server.close(force: true);
  });

  setUp(() {
    temp = Directory.systemTemp.createTempSync('mihomo-tui-repo');
    payload = _validConfig;
    statusCode = 200;
  });

  tearDown(() {
    if (temp.existsSync()) temp.deleteSync(recursive: true);
  });

  ProfileRepository buildRepo({String? configDir, String? home}) {
    final paths = AppPaths(
      configDir: configDir ?? '${temp.path}/data',
      mihomoHome: home ?? '${temp.path}/home',
      mihomoBin: null,
      editor: 'vi',
    );
    final repo = ProfileRepository(
      paths: paths,
      settings: const Settings(),
      downloaderFactory: () => Downloader(proxy: ''),
    );
    repo.ensureLayout();
    return repo;
  }

  test('add downloads and records a profile', () async {
    final repo = buildRepo();
    await repo.add(name: 'pm', url: baseUrl);

    expect(repo.profiles.single.name, 'pm');
    expect(File(repo.profileFile('pm')).existsSync(), isTrue);
    final info = repo.cachedInfo('pm');
    expect(info?.nodeCount, 1);
    expect(info?.mixedPort, 7890);
    expect(repo.profiles.single.size, greaterThan(0));
    expect(repo.profiles.single.updatedAt, isNotNull);
    expect(repo.profiles.single.trafficTotal, 1073741824);
    expect(repo.profiles.single.trafficUsed, 3145728);
    expect(repo.profiles.single.trafficExpireAt?.year, 2030);
  });

  test('rejects duplicate names and invalid input', () async {
    final repo = buildRepo();
    await repo.add(name: 'pm', url: baseUrl);
    expect(
      () => repo.add(name: 'pm', url: baseUrl),
      throwsA(isA<ProfileException>()),
    );
    expect(
      () => repo.add(name: 'bad/name', url: baseUrl),
      throwsA(isA<ProfileException>()),
    );
    expect(
      () => repo.add(name: 'x', url: 'ftp://example.com/sub'),
      throwsA(isA<ProfileException>()),
    );
  });

  test('rejects configs without nodes and keeps no file', () async {
    payload = 'mode: rule\nproxies: []\n';
    final repo = buildRepo();
    await expectLater(
      repo.add(name: 'empty', url: baseUrl),
      throwsA(isA<ProfileException>()),
    );
    expect(repo.profiles, isEmpty);
    expect(File(repo.profileFile('empty')).existsSync(), isFalse);
  });

  test('a failing update keeps the previous file intact', () async {
    final repo = buildRepo();
    await repo.add(name: 'pm', url: baseUrl);
    final before = File(repo.profileFile('pm')).readAsStringSync();

    statusCode = 500;
    await expectLater(
      repo.update(repo.profiles.single),
      throwsA(isA<DownloadException>()),
    );
    expect(File(repo.profileFile('pm')).readAsStringSync(), before);
  });

  test('update refreshes the timestamp and content', () async {
    final repo = buildRepo();
    await repo.add(name: 'pm', url: baseUrl);
    final firstStamp = repo.profiles.single.updatedAt!;
    payload = _validConfig.replaceFirst('mixed-port: 7890', 'mixed-port: 7895');
    await Future<void>.delayed(const Duration(milliseconds: 10));
    await repo.update(repo.profiles.single);
    expect(repo.cachedInfo('pm')?.mixedPort, 7895);
    expect(
      repo.profiles.single.updatedAt!.isAfter(firstStamp) ||
          repo.profiles.single.updatedAt!.isAtSameMomentAs(firstStamp),
      isTrue,
    );
  });

  test('activate copies the config and records the active profile', () async {
    final repo = buildRepo();
    await repo.add(name: 'pm', url: baseUrl);
    repo.activate(repo.profiles.single);

    expect(repo.activeName, 'pm');
    expect(File(repo.paths.mihomoConfigFile).existsSync(), isTrue);
    expect(
      File(repo.paths.mihomoConfigFile).readAsStringSync(),
      File(repo.profileFile('pm')).readAsStringSync(),
    );

    // Switching again keeps a backup of the previous config.
    await repo.add(name: 'alt', url: baseUrl);
    repo.activate(repo.byName('alt')!);
    expect(repo.activeName, 'alt');
    expect(File('${repo.paths.mihomoConfigFile}.bak').existsSync(), isTrue);
  });

  test('rename moves the file and follows the active pointer', () async {
    final repo = buildRepo();
    await repo.add(name: 'pm', url: baseUrl);
    repo.activate(repo.profiles.single);
    repo.rename(repo.profiles.single, '机场');

    expect(repo.byName('机场'), isNotNull);
    expect(repo.byName('pm'), isNull);
    expect(repo.activeName, '机场');
    expect(File(repo.profileFile('机场')).existsSync(), isTrue);
    expect(File(repo.profileFile('pm')).existsSync(), isFalse);
    expect(repo.cachedInfo('机场')?.nodeCount, 1);
  });

  test('updateMeta renames and re-points the subscription url', () async {
    final repo = buildRepo();
    await repo.add(name: 'pm', url: baseUrl);
    repo.activate(repo.profiles.single);

    final updated = repo.updateMeta(
      repo.profiles.single,
      name: '机场',
      url: 'https://example.com/other',
    );
    expect(updated.name, '机场');
    expect(updated.url, 'https://example.com/other');
    expect(repo.activeName, '机场');
    expect(File(repo.profileFile('机场')).existsSync(), isTrue);
    expect(File(repo.profileFile('pm')).existsSync(), isFalse);
    // The profile file itself is untouched by a metadata edit.
    expect(repo.cachedInfo('机场')?.nodeCount, 1);
  });

  test('updateMeta validates name and url', () async {
    final repo = buildRepo();
    await repo.add(name: 'pm', url: baseUrl);
    expect(
      () => repo.updateMeta(repo.profiles.single, name: 'a/b', url: baseUrl),
      throwsA(isA<ProfileException>()),
    );
    expect(
      () => repo.updateMeta(repo.profiles.single, name: 'pm', url: 'ftp://x'),
      throwsA(isA<ProfileException>()),
    );
    await repo.add(name: 'other', url: baseUrl);
    expect(
      () => repo.updateMeta(repo.profiles.first, name: 'other', url: baseUrl),
      throwsA(isA<ProfileException>()),
    );
  });

  test('delete removes the file and clears the active pointer', () async {
    final repo = buildRepo();
    await repo.add(name: 'pm', url: baseUrl);
    repo.activate(repo.profiles.single);
    repo.delete(repo.profiles.single);
    expect(repo.profiles, isEmpty);
    expect(repo.activeName, isNull);
    expect(File(repo.profileFile('pm')).existsSync(), isFalse);
  });

  test('data survives a reload from disk', () async {
    final repo = buildRepo();
    await repo.add(name: 'pm', url: baseUrl);
    repo.activate(repo.profiles.single);

    final reopened = buildRepo();
    expect(reopened.profiles.single.name, 'pm');
    expect(reopened.activeName, 'pm');
  });

  test('imports legacy clash_tui data', () async {
    final legacy = Directory('${temp.path}/legacy')
      ..createSync(recursive: true);
    Directory('${legacy.path}/config').createSync(recursive: true);
    File('${legacy.path}/data.json').writeAsStringSync(jsonEncode([
      {'name': 'old', 'url': 'https://example.com/old'},
    ]));
    File('${legacy.path}/config/old').writeAsStringSync(_validConfig);

    final repo = buildRepo();
    expect(repo.importLegacy(legacy.path), 1);
    expect(repo.byName('old')?.url, 'https://example.com/old');
    expect(repo.cachedInfo('old')?.nodeCount, 1);
    // Importing twice is a no-op.
    expect(repo.importLegacy(legacy.path), 0);
  });
}
