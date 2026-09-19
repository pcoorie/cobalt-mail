# Password Field Visibility Toggle Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the account form's password field a standard eye-icon toggle so the user can verify what they typed, instead of a permanently obscured field.

**Architecture:** One new `bool` state field plus a `suffixIcon` `IconButton` added to `_AccountFormScreenState._buildPasswordField()` in `lib/screens/account_form_screen.dart`, guarded by a widget test that drives the toggle and asserts the underlying `TextField.obscureText` value at each step.

**Tech Stack:** Flutter, `flutter_test`, `flutter_riverpod` (`ProviderScope`).

**Spec:** `docs/superpowers/specs/2026-09-19-password-field-visibility-toggle-design.md`

## Global Constraints

- Field starts obscured (`obscureText: true`), same as today.
- Toggling flips `obscureText` on the same `TextField` (key `passwordField` unchanged) — no new controller, no new field.
- Icon's `tooltip` describes the action it performs next: `'Show password'` while obscured, `'Hide password'` while visible.
- Applies to both the App ID and plain variants of the field (same `TextField`, so no extra work needed — both already share `_buildPasswordField()`).

---

### Task 1: Visibility toggle + regression test

**Files:**
- Modify: `lib/screens/account_form_screen.dart:38-42` (state fields), `lib/screens/account_form_screen.dart:187-193` (`_buildPasswordField`)
- Test: `test/widget/account_form_screen_test.dart`

**Interfaces:**
- Consumes: nothing new.
- Produces: nothing consumed by later tasks — this is the only task in the plan.

- [ ] **Step 1: Write the failing test**

Add this test to `test/widget/account_form_screen_test.dart`, alongside the existing `testWidgets('Save button is disabled until required fields are filled', ...)` block (same file, so it shares the `useTallSurface` helper already defined above in `main()`):

```dart
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
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/widget/account_form_screen_test.dart --plain-name "password field has a show/hide visibility toggle"`

Expected: FAIL — `find.byTooltip('Show password')` finds zero widgets (no toggle exists yet).

- [ ] **Step 3: Add the toggle**

In `lib/screens/account_form_screen.dart`, add a new state field next to the other `bool` fields (after `bool _advancedExpanded = false;`):

```dart
  bool _obscurePassword = true;
```

Then change `_buildPasswordField()`:

```dart
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
```

(Only the `obscureText` line and the `decoration:` block change — everything else in the method, including the `if (!_isAppleId)` branch below it, stays exactly as it is today.)

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/widget/account_form_screen_test.dart`

Expected: PASS — all tests in the file, including the new one.

- [ ] **Step 5: Run the full test suite**

Run: `flutter test`

Expected: PASS — no other test asserts on the password field's decoration or obscureText, so no other test should be affected.

- [ ] **Step 6: Commit**

```bash
git add lib/screens/account_form_screen.dart test/widget/account_form_screen_test.dart
git commit -m "fix: add show/hide toggle to account form password field"
```
