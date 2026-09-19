import 'package:flutter_test/flutter_test.dart';
import 'package:imap_mail/models/enums.dart';
import 'package:imap_mail/models/provider_preset.dart';

void main() {
  test('recognizes Gmail addresses', () {
    final preset = lookupProviderPreset('someone@gmail.com');

    expect(preset, isNotNull);
    expect(preset!.name, 'Gmail');
    expect(preset.imapHost, 'imap.gmail.com');
    expect(preset.imapPort, 993);
    expect(preset.imapSecurity, MailSecurity.ssl);
    expect(preset.smtpHost, 'smtp.gmail.com');
    expect(preset.smtpPort, 465);
    expect(preset.smtpSecurity, MailSecurity.ssl);
  });

  test('recognizes Outlook addresses across its consumer domains', () {
    for (final domain in ['outlook.com', 'hotmail.com', 'live.com', 'msn.com']) {
      final preset = lookupProviderPreset('someone@$domain');
      expect(preset, isNotNull, reason: domain);
      expect(preset!.name, 'Outlook');
      expect(preset.imapHost, 'outlook.office365.com');
      expect(preset.smtpSecurity, MailSecurity.startTls);
    }
  });

  test('recognizes iCloud addresses across its domains', () {
    for (final domain in ['icloud.com', 'me.com', 'mac.com']) {
      final preset = lookupProviderPreset('someone@$domain');
      expect(preset, isNotNull, reason: domain);
      expect(preset!.name, 'iCloud');
      expect(preset.imapHost, 'imap.mail.me.com');
    }
  });

  test('recognizes Fastmail addresses', () {
    for (final domain in ['fastmail.com', 'fastmail.fm']) {
      final preset = lookupProviderPreset('someone@$domain');
      expect(preset, isNotNull, reason: domain);
      expect(preset!.name, 'Fastmail');
      expect(preset.imapHost, 'imap.fastmail.com');
    }
  });

  test('matching is case-insensitive on the domain', () {
    final preset = lookupProviderPreset('Someone@GMAIL.COM');
    expect(preset, isNotNull);
    expect(preset!.name, 'Gmail');
  });

  test('returns null for a domain with no known preset', () {
    expect(lookupProviderPreset('someone@example.com'), isNull);
  });

  test('returns null for malformed input without a domain', () {
    expect(lookupProviderPreset('not-an-email'), isNull);
    expect(lookupProviderPreset('trailing@'), isNull);
    expect(lookupProviderPreset(''), isNull);
  });
}
