# Compose Has No Discard Protection — Design

Date: 2026-09-20
Status: Ready to implement
Issue: https://github.com/pcoorie/cobalt-mail/issues/6

## 1. Bug report

`ComposeScreen` is a plain `Scaffold` with a default `AppBar` back arrow.
Nothing intercepts a pop — no `PopScope`/`WillPopScope` anywhere in the
codebase. The back button, the system back gesture, and (once
[#10](https://github.com/pcoorie/cobalt-mail/issues/10)'s Drafts-tab work
is in) any other way off the screen all silently destroy an in-progress
email with no confirmation and no fallback, since Cobalt has no draft-save
feature at all yet. This is the "related drafts problem": issue #10 is
about finding drafts that already exist; this issue is about not losing
one in the first place.

## 2. Why it hurts the outcome

Losing a half-written email to an accidental back-swipe is one of the
most reliable ways to generate a 1-star review — "app ate my email" — and
there's currently no recovery path once it happens. Priority: Blocker.

## 3. Desired behavior

Leaving `ComposeScreen` (back button, system back gesture, or edge-swipe)
while there's unsaved content shows a "Discard this message?" confirmation
before popping. Confirming pops; canceling stays on the screen with every
field untouched. Leaving with nothing unsaved (a blank new compose, or a
reply/forward the user hasn't actually edited — see 4.2) pops immediately,
same as today.

The issue's own suggested fix is a confirmation only, not full draft
persistence ("Persisting an actual draft is the better fix but the
confirmation alone closes the acute risk") — that's the scope here.
Draft persistence is tracked separately.

## 4. Design

### 4.1 `PopScope`, not an `AppBar` back-button override

`PopScope` (not `WillPopScope`, which it replaced) wraps the screen's
`Scaffold`. It intercepts every pop attempt that goes through
`Navigator.maybePop` — which is what both the default `AppBar` back
button (`BackButtonIcon`'s `_onPressedCallback` calls
`Navigator.maybePop`) and the system back gesture/predictive-back use.
One primitive covers everything the issue's two suggested options
(`PopScope` "or" intercepting the `AppBar` back button) were trying to
cover separately.

Confirmed against the installed Flutter (3.47.4) framework source
(`packages/flutter/lib/src/widgets/navigator.dart`): `Navigator.pop()` —
the *imperative* call `_send()` already makes on a successful send
(`compose_screen.dart:207`) — is unconditional and does **not** consult
`PopScope.canPop` at all; only `Navigator.maybePop()` does. So the
existing post-send `Navigator.of(context).pop()` keeps working exactly as
it does today, with no special-casing needed for "just sent" — it was
never going to be intercepted in the first place.

```dart
return PopScope(
  canPop: !_hasUnsavedContent,
  onPopInvokedWithResult: (didPop, result) async {
    if (didPop) return;
    final confirmed = await _confirmDiscard();
    if (confirmed && mounted) Navigator.of(context).pop();
  },
  child: Scaffold(...),
);
```

`_confirmDiscard` mirrors the existing `showDialog<bool>`/`AlertDialog`
pattern already used for delete confirmation
(`message_detail_screen.dart:131-142`) and account-removal confirmation
(`settings_screen.dart`) — same shape, same Cancel/action button pair, so
this doesn't introduce a new confirmation-dialog idiom to the app:

```dart
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

### 4.2 "Has content" must be a dirty-check, not a blank-check

The issue's suggested condition — "if `_to`/`_subject`/`_body` have
content" — is correct for a brand-new compose (all three start empty),
but `ComposeScreen` also opens pre-filled for replies (`_to`, `_subject`)
and forwards (`_subject`, `_body` — the quoted original), set in
`initState` (`compose_screen.dart:99-109`). A plain non-empty check would
show "Discard this message?" the instant a user opens a reply and taps
back without typing anything — every reply/forward becomes an extra
confirmation tap for nothing actually written. That's a real regression
this design has to avoid, not carry over from the issue's literal wording.

Fix: snapshot the pre-filled values once in `initState`, and compare
current-vs-initial instead of current-vs-empty for exactly the three
fields that can start non-empty:

```dart
late final String _initialTo = _to.text.trim();
late final String _initialSubject = _subject.text.trim();
late final String _initialBody = _body.text.trim();

bool get _hasUnsavedContent =>
    _to.text.trim() != _initialTo ||
    _subject.text.trim() != _initialSubject ||
    _body.text.trim() != _initialBody ||
    _cc.text.trim().isNotEmpty ||
    _bcc.text.trim().isNotEmpty ||
    _attachmentPaths.isNotEmpty;
```

`_cc`/`_bcc`/`_attachmentPaths` always start empty regardless of
reply/forward, so a plain non-empty/non-blank check is already correct
for those three — only `_to`/`_subject`/`_body` need the initial-value
comparison.

The existing `controller.addListener(() => setState(() {}))` loop
(`:110-112`) already rebuilds on every keystroke in all five text
controllers, so `canPop`'s value passed to `PopScope` is always current by
the time the user actually attempts to leave — no additional listener
plumbing needed.

## 5. Non-goals

- No draft persistence. This is the confirmation-only mitigation the
  issue itself scopes as sufficient for the acute risk; saving a real
  draft is separate follow-up work (and would want to reuse
  [#10](https://github.com/pcoorie/cobalt-mail/issues/10)'s new
  `MailFolderType.drafts`, once that lands).
- `_includeOriginalAttachments` (the forward-attachments checkbox)
  toggling alone doesn't count toward "unsaved content." Unchecking it
  and leaving loses no typed content — only reverts a checkbox default —
  so prompting for that alone would be more annoying than protective.
- No "always confirm" mode or user preference — matches the issue's ask,
  no evidence anyone wants a toggle for this.

## 6. Testing strategy

Widget tests against `ComposeScreen`, pushed onto a real route stack
(unlike its existing tests, which use it directly as `MaterialApp.home`
— that's fine for form-field assertions, but a screen with no route
underneath it can't demonstrate a pop being blocked/allowed, so these new
tests specifically need a pushable stack):

- Leaving a blank new compose pops immediately, no dialog.
- Typing into the body (or to/subject/cc/bcc, or adding an attachment)
  then tapping back shows "Discard this message?"; Cancel keeps the
  screen and its content; Discard pops.
- Opening a reply or forward (pre-filled `to`/`subject`/`body`) and
  tapping back **without editing anything** pops immediately, no dialog
  — the regression case from §4.2.
- Editing a pre-filled reply/forward field, then backing out, does show
  the dialog.
- The existing "plays after a successful send" / "shows an inline error"
  tests are unaffected — `_send()`'s own `Navigator.pop()` call was never
  going through `PopScope` in the first place (§4.1), so no changes
  needed there; re-run as regression coverage, not new assertions.

See the accompanying plan for the concrete task breakdown.
