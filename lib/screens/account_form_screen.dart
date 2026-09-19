// lib/screens/account_form_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/enums.dart';
import '../models/mail_account.dart';
import '../models/mail_provider_rules.dart';
import '../providers/account_providers.dart';
import '../providers/repository_providers.dart';
import '../services/discovered_mail_config.dart';

class AccountFormScreen extends ConsumerStatefulWidget {
  const AccountFormScreen({super.key, this.existing, this.initialEmail, this.discoveredConfig});

  final MailAccount? existing;

  /// Only meaningful when [existing] is null: the email already entered on
  /// [AccountEmailScreen] (Screen 1).
  final String? initialEmail;

  /// Only meaningful when [existing] is null: the result of
  /// [AccountDiscoveryService.discover] for [initialEmail], or null if
  /// nothing could be discovered.
  final DiscoveredMailConfig? discoveredConfig;

  @override
  ConsumerState<AccountFormScreen> createState() => _AccountFormScreenState();
}

class _AccountFormScreenState extends ConsumerState<AccountFormScreen> {
  late final TextEditingController _displayName;
  late final TextEditingController _email;
  late final TextEditingController _imapHost;
  late final TextEditingController _imapPort;
  late final TextEditingController _smtpHost;
  late final TextEditingController _smtpPort;
  late final TextEditingController _username;
  final _password = TextEditingController();
  MailSecurity _imapSecurity = MailSecurity.ssl;
  MailSecurity _smtpSecurity = MailSecurity.ssl;
  String? _testResult;
  bool _testing = false;
  bool _saving = false;
  bool _advancedExpanded = false;
  bool _obscurePassword = true;

