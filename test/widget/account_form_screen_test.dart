import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imap_mail/models/enums.dart';
import 'package:imap_mail/models/mail_account.dart';
import 'package:imap_mail/providers/account_providers.dart';
import 'package:imap_mail/screens/account_form_screen.dart';
import 'package:imap_mail/services/discovered_mail_config.dart';

class _RecordingAccountsNotifier extends AccountsNotifier {
  _RecordingAccountsNotifier(this._accounts);

  final List<MailAccount> _accounts;
  bool addCalled = false;
  bool updateCalled = false;
  MailAccount? lastUpdated;
  String? lastUpdatedPassword;

  @override
  Future<List<MailAccount>> build() async => _accounts;

  @override
  Future<void> add(MailAccount account, String password) async {
    addCalled = true;
  }

  @override
  Future<void> updateAccount(MailAccount account, {String? newPassword}) async {
    updateCalled = true;
    lastUpdated = account;
    lastUpdatedPassword = newPassword;
  }
}

void main() {
  // The form's fields don't all fit within the default 800x600 test surface,
  // which would leave the Save button laid out but "offstage" (outside the
  // visible viewport) and therefore invisible to `find` (skipOffstage is true
  // by default). Widening the surface avoids relying on scrolling within the
  // test and keeps production layout untouched.
  Future<void> useTallSurface(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
  }

  testWidgets('Save button is disabled until required fields are filled', (tester) async {
    await useTallSurface(tester);
    // The email field is read-only for new accounts (Finding 2: it was
    // already collected and validated on Screen 1), so the email here
    // comes in via initialEmail rather than being typed into the field.
    await tester.pumpWidget(const ProviderScope(
      child: MaterialApp(home: AccountFormScreen(initialEmail: 'me@example.com')),
    ));
    await tester.tap(find.byKey(const Key('advancedSetupToggle')));
    await tester.pump();

    final saveButtonFinder = find.widgetWithText(ElevatedButton, 'Save');
    ElevatedButton saveButton() => tester.widget(saveButtonFinder);
    expect(saveButton().onPressed, isNull);

    await tester.enterText(find.byKey(const Key('displayNameField')), 'Work');
    await tester.enterText(find.byKey(const Key('imapHostField')), 'imap.example.com');
    await tester.enterText(find.byKey(const Key('imapPortField')), '993');
    await tester.enterText(find.byKey(const Key('smtpHostField')), 'smtp.example.com');
    await tester.enterText(find.byKey(const Key('smtpPortField')), '465');
    await tester.enterText(find.byKey(const Key('usernameField')), 'me@example.com');
    await tester.enterText(find.byKey(const Key('passwordField')), 'app-password');
    await tester.pump();

    expect(saveButton().onPressed, isNotNull);
  });

  testWidgets('password field has a show/hide visibility toggle', (tester) async {
    await useTallSurface(tester);
    await tester.pumpWidget(const ProviderScope(
      child: MaterialApp(home: AccountFormScreen(initialEmail: 'me@example.com')),
    ));

    final passwordFieldFinder = find.byKey(const Key('passwordField'));
    bool obscured() => tester.widget<TextField>(passwordFieldFinder).obscureText;

    expect(obscured(), isTrue);
    expect(find.byTooltip('Show password'), findsOneWidget);

    await tester.tap(find.byTooltip('Show password'));
    await tester.pump();

    expect(obscured(), isFalse);
    expect(find.byTooltip('Hide password'), findsOneWidget);

    await tester.tap(find.byTooltip('Hide password'));
    await tester.pump();

    expect(obscured(), isTrue);
    expect(find.byTooltip('Show password'), findsOneWidget);
  });

  testWidgets('shows a Test connection button', (tester) async {
    await useTallSurface(tester);
    await tester.pumpWidget(const ProviderScope(
      child: MaterialApp(home: AccountFormScreen()),
    ));
    expect(find.widgetWithText(OutlinedButton, 'Test connection'), findsOneWidget);
  });

  testWidgets('shows IMAP and SMTP security dropdowns defaulting to SSL/TLS', (tester) async {
    await useTallSurface(tester);
    await tester.pumpWidget(const ProviderScope(
      child: MaterialApp(home: AccountFormScreen()),
    ));
    await tester.tap(find.byKey(const Key('advancedSetupToggle')));
    await tester.pump();

    final imapDropdownFinder = find.byKey(const Key('imapSecurityDropdown'));
    final smtpDropdownFinder = find.byKey(const Key('smtpSecurityDropdown'));
    expect(imapDropdownFinder, findsOneWidget);
    expect(smtpDropdownFinder, findsOneWidget);

    DropdownButtonFormField<MailSecurity> imapDropdown() =>
        tester.widget(imapDropdownFinder);
    expect(imapDropdown().initialValue, MailSecurity.ssl);

    // Open the IMAP dropdown and select STARTTLS.
    await tester.tap(imapDropdownFinder);
    await tester.pumpAndSettle();
    await tester.tap(find.text('STARTTLS').last);
    await tester.pumpAndSettle();

    expect(imapDropdown().initialValue, MailSecurity.startTls);
    // SMTP dropdown is unaffected by the IMAP change.
    expect((tester.widget(smtpDropdownFinder) as DropdownButtonFormField<MailSecurity>)
        .initialValue, MailSecurity.ssl);
  });

  const existingAccount = MailAccount(
    id: 1,
    displayName: 'Work',
    email: 'me@example.com',
    imapHost: 'imap.example.com',
    imapPort: 993,
    imapSecurity: MailSecurity.ssl,
    smtpHost: 'smtp.example.com',
    smtpPort: 465,
    smtpSecurity: MailSecurity.ssl,
    username: 'me@example.com',
  );

  testWidgets('editing an account: Save is enabled with an empty password field', (tester) async {
    await useTallSurface(tester);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        accountsProvider.overrideWith(() => _RecordingAccountsNotifier([existingAccount])),
      ],
      child: const MaterialApp(home: AccountFormScreen(existing: existingAccount)),
    ));

    final saveButtonFinder = find.widgetWithText(ElevatedButton, 'Save');
    ElevatedButton saveButton() => tester.widget(saveButtonFinder);

    // All fields are pre-filled from `existing`; the password field is
    // deliberately left blank (existing accounts don't round-trip a stored
    // password into the form). Save must still be enabled.
    expect(find.byKey(const Key('passwordField')), findsOneWidget);
    expect(tester.widget<TextField>(find.byKey(const Key('passwordField'))).controller!.text, isEmpty);
    expect(saveButton().onPressed, isNotNull);
  });

  testWidgets('editing an account calls updateAccount (not add), with null password when left blank', (tester) async {
    await useTallSurface(tester);
    final notifier = _RecordingAccountsNotifier([existingAccount]);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        accountsProvider.overrideWith(() => notifier),
      ],
      child: const MaterialApp(home: AccountFormScreen(existing: existingAccount)),
    ));

    await tester.tap(find.widgetWithText(ElevatedButton, 'Save'));
    await tester.pump();
    await tester.pump();

    expect(notifier.updateCalled, isTrue);
    expect(notifier.addCalled, isFalse);
    expect(notifier.lastUpdated!.id, existingAccount.id);
    expect(notifier.lastUpdatedPassword, isNull);
  });

  testWidgets(
      'saving a new account when the form is the app root does not crash '
      '(onboarding: zero accounts, no previous route to pop to)', (tester) async {
    await useTallSurface(tester);
    final notifier = _RecordingAccountsNotifier([]);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        accountsProvider.overrideWith(() => notifier),
      ],
      // Regression coverage for AccountFormScreen being used directly as
      // MaterialApp.home with no previous route to pop back to. The email
      // field is read-only for new accounts (Finding 2), so it comes in
      // via initialEmail here rather than being typed into the field.
      child: const MaterialApp(home: AccountFormScreen(initialEmail: 'me@example.com')),
    ));
    await tester.tap(find.byKey(const Key('advancedSetupToggle')));
    await tester.pump();

    await tester.enterText(find.byKey(const Key('displayNameField')), 'Work');
    await tester.enterText(find.byKey(const Key('imapHostField')), 'imap.example.com');
    await tester.enterText(find.byKey(const Key('imapPortField')), '993');
    await tester.enterText(find.byKey(const Key('smtpHostField')), 'smtp.example.com');
    await tester.enterText(find.byKey(const Key('smtpPortField')), '465');
    await tester.enterText(find.byKey(const Key('usernameField')), 'me@example.com');
    await tester.enterText(find.byKey(const Key('passwordField')), 'app-password');
    await tester.pump();

    await tester.tap(find.widgetWithText(ElevatedButton, 'Save'));
    await tester.pump();
    await tester.pump();

    expect(notifier.addCalled, isTrue);
    expect(tester.takeException(), isNull);
    // The form (or whatever the accountsProvider watcher swaps in) must
    // still be showing a real screen, not a blank/empty Overlay.
    expect(find.byType(Scaffold), findsWidgets);
  });

  testWidgets('editing an account with a new password passes it through to updateAccount', (tester) async {
    await useTallSurface(tester);
    final notifier = _RecordingAccountsNotifier([existingAccount]);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        accountsProvider.overrideWith(() => notifier),
      ],
      child: const MaterialApp(home: AccountFormScreen(existing: existingAccount)),
    ));

    await tester.enterText(find.byKey(const Key('passwordField')), 'new-password');
    await tester.pump();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Save'));
    await tester.pump();
    await tester.pump();

    expect(notifier.updateCalled, isTrue);
    expect(notifier.lastUpdatedPassword, 'new-password');
  });

  testWidgets('new account: Advanced setup is always collapsed by default', (tester) async {
    await useTallSurface(tester);
    await tester.pumpWidget(const ProviderScope(
      child: MaterialApp(home: AccountFormScreen()),
    ));

    expect(find.byKey(const Key('imapHostField')), findsNothing);
    expect(find.byKey(const Key('usernameField')), findsNothing);
    expect(find.byKey(const Key('advancedSetupToggle')), findsOneWidget);
  });

  testWidgets('new account: an iCloud email shows the App-Specific Password label, hint, and link',
      (tester) async {
    await useTallSurface(tester);
    await tester.pumpWidget(const ProviderScope(
      child: MaterialApp(home: AccountFormScreen(
        initialEmail: 'me@icloud.com',
        discoveredConfig: DiscoveredMailConfig(
          imapHost: 'imap.mail.me.com',
          imapPort: 993,
          imapSecurity: MailSecurity.ssl,
          smtpHost: 'smtp.mail.me.com',
          smtpPort: 587,
          smtpSecurity: MailSecurity.startTls,
        ),
      )),
    ));

    expect(find.text('App-Specific Password'), findsOneWidget);
    expect(find.byKey(const Key('appSpecificPasswordHint')), findsOneWidget);
    expect(find.byKey(const Key('appSpecificPasswordLink')), findsOneWidget);
    expect(find.byKey(const Key('imapHostField')), findsNothing);
  });

  testWidgets('new account: a non-Apple email shows the plain Password label, no App-Specific hint',
      (tester) async {
    await useTallSurface(tester);
    await tester.pumpWidget(const ProviderScope(
      child: MaterialApp(home: AccountFormScreen(
        initialEmail: 'me@example.com',
        discoveredConfig: DiscoveredMailConfig(
          imapHost: 'imap.example.com',
          imapPort: 993,
          imapSecurity: MailSecurity.ssl,
          smtpHost: 'smtp.example.com',
          smtpPort: 465,
          smtpSecurity: MailSecurity.ssl,
        ),
      )),
    ));

    expect(find.text('Password'), findsOneWidget);
    expect(find.byKey(const Key('appSpecificPasswordHint')), findsNothing);
    expect(find.byKey(const Key('discoveryFailedCaption')), findsNothing);
  });

  testWidgets('new account: no discovered config shows the failure caption, still collapsed',
      (tester) async {
    await useTallSurface(tester);
    await tester.pumpWidget(const ProviderScope(
      child: MaterialApp(home: AccountFormScreen(initialEmail: 'me@example.com')),
    ));

    expect(find.byKey(const Key('discoveryFailedCaption')), findsOneWidget);
    expect(find.byKey(const Key('imapHostField')), findsNothing);
  });

  testWidgets('new account: expanding Advanced setup pre-fills a partial discovered config, blank for the rest',
      (tester) async {
    await useTallSurface(tester);
    await tester.pumpWidget(const ProviderScope(
      child: MaterialApp(home: AccountFormScreen(
        initialEmail: 'me@example.com',
        discoveredConfig: DiscoveredMailConfig(
          imapHost: 'imap.example.com',
          imapPort: 993,
          imapSecurity: MailSecurity.ssl,
        ),
      )),
    ));

    // A partial discovery result (IMAP resolved, SMTP not) still leaves the
    // form unsavable without expanding Advanced setup, so the caption must
    // appear here too, not just for a fully-null config.
    expect(find.byKey(const Key('discoveryFailedCaption')), findsOneWidget);

    await tester.tap(find.byKey(const Key('advancedSetupToggle')));
    await tester.pump();

    expect(tester.widget<TextField>(find.byKey(const Key('imapHostField'))).controller!.text,
        'imap.example.com');
    expect(tester.widget<TextField>(find.byKey(const Key('smtpHostField'))).controller!.text, isEmpty);
    expect(tester.widget<TextField>(find.byKey(const Key('usernameField'))).controller!.text,
        'me@example.com');
  });

  testWidgets('new account: saving with a fully discovered config works without expanding Advanced setup',
      (tester) async {
    await useTallSurface(tester);
    final notifier = _RecordingAccountsNotifier([]);
    await tester.pumpWidget(ProviderScope(
      overrides: [accountsProvider.overrideWith(() => notifier)],
      child: const MaterialApp(home: AccountFormScreen(
        initialEmail: 'me@example.com',
        discoveredConfig: DiscoveredMailConfig(
          imapHost: 'imap.example.com',
          imapPort: 993,
          imapSecurity: MailSecurity.ssl,
          smtpHost: 'smtp.example.com',
          smtpPort: 465,
          smtpSecurity: MailSecurity.ssl,
        ),
      )),
    ));

    await tester.enterText(find.byKey(const Key('passwordField')), 'app-password');
    await tester.pump();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Save'));
    await tester.pump();
    await tester.pump();

    expect(notifier.addCalled, isTrue);
  });

  testWidgets('new account: the email field is read-only (Screen 1 already collected and validated it)',
      (tester) async {
    await useTallSurface(tester);
    await tester.pumpWidget(const ProviderScope(
      child: MaterialApp(home: AccountFormScreen(initialEmail: 'me@example.com')),
    ));

    final emailField = tester.widget<TextField>(find.byKey(const Key('emailField')));
    expect(emailField.readOnly, isTrue);

    // Attempting to type into it must not change its text — readOnly
    // blocks keyboard input, unlike merely disabling the field visually.
    await tester.enterText(find.byKey(const Key('emailField')), 'me@gmail.com');
    await tester.pump();
    expect(emailField.controller!.text, 'me@example.com');
  });

  testWidgets('editing an existing account: the email field remains fully editable', (tester) async {
    await useTallSurface(tester);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        accountsProvider.overrideWith(() => _RecordingAccountsNotifier([existingAccount])),
      ],
      child: const MaterialApp(home: AccountFormScreen(existing: existingAccount)),
    ));

    final emailField = tester.widget<TextField>(find.byKey(const Key('emailField')));
    expect(emailField.readOnly, isFalse);

    await tester.enterText(find.byKey(const Key('emailField')), 'changed@example.com');
    await tester.pump();
    expect(emailField.controller!.text, 'changed@example.com');
  });

  testWidgets('editing an existing account shows the full form even with a recognized email domain',
      (tester) async {
    await useTallSurface(tester);
    const gmailAccount = MailAccount(
      id: 2,
      displayName: 'Personal',
      email: 'me@gmail.com',
      imapHost: 'imap.gmail.com',
      imapPort: 993,
      imapSecurity: MailSecurity.ssl,
      smtpHost: 'smtp.gmail.com',
      smtpPort: 465,
      smtpSecurity: MailSecurity.ssl,
      username: 'me@gmail.com',
    );
    await tester.pumpWidget(ProviderScope(
      overrides: [
        accountsProvider.overrideWith(() => _RecordingAccountsNotifier([gmailAccount])),
      ],
      child: const MaterialApp(home: AccountFormScreen(existing: gmailAccount)),
    ));

    expect(find.byKey(const Key('imapHostField')), findsOneWidget);
    expect(find.byKey(const Key('usernameField')), findsOneWidget);
    expect(find.byKey(const Key('advancedSetupToggle')), findsNothing);
  });
}
