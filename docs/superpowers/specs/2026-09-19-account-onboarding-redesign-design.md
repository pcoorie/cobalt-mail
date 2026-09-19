# Account Onboarding Redesign — Email-First Setup with RFC 6186 Autodiscovery

Date: 2026-09-19
Status: Design approved by user in chat — not yet implemented

## 1. Background

The single-screen provider-preset fix shipped for issue #5 (commit `48f0dc8`)
solved the "ten manual fields" problem for four hardcoded domains (Gmail,
Outlook, iCloud, Fastmail), but real-world testing surfaced a bigger problem:
**for three of those four providers, a plain account password doesn't work
at all.**

- **Gmail**: Google removed Basic Authentication for IMAP/SMTP/POP entirely
  in 2026. There is no password, app-specific or otherwise, that works —
  only OAuth2, which this app doesn't implement.
- **Outlook/Hotmail**: Microsoft has deprecated Basic Authentication for
  IMAP/SMTP/POP for both organizational (Exchange Online) and personal
  (outlook.com/hotmail.com/live.com/msn.com) accounts, pushing everything
  to OAuth2 — same dead end as Gmail, no password of any kind works.
- **iCloud**: Apple requires an app-specific password, generated at
  `appleid.apple.com`, for any third-party IMAP client. The regular Apple ID
  password is rejected — but this one *does* work, since the app-specific
  password is still plain-password auth as far as IMAP/SMTP is concerned.
- **Fastmail**: never accepts the account's master password for IMAP/SMTP —
  an app password is mandatory.

A UI/UX review (via the `reviewing-mobile-app-uiux` skill) confirmed this is
a **blocker**, not polish: the auto-filled form now looks like it will work,
then fails silently at the last step with no explanation — a worse
abandonment point than the original bare-IMAP form, because there's nothing
on screen telling the user how to recover.

Separately, the user decided to drop Outlook and Fastmail as special-cased
providers (product decision — not worth maintaining bespoke handling for
either), and to replace domain-by-domain guessing with a real discovery
protocol: **RFC 6186** (DNS SRV records for mail service discovery), which
returns actual hostnames/ports rather than guessing common patterns.

## 2. Goals

- New-account setup starts with **one field: email**. No display name, no
  server details, up front.
- Server settings (host/port/security) are discovered automatically via DNS
  wherever possible, using the actual IETF standard for it rather than a
  hardcoded table.
- iCloud is special-cased only for the one thing that can't be discovered:
  the requirement for an app-specific password, made unmissable in the UI.
- Gmail and Outlook/Hotmail are blocked outright, before the user wastes
  effort on a form that cannot possibly succeed. In practice this leaves
  two supported paths: iCloud (app-specific password), or plain IMAP with
  a real account/app password on any other domain.
