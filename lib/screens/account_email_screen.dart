// lib/screens/account_email_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/mail_provider_rules.dart';
import '../providers/repository_providers.dart';
import '../services/discovered_mail_config.dart';
import 'account_form_screen.dart';

/// Screen 1 of new-account setup: a single email field. Blocks known dead
/// ends (Gmail, Outlook/Hotmail) outright; otherwise runs discovery and
/// hands the result to [AccountFormScreen] (Screen 2).
class AccountEmailScreen extends ConsumerStatefulWidget {
  const AccountEmailScreen({super.key});

  @override
  ConsumerState<AccountEmailScreen> createState() => _AccountEmailScreenState();
}

class _AccountEmailScreenState extends ConsumerState<AccountEmailScreen> {
  final _email = TextEditingController();
  bool _checking = false;
  BlockedProvider? _blockedProvider;

  @override
  void initState() {
    super.initState();
    _email.addListener(() {
      // Rebuild on every keystroke so the Next button's enabled state
      // (computed from `_looksLikeEmail` in `build()`) stays in sync with
      // the field's text; also clears a stale blocked-provider message.
      setState(() {
        _blockedProvider = null;
      });
    });
  }

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  bool get _looksLikeEmail {
    final value = _email.text.trim();
    final at = value.indexOf('@');
    return at > 0 && at < value.length - 1;
  }

  Future<void> _next() async {
    final email = _email.text.trim();
    final blocked = detectBlockedProvider(email);
    if (blocked != null) {
      setState(() => _blockedProvider = blocked);
      return;
    }
    setState(() => _checking = true);
    // Defense in depth: DefaultAccountDiscoveryService already degrades
    // network failures to a null result internally, but if something above
    // that layer still throws, this screen must proceed exactly as it
    // would for a clean null result rather than leaving `_checking` true
    // forever (stuck spinner, Next never re-enabled, no recovery for the
    // user).
    DiscoveredMailConfig? config;
    try {
      config = await ref.read(accountDiscoveryServiceProvider).discover(email);
    } catch (_) {
      config = null;
    }
    if (!mounted) return;
    setState(() => _checking = false);
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => AccountFormScreen(initialEmail: email, discoveredConfig: config),
    ));
  }

  static String _blockedMessage(BlockedProvider provider) {
    switch (provider) {
      case BlockedProvider.gmail:
        return "Gmail isn't supported. Google removed plain sign-in for "
            "apps like this in 2026, and this app doesn't support Google's "
            "newer sign-in method yet. Try a different email address.";
      case BlockedProvider.outlookHotmail:
        return "Outlook and Hotmail aren't supported. Microsoft has moved "
            "these accounts to a sign-in method this app doesn't support "
            "yet. Try a different email address.";
    }
  }

  @override
  Widget build(BuildContext context) {
    final blocked = _blockedProvider;
    return Scaffold(
      appBar: AppBar(title: const Text('Add account')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              key: const Key('emailField'),
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'Email'),
            ),
            if (blocked != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_blockedMessage(blocked), key: const Key('blockedProviderMessage')),
              ),
            const SizedBox(height: 16),
            if (_checking)
              const Padding(
                padding: EdgeInsets.only(bottom: 16),
                child: Text('Looking up mail server settings…', key: Key('discoveryLoadingLabel')),
              ),
            ElevatedButton(
              key: const Key('nextButton'),
              onPressed: (_looksLikeEmail && !_checking) ? _next : null,
              child: const Text('Next'),
            ),
          ],
        ),
      ),
    );
  }
}
