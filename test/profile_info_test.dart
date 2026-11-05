import 'package:mihomo_tui/src/model/profile_info.dart';
import 'package:test/test.dart';

const _sample = '''
mixed-port: 7890
socks-port: 7891
port: 7892
allow-lan: true
ipv6: true
mode: global
log-level: debug
external-controller: 0.0.0.0:9090
secret: s3cret
external-ui: ui
tun:
  enable: true
proxies:
  - {name: a, type: ss, server: 1.1.1.1, port: 1, cipher: aes-128-gcm, password: x}
  - {name: b, type: ss, server: 1.1.1.2, port: 1, cipher: aes-128-gcm, password: x}
proxy-groups:
  - {name: g, type: select, proxies: [a, b]}
rules:
  - MATCH,g
proxy-providers:
  p1: {type: http, url: "https://example.com/p"}
''';

void main() {
  test('parses a typical config', () {
    final info = ProfileInfo.parse(_sample);
    expect(info.mixedPort, 7890);
    expect(info.socksPort, 7891);
    expect(info.port, 7892);
    expect(info.mode, 'global');
    expect(info.logLevel, 'debug');
    expect(info.allowLan, isTrue);
    expect(info.ipv6, isTrue);
    expect(info.tunEnabled, isTrue);
    expect(info.nodeCount, 2);
    expect(info.groupCount, 1);
    expect(info.ruleCount, 1);
    expect(info.providerCount, 1);
    expect(info.secret, 's3cret');
    expect(info.externalUi, 'ui');
  });

  test('normalises the controller address', () {
    expect(ProfileInfo.parse(_sample).controllerAddress, '127.0.0.1:9090');
    expect(
      ProfileInfo.parse('external-controller: :9090').controllerAddress,
      '127.0.0.1:9090',
    );
    expect(
      ProfileInfo.parse('external-controller: 192.168.1.5:9090')
          .controllerAddress,
      '192.168.1.5:9090',
    );
    expect(
      ProfileInfo.parse('external-controller: "http://127.0.0.1:9090"')
          .controllerAddress,
      '127.0.0.1:9090',
    );
    expect(ProfileInfo.parse('mode: rule').controllerAddress, isNull);
  });

  test('builds an api base and panel url', () {
    final selfHosted = ProfileInfo.parse(_sample);
    expect(selfHosted.apiBase, 'http://127.0.0.1:9090');
    // external-ui is served by mihomo itself.
    expect(selfHosted.panelUrl, 'http://127.0.0.1:9090/ui/');

    final hosted = ProfileInfo.parse('''
external-controller: 127.0.0.1:9090
secret: s3cret
''');
    expect(hosted.panelUrl, contains('port=9090'));
    expect(hosted.panelUrl, contains('secret=s3cret'));
  });

  test('preferred proxy port falls back through mixed/http/socks', () {
    expect(ProfileInfo.parse('mixed-port: 1').preferredProxyPort, 1);
    expect(ProfileInfo.parse('port: 2').preferredProxyPort, 2);
    expect(ProfileInfo.parse('socks-port: 3').preferredProxyPort, 3);
    expect(ProfileInfo.parse('mode: rule').preferredProxyPort, isNull);
  });

  test('port summary lists configured ports', () {
    final summary = ProfileInfo.parse(_sample).portSummary;
    expect(summary, contains('mixed 7890'));
    expect(summary, contains('http 7892'));
    expect(summary, contains('socks 7891'));
  });

  test('missing keys get safe defaults', () {
    final info = ProfileInfo.parse('mode: rule');
    expect(info.nodeCount, 0);
    expect(info.mode, 'rule');
    expect(info.allowLan, isFalse);
    expect(info.ipv6, isFalse);
    expect(info.tunEnabled, isFalse);
    expect(info.externalController, isNull);
    expect(info.logLevel, isNull);
  });

  test('invalid yaml throws FormatException', () {
    expect(
      () => ProfileInfo.parse('proxies: [a, b'),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => ProfileInfo.parse('- just\n- a list'),
      throwsA(isA<FormatException>()),
    );
  });
}