  bool get _isNewAccount => widget.existing == null;
  bool get _showAdvancedFields => !_isNewAccount || _advancedExpanded;
  // True whenever the new-account form can't be saved without expanding
  // Advanced setup: either discovery found nothing at all, or it found a
  // partial result (e.g. SRV resolved IMAP but not SMTP) that still leaves
  // one of the two required hosts empty. `_isValid` requires both imapHost
  // and smtpHost non-empty, so both cases leave Save permanently disabled
  // until Advanced setup is expanded — the caption must fire for both, not
  // just the "discovered absolutely nothing" case.
  bool get _discoveryIncomplete =>
      _isNewAccount &&
      (widget.discoveredConfig?.imapHost == null || widget.discoveredConfig?.smtpHost == null);
  bool get _isAppleId => _isNewAccount && isAppleIdDomain(widget.initialEmail ?? '');

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    final discovered = widget.discoveredConfig;
    final initialEmail = widget.initialEmail ?? '';
    _displayName = TextEditingController(
      text: existing?.displayName ?? _defaultDisplayName(initialEmail),
    );
    _email = TextEditingController(text: existing?.email ?? initialEmail);
    _imapHost = TextEditingController(text: existing?.imapHost ?? discovered?.imapHost ?? '');
    _imapPort = TextEditingController(
      text: (existing?.imapPort ?? discovered?.imapPort ?? 993).toString(),
    );
    _smtpHost = TextEditingController(text: existing?.smtpHost ?? discovered?.smtpHost ?? '');
    _smtpPort = TextEditingController(
      text: (existing?.smtpPort ?? discovered?.smtpPort ?? 465).toString(),
    );
    _username = TextEditingController(text: existing?.username ?? initialEmail);
    _imapSecurity = existing?.imapSecurity ?? discovered?.imapSecurity ?? MailSecurity.ssl;
    _smtpSecurity = existing?.smtpSecurity ?? discovered?.smtpSecurity ?? MailSecurity.ssl;
    for (final controller in [
      _displayName, _email, _imapHost, _imapPort, _smtpHost, _smtpPort, _username, _password,
    ]) {
      controller.addListener(() => setState(() {}));
    }
  }

  static String _defaultDisplayName(String email) {
    final at = email.indexOf('@');
    return at > 0 ? email.substring(0, at) : email;
  }

  @override
  void dispose() {
    _displayName.dispose();
    _email.dispose();
    _imapHost.dispose();
    _imapPort.dispose();
    _smtpHost.dispose();
    _smtpPort.dispose();
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  bool get _isValid =>
      _displayName.text.trim().isNotEmpty &&
      _email.text.trim().contains('@') &&
      _imapHost.text.trim().isNotEmpty &&
      int.tryParse(_imapPort.text.trim()) != null &&
      _smtpHost.text.trim().isNotEmpty &&
      int.tryParse(_smtpPort.text.trim()) != null &&
      _username.text.trim().isNotEmpty &&
      (widget.existing != null || _password.text.isNotEmpty);

  MailAccount _buildAccount() {
    return MailAccount(
      id: widget.existing?.id,
      displayName: _displayName.text.trim(),
      email: _email.text.trim(),
      imapHost: _imapHost.text.trim(),
      imapPort: int.parse(_imapPort.text.trim()),
      imapSecurity: _imapSecurity,
      smtpHost: _smtpHost.text.trim(),
      smtpPort: int.parse(_smtpPort.text.trim()),
      smtpSecurity: _smtpSecurity,
      username: _username.text.trim(),
    );
  }

  static String _securityLabel(MailSecurity security) {
    switch (security) {
      case MailSecurity.ssl:
        return 'SSL/TLS';
      case MailSecurity.startTls:
        return 'STARTTLS';
      case MailSecurity.none:
        return 'None';
    }
  }

  Future<void> _testConnection() async {
    setState(() {
      _testing = true;
      _testResult = null;
    });
    try {
      final transport = ref.read(mailTransportProvider);
      await transport.testConnection(_buildAccount(), _password.text);
      setState(() => _testResult = 'Connection succeeded');
    } catch (e) {
      setState(() => _testResult = 'Connection failed: $e');
    } finally {
      setState(() => _testing = false);
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final notifier = ref.read(accountsProvider.notifier);
      if (widget.existing == null) {
        await notifier.add(_buildAccount(), _password.text);
      } else {
        await notifier.updateAccount(
          _buildAccount(),
          newPassword: _password.text.isEmpty ? null : _password.text,
        );
      }
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) setState(() => _testResult = 'Could not save: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _openAppSpecificPasswordPage() async {
    await launchUrl(
      Uri.parse('https://appleid.apple.com/account/manage'),
      mode: LaunchMode.externalApplication,
    );
  }

  Widget _buildPasswordField() {
    final passwordField = TextField(
      key: const Key('passwordField'),
      controller: _password,
      obscureText: _obscurePassword,
      decoration: InputDecoration(
        labelText: _isAppleId ? 'App-Specific Password' : 'Password',
        suffixIcon: IconButton(
          icon: Icon(_obscurePassword ? Icons.visibility : Icons.visibility_off),
          tooltip: _obscurePassword ? 'Show password' : 'Hide password',
          onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
        ),
      ),
    );
    if (!_isAppleId) return passwordField;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        passwordField,
        const Padding(
          padding: EdgeInsets.only(top: 4),
          child: Text(
            "Your regular Apple ID password won't work here.",
            key: Key('appSpecificPasswordHint'),
          ),
        ),
        TextButton(
          key: const Key('appSpecificPasswordLink'),
          onPressed: _openAppSpecificPasswordPage,
          child: const Text('Generate an app-specific password'),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.existing == null ? 'Add account' : 'Edit account')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(key: const Key('displayNameField'), controller: _displayName,
              decoration: const InputDecoration(labelText: 'Display name')),
          TextField(key: const Key('emailField'), controller: _email,
              // The email was already collected and validated (against the
              // blocked-provider list) on Screen 1; letting it change here
              // for a new account would silently desync `_isAppleId` and
              // the default username/display name (all derived once from
              // `widget.initialEmail` in initState) from what actually gets
              // saved, and could bypass the Screen 1 block entirely (e.g.
              // typing a normal address there, then switching to
              // me@gmail.com here). Editing an existing account keeps this
              // fully editable, as before.
              readOnly: _isNewAccount,
              decoration: const InputDecoration(labelText: 'Email')),
          const SizedBox(height: 16),
          if (_showAdvancedFields) ...[
            TextField(key: const Key('imapHostField'), controller: _imapHost,
                decoration: const InputDecoration(labelText: 'IMAP host')),
            TextField(key: const Key('imapPortField'), controller: _imapPort,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'IMAP port')),
            DropdownButtonFormField<MailSecurity>(
              key: const Key('imapSecurityDropdown'),
              initialValue: _imapSecurity,
              decoration: const InputDecoration(labelText: 'IMAP security'),
              items: MailSecurity.values
                  .map((s) => DropdownMenuItem(value: s, child: Text(_securityLabel(s))))
                  .toList(),
              onChanged: (value) => setState(() => _imapSecurity = value!),
            ),
            const SizedBox(height: 16),
            TextField(key: const Key('smtpHostField'), controller: _smtpHost,
                decoration: const InputDecoration(labelText: 'SMTP host')),
            TextField(key: const Key('smtpPortField'), controller: _smtpPort,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'SMTP port')),
            DropdownButtonFormField<MailSecurity>(
              key: const Key('smtpSecurityDropdown'),
              initialValue: _smtpSecurity,
              decoration: const InputDecoration(labelText: 'SMTP security'),
              items: MailSecurity.values
                  .map((s) => DropdownMenuItem(value: s, child: Text(_securityLabel(s))))
                  .toList(),
              onChanged: (value) => setState(() => _smtpSecurity = value!),
            ),
            const SizedBox(height: 16),
            TextField(key: const Key('usernameField'), controller: _username,
                decoration: const InputDecoration(labelText: 'Username')),
          ] else if (_discoveryIncomplete)
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text(
                "Some settings couldn't be detected automatically — tap "
                "Advanced setup to review them.",
                key: Key('discoveryFailedCaption'),
              ),
            ),
          if (_isNewAccount)
            TextButton(
              key: const Key('advancedSetupToggle'),
              onPressed: () => setState(() => _advancedExpanded = !_advancedExpanded),
              child: Text(_advancedExpanded ? 'Hide advanced setup' : 'Advanced setup'),
            ),
          _buildPasswordField(),
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: _testing ? null : _testConnection,
            child: Text(_testing ? 'Testing...' : 'Test connection'),
          ),
          if (_testResult != null) Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(_testResult!),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _isValid && !_saving ? _save : null,
            child: Text(_saving ? 'Saving...' : 'Save'),
          ),
        ],
      ),
    );
  }
}
