import 'package:mihomo_tui/src/util/url.dart';
import 'package:test/test.dart';

void main() {
  test('keeps plain urls', () {
    final uri = normalizeHttpUri('https://sub.example.com/a?token=1%2Fb');
    expect(uri.toString(), 'https://sub.example.com/a?token=1%2Fb');
    expect(uri?.host, 'sub.example.com');
  });

  test('adds the scheme when missing', () {
    expect(normalizeHttpUri('sub.example.com/sub')?.toString(),
        'https://sub.example.com/sub');
  });

  test('converts internationalised hosts to punycode', () {
    expect(
        normalizeHttpUri('https://例子.中国/sub')?.host, 'xn--fsqu00a.xn--fiqs8s');
    expect(normalizeHttpUri('https://münchen.de/x')?.host, 'xn--mnchen-3ya.de');
  });

  test('strips paste wrappers and invisible characters', () {
    expect(normalizeHttpUri('  <https://sub.example.com/sub>  ')?.host,
        'sub.example.com');
    expect(normalizeHttpUri('https://sub.example.com\u200b/sub')?.host,
        'sub.example.com');
  });

  test('rejects unusable input', () {
    expect(normalizeHttpUri(''), isNull);
    expect(normalizeHttpUri('ftp://example.com/x'), isNull);
    expect(normalizeHttpUri('not a url'), isNull);
    expect(normalizeHttpUri('https://'), isNull);
  });

  test('keeps ipv4 and ipv6 literals', () {
    expect(normalizeHttpUri('http://127.0.0.1:8080/x')?.host, '127.0.0.1');
    expect(normalizeHttpUri('http://[::1]:8080/x')?.host, '::1');
    expect(normalizeHttpUri('http://[::1]:8080/x').toString(),
        'http://[::1]:8080/x');
  });
}
