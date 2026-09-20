# Compose Discard Protection Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Leaving `ComposeScreen` (back button, system back gesture) while there's unsaved content shows a "Discard this message?" confirmation instead of silently destroying the draft; leaving with nothing unsaved — including an unedited reply/forward — still pops immediately.

**Architecture:** One `PopScope` wraps `ComposeScreen`'s `Scaffold`, gated on a `_hasUnsavedContent` getter that compares `to`/`subject`/`body` against the values they were initialized with (not against blank), so pre-filled replies/forwards don't false-positive. `_send()`'s existing `Navigator.pop()` call is untouched — it's an imperative pop, which `PopScope.canPop` never intercepts (only `Navigator.maybePop()`, which the `AppBar` back button and system back gesture use).

**Tech Stack:** Flutter (`PopScope`), `flutter_test`.

**Spec:** `docs/superpowers/specs/2026-09-20-compose-discard-protection-design.md`

## Global Constraints

- Dialog text: title `'Discard this message?'`, content `'Your unsent message will be lost.'`, actions `Cancel`/`Discard` — matches the existing delete-confirmation dialog's shape (`message_detail_screen.dart`).
- `_hasUnsavedContent` compares `to`/`subject`/`body` to their `initState`-time values, not to empty — see spec §4.2. `cc`/`bcc`/attachments use a plain non-empty check (they never start pre-filled).
- No changes to `_send()`'s pop call, and no new flag/state needed for "just sent" — confirmed unnecessary per spec §4.1.

---

### Task 1: `PopScope` + discard confirmation on `ComposeScreen`

**Files:**
- Modify: `lib/screens/compose_screen.dart`
- Test: `test/widget/compose_screen_test.dart`

**Interfaces:**
- Produces: nothing consumed elsewhere — self-contained to this screen.

- [ ] **Step 1: Write the failing tests**

Add to `test/widget/compose_screen_test.dart`. These push `ComposeScreen`
onto a real stack (existing tests use it as `MaterialApp.home` directly,
which can't demonstrate a pop being blocked — there's nothing to pop
back to). Add this helper near `_growViewport` and use it in place of
the plain `MaterialApp(home: ComposeScreen(...))` pump for these four
new tests only — existing tests are unaffected and stay as they are:

```dart
Future<void> _pumpPushedComposeScreen(
  WidgetTester tester, {
  MailMessage? replyTo,
  MailMessage? forwardOf,
}) async {
  await tester.pumpWidget(ProviderScope(
    child: MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => ComposeScreen(accountId: 1, replyTo: replyTo, forwardOf: forwardOf),
              )),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}
```

Then, alongside the existing `'Send is disabled until a recipient and body are entered'` test (same file, same `main()`):

```dart
  testWidgets('pops immediately when leaving a blank new compose', (tester) async {
    _growViewport(tester);
    await _pumpPushedComposeScreen(tester);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    expect(find.text('Discard this message?'), findsNothing);
    expect(find.byType(ComposeScreen), findsNothing);
  });

  testWidgets('shows a discard confirmation when leaving with unsaved content', (tester) async {
    _growViewport(tester);
    await _pumpPushedComposeScreen(tester);

    await tester.enterText(find.byKey(const Key('bodyField')), 'Hello Bob');
    await tester.pump();
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    expect(find.text('Discard this message?'), findsOneWidget);
    // Cancel keeps the screen and its content.
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.byType(ComposeScreen), findsOneWidget);
    expect(find.text('Hello Bob'), findsOneWidget);
  });

  testWidgets('discarding via the confirmation pops the screen', (tester) async {
    _growViewport(tester);
    await _pumpPushedComposeScreen(tester);

    await tester.enterText(find.byKey(const Key('bodyField')), 'Hello Bob');
    await tester.pump();
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();

    expect(find.byType(ComposeScreen), findsNothing);
  });

  testWidgets('an unedited reply pops immediately — prefilled fields are not "unsaved content"', (tester) async {
    _growViewport(tester);
    await _pumpPushedComposeScreen(tester, replyTo: message);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    expect(find.text('Discard this message?'), findsNothing);
    expect(find.byType(ComposeScreen), findsNothing);
  });

  testWidgets('editing a prefilled reply field does show the discard confirmation', (tester) async {
    _growViewport(tester);
    await _pumpPushedComposeScreen(tester, replyTo: message);

    await tester.enterText(find.byKey(const Key('subjectField')), 'Re: Hello (edited)');
    await tester.pump();
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    expect(find.text('Discard this message?'), findsOneWidget);
  });
```

(`message` is the file's existing top-level fixture, already
`registerFallbackValue`'d in `setUpAll`.)

- [ ] **Step 2: Run to verify they fail**

Run: `flutter test test/widget/compose_screen_test.dart`

Expected: the five new tests FAIL (no `PopScope` yet, so the back button
pops immediately every time and no dialog ever appears); all pre-existing
tests in the file still PASS unchanged.

- [ ] **Step 3: Implement**

In `lib/screens/compose_screen.dart`, capture the initial values in
`_ComposeScreenState` (right after the existing field declarations):

```dart
  late final String _initialTo = _to.text.trim();
  late final String _initialSubject = _subject.text.trim();
  late final String _initialBody = _body.text.trim();
```

`late final ... = expr` initializers run in declaration order the first
time the field is read, which for these is after `initState` has set up
`_to`/`_subject`/`_body` — but to keep the ordering obviously correct
rather than relying on that, initialize them explicitly at the end of
`initState` instead:

```dart
  late String _initialTo;
  late String _initialSubject;
  late String _initialBody;

  @override
  void initState() {
    super.initState();
    final source = widget.replyTo ?? widget.forwardOf;
    _to = TextEditingController(text: widget.replyTo?.from ?? '');
    _subject = TextEditingController(
      text: source == null
          ? ''
          : widget.replyTo != null
              ? 'Re: ${source.subject}'
              : 'Fwd: ${source.subject}',
    );
    _body = TextEditingController(
      text: widget.forwardOf != null ? '\n\n---\n${_quotedBody(widget.forwardOf!)}' : '',
    );
    _initialTo = _to.text.trim();
    _initialSubject = _subject.text.trim();
    _initialBody = _body.text.trim();
    for (final controller in [_to, _cc, _bcc, _subject, _body]) {
      controller.addListener(() => setState(() {}));
    }
  }
```

Add the getter, near `_isValid`:

```dart
  bool get _hasUnsavedContent =>
      _to.text.trim() != _initialTo ||
      _subject.text.trim() != _initialSubject ||
      _body.text.trim() != _initialBody ||
      _cc.text.trim().isNotEmpty ||
      _bcc.text.trim().isNotEmpty ||
      _attachmentPaths.isNotEmpty;

  Future<bool> _confirmDiscard() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Discard this message?'),
        content: const Text('Your unsent message will be lost.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Discard')),
        ],
      ),
    );
    return confirmed == true;
  }
```

Wrap `build`'s return value:

```dart
  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_hasUnsavedContent,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final confirmed = await _confirmDiscard();
        if (confirmed && mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Compose')),
        // ...unchanged...
      ),
    );
  }
```

- [ ] **Step 4: Run to verify they pass**

Run: `flutter test test/widget/compose_screen_test.dart`

Expected: PASS — all tests in the file, including the five new ones.

- [ ] **Step 5: Run the full suite**

Run: `flutter test`

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/screens/compose_screen.dart test/widget/compose_screen_test.dart
git commit -m "fix: confirm before discarding an in-progress compose (#6)"
```
