# Compose FAB Has No Tooltip/Semantic Label — Design

Date: 2026-09-19
Status: Ready to implement
Issue: https://github.com/pcoorie/cobalt-mail/issues/11

## 1. Bug report

The floating action button (FAB) used to start composing a new message has
no tooltip, unlike every other icon-only action in the app.

## 2. Root cause

There are exactly two `FloatingActionButton`s in the app, both for compose,
and neither sets `tooltip`:

```dart
// lib/screens/unified_inbox_screen.dart:95-98
floatingActionButton: FloatingActionButton(
  onPressed: () => _compose(context, ref),
  child: const Icon(Icons.edit),
),
```

```dart
// lib/screens/folder_view_screen.dart:261-268
: FloatingActionButton(
    onPressed: () => Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ComposeScreen(accountId: widget.accountId),
      ),
    ),
    child: const Icon(Icons.edit),
  ),
```

Every other icon-only action in the app already sets `tooltip` — e.g.
`lib/screens/folder_view_screen.dart:196` (`'Show all messages'`/`'Show
unread only'`), `:223` (`'Cancel selection'`), `:230` (`'Move to folder'`),
`:235` (`'Delete'`), and `lib/screens/message_detail_screen.dart:254`
(`'Retry sending'`). The two compose FABs are the outliers.

## 3. Why it hurts the outcome

`FloatingActionButton.tooltip` is also what `Semantics` uses for the
button's accessibility label. Without it, VoiceOver/TalkBack announces the
button as an unlabeled "Button" instead of "Compose" — a real accessibility
gap on the app's single most-used action (starting a new email), and
inconsistent with every other icon action's own convention.

## 4. Desired behavior

Both compose FABs get `tooltip: 'Compose'`, matching the label
`ComposeScreen`'s own `AppBar` already uses (see
`test/widget/unified_inbox_screen_test.dart:184`, which asserts `find.text
('Compose')` for `ComposeScreen`'s app bar title) — so the label a screen
reader announces for the FAB matches the screen it opens.

## 5. Non-goals

- Not adding tooltips to any other widget — this issue is scoped to the two
  compose FABs named above.
- Not changing the FABs' icon, behavior, or placement.

## 6. Testing strategy

Widget tests pump each screen and assert `find.byTooltip('Compose')` finds
the FAB — `Tooltip` is how `FloatingActionButton.tooltip` is implemented
internally, so this exercises the real accessibility label a screen reader
would read, not just a hardcoded string check. One test per screen
(`test/widget/unified_inbox_screen_test.dart`,
`test/widget/folder_view_screen_test.dart`), reusing each file's existing
fixtures.

See the accompanying plan for the concrete steps.
