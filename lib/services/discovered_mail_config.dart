import '../models/enums.dart';

/// The result of automatic mail-server discovery for an email address.
/// Each half (incoming/outgoing) is independently nullable because RFC 6186
/// SRV records and ISPDB/autoconfig data can resolve one without the other.
class DiscoveredMailConfig {
  const DiscoveredMailConfig({
    this.imapHost,
    this.imapPort,
    this.imapSecurity,
    this.smtpHost,
    this.smtpPort,
    this.smtpSecurity,
  });

  final String? imapHost;
  final int? imapPort;
  final MailSecurity? imapSecurity;
  final String? smtpHost;
  final int? smtpPort;
  final MailSecurity? smtpSecurity;
}
