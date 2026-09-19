import 'package:flutter_test/flutter_test.dart';
import 'package:imap_mail/models/enums.dart';
import 'package:imap_mail/services/account_discovery_service.dart';
import 'package:imap_mail/services/discovered_mail_config.dart';
import 'package:imap_mail/services/ispdb_discovery.dart';
import 'package:imap_mail/services/srv_resolver.dart';

class _FakeSrvResolver implements SrvResolver {
  _FakeSrvResolver(this._answers);
  final Map<String, List<SrvTarget>> _answers;
  final List<String> queried = [];

  @override
  Future<List<SrvTarget>> lookup(String serviceName) async {
    queried.add(serviceName);
    return _answers[serviceName] ?? const [];
  }
}

class _FakeIspdbDiscovery implements IspdbDiscovery {
  _FakeIspdbDiscovery(this._result);
  final DiscoveredMailConfig? _result;
  bool called = false;

  @override
  Future<DiscoveredMailConfig?> discover(String email) async {
    called = true;
    return _result;
  }
}

void main() {
  test('iCloud domains use the hardcoded config and never touch DNS or ISPDB', () async {
    final srv = _FakeSrvResolver(const {});
    final ispdb = _FakeIspdbDiscovery(null);
    final service = DefaultAccountDiscoveryService(srvResolver: srv, ispdbDiscovery: ispdb);

    final result = await service.discover('me@icloud.com');

    expect(result, isNotNull);
    expect(result!.imapHost, 'imap.mail.me.com');
    expect(result.imapPort, 993);
    expect(result.imapSecurity, MailSecurity.ssl);
    expect(result.smtpHost, 'smtp.mail.me.com');
    expect(result.smtpPort, 587);
    expect(result.smtpSecurity, MailSecurity.startTls);
    expect(srv.queried, isEmpty);
    expect(ispdb.called, isFalse);
  });

  test('a full SRV match is used directly, without consulting ISPDB', () async {
    final srv = _FakeSrvResolver({
      '_imaps._tcp.example.com': const [
        SrvTarget(priority: 0, weight: 1, port: 993, target: 'mail.example.com'),
      ],
      '_submissions._tcp.example.com': const [
        SrvTarget(priority: 0, weight: 1, port: 465, target: 'mail.example.com'),
      ],
    });
    final ispdb = _FakeIspdbDiscovery(null);
    final service = DefaultAccountDiscoveryService(srvResolver: srv, ispdbDiscovery: ispdb);

    final result = await service.discover('me@example.com');

    expect(result, isNotNull);
    expect(result!.imapHost, 'mail.example.com');
    expect(result.imapPort, 993);
    expect(result.imapSecurity, MailSecurity.ssl);
    expect(result.smtpHost, 'mail.example.com');
    expect(result.smtpPort, 465);
    expect(result.smtpSecurity, MailSecurity.ssl);
    expect(ispdb.called, isFalse);
  });

  test('falls back to STARTTLS SRV records when the implicit-TLS ones are absent', () async {
    final srv = _FakeSrvResolver({
      '_imap._tcp.example.com': const [
        SrvTarget(priority: 0, weight: 1, port: 143, target: 'mail.example.com'),
      ],
      '_submission._tcp.example.com': const [
        SrvTarget(priority: 0, weight: 1, port: 587, target: 'mail.example.com'),
      ],
    });
    final service = DefaultAccountDiscoveryService(
      srvResolver: srv,
      ispdbDiscovery: _FakeIspdbDiscovery(null),
    );

    final result = await service.discover('me@example.com');

    expect(result!.imapPort, 143);
    expect(result.imapSecurity, MailSecurity.startTls);
    expect(result.smtpPort, 587);
    expect(result.smtpSecurity, MailSecurity.startTls);
  });

  test('a "." SRV target is treated as not offered, same as no record', () async {
    final srv = _FakeSrvResolver({
      '_imaps._tcp.example.com': const [
        SrvTarget(priority: 0, weight: 0, port: 0, target: '.'),
      ],
    });
    final ispdb = _FakeIspdbDiscovery(
      const DiscoveredMailConfig(imapHost: 'ispdb.example.com', imapPort: 993, imapSecurity: MailSecurity.ssl),
    );
    final service = DefaultAccountDiscoveryService(srvResolver: srv, ispdbDiscovery: ispdb);

    final result = await service.discover('me@example.com');

    expect(result!.imapHost, 'ispdb.example.com');
  });

  test('a partial SRV result is filled in from ISPDB for the missing half only', () async {
    final srv = _FakeSrvResolver({
      '_imaps._tcp.example.com': const [
        SrvTarget(priority: 0, weight: 1, port: 993, target: 'srv.example.com'),
      ],
    });
    final ispdb = _FakeIspdbDiscovery(const DiscoveredMailConfig(
      imapHost: 'ispdb-imap.example.com',
      imapPort: 993,
      imapSecurity: MailSecurity.ssl,
      smtpHost: 'ispdb-smtp.example.com',
      smtpPort: 587,
      smtpSecurity: MailSecurity.startTls,
    ));
    final service = DefaultAccountDiscoveryService(srvResolver: srv, ispdbDiscovery: ispdb);

    final result = await service.discover('me@example.com');

    // SRV's incoming result wins; ISPDB only fills the outgoing gap.
    expect(result!.imapHost, 'srv.example.com');
    expect(result.smtpHost, 'ispdb-smtp.example.com');
    expect(ispdb.called, isTrue);
  });

  test('returns null when neither SRV nor ISPDB find anything', () async {
    final service = DefaultAccountDiscoveryService(
      srvResolver: _FakeSrvResolver(const {}),
      ispdbDiscovery: _FakeIspdbDiscovery(null),
    );

    expect(await service.discover('me@example.com'), isNull);
  });
}
