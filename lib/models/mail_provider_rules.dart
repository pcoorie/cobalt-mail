// lib/models/mail_provider_rules.dart

/// A common consumer mail provider this app cannot authenticate against at
/// all (no password of any kind works — see the design spec §1).
enum BlockedProvider { gmail, outlookHotmail }

const _gmailDomains = {'gmail.com', 'googlemail.com'};
const _outlookHotmailDomains = {'outlook.com', 'hotmail.com', 'live.com', 'msn.com'};
const _appleIdDomains = {'icloud.com', 'me.com', 'mac.com'};

/// Extracts and lowercases the domain from [email], or `null` if there
/// isn't a well-formed one (no `@`, or nothing after it).
String? emailDomain(String email) {
  final at = email.lastIndexOf('@');
  if (at == -1 || at == email.length - 1) return null;
  return email.substring(at + 1).trim().toLowerCase();
}

/// Returns which [BlockedProvider] `email`'s domain matches, or `null` if
/// it isn't one of the known dead ends.
BlockedProvider? detectBlockedProvider(String email) {
  final domain = emailDomain(email);
  if (domain == null) return null;
  if (_gmailDomains.contains(domain)) return BlockedProvider.gmail;
  if (_outlookHotmailDomains.contains(domain)) return BlockedProvider.outlookHotmail;
  return null;
}

/// Whether `email`'s domain is one of Apple's iCloud Mail domains.
bool isAppleIdDomain(String email) {
  final domain = emailDomain(email);
  return domain != null && _appleIdDomains.contains(domain);
}
