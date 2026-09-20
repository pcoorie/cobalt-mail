# Promote Drafts into the Primary Tab Row When It Has Messages — Design

Date: 2026-09-20
Status: Ready to implement
Issue: https://github.com/pcoorie/cobalt-mail/issues/10

## 1. Issue

`FolderViewScreen` only ever shows Inbox/Sent/Trash in the primary
`FolderTabBar` row. Every other folder — including Drafts — is hidden
behind the collapsed "More folders" disclosure (`FolderTreeExpander`,
`initiallyExpanded: false`). Drafts is a folder users expect to reach in
one tap, not a disclosure-then-scroll, especially since a user chasing a
lost compose draft has no obvious place to look for it otherwise.

## 2. Current behavior

`FolderViewScreen.build()` (`lib/screens/folder_view_screen.dart:272-280`)
and `_currentFolder` (`:56-68`) both build the primary row from a hardcoded
type list:

```dart
for (final type in [
  MailFolderType.inbox,
  MailFolderType.sent,
  MailFolderType.trash,
])
```

Everything else — Drafts included — falls into `rest` and only ever
renders inside `FolderTreeExpander`.

There is no `MailFolderType.drafts` today. `EnoughMailTransport._folderTypeFor`
(`lib/data/transport/enough_mail_transport.dart:75-81`) only recognizes
`isInbox`/`isSent`/`isTrash`/`isArchive`; a Drafts mailbox (`box.isDrafts`
in the vendored `enough_mail`, `third_party/enough_mail/lib/src/imap/mailbox.dart:254`)
falls through to `MailFolderType.other`, indistinguishable from any other
custom folder.

`MailFolder` also has no total-message-count field — only `unreadCount`,
which this app computes locally from cached rows
(`MailRepository._refreshUnreadCount`) and which is unreliable for Drafts:
messages sitting in Drafts are commonly already marked `\Seen` by
whichever client created them, so `unreadCount == 0` is not the same as
"no drafts."

## 3. Desired behavior

Promote Drafts into the primary tab row **only when the account's Drafts
folder actually contains at least one message** — not unconditionally
(that would show an empty Drafts tab for every account that has no
drafts, which is worse than today for the common case). Order:
Inbox, Sent, Drafts (when promoted), Trash. When not promoted, Drafts
stays exactly where it is today, inside "More folders."

This needs three things that don't exist yet:

1. A way to recognize a Drafts folder as its own type, not `other`.
2. A way to know its total message count without requiring the user to
   have already opened it once (the local per-folder message cache is
   only ever populated by opening a folder — see `messagesProvider`/
   `MailRepository.syncHeaders`, which only fetches for the folder
   currently being viewed).
3. The primary-row logic in `FolderViewScreen` reading that.

## 4. Design

### 4.1 New folder type

Add `drafts` to `MailFolderType` (`lib/models/enums.dart`):

```dart
enum MailFolderType { inbox, sent, drafts, trash, archive, other }
```

Stored as a `TEXT` column by `.name`/`.byName` (`MailFolder.toMap`/
`.fromMap`) — adding an enum value needs no column migration by itself.

`EnoughMailTransport._folderTypeFor` gets one more check, ordered next to
the other special-use flags:

```dart
if (box.isDrafts) return MailFolderType.drafts;
```

### 4.2 Message count, fetched without an extra sync for every folder

Add `messageCount` to `MailFolder` (default `0`), threaded through
`copyWith`/`toMap`/`fromMap`/`props` the same way `unreadCount` is today.
Doc comment on the field is explicit that it's only ever populated for
Drafts — see below for why, so a future reader doesn't assume it's a
general-purpose total for every folder.

`EnoughMailTransport.discoverFolders` already opens one `MailClient`
connection and calls `listMailboxes()`, which does not return message
counts (a plain IMAP `LIST` doesn't; only `SELECT`/`EXAMINE`/`STATUS` do).
Adding a `STATUS` call for *every* discovered folder would be exactly the
kind of extra per-folder IMAP round trip this app deliberately avoids
elsewhere (see `MailRepository._refreshUnreadCount`'s doc comment on why
`unreadCount` is computed locally instead of trusted from the transport).

Scoping the `STATUS` call to only the folder(s) typed `drafts` keeps that
property intact — one extra command, in the connection `discoverFolders`
already has open, only for the one folder this feature needs a count
for:

```dart
final lowLevel = client.lowLevelIncomingMailClient;
if (type == MailFolderType.drafts && lowLevel is enough.ImapClient) {
  final status = await lowLevel.statusMailbox(box, [enough.StatusFlags.messages]);
  messageCount = status.messagesExists;
}
```

`statusMailbox` issues IMAP `STATUS`, which per RFC 3501 does not change
the selected mailbox or affect any message's `\Recent` flag — safe to
call on a mailbox that isn't (and won't be) selected.

