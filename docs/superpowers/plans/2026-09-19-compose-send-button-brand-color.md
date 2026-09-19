# Compose Send Button Brand Color Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the Compose screen's Send button use the app's real brand color (`brandSeed`) instead of a hardcoded, visibly different blue.

**Architecture:** One-line color swap plus a matching import in `lib/screens/compose_screen.dart`, guarded by a new widget test that resolves the Send button's `ElevatedButton` style and asserts the background color equals `brandSeed`.

**Tech Stack:** Flutter, `flutter_test`, `flutter_riverpod` (`ProviderScope`).

**Spec:** `docs/superpowers/specs/2026-09-19-compose-send-button-brand-color-design.md`

## Global Constraints

- The fix must set `backgroundColor: brandSeed` explicitly on the existing `ElevatedButton.styleFrom` call — do not remove the `style:` override or change `foregroundColor`.
- `brandSeed` must be imported from `../theme/brand_colors.dart`, matching the pattern already used in `lib/widgets/folder_tab_bar.dart` and `lib/widgets/folder_tree_expander.dart`.
- No other colors in `compose_screen.dart` change.

---

### Task 1: Regression test + fix for the Send button color

**Files:**
- Modify: `lib/screens/compose_screen.dart:1-15` (imports), `lib/screens/compose_screen.dart:253-259` (Send button)
- Test: `test/widget/compose_screen_test.dart`

**Interfaces:**
- Consumes: `brandSeed` (`Color`, `package:imap_mail/theme/brand_colors.dart`), `ComposeScreen` widget (`accountId` constructor param, already used throughout this test file).
- Produces: nothing consumed by later tasks — this is the only task in the plan.

- [ ] **Step 1: Write the failing test**

Add this test to `test/widget/compose_screen_test.dart`, alongside the existing `testWidgets('Send is disabled until a recipient and body are entered', ...)` block (same file, so it shares the existing `setUpAll`/`_growViewport`/`account` fixtures already defined above in `main()`):

```dart
  testWidgets('Send button uses the brand color, not a hardcoded blue', (tester) async {
    _growViewport(tester);
    await tester.pumpWidget(const ProviderScope(
      child: MaterialApp(home: ComposeScreen(accountId: 1)),
    ));

    final sendButtonFinder = find.widgetWithText(ElevatedButton, 'Send');
    final button = tester.widget<ElevatedButton>(sendButtonFinder);
    final resolvedColor = button.style?.backgroundColor?.resolve(<WidgetState>{});

    expect(resolvedColor, brandSeed);
  });
```

Also add this import at the top of `test/widget/compose_screen_test.dart`, next to the other `package:imap_mail/...` imports:

```dart
import 'package:imap_mail/theme/brand_colors.dart';
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/widget/compose_screen_test.dart --plain-name "Send button uses the brand color"`

Expected: FAIL — `resolvedColor` is `Color(0xff1e88e5)`, not `brandSeed` (`Color(0xff0a5bd6)`).

- [ ] **Step 3: Fix the hardcoded color**

In `lib/screens/compose_screen.dart`, add the import next to the other relative imports (after `import '../providers/message_providers.dart';`):

```dart
import '../theme/brand_colors.dart';
```

Then change the Send button's style:

```dart
          ElevatedButton(
            onPressed: _isValid && !_sending ? _send : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: brandSeed,
              foregroundColor: Colors.white,
            ),
            child: Text(_sending ? 'Sending...' : 'Send'),
          ),
```

(This replaces only the `backgroundColor: const Color(0xFF1E88E5),` line — `foregroundColor: Colors.white` is unchanged.)

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/widget/compose_screen_test.dart`

Expected: PASS — all tests in the file, including the new one.

- [ ] **Step 5: Run the full test suite**

Run: `flutter test`

Expected: PASS — no other test references the old hardcoded color, so no other test should be affected.

- [ ] **Step 6: Commit**

```bash
git add lib/screens/compose_screen.dart test/widget/compose_screen_test.dart
git commit -m "fix: use brandSeed for Compose Send button instead of hardcoded blue"
```
