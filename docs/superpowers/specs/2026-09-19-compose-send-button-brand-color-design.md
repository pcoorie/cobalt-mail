# Compose Send Button Uses a Hardcoded Off-Brand Color — Design

Date: 2026-09-19
Status: Ready to implement
Issue: https://github.com/pcoorie/cobalt-mail/issues/9

## 1. Bug report

The Send button on the compose screen is a visibly different blue than the
rest of the app's chrome (FolderTabBar's selected pill, FolderTreeExpander's
accent icon).

## 2. Root cause

`ComposeScreen`'s `ElevatedButton.styleFrom` hardcodes its own color instead
of using the app's brand constant:

```dart
// lib/screens/compose_screen.dart:253-259
ElevatedButton(
  onPressed: _isValid && !_sending ? _send : null,
  style: ElevatedButton.styleFrom(
    backgroundColor: const Color(0xFF1E88E5),
    foregroundColor: Colors.white,
  ),
  child: Text(_sending ? 'Sending...' : 'Send'),
),
```

`Color(0xFF1E88E5)` is a plain Material blue that predates (or was never
reconciled with) the app's actual brand color:

```dart
// lib/theme/brand_colors.dart
const brandSeed = Color(0xFF0A5BD6);
```

Every other call site that needs the exact brand blue already imports and
uses `brandSeed` directly — `FolderTabBar` (`lib/widgets/folder_tab_bar.dart:55`)
and `FolderTreeExpander` (`lib/widgets/folder_tree_expander.dart:48,55`) both
do `color: brandSeed`. `compose_screen.dart` is the one outlier, and it
doesn't currently import `theme/brand_colors.dart` at all.

## 3. Why it hurts the outcome

Compose is the screen with the highest intent in the app — the user is about
to send an email. A primary action button in a visibly off-brand color reads
as unfinished right at the moment of commitment.

## 4. Desired behavior

The Send button's background color must be `brandSeed`, matching every other
full-saturation brand-color use in the app. `foregroundColor: Colors.white`
is unaffected — `brandSeed` is dark enough that white text stays legible on
it, same as it already does on `FolderTabBar`'s selected pill.

## 5. Non-goals

- Not touching any other color in `compose_screen.dart` (error text color,
  etc.) — out of scope for this issue.
- Not switching the button to inherit the theme's default `ElevatedButton`
  style (dropping the `style:` override entirely) — the app's `ThemeData`
  is not guaranteed to derive its primary color from `brandSeed` today, and
  auditing/changing that is a separate, larger concern than fixing this one
  hardcoded value. Setting `backgroundColor: brandSeed` explicitly is the
  minimal, safe fix and matches the pattern every other call site already
  uses.

## 6. Testing strategy

This is a pure widget-styling change with no logic branch to exercise via
unit test. The regression test pumps `ComposeScreen` (following the existing
pattern in `test/widget/compose_screen_test.dart`), finds the `Send`
`ElevatedButton`, resolves its `style.backgroundColor`, and asserts it
equals `brandSeed` rather than the old hardcoded hex — so a future
regression back to a hardcoded color fails the test immediately.

See the accompanying plan for the concrete steps.
