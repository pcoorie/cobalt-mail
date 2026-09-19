# Compose FAB Tooltip Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give both of the app's compose floating action buttons a `tooltip: 'Compose'`, matching the accessibility-label convention every other icon action in the app already follows.

**Architecture:** Two one-line additions (`lib/screens/unified_inbox_screen.dart`, `lib/screens/folder_view_screen.dart`), each guarded by a widget test that asserts `find.byTooltip('Compose')` finds the FAB.

**Tech Stack:** Flutter, `flutter_test`, `flutter_riverpod` (`ProviderScope`).

**Spec:** `docs/superpowers/specs/2026-09-19-compose-fab-tooltip-design.md`

## Global Constraints

- Both FABs get exactly `tooltip: 'Compose'` — same string, matching `ComposeScreen`'s own AppBar title.
- No other widget's tooltip changes. No FAB icon, `onPressed`, or placement changes.

---

### Task 1: Tooltip on both compose FABs + regression tests

**Files:**
- Modify: `lib/screens/unified_inbox_screen.dart:95-98`
- Modify: `lib/screens/folder_view_screen.dart:261-268`
- Test: `test/widget/unified_inbox_screen_test.dart`
- Test: `test/widget/folder_view_screen_test.dart`

**Interfaces:**
- Consumes: nothing new — `FloatingActionButton.tooltip` is a built-in Flutter constructor parameter.
- Produces: nothing consumed by later tasks — this is the only task in the plan.

This is a single small, uniform change across two files (same one-line fix, same test shape in each) — implement both file's changes and both tests together as one unit, then run the full suite once.

- [ ] **Step 1: Write the failing tests**

Add this test to `test/widget/unified_inbox_screen_test.dart`, alongside the existing `testWidgets('shows a friendly empty-state placeholder ...')` block (same file, so it shares the `work`/`registerFallbackValue` fixtures already defined above in `main()`):

```dart
  testWidgets('compose FAB has a "Compose" tooltip for accessibility', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        accountsProvider.overrideWith(() => _FakeAccountsNotifier([work])),
        unifiedInboxProvider.overrideWith((ref) async => []),
        swipeActionConfigProvider.overrideWith(() => _FakeSwipeActionConfigNotifier(SwipeActionConfig.defaults)),
      ],
      child: const MaterialApp(home: UnifiedInboxScreen()),
    ));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Compose'), findsOneWidget);
  });
```

Add this test to `test/widget/folder_view_screen_test.dart`, alongside the existing `testWidgets('shows a friendly empty-state placeholder ...')` block (same file, shares the `accountId`/`inbox`/`sent`/`trash` fixtures already defined above in `main()`):

```dart
  testWidgets('compose FAB has a "Compose" tooltip for accessibility', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        foldersProvider.overrideWith((ref, id) async => [inbox, sent, trash]),
        messagesProvider.overrideWith((ref, folder) async => const []),
        swipeActionConfigProvider.overrideWith(() => _FakeSwipeActionConfigNotifier(SwipeActionConfig.defaults)),
      ],
      child: const MaterialApp(home: FolderViewScreen(accountId: accountId)),
    ));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Compose'), findsOneWidget);
  });
```

- [ ] **Step 2: Run both tests to verify they fail**

Run: `flutter test test/widget/unified_inbox_screen_test.dart test/widget/folder_view_screen_test.dart --plain-name "compose FAB has a \"Compose\" tooltip"`

Expected: both FAIL — `find.byTooltip('Compose')` finds zero widgets (neither `FloatingActionButton` currently sets `tooltip`).

- [ ] **Step 3: Add the tooltip to both FABs**

In `lib/screens/unified_inbox_screen.dart`, change:

```dart
      floatingActionButton: FloatingActionButton(
        onPressed: () => _compose(context, ref),
        child: const Icon(Icons.edit),
      ),
```

to:

```dart
      floatingActionButton: FloatingActionButton(
        onPressed: () => _compose(context, ref),
        tooltip: 'Compose',
        child: const Icon(Icons.edit),
      ),
```

In `lib/screens/folder_view_screen.dart`, change:

```dart
          : FloatingActionButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ComposeScreen(accountId: widget.accountId),
                ),
              ),
              child: const Icon(Icons.edit),
            ),
```

to:

```dart
          : FloatingActionButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ComposeScreen(accountId: widget.accountId),
                ),
              ),
              tooltip: 'Compose',
              child: const Icon(Icons.edit),
            ),
```

- [ ] **Step 4: Run both tests to verify they pass**

Run: `flutter test test/widget/unified_inbox_screen_test.dart test/widget/folder_view_screen_test.dart`

Expected: PASS — all tests in both files, including the two new ones.

- [ ] **Step 5: Run the full test suite**

Run: `flutter test`

Expected: PASS — no other test references these FABs' absence of a tooltip, so nothing else should be affected.

- [ ] **Step 6: Commit**

```bash
git add lib/screens/unified_inbox_screen.dart lib/screens/folder_view_screen.dart test/widget/unified_inbox_screen_test.dart test/widget/folder_view_screen_test.dart
git commit -m "fix: add 'Compose' tooltip/semantic label to both compose FABs"
```
