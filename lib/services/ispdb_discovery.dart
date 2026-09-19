import 'package:enough_mail/enough_mail.dart' as enough;
import '../models/enums.dart';
import 'discovered_mail_config.dart';

/// Falls back to `enough_mail`'s existing Mozilla-ISPDB / Thunderbird-style
/// autoconfig / MX-based discovery for whatever RFC 6186 SRV lookups
/// (`SrvResolver`) didn't resolve.
abstract class IspdbDiscovery {
  Future<DiscoveredMailConfig?> discover(String email);
}

/// Maps an `enough_mail` [enough.ClientConfig] to our own
/// [DiscoveredMailConfig] shape. Pure and side-effect free so it's directly
/// testable without any network access.
DiscoveredMailConfig? mapClientConfig(enough.ClientConfig? config) {
  if (config == null) return null;
  final incoming = config.preferredIncomingImapServer;
  final outgoing = config.preferredOutgoingSmtpServer;
  if (incoming == null && outgoing == null) return null;
  return DiscoveredMailConfig(
    imapHost: incoming?.hostname,
    imapPort: incoming?.port,
    imapSecurity: incoming == null ? null : _toMailSecurity(incoming.socketType),
    smtpHost: outgoing?.hostname,
    smtpPort: outgoing?.port,
    smtpSecurity: outgoing == null ? null : _toMailSecurity(outgoing.socketType),
  );
}

MailSecurity _toMailSecurity(enough.SocketType socketType) {
  switch (socketType) {
    case enough.SocketType.ssl:
      return MailSecurity.ssl;
    case enough.SocketType.starttls:
      return MailSecurity.startTls;
    case enough.SocketType.plain:
    case enough.SocketType.plainNoStartTls:
    case enough.SocketType.unknown:
      return MailSecurity.none;
  }
}

class EnoughMailIspdbDiscovery implements IspdbDiscovery {
  @override
  Future<DiscoveredMailConfig?> discover(String email) async {
    final config = await enough.Discover.discover(email);
    return mapClientConfig(config);
  }
}
