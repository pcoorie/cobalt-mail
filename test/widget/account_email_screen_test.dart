// test/widget/account_email_screen_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imap_mail/providers/repository_providers.dart';
import 'package:imap_mail/screens/account_email_screen.dart';
import 'package:imap_mail/screens/account_form_screen.dart';
import 'package:imap_mail/services/account_discovery_service.dart';
import 'package:imap_mail/services/discovered_mail_config.dart';
import 'package:imap_mail/models/enums.dart';

class _FakeAccountDiscoveryService implements AccountDiscoveryService {
  _FakeAccountDiscoveryService(this._result);
  final DiscoveredMailConfig? _result;
  String? lastEmail;

  @override
  Future<DiscoveredMailConfig?> discover(String email) async {
    lastEmail = email;
    return _result;
  }
}

void main() {
  testWidgets('Next is disabled until the email looks valid', (tester) async {
    await tester.pumpWidget(const ProviderScope(
      child: MaterialApp(home: AccountEmailScreen()),
    ));

    final nextFinder = find.byKey(const Key('nextButton'));
    expect(tester.widget<ElevatedButton>(nextFinder).onPressed, isNull);

    await tester.enterText(find.byKey(const Key('emailField')), 'me@example.com');
    await tester.pump();

    expect(tester.widget<ElevatedButton>(nextFinder).onPressed, isNotNull);
  });

  testWidgets('a gmail.com address blocks with an explanation and never navigates', (tester) async {
    await tester.pumpWidget(const ProviderScope(
      child: MaterialApp(home: AccountEmailScreen()),
    ));

    await tester.enterText(find.byKey(const Key('emailField')), 'me@gmail.com');
    await tester.pump();
    await tester.tap(find.byKey(const Key('nextButton')));
    await tester.pump();

    expect(find.byKey(const Key('blockedProviderMessage')), findsOneWidget);
    expect(find.byType(AccountFormScreen), findsNothing);
  });

  testWidgets('an outlook.com address blocks with an explanation', (tester) async {
    await tester.pumpWidget(const ProviderScope(
      child: MaterialApp(home: AccountEmailScreen()),
    ));

    await tester.enterText(find.byKey(const Key('emailField')), 'me@outlook.com');
    await tester.pump();
    await tester.tap(find.byKey(const Key('nextButton')));
    await tester.pump();

    expect(find.byKey(const Key('blockedProviderMessage')), findsOneWidget);
  });

  testWidgets('a non-blocked address runs discovery then navigates to AccountFormScreen', (tester) async {
    const config = DiscoveredMailConfig(
      imapHost: 'imap.example.com',
      imapPort: 993,
      imapSecurity: MailSecurity.ssl,
      smtpHost: 'smtp.example.com',
      smtpPort: 465,
      smtpSecurity: MailSecurity.ssl,
    );
    final fakeService = _FakeAccountDiscoveryService(config);
    await tester.pumpWidget(ProviderScope(
      overrides: [accountDiscoveryServiceProvider.overrideWithValue(fakeService)],
      child: const MaterialApp(home: AccountEmailScreen()),
    ));

    await tester.enterText(find.byKey(const Key('emailField')), 'me@example.com');
    await tester.pump();
    await tester.tap(find.byKey(const Key('nextButton')));
    await tester.pumpAndSettle();

    expect(fakeService.lastEmail, 'me@example.com');
    expect(find.byType(AccountFormScreen), findsOneWidget);
  });
}
