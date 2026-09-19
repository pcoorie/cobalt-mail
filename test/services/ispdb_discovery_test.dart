import 'package:enough_mail/enough_mail.dart' as enough;
import 'package:flutter_test/flutter_test.dart';
import 'package:imap_mail/models/enums.dart';
import 'package:imap_mail/services/ispdb_discovery.dart';

// NOTE: `enough.ClientConfig`'s own `preferredIncomingImapServer` /
// `preferredOutgoingSmtpServer` setters delegate to `emailProviders.first`
// and are a silent no-op when `emailProviders` is null (the default from
// `ClientConfig()`). The brief's original helper assigned directly on a
// bare `ClientConfig()`, which doesn't work. This constructs the
// `ConfigEmailProvider` first and sets the preferred-server fields on it
// directly, matching the pattern the vendored library itself uses in
// `lib/src/private/util/discover_helper.dart` (`_buildClientConfig`).
enough.ClientConfig _configWith({enough.ServerConfig? incoming, enough.ServerConfig? outgoing}) {
  final provider = enough.ConfigEmailProvider()
    ..preferredIncomingImapServer = incoming
    ..preferredOutgoingSmtpServer = outgoing;
  return enough.ClientConfig(emailProviders: [provider]);
}

void main() {
  test('null input maps to null', () {
    expect(mapClientConfig(null), isNull);
  });

  test('a config with neither server maps to null', () {
    expect(mapClientConfig(_configWith()), isNull);
  });

  test('maps SSL and STARTTLS server configs to the matching MailSecurity', () {
    final config = _configWith(
      incoming: enough.ServerConfig(
        type: enough.ServerType.imap,
        hostname: 'imap.example.com',
        port: 993,
        socketType: enough.SocketType.ssl,
        authentication: enough.Authentication.plain,
        usernameType: enough.UsernameType.emailAddress,
      ),
      outgoing: enough.ServerConfig(
        type: enough.ServerType.smtp,
        hostname: 'smtp.example.com',
        port: 587,
        socketType: enough.SocketType.starttls,
        authentication: enough.Authentication.plain,
        usernameType: enough.UsernameType.emailAddress,
      ),
    );

    final result = mapClientConfig(config);

    expect(result, isNotNull);
    expect(result!.imapHost, 'imap.example.com');
    expect(result.imapPort, 993);
    expect(result.imapSecurity, MailSecurity.ssl);
    expect(result.smtpHost, 'smtp.example.com');
    expect(result.smtpPort, 587);
    expect(result.smtpSecurity, MailSecurity.startTls);
  });

  test('maps a partial config (incoming only) leaving outgoing null', () {
    final config = _configWith(
      incoming: enough.ServerConfig(
        type: enough.ServerType.imap,
        hostname: 'imap.example.com',
        port: 993,
        socketType: enough.SocketType.ssl,
        authentication: enough.Authentication.plain,
        usernameType: enough.UsernameType.emailAddress,
      ),
    );

    final result = mapClientConfig(config);

    expect(result, isNotNull);
    expect(result!.imapHost, 'imap.example.com');
    expect(result.smtpHost, isNull);
  });
}
