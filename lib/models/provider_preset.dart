import 'enums.dart';

/// A known IMAP/SMTP configuration for a common mail provider, keyed by
/// email domain so account setup can skip asking for it manually.
class ProviderPreset {
  const ProviderPreset({
    required this.name,
    required this.imapHost,
    required this.imapPort,
    required this.imapSecurity,
    required this.smtpHost,
    required this.smtpPort,
    required this.smtpSecurity,
  });

  final String name;
  final String imapHost;
  final int imapPort;
  final MailSecurity imapSecurity;
  final String smtpHost;
  final int smtpPort;
  final MailSecurity smtpSecurity;
}

const _gmail = ProviderPreset(
  name: 'Gmail',
  imapHost: 'imap.gmail.com',
  imapPort: 993,
  imapSecurity: MailSecurity.ssl,
  smtpHost: 'smtp.gmail.com',
  smtpPort: 465,
  smtpSecurity: MailSecurity.ssl,
);

const _outlook = ProviderPreset(
  name: 'Outlook',
  imapHost: 'outlook.office365.com',
  imapPort: 993,
  imapSecurity: MailSecurity.ssl,
  smtpHost: 'smtp.office365.com',
  smtpPort: 587,
  smtpSecurity: MailSecurity.startTls,
);

const _icloud = ProviderPreset(
  name: 'iCloud',
  imapHost: 'imap.mail.me.com',
  imapPort: 993,
  imapSecurity: MailSecurity.ssl,
  smtpHost: 'smtp.mail.me.com',
  smtpPort: 587,
  smtpSecurity: MailSecurity.startTls,
);

const _fastmail = ProviderPreset(
  name: 'Fastmail',
  imapHost: 'imap.fastmail.com',
  imapPort: 993,
  imapSecurity: MailSecurity.ssl,
  smtpHost: 'smtp.fastmail.com',
  smtpPort: 465,
  smtpSecurity: MailSecurity.ssl,
);

const _presetsByDomain = <String, ProviderPreset>{
  'gmail.com': _gmail,
  'googlemail.com': _gmail,
  'outlook.com': _outlook,
  'hotmail.com': _outlook,
  'live.com': _outlook,
  'msn.com': _outlook,
  'icloud.com': _icloud,
  'me.com': _icloud,
  'mac.com': _icloud,
  'fastmail.com': _fastmail,
  'fastmail.fm': _fastmail,
};

/// Looks up the known [ProviderPreset] for [email]'s domain, or `null` if
/// the domain isn't one of the common providers this app recognizes.
ProviderPreset? lookupProviderPreset(String email) {
  final at = email.lastIndexOf('@');
  if (at == -1 || at == email.length - 1) return null;
  final domain = email.substring(at + 1).trim().toLowerCase();
  return _presetsByDomain[domain];
}
