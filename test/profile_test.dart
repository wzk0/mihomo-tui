import 'package:mihomo_tui/src/model/profile.dart';
import 'package:test/test.dart';

void main() {
  group('validateProfileName', () {
    test('accepts normal names', () {
      expect(validateProfileName('pm'), isNull);
      expect(validateProfileName('我的机场 2026'), isNull);
      expect(validateProfileName('sub_1.2'), isNull);
    });

    test('rejects empty and padded names', () {
      expect(validateProfileName(''), isNotNull);
      expect(validateProfileName('   '), isNotNull);
      expect(validateProfileName(' pm'), isNotNull);
    });

    test('rejects path separators and control characters', () {
      expect(validateProfileName('a/b'), isNotNull);
      expect(validateProfileName(r'a\b'), isNotNull);
      expect(validateProfileName('a:b'), isNotNull);
      expect(validateProfileName('a\tb'), isNotNull);
    });

    test('rejects reserved windows names and trailing dots', () {
      expect(validateProfileName('CON'), isNotNull);
      expect(validateProfileName('lpt1'), isNotNull);
      expect(validateProfileName('name.'), isNotNull);
    });

    test('rejects overly long names', () {
      expect(validateProfileName('a' * 65), isNotNull);
      expect(validateProfileName('a' * 64), isNull);
    });
  });

  group('validateSubscriptionUrl', () {
    test('accepts http and https', () {
      expect(
          validateSubscriptionUrl('https://example.com/sub?token=1'), isNull);
      expect(validateSubscriptionUrl('http://127.0.0.1:8080/sub'), isNull);
    });

    test('rejects other schemes and garbage', () {
      expect(validateSubscriptionUrl(''), isNotNull);
      expect(validateSubscriptionUrl('ftp://example.com/sub'), isNotNull);
      expect(validateSubscriptionUrl('not a url'), isNotNull);
      expect(validateSubscriptionUrl('https://'), isNotNull);
    });
  });

  group('Profile json', () {
    test('round trips', () {
      final profile = Profile(
        name: 'pm',
        url: 'https://example.com/sub',
        updatedAt: DateTime.utc(2026, 1, 2, 3, 4, 5),
        size: 1234,
      );
      final restored = Profile.fromJson(profile.toJson());
      expect(restored, isNotNull);
      expect(restored!.name, 'pm');
      expect(restored.url, 'https://example.com/sub');
      expect(restored.updatedAt, profile.updatedAt);
      expect(restored.size, 1234);
    });

    test('tolerates missing optional fields and junk', () {
      final restored = Profile.fromJson({'name': 'a', 'url': 'u'});
      expect(restored!.updatedAt, isNull);
      expect(restored.size, isNull);
      expect(Profile.fromJson({'url': 'u'}), isNull);
      expect(Profile.fromJson('nope'), isNull);
    });
  });
}