- Editing an existing account is unaffected — full manual form, unchanged
  (already the behavior after #5's fix).

## 3. Non-goals

- No OAuth2 / Google or Microsoft sign-in of any kind (confirmed out of
  scope — see the OAuth feasibility discussion in chat: Gmail's OAuth
  verification is costly, Outlook/Exchange has its own registration
  overhead, and iCloud has no public OAuth path for third-party IMAP at
  all, so OAuth wouldn't even fully solve the problem).
- No special-casing for Fastmail beyond what generic discovery finds for
  it. Outlook/Hotmail gets no *setup* special-casing either — it's blocked
  entirely (§4), not routed through discovery at all.
- No change to the account **editing** flow.

## 4. Flow

### Screen 1 — Email

- Single email field + "Next" (disabled until the input looks like a valid
  email address).
- **Blocked-provider check**: if the domain matches one of the two known
  dead ends, "Next" leads to an inline blocking message on this same
  screen — not a navigation forward, not the manual form:
  - `gmail.com`, `googlemail.com`:
    > "Gmail isn't supported. Google removed plain sign-in for apps like
    > this in 2026, and this app doesn't support Google's newer sign-in
    > method yet. Try a different email address."
  - `outlook.com`, `hotmail.com`, `live.com`, `msn.com`:
    > "Outlook and Hotmail aren't supported. Microsoft has moved these
    > accounts to a sign-in method this app doesn't support yet. Try a
    > different email address."
  There is no path forward from either state except changing the email —
  no Advanced setup escape hatch, since a real password genuinely cannot
  work for these domains.
- Otherwise, tapping "Next" shows a brief loading state ("Looking up mail
  server settings…") while discovery runs (§5), then navigates to Screen 2
  regardless of whether discovery found anything.

### Screen 2 — Password (+ Advanced setup)

- Display name, defaulted to the email's local-part (e.g. `pete` from
  `pete@example.com`), editable.
- Password field:
  - **iCloud domains** (`icloud.com`, `me.com`, `mac.com`): labeled
    **"App-Specific Password"**, with a visible note ("Your regular Apple ID
    password won't work here") and a tappable link to
    `https://appleid.apple.com/account/manage` to generate one.
  - **Everything else**: labeled "Password", no special note.
- **Advanced setup** — always present as a collapsed toggle, regardless of
  whether discovery succeeded or failed:
  - Collapsed by default in every case. The user never needs to look at
    IMAP/SMTP host/port/security/username unless they choose to.
  - When discovery found settings, expanding shows them pre-filled
    (override-able).
  - When discovery found nothing, expanding shows the same fields blank,
    for full manual entry — this is the *only* path to a working account
    when autodiscovery fails, since `Save` stays disabled until host/port
    are non-empty either way (existing `_isValid` logic already enforces
    this with no extra code).
  - A short caption appears above the toggle only when discovery found
    **nothing at all** (both incoming and outgoing unresolved — the
    `DiscoveredMailConfig?` from §5 is null) — "Couldn't detect your mail
    server settings automatically — tap Advanced setup to enter them." —
    so the user isn't left guessing why Save won't enable. A **partial**
    result (e.g. SRV found IMAP but not SMTP) shows no caption: expanding
    Advanced setup shows the discovered half pre-filled and the other half
    blank, which is self-explanatory without extra copy.
- Username defaults to the full email address (neither SRV nor ISPDB
  discovery ever returns credentials), editable via Advanced setup.
- Test Connection / Save unchanged.

## 5. Discovery algorithm

Given an email address (already past the blocked-provider check), in
order, first match wins:

1. **iCloud special case** — domain is `icloud.com`/`me.com`/`mac.com`:
   use the existing hardcoded config (`imap.mail.me.com:993` SSL /
   `smtp.mail.me.com:587` STARTTLS). Apple does not publish RFC 6186 SRV
   records for this domain, so skip DNS entirely.

2. **RFC 6186 DNS SRV lookup** — query, in this order, taking the
   lowest-priority (most preferred) non-`.` target from each:
   - Incoming: `_imaps._tcp.<domain>` (implicit TLS) → fall back to
     `_imap._tcp.<domain>` (STARTTLS)
   - Outgoing: `_submissions._tcp.<domain>` (implicit TLS, port 465) → fall
     back to `_submission._tcp.<domain>` (STARTTLS, port 587)
   - A returned target of `.` means the service is explicitly declared
     unavailable (RFC 6186 §5) — treated the same as "no record," not as a
     usable result.
   - Strip the trailing dot DNS returns on hostnames before using them.
   - Incoming and outgoing are resolved independently; a domain can
     legitimately publish one and not the other. Whatever resolves gets
     used; whatever doesn't falls through to step 3 below **for that half
     only**.

3. **ISPDB / autoconfig fallback** — for any half not resolved by SRV,
   delegate to the vendored `enough_mail` package's existing
   `Discover.discover(email)`, which already implements Thunderbird-style
   `autoconfig.<domain>` / `<domain>/.well-known/autoconfig` probing, MX
   lookup, and a query to Mozilla's Thunderbird ISPDB
   (`autoconfig.thunderbird.net`). Confirmed with the user this external
   lookup is acceptable to layer in despite the app's "private" framing —
   it's a fallback, not the default path, and only sends the domain, not
   the full email or any account details.

4. **Nothing resolves** — Screen 2 opens with Advanced setup collapsed and
   empty, per §4.

DNS SRV lookups use `basic_utils`'s `DnsUtils.lookupRecord(name,
RRecordType.SRV)` — already a transitive dependency (declared by
`third_party/enough_mail/pubspec.yaml`, resolved in `pubspec.lock`) and
already used elsewhere in the vendored package for MX lookups. It needs to
be added as a **direct** dependency in the app's own `pubspec.yaml` to be
imported from app code rather than relying on transitive resolution.

## 6. New/changed code

- `lib/services/account_discovery_service.dart` (new): defines
  `DiscoveredMailConfig` (imapHost/Port/Security, smtpHost/Port/Security,
  each host possibly null if that half wasn't discovered) and an abstract
  `AccountDiscoveryService` with `Future<DiscoveredMailConfig?>
  discover(String email)`. `DefaultAccountDiscoveryService` implements the
  §5 algorithm. Exposed via
  `accountDiscoveryServiceProvider = Provider<AccountDiscoveryService>(...)`
  in `lib/providers/repository_providers.dart`, matching the existing
  `mailTransportProvider` pattern — so widget tests can override it with a
  fake instead of hitting real DNS/HTTP.
- `lib/models/provider_preset.dart`: trimmed to iCloud only, or replaced
  with a small `isAppleIdDomain(String email)` helper plus the hardcoded
  iCloud host/port/security constants — whichever reads cleaner once
  written (implementation detail, not a design decision).
- `detectBlockedProvider(String email)` (new, small pure function, likely
  alongside the iCloud helper): returns an enum
  (`BlockedProvider.gmail`/`.outlookHotmail`) or `null`. Matches
  `gmail.com`/`googlemail.com` for Gmail and
  `outlook.com`/`hotmail.com`/`live.com`/`msn.com` for Outlook/Hotmail —
  the same four domains dropped from the old preset table in commit
  `48f0dc8`, now used to block rather than to configure.
- New screen `lib/screens/account_email_screen.dart` (Screen 1: email
  input, blocked-provider message, discovery loading state).
- `lib/screens/account_form_screen.dart` becomes Screen 2 for the
  *new-account* path (receives the `DiscoveredMailConfig?` and email as
  constructor input instead of driving discovery itself via the
  `_onEmailChanged` listener added in commit `48f0dc8` — that listener and
  the per-keystroke preset lookup are removed). The **editing** path
  (`existing != null`) is unchanged: full form, no discovery, no Gmail
  block, reached directly as it is today.
- All routes that currently push `AccountFormScreen()` for a *new* account
  (`app.dart`, `settings_screen.dart`, `account_list_screen.dart`) instead
  push the new `AccountEmailScreen()`. Routes that push
  `AccountFormScreen(existing: ...)` for editing are untouched.

## 7. Testing strategy

- `AccountDiscoveryService` is an injected interface — unit/widget tests
  use a fake implementation returning canned `DiscoveredMailConfig?`
  results (full success, partial success, `.`-target "not offered", null)
  with no real network I/O.
- SRV record parsing (priority ordering, trailing-dot stripping, `.`-target
  handling) gets direct unit tests against a fake `DnsUtils`-shaped
  resolver, not real DNS — real SRV records for real domains can change
  out from under a test suite.
- `AccountEmailScreen` widget tests: a Gmail domain and an Outlook/Hotmail
  domain each show their respective block message and never navigate
  forward (and show no Advanced-setup escape hatch); a domain whose fake
  discovery result resolves fully navigates to Screen 2 with fields
  hidden; a domain whose fake result is null navigates to Screen 2 with
  Advanced setup collapsed and the "couldn't detect" caption shown.
- `AccountFormScreen` (Screen 2) tests updated: replace the removed
  per-keystroke email-listener tests from commit `48f0dc8`
  (`test/widget/account_form_screen_test.dart`) with tests driven by the
  `DiscoveredMailConfig?` constructor input instead — iCloud config shows
  the App-Specific Password label + link; a null config shows the
  "couldn't detect" caption; Advanced setup always starts collapsed and
  reveals pre-filled or blank fields correctly either way.
- Existing edit-flow tests (full form, no discovery) stay as regression
  coverage, unchanged.

## 8. Open implementation details (not blocking, to resolve while coding)

- Exact malformed-input handling for the email field validity check on
  Screen 1 (already have `lookupProviderPreset`'s domain-extraction logic
  to reuse/adapt).
