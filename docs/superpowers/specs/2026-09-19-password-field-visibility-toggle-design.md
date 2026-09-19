# Password Field Has No Show/Hide Toggle — Design

Date: 2026-09-19
Status: Ready to implement
Issue: https://github.com/pcoorie/cobalt-mail/issues/8

## 1. Bug report

The password field on the account form is permanently obscured, with no
way to verify what was typed.

## 2. Root cause

`_AccountFormScreenState._buildPasswordField()` hardcodes `obscureText:
true` with no toggle:

```dart
// lib/screens/account_form_screen.dart:187-193
Widget _buildPasswordField() {
  final passwordField = TextField(
    key: const Key('passwordField'),
    controller: _password,
    obscureText: true,
    decoration: InputDecoration(labelText: _isAppleId ? 'App-Specific Password' : 'Password'),
  );
  ...
```

## 3. Why it hurts the outcome

This is the single highest-friction, highest-abandonment screen in the
app. IMAP passwords are frequently long, random app-specific passwords
(Gmail/iCloud app passwords are 16+ characters) — with no way to verify
what was typed, a single mistyped character produces a silent auth failure
the user can't self-diagnose.

## 4. Desired behavior

The password field gets a standard eye-icon `suffixIcon` that toggles
`obscureText`:

- Field starts obscured (`obscureText: true`), same as today.
- Tapping the icon reveals the password (`obscureText: false`) and the icon
  switches to the "hide" variant; tapping again re-obscures it.
- The icon has a `tooltip` describing the action it performs next ("Show
  password" while obscured, "Hide password" while visible), matching every
  other icon action's convention in this app (see
  `lib/screens/folder_view_screen.dart:196`, which does the same
  toggle-label pattern for its unread-only filter icon).
- This applies to the field in both its states — the App ID variant (`_isAppleId
  == true`, labeled "App-Specific Password", with the extra hint/link column
  below it) and the plain variant (`_isAppleId == false`, labeled
  "Password") both get the toggle, since it's the same `TextField`
  either way.

## 5. Non-goals

- Not adding a strength meter, paste-detection, or any other password-field
  behavior — just visibility toggling.
- Not changing the field's `key`, `controller`, or label logic.

## 6. Testing strategy

A widget test pumps `AccountFormScreen` (new-account mode, matching the
existing pattern in `test/widget/account_form_screen_test.dart`), types
into the password field, confirms it starts obscured (`obscureText ==
true` on the underlying `TextField`), taps the toggle icon, confirms it's
now visible (`obscureText == false`), taps again, confirms it's obscured
again — exercising the real `TextField.obscureText` property that controls
whether the OS renders dots or the actual characters, not just checking
which icon is on screen.

See the accompanying plan for the concrete steps.