`FolderDao.upsert`'s update path already writes back the transport's
fresh value for every field it doesn't explicitly protect (it only
excludes `id`, `last_synced_uid`, and `unread_count` — those three are
locally-owned and must not be clobbered by the transport's default).
`message_count` is transport-owned instead — like `name`/`path`/`type` — so
no change needed there: every `syncFolders` call refreshes it.

### 4.3 Schema migration

`AppDatabase` version bumps 3 → 4:

```dart
// onCreate:
message_count INTEGER NOT NULL DEFAULT 0

// onUpgrade:
if (oldVersion < 4) {
  await db.execute('ALTER TABLE folders ADD COLUMN message_count INTEGER NOT NULL DEFAULT 0');
}
```

### 4.4 Primary row logic

`FolderViewScreen` currently duplicates the same hardcoded type list in
two places (`_currentFolder` and `build`). Factor out one helper both call,
rather than letting a third copy of the list drift in later:

```dart
List<MailFolderType> _primaryFolderTypes(List<MailFolder> folders) {
  final hasDrafts = folders.any(
    (f) => f.type == MailFolderType.drafts && f.messageCount > 0,
  );
  return [
    MailFolderType.inbox,
    MailFolderType.sent,
    if (hasDrafts) MailFolderType.drafts,
    MailFolderType.trash,
  ];
}
```

Both call sites replace their literal `[MailFolderType.inbox, ...]` list
with `_primaryFolderTypes(folders)`. No other change needed —
`FolderTreeExpander`'s `rest` list is already "everything not in
`defaults`," so a promoted Drafts folder disappears from "More folders"
automatically once it's in `defaults`.

## 5. Non-goals

- Not changing anything about how drafts are created, saved, or synced —
  this is purely about where the folder appears in the UI. The "no draft
  save on discard" bug the GitHub issue also mentions is a separate,
  unrelated fix.
- Not adding a general per-folder total-message-count feature — `messageCount`
  is deliberately scoped to Drafts only (see 4.2). Extending it to every
  folder would reintroduce the extra-sync cost this design avoids and
  isn't needed by anything today.
- Not adding "always show Drafts" as a user preference — the issue's own
  proposed fix offers that as an alternative, but conditional promotion
  is the more correct default and there's no evidence yet anyone wants
  the toggle.

## 6. Testing strategy

- **Model**: `MailFolder` round-trips `messageCount` through
  `toMap`/`fromMap`/`copyWith` (mirrors existing `unreadCount` coverage).
- **Migration**: `test/data/local/app_database_test.dart` gets the same
  two-test shape already used for `is_flagged`/`from_name` — an
  `onUpgrade` test (pre-v4 DB gets the column, existing rows keep their
  data) and an `onCreate` test (fresh DB already has it).
- **Screen**: `test/widget/folder_view_screen_test.dart` gets two new
  cases — Drafts with `messageCount: 0` stays behind "More folders"
  (`find.text('Drafts')` is `findsNothing` until expanded, mirroring the
  existing Archive case); Drafts with `messageCount > 0` shows up in the
  primary row immediately (`findsOneWidget` before any tap).
- **Transport (`EnoughMailTransport._folderTypeFor`/`discoverFolders`)**:
  not covered by an automated test, matching every other special-use
  mapping in that method today (`isInbox`/`isSent`/`isTrash`/`isArchive`
  have none either) — every existing test exercises `MailTransport` only
  through a hand-written fake/mock, never the real `enough_mail`-backed
  implementation. Verified manually instead: connect a real account whose
  Drafts folder has at least one message and confirm the tab appears;
  confirm an account with an empty (or absent) Drafts folder is
  unaffected.

See the accompanying plan for the concrete task breakdown.
