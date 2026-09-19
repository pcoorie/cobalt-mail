# Account Onboarding Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the single-screen provider-preset account setup (commit `48f0dc8`) with a two-screen flow: email-only Screen 1 (blocks Gmail/Outlook/Hotmail outright, runs RFC 6186 DNS SRV + ISPDB discovery for everything else) feeding a Screen 2 password step that always keeps IMAP/SMTP details collapsed and calls out iCloud's app-specific-password requirement.

**Architecture:** A new `AccountDiscoveryService` interface (real impl backed by DNS SRV lookups via `basic_utils`, falling back to `enough_mail`'s existing ISPDB/autoconfig discovery) sits behind a Riverpod provider. A new `AccountEmailScreen` (Screen 1) calls it and hands the result to a reworked `AccountFormScreen` (Screen 2), which drops its old per-keystroke preset-detection logic in favor of taking the discovery result as constructor input.

**Tech Stack:** Flutter, Riverpod, `enough_mail` (vendored, `third_party/enough_mail`), `basic_utils` (DNS-over-HTTPS SRV/MX lookups), `url_launcher`.

**Spec:** `docs/superpowers/specs/2026-09-19-account-onboarding-redesign-design.md`

## Global Constraints

- SRV service names, in order, per RFC 6186: incoming `_imaps._tcp.<domain>` (SSL) → `_imap._tcp.<domain>` (STARTTLS); outgoing `_submissions._tcp.<domain>` (SSL, port 465) → `_submission._tcp.<domain>` (STARTTLS, port 587).
- A returned SRV target of exactly `.` means "explicitly not offered" (RFC 6186 §5) — treat identically to "no record."
- iCloud domains: `icloud.com`, `me.com`, `mac.com` — hardcoded, no DNS lookup.
- Blocked domains: Gmail = `gmail.com`, `googlemail.com`; Outlook/Hotmail = `outlook.com`, `hotmail.com`, `live.com`, `msn.com`.
- Advanced setup (IMAP/SMTP/security/username fields) is **always collapsed by default** for new accounts, regardless of discovery outcome. Editing an existing account is **never** affected by any of this — full form, always expanded, exactly as today.
- No OAuth2, anywhere, in this plan.
- Every new async dependency (`AccountDiscoveryService`, `SrvResolver`, `IspdbDiscovery`) must be behind an interface with a fake usable in tests — no test may hit real DNS or HTTP.

---

## Task 1: Add direct dependencies

**Files:**
- Modify: `pubspec.yaml`

**Interfaces:** None (no code yet).

- [ ] **Step 1: Add `basic_utils` and `url_launcher` as direct dependencies**

In `pubspec.yaml`, under `dependencies:`, add (matching the versions already resolved in `pubspec.lock` via transitive resolution, so `pub get` won't need to bump anything else):

```yaml
  basic_utils: ^5.8.2
  url_launcher: ^6.3.2
```

Add a one-line comment above them matching the existing convention for `just_audio` in this file:

```yaml
  # Already resolved transitively (enough_mail's DNS lookups) — declared
  # directly now that AccountDiscoveryService also uses it for SRV lookups.
  basic_utils: ^5.8.2
  url_launcher: ^6.3.2
```

- [ ] **Step 2: Run `flutter pub get` and confirm no version changes**

Run: `flutter pub get`
Expected: succeeds; `git diff pubspec.lock` shows no changes other than `basic_utils` and `url_launcher` gaining a `direct main` dependency marker (no version bumps, since both were already resolved at these versions transitively).

- [ ] **Step 3: Commit**

```bash
git add pubspec.yaml pubspec.lock
git commit -m "chore: declare basic_utils and url_launcher as direct dependencies"
```

---

## Task 2: `mail_provider_rules` — blocked-provider and iCloud domain detection

**Files:**
- Create: `lib/models/mail_provider_rules.dart`
- Test: `test/models/mail_provider_rules_test.dart`

**Interfaces:**
- Produces: `enum BlockedProvider { gmail, outlookHotmail }`; `BlockedProvider? detectBlockedProvider(String email)`; `bool isAppleIdDomain(String email)`; `String? emailDomain(String email)`.

- [ ] **Step 1: Write the failing tests**

```dart
// test/models/mail_provider_rules_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:imap_mail/models/mail_provider_rules.dart';

void main() {
  group('emailDomain', () {
    test('extracts the lowercased domain', () {
      expect(emailDomain('Someone@Example.COM'), 'example.com');
    });

    test('returns null when there is no domain', () {
      expect(emailDomain('not-an-email'), isNull);
      expect(emailDomain('trailing@'), isNull);
      expect(emailDomain(''), isNull);
    });
  });

  group('detectBlockedProvider', () {
    test('flags Gmail domains', () {
      expect(detectBlockedProvider('me@gmail.com'), BlockedProvider.gmail);
      expect(detectBlockedProvider('me@googlemail.com'), BlockedProvider.gmail);
    });

    test('flags Outlook/Hotmail domains', () {
      for (final domain in ['outlook.com', 'hotmail.com', 'live.com', 'msn.com']) {
        expect(detectBlockedProvider('me@$domain'), BlockedProvider.outlookHotmail, reason: domain);
      }
    });

    test('returns null for anything else, including iCloud', () {
      expect(detectBlockedProvider('me@icloud.com'), isNull);
      expect(detectBlockedProvider('me@example.com'), isNull);
    });
  });

  group('isAppleIdDomain', () {
    test('recognizes icloud.com, me.com, and mac.com', () {
      expect(isAppleIdDomain('me@icloud.com'), isTrue);
      expect(isAppleIdDomain('me@me.com'), isTrue);
      expect(isAppleIdDomain('me@mac.com'), isTrue);
    });

    test('is false for anything else', () {
      expect(isAppleIdDomain('me@gmail.com'), isFalse);
      expect(isAppleIdDomain('me@example.com'), isFalse);
    });
  });
}
```

- [ ] **Step 2: Run and verify it fails**

Run: `flutter test test/models/mail_provider_rules_test.dart`
Expected: FAIL — `Target of URI doesn't exist: 'package:imap_mail/models/mail_provider_rules.dart'`.

- [ ] **Step 3: Implement**

```dart
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
```

- [ ] **Step 4: Run and verify it passes**

Run: `flutter test test/models/mail_provider_rules_test.dart`
Expected: PASS, all 7 tests.

- [ ] **Step 5: Commit**

```bash
git add lib/models/mail_provider_rules.dart test/models/mail_provider_rules_test.dart
git commit -m "feat: detect blocked email providers and Apple ID domains"
```

---

## Task 3: `srv_resolver` — RFC 6186 SRV record parsing

**Files:**
- Create: `lib/services/srv_resolver.dart`
- Test: `test/services/srv_resolver_test.dart`

**Interfaces:**
- Produces: `class SrvTarget { priority, weight, port, target, isNotOffered }`; `SrvTarget? parseSrvRecordData(String raw)`; `SrvTarget? pickBestTarget(List<SrvTarget> targets)`; `abstract class SrvResolver { Future<List<SrvTarget>> lookup(String serviceName); }`; `class DnsSrvResolver implements SrvResolver`.
- Consumes: `basic_utils`'s `DnsUtils.lookupRecord`/`RRecordType.SRV`/`RRecord.data` (Task 1's dependency).

- [ ] **Step 1: Write the failing tests**

```dart
// test/services/srv_resolver_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:imap_mail/services/srv_resolver.dart';

void main() {
  group('parseSrvRecordData', () {
    test('parses a well-formed SRV answer and strips the trailing dot', () {
      final target = parseSrvRecordData('0 5 993 imap.example.com.');
      expect(target, isNotNull);
      expect(target!.priority, 0);
      expect(target.weight, 5);
      expect(target.port, 993);
      expect(target.target, 'imap.example.com');
    });

    test('recognizes a "." target as explicitly not offered', () {
      final target = parseSrvRecordData('0 0 0 .');
      expect(target, isNotNull);
      expect(target!.isNotOffered, isTrue);
    });

    test('returns null for malformed data', () {
      expect(parseSrvRecordData('not a valid record'), isNull);
      expect(parseSrvRecordData('0 5 not-a-port imap.example.com.'), isNull);
      expect(parseSrvRecordData(''), isNull);
    });
  });

  group('pickBestTarget', () {
    test('picks the lowest-priority target', () {
      const low = SrvTarget(priority: 0, weight: 1, port: 993, target: 'a.example.com');
      const high = SrvTarget(priority: 10, weight: 1, port: 993, target: 'b.example.com');
      expect(pickBestTarget([high, low]), same(low));
    });

    test('skips "not offered" targets', () {
      const notOffered = SrvTarget(priority: 0, weight: 0, port: 0, target: '.');
      const usable = SrvTarget(priority: 10, weight: 1, port: 993, target: 'a.example.com');
      expect(pickBestTarget([notOffered, usable]), same(usable));
    });

    test('returns null when nothing is usable', () {
      const notOffered = SrvTarget(priority: 0, weight: 0, port: 0, target: '.');
      expect(pickBestTarget([notOffered]), isNull);
      expect(pickBestTarget(const []), isNull);
    });
  });
}
```

- [ ] **Step 2: Run and verify it fails**

Run: `flutter test test/services/srv_resolver_test.dart`
Expected: FAIL — `Target of URI doesn't exist: 'package:imap_mail/services/srv_resolver.dart'`.

- [ ] **Step 3: Implement**

```dart
// lib/services/srv_resolver.dart
import 'package:basic_utils/basic_utils.dart' as dns;

/// One answer from an RFC 6186 SRV lookup.
class SrvTarget {
  const SrvTarget({
    required this.priority,
    required this.weight,
    required this.port,
    required this.target,
  });

  final int priority;
  final int weight;
  final int port;
  final String target;

  /// RFC 6186 §5: a lone SRV record with Target "." means the service is
  /// explicitly declared unavailable — distinct from no record existing.
  bool get isNotOffered => target == '.';
}

/// Parses one SRV record's raw presentation-format `data` string
/// (`"<priority> <weight> <port> <target>"`, as returned by the DNS-over-
/// HTTPS provider `basic_utils` queries), stripping the target's trailing
/// root dot. Returns null if [raw] isn't a well-formed SRV record.
SrvTarget? parseSrvRecordData(String raw) {
  final parts = raw.trim().split(RegExp(r'\s+'));
  if (parts.length != 4) return null;
  final priority = int.tryParse(parts[0]);
  final weight = int.tryParse(parts[1]);
  final port = int.tryParse(parts[2]);
  if (priority == null || weight == null || port == null) return null;
  var target = parts[3];
  if (target.length > 1 && target.endsWith('.')) {
    target = target.substring(0, target.length - 1);
  }
  return SrvTarget(priority: priority, weight: weight, port: port, target: target);
}

/// Picks the most-preferred usable target: lowest priority number wins
/// (RFC 2782); a target of "." ("not offered") is never returned. Returns
/// null if [targets] is empty or every entry is "not offered".
SrvTarget? pickBestTarget(List<SrvTarget> targets) {
  final usable = targets.where((t) => !t.isNotOffered).toList()
    ..sort((a, b) => a.priority.compareTo(b.priority));
  return usable.isEmpty ? null : usable.first;
}

/// Looks up SRV records for a fully-qualified service name (e.g.
/// `_imaps._tcp.example.com`).
abstract class SrvResolver {
  Future<List<SrvTarget>> lookup(String serviceName);
}

/// Real implementation, backed by `basic_utils`'s DNS-over-HTTPS lookup
/// (the same mechanism `enough_mail`'s own MX-based discovery already uses
/// in this codebase).
class DnsSrvResolver implements SrvResolver {
  @override
  Future<List<SrvTarget>> lookup(String serviceName) async {
    final records = await dns.DnsUtils.lookupRecord(serviceName, dns.RRecordType.SRV);
    if (records == null) return [];
    return records.map((r) => parseSrvRecordData(r.data)).whereType<SrvTarget>().toList();
  }
}
```

- [ ] **Step 4: Run and verify it passes**

Run: `flutter test test/services/srv_resolver_test.dart`
Expected: PASS, all 6 tests. (`DnsSrvResolver` itself is a thin network wrapper with no branching logic — not unit tested directly, matching how `EnoughMailTransport` isn't unit tested directly elsewhere in this codebase either; its consumer, `DefaultAccountDiscoveryService` in Task 5, is tested against a fake `SrvResolver`.)

- [ ] **Step 5: Commit**

```bash
git add lib/services/srv_resolver.dart test/services/srv_resolver_test.dart
git commit -m "feat: add RFC 6186 SRV record parsing and target selection"
```

---

## Task 4: `discovered_mail_config` + `ispdb_discovery` — ISPDB fallback

**Files:**
- Create: `lib/services/discovered_mail_config.dart`
- Create: `lib/services/ispdb_discovery.dart`
- Test: `test/services/ispdb_discovery_test.dart`

**Interfaces:**
- Produces: `class DiscoveredMailConfig { imapHost, imapPort, imapSecurity, smtpHost, smtpPort, smtpSecurity }` (all nullable); `abstract class IspdbDiscovery { Future<DiscoveredMailConfig?> discover(String email); }`; `DiscoveredMailConfig? mapClientConfig(enough.ClientConfig? config)`; `class EnoughMailIspdbDiscovery implements IspdbDiscovery`.
- Consumes: `enough_mail`'s `Discover.discover`, `ClientConfig`, `ServerConfig`, `SocketType` (`third_party/enough_mail/lib/src/discover/`).

- [ ] **Step 1: Create the shared config type (no test needed — plain data class)**

```dart
// lib/services/discovered_mail_config.dart
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
```

- [ ] **Step 2: Write the failing test for `mapClientConfig`**

```dart
// test/services/ispdb_discovery_test.dart
import 'package:enough_mail/enough_mail.dart' as enough;
import 'package:flutter_test/flutter_test.dart';
import 'package:imap_mail/models/enums.dart';
import 'package:imap_mail/services/ispdb_discovery.dart';

enough.ClientConfig _configWith({enough.ServerConfig? incoming, enough.ServerConfig? outgoing}) {
  final config = enough.ClientConfig();
  config.preferredIncomingImapServer = incoming;
  config.preferredOutgoingSmtpServer = outgoing;
  return config;
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
      ),
      outgoing: enough.ServerConfig(
        type: enough.ServerType.smtp,
        hostname: 'smtp.example.com',
        port: 587,
        socketType: enough.SocketType.starttls,
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
      ),
    );

    final result = mapClientConfig(config);

    expect(result, isNotNull);
    expect(result!.imapHost, 'imap.example.com');
    expect(result.smtpHost, isNull);
  });
}
```

- [ ] **Step 3: Run and verify it fails**

Run: `flutter test test/services/ispdb_discovery_test.dart`
Expected: FAIL — `Target of URI doesn't exist: 'package:imap_mail/services/ispdb_discovery.dart'`.

- [ ] **Step 4: Implement**

```dart
// lib/services/ispdb_discovery.dart
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
```

- [ ] **Step 5: Run and verify it passes**

Run: `flutter test test/services/ispdb_discovery_test.dart`
Expected: PASS, all 4 tests. (`EnoughMailIspdbDiscovery` itself isn't unit tested directly — it's a one-line call into `enough.Discover.discover` plus the already-tested `mapClientConfig`; `DefaultAccountDiscoveryService` in Task 5 exercises it via a fake.)

- [ ] **Step 6: Commit**

```bash
git add lib/services/discovered_mail_config.dart lib/services/ispdb_discovery.dart test/services/ispdb_discovery_test.dart
git commit -m "feat: add DiscoveredMailConfig and ISPDB/autoconfig fallback mapping"
```

---

## Task 5: `account_discovery_service` — the full discovery algorithm

**Files:**
- Create: `lib/services/account_discovery_service.dart`
- Test: `test/services/account_discovery_service_test.dart`

**Interfaces:**
- Consumes: `mail_provider_rules.dart`'s `isAppleIdDomain`, `emailDomain` (Task 2); `srv_resolver.dart`'s `SrvResolver`, `pickBestTarget` (Task 3); `ispdb_discovery.dart`'s `IspdbDiscovery` (Task 4); `discovered_mail_config.dart`'s `DiscoveredMailConfig` (Task 4).
- Produces: `abstract class AccountDiscoveryService { Future<DiscoveredMailConfig?> discover(String email); }`; `class DefaultAccountDiscoveryService implements AccountDiscoveryService` with constructor `DefaultAccountDiscoveryService({SrvResolver? srvResolver, IspdbDiscovery? ispdbDiscovery})`.

- [ ] **Step 1: Write the failing tests**

```dart
// test/services/account_discovery_service_test.dart
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
```

- [ ] **Step 2: Run and verify it fails**

Run: `flutter test test/services/account_discovery_service_test.dart`
Expected: FAIL — `Target of URI doesn't exist: 'package:imap_mail/services/account_discovery_service.dart'`.

- [ ] **Step 3: Implement**

```dart
// lib/services/account_discovery_service.dart
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
```

- [ ] **Step 4: Run and verify it passes**

Run: `flutter test test/services/account_discovery_service_test.dart`
Expected: PASS, all 6 tests.

- [ ] **Step 5: Commit**

```bash
git add lib/services/account_discovery_service.dart test/services/account_discovery_service_test.dart
git commit -m "feat: implement RFC 6186 + ISPDB account discovery algorithm"
```

---

## Task 6: Wire `accountDiscoveryServiceProvider`

**Files:**
- Modify: `lib/providers/repository_providers.dart`
- Test: none new (covered by Task 7/8 widget tests overriding this provider).

**Interfaces:**
- Consumes: `AccountDiscoveryService`, `DefaultAccountDiscoveryService` (Task 5).
- Produces: `accountDiscoveryServiceProvider` (`Provider<AccountDiscoveryService>`).

- [ ] **Step 1: Add the provider**

In `lib/providers/repository_providers.dart`, add the import and provider next to the existing simple providers (`credentialStoreProvider`, `mailTransportProvider`, `mailSenderProvider`):

```dart
import '../services/account_discovery_service.dart';
```

```dart
final accountDiscoveryServiceProvider =
    Provider<AccountDiscoveryService>((ref) => DefaultAccountDiscoveryService());
```

- [ ] **Step 2: Verify it compiles**

Run: `flutter analyze lib/providers/repository_providers.dart`
Expected: `No issues found!`

- [ ] **Step 3: Commit**

```bash
git add lib/providers/repository_providers.dart
git commit -m "feat: expose accountDiscoveryServiceProvider"
```

---

## Task 7: `AccountEmailScreen` — Screen 1

**Files:**
- Create: `lib/screens/account_email_screen.dart`
- Test: `test/widget/account_email_screen_test.dart`

**Interfaces:**
- Consumes: `detectBlockedProvider`, `BlockedProvider` (Task 2); `accountDiscoveryServiceProvider` (Task 6); `AccountFormScreen` — extended in Task 8 to accept `initialEmail`/`discoveredConfig` constructor params (this task's tests construct `AccountFormScreen` only indirectly, by checking `find.byType(AccountFormScreen)` after navigation — they do not need Task 8 to be done first, since Flutter widget construction doesn't fail just because a constructor parameter isn't recognized yet... **note:** this task's implementation *does* need those two params to exist on `AccountFormScreen`, so do Task 8's constructor-signature change (just the constructor, not the rest of Task 8) first, or do Task 8 before Task 7. Recommended order: do Task 8 before Task 7 if executing out of the order written here. As written, Task 7 assumes `AccountFormScreen` already accepts `initialEmail` and `discoveredConfig`.
- Produces: `class AccountEmailScreen extends ConsumerStatefulWidget`.

- [ ] **Step 1: Write the failing tests**

```dart
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
    await tester.tap(find.byKey(const Key('nextButton')));
    await tester.pumpAndSettle();

    expect(fakeService.lastEmail, 'me@example.com');
    expect(find.byType(AccountFormScreen), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run and verify it fails**

Run: `flutter test test/widget/account_email_screen_test.dart`
Expected: FAIL — `Target of URI doesn't exist: 'package:imap_mail/screens/account_email_screen.dart'`.

- [ ] **Step 3: Implement**

```dart
// lib/screens/account_email_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/mail_provider_rules.dart';
import '../providers/repository_providers.dart';
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
      if (_blockedProvider != null) setState(() => _blockedProvider = null);
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
    final config = await ref.read(accountDiscoveryServiceProvider).discover(email);
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
```

- [ ] **Step 4: Run and verify it passes**

Run: `flutter test test/widget/account_email_screen_test.dart`
Expected: PASS, all 4 tests.

- [ ] **Step 5: Commit**

```bash
git add lib/screens/account_email_screen.dart test/widget/account_email_screen_test.dart
git commit -m "feat: add AccountEmailScreen (onboarding Screen 1)"
```

---

## Task 8: Rework `AccountFormScreen` for the new-account path (Screen 2)

**Files:**
- Modify: `lib/screens/account_form_screen.dart`
- Modify: `test/widget/account_form_screen_test.dart`
- Delete: `lib/models/provider_preset.dart`
- Delete: `test/models/provider_preset_test.dart`

**Interfaces:**
- Consumes: `isAppleIdDomain` (Task 2); `DiscoveredMailConfig` (Task 4).
- Produces: `AccountFormScreen(existing, initialEmail, discoveredConfig)` — `initialEmail`/`discoveredConfig` are only meaningful when `existing` is null.

**Note on ordering:** if executing tasks strictly in file order, do this task *before* Task 7, since Task 7's widget builds an `AccountFormScreen(initialEmail: ..., discoveredConfig: ...)` that only compiles once this task's constructor change lands. (Subagent-driven execution should sequence Task 8 ahead of Task 7 for this reason, despite the numbering here following the user-facing screen order.)

- [ ] **Step 1: Delete the superseded preset table**

```bash
git rm lib/models/provider_preset.dart test/models/provider_preset_test.dart
```

- [ ] **Step 2: Update `test/widget/account_form_screen_test.dart` — adjust tests that assumed default-visible advanced fields**

Three existing tests construct `AccountFormScreen()` (new account) and immediately fill IMAP/SMTP/username fields, which are now collapsed by default. Add one line to each, tapping the Advanced setup toggle first (`find.byKey(const Key('advancedSetupToggle'))`), right after `pumpWidget` and before `enterText` on any hidden field:

In **`Save button is disabled until required fields are filled`**, **`shows IMAP and SMTP security dropdowns defaulting to SSL/TLS`**, and **`saving a new account when the form is the app root does not crash...`**, insert immediately after the `pumpWidget` call:

```dart
await tester.tap(find.byKey(const Key('advancedSetupToggle')));
await tester.pump();
```

- [ ] **Step 3: Replace the four commit-`48f0dc8` preset-behavior tests**

Delete these four tests (they test the removed per-keystroke `_onEmailChanged`/`ProviderPreset` behavior):
- `new account: a recognized email hides the advanced fields and shows the detected provider`
- `new account: an unrecognized email leaves the full advanced form visible`
- `new account: Advanced setup toggle reveals the fields for a matched provider, pre-filled`
- `new account: saving with a matched provider and no override sends the preset config`

Replace them with (keep the final `editing an existing account shows the full form...` test as-is — it's still valid):

```dart
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
```

Add the new imports at the top of the test file:

```dart
import 'package:imap_mail/services/discovered_mail_config.dart';
```

- [ ] **Step 4: Run and verify the updated test file fails correctly**

Run: `flutter test test/widget/account_form_screen_test.dart`
Expected: FAIL — compile errors, since `AccountFormScreen` doesn't yet accept `initialEmail`/`discoveredConfig`, and `provider_preset.dart` (still imported by the *old* `account_form_screen.dart`) no longer exists.

- [ ] **Step 5: Rewrite `lib/screens/account_form_screen.dart`**

```dart
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

  bool get _isNewAccount => widget.existing == null;
  bool get _showAdvancedFields => !_isNewAccount || _advancedExpanded;
  bool get _discoveryFoundNothing => _isNewAccount && widget.discoveredConfig == null;
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
      obscureText: true,
      decoration: InputDecoration(labelText: _isAppleId ? 'App-Specific Password' : 'Password'),
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
          ] else if (_discoveryFoundNothing)
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text(
                "Couldn't detect your mail server settings automatically — tap "
                "Advanced setup to enter them.",
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
```

- [ ] **Step 6: Run and verify all tests pass**

Run: `flutter test test/widget/account_form_screen_test.dart`
Expected: PASS, all tests (6 unchanged + 3 adjusted + 6 new = 15).

- [ ] **Step 7: Commit**

```bash
git add lib/screens/account_form_screen.dart test/widget/account_form_screen_test.dart
git commit -m "feat: rework AccountFormScreen as onboarding Screen 2

Drops the per-keystroke provider-preset detection from 48f0dc8 in
favor of taking a DiscoveredMailConfig from AccountEmailScreen.
Advanced setup is now always collapsed by default; iCloud accounts
get an App-Specific Password label, hint, and link."
```

---

## Task 9: Route new-account entry points to `AccountEmailScreen`

**Files:**
- Modify: `lib/app.dart:74`
- Modify: `lib/screens/settings_screen.dart:45`
- Modify: `lib/screens/account_list_screen.dart:22`

**Interfaces:**
- Consumes: `AccountEmailScreen` (Task 7).

- [ ] **Step 1: Update `lib/app.dart`**

Replace the import and the zero-accounts case:

```dart
import 'screens/account_email_screen.dart';
```

```dart
              0 => const AccountEmailScreen(),
```

(The `account_form_screen.dart` import stays — `folder_view_screen.dart`'s edit route still needs it indirectly via other files, but `app.dart` itself no longer references `AccountFormScreen` directly once this line changes; remove the now-unused `import 'screens/account_form_screen.dart';` line from `app.dart` if `flutter analyze` flags it as unused.)

- [ ] **Step 2: Update `lib/screens/settings_screen.dart`**

Add the import and change the add-account button's route (the edit route at line 139, `AccountFormScreen(existing: account)`, stays untouched):

```dart
import 'account_email_screen.dart';
```

```dart
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const AccountEmailScreen()),
            ),
          ),
```

- [ ] **Step 3: Update `lib/screens/account_list_screen.dart`**

Add the import and change the add-account button's route:

```dart
import 'account_email_screen.dart';
```

```dart
        IconButton(
          icon: const Icon(Icons.add),
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const AccountEmailScreen()),
          ),
        ),
```

- [ ] **Step 4: Verify nothing else references the old routes and analysis is clean**

Run: `grep -rn "AccountFormScreen()" lib/`
Expected: no matches (every remaining `AccountFormScreen(...)` construction passes `existing:`).

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 5: Commit**

```bash
git add lib/app.dart lib/screens/settings_screen.dart lib/screens/account_list_screen.dart
git commit -m "feat: route new-account entry points through AccountEmailScreen"
```

---

## Task 10: Full regression pass

**Files:** none (verification only).

- [ ] **Step 1: Run static analysis**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 2: Run the full test suite**

Run: `flutter test`
Expected: all tests pass, no regressions in unrelated suites (folder view, message list, swipe actions, etc.).

- [ ] **Step 3: Manual smoke test on the iOS Simulator**

Following this project's known simulator-staleness gotcha, do a clean run first:

```bash
rm -rf ~/Library/Developer/Xcode/DerivedData/Runner-*
flutter clean
flutter pub get
cd ios && pod install && cd ..
flutter run -d <simulator-id>
```

Manually verify:
- A brand-new "Add account" flow shows the email-only Screen 1.
- `test@gmail.com` and `test@outlook.com` each block with their message and never proceed.
- A real domain with published SRV records (or any domain that falls through to ISPDB, e.g. a well-known provider in Mozilla's database) reaches Screen 2 with Advanced setup collapsed.
- `test@icloud.com` reaches Screen 2 showing "App-Specific Password", the hint text, and a working link to `appleid.apple.com`.
- A nonsense domain (e.g. `test@this-domain-does-not-exist-12345.example`) reaches Screen 2 with the "couldn't detect" caption, and tapping Advanced setup reveals empty fields.
- Editing an existing account still shows the full form immediately, unchanged.

- [ ] **Step 4: No commit for this task** — it's verification only. If the manual smoke test finds a bug, fix it as a new commit before considering the plan complete.

---

## Self-Review Notes (completed while writing this plan)

- **Spec coverage:** §4 Screen 1 blocking → Task 7/9. §4 Screen 2 password label/Advanced/caption → Task 8. §5 discovery algorithm → Tasks 3–5. §6 file list → Tasks 2–9 cover every file named. §7 testing strategy → each task's own test step; the "fake `DnsUtils`-shaped resolver" language in the spec is satisfied by `SrvResolver`/`_FakeSrvResolver` rather than mocking `DnsUtils` itself, which is equivalent and simpler. §3 non-goals (no OAuth, no Fastmail/Outlook special-casing beyond blocking) — nothing in this plan adds either.
- **Placeholder scan:** none found — every step has real code or a real shell command.
- **Type consistency:** `DiscoveredMailConfig` fields (`imapHost`, `imapPort`, `imapSecurity`, `smtpHost`, `smtpPort`, `smtpSecurity`) are used identically in Tasks 4, 5, 7, and 8. `AccountDiscoveryService.discover(String email) -> Future<DiscoveredMailConfig?>` matches everywhere it's called. `BlockedProvider`/`detectBlockedProvider`/`isAppleIdDomain`/`emailDomain` signatures from Task 2 are used unchanged in Tasks 5, 7, and 8.
