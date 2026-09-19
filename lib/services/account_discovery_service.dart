import '../models/enums.dart';
import '../models/mail_provider_rules.dart';
import 'discovered_mail_config.dart';
import 'ispdb_discovery.dart';
import 'srv_resolver.dart';

abstract class AccountDiscoveryService {
  Future<DiscoveredMailConfig?> discover(String email);
}

class _ResolvedServer {
  const _ResolvedServer(this.host, this.port, this.security);
  final String host;
  final int port;
  final MailSecurity security;
}

/// Implements the design spec's discovery algorithm: iCloud is hardcoded
/// (Apple publishes no RFC 6186 records for it); everything else tries
/// RFC 6186 DNS SRV first, then falls back to ISPDB/autoconfig for
/// whichever half (incoming/outgoing) SRV didn't resolve.
class DefaultAccountDiscoveryService implements AccountDiscoveryService {
  DefaultAccountDiscoveryService({SrvResolver? srvResolver, IspdbDiscovery? ispdbDiscovery})
      : _srvResolver = srvResolver ?? DnsSrvResolver(),
        _ispdbDiscovery = ispdbDiscovery ?? EnoughMailIspdbDiscovery();

  final SrvResolver _srvResolver;
  final IspdbDiscovery _ispdbDiscovery;

  @override
  Future<DiscoveredMailConfig?> discover(String email) async {
    if (isAppleIdDomain(email)) {
      return const DiscoveredMailConfig(
        imapHost: 'imap.mail.me.com',
        imapPort: 993,
        imapSecurity: MailSecurity.ssl,
        smtpHost: 'smtp.mail.me.com',
        smtpPort: 587,
        smtpSecurity: MailSecurity.startTls,
      );
    }

    final domain = emailDomain(email);
    if (domain == null) return null;

    var incoming = await _resolveIncoming(domain);
    var outgoing = await _resolveOutgoing(domain);

    if (incoming == null || outgoing == null) {
      final fallback = await _ispdbDiscovery.discover(email);
      incoming ??= _asResolvedIncoming(fallback);
      outgoing ??= _asResolvedOutgoing(fallback);
    }

    if (incoming == null && outgoing == null) return null;

    return DiscoveredMailConfig(
      imapHost: incoming?.host,
      imapPort: incoming?.port,
      imapSecurity: incoming?.security,
      smtpHost: outgoing?.host,
      smtpPort: outgoing?.port,
      smtpSecurity: outgoing?.security,
    );
  }

  _ResolvedServer? _asResolvedIncoming(DiscoveredMailConfig? config) {
    final host = config?.imapHost;
    if (host == null) return null;
    return _ResolvedServer(host, config!.imapPort!, config.imapSecurity!);
  }

  _ResolvedServer? _asResolvedOutgoing(DiscoveredMailConfig? config) {
    final host = config?.smtpHost;
    if (host == null) return null;
    return _ResolvedServer(host, config!.smtpPort!, config.smtpSecurity!);
  }

  Future<_ResolvedServer?> _resolveIncoming(String domain) async {
    final implicit = pickBestTarget(await _srvResolver.lookup('_imaps._tcp.$domain'));
    if (implicit != null) return _ResolvedServer(implicit.target, implicit.port, MailSecurity.ssl);
    final startTls = pickBestTarget(await _srvResolver.lookup('_imap._tcp.$domain'));
    if (startTls != null) return _ResolvedServer(startTls.target, startTls.port, MailSecurity.startTls);
    return null;
  }

  Future<_ResolvedServer?> _resolveOutgoing(String domain) async {
    final implicit = pickBestTarget(await _srvResolver.lookup('_submissions._tcp.$domain'));
    if (implicit != null) return _ResolvedServer(implicit.target, implicit.port, MailSecurity.ssl);
    final startTls = pickBestTarget(await _srvResolver.lookup('_submission._tcp.$domain'));
    if (startTls != null) return _ResolvedServer(startTls.target, startTls.port, MailSecurity.startTls);
    return null;
  }
}
