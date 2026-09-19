// test/models/mail_provider_rules_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:imap_mail/models/mail_provider_rules.dart';

void main() {
  group('emailDomain', () {
    test('extracts the lowercased domain', () {
      expect(emailDomain('Someone@Example.COM'), 'example.com');
    });

    test('returns null when there is no domain', () {
      expect(emailDomain('not-an-email'), isNull);
      expect(emailDomain('trailing@'), isNull);
      expect(emailDomain(''), isNull);
    });
  });

  group('detectBlockedProvider', () {
    test('flags Gmail domains', () {
      expect(detectBlockedProvider('me@gmail.com'), BlockedProvider.gmail);
      expect(detectBlockedProvider('me@googlemail.com'), BlockedProvider.gmail);
    });

    test('flags Outlook/Hotmail domains', () {
      for (final domain in ['outlook.com', 'hotmail.com', 'live.com', 'msn.com']) {
        expect(detectBlockedProvider('me@$domain'), BlockedProvider.outlookHotmail, reason: domain);
      }
    });

    test('returns null for anything else, including iCloud', () {
      expect(detectBlockedProvider('me@icloud.com'), isNull);
      expect(detectBlockedProvider('me@example.com'), isNull);
    });
  });

  group('isAppleIdDomain', () {
    test('recognizes icloud.com, me.com, and mac.com', () {
      expect(isAppleIdDomain('me@icloud.com'), isTrue);
      expect(isAppleIdDomain('me@me.com'), isTrue);
      expect(isAppleIdDomain('me@mac.com'), isTrue);
    });

    test('is false for anything else', () {
      expect(isAppleIdDomain('me@gmail.com'), isFalse);
      expect(isAppleIdDomain('me@example.com'), isFalse);
    });
  });
}
