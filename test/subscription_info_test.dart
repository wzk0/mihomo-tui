import 'package:mihomo_tui/src/service/downloader.dart';
import 'package:test/test.dart';

void main() {
  test('parses a full header', () {
    final info = SubscriptionInfo.parse(
      'upload=1024; download=2048; total=1048576; expire=1893456000',
    )!;
    expect(info.upload, 1024);
    expect(info.download, 2048);
    expect(info.used, 3072);
    expect(info.total, 1048576);
    expect(info.remaining, 1048576 - 3072);
    expect(info.fraction, closeTo(3072 / 1048576, 1e-9));
    expect(info.expireAt?.year, 2030);
  });

  test('handles missing total / expire', () {
    final info = SubscriptionInfo.parse('upload=1; download=2')!;
    expect(info.total, isNull);
    expect(info.remaining, isNull);
    expect(info.fraction, isNull);
    expect(info.hasAny, isTrue);
  });

  test('clamps when usage exceeds the quota', () {
    final info = SubscriptionInfo.parse(
      'upload=200; download=200; total=100',
    )!;
    expect(info.remaining, 0);
    expect(info.fraction, 1.0);
  });

  test('returns null for empty / unrelated headers', () {
    expect(SubscriptionInfo.parse(null), isNull);
    expect(SubscriptionInfo.parse(''), isNull);
    expect(SubscriptionInfo.parse('foo=1'), isNull);
  });
}
