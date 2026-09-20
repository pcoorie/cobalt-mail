# Promote Drafts into the Primary Tab Row — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `FolderViewScreen` shows Drafts in its primary `FolderTabBar` row (alongside Inbox/Sent/Trash) whenever the account's Drafts folder actually has at least one message, instead of always hiding it behind "More folders."

**Architecture:** A new `MailFolderType.drafts` lets `EnoughMailTransport` recognize a Drafts mailbox instead of lumping it into `other`. A new `MailFolder.messageCount` field, populated only for Drafts via one scoped IMAP `STATUS` call inside `discoverFolders`'s existing connection, tells `FolderViewScreen` whether that folder is non-empty. `FolderViewScreen`'s two duplicate hardcoded primary-type lists become one shared helper that conditionally includes `drafts`.

**Tech Stack:** Flutter, Riverpod, `sqflite`/`sqflite_common_ffi`, vendored `enough_mail`, `flutter_test`.

**Spec:** `docs/superpowers/specs/2026-09-20-drafts-tab-promotion-design.md`

## Global Constraints

- Order when promoted: Inbox, Sent, Drafts, Trash.
- `messageCount` is populated only for the `drafts`-typed folder — not a general per-folder count (see spec §4.2/§5). Do not add a `STATUS` call for any other folder type.
- No changes to draft creation/saving, or to `FolderTreeExpander`'s rendering — a promoted Drafts folder disappears from "More folders" automatically because it's already excluded by id.
- `unread_count` and `last_synced_uid` stay locally-owned in `FolderDao.upsert` (unchanged); `message_count` is transport-owned and gets overwritten on every `syncFolders` call.

---

### Task 1: Model + schema — `MailFolderType.drafts` and `MailFolder.messageCount`

**Files:**
- Modify: `lib/models/enums.dart`
- Modify: `lib/models/mail_folder.dart`
- Modify: `lib/data/local/app_database.dart`
- Test: `test/data/local/app_database_test.dart`

**Interfaces:**
- Produces: `MailFolderType.drafts`; `MailFolder({..., this.messageCount = 0})`, threaded through `copyWith`/`toMap`/`fromMap`/`props`. Consumed by Task 2 (transport) and Task 3 (screen).

- [ ] **Step 1: Write the failing migration tests**

Add to `test/data/local/app_database_test.dart`, following the exact shape of the existing `from_name` tests (append inside `main()`, after the last test):

```dart
  test('onUpgrade from version 3 adds message_count without losing existing data', () async {
    final dir = await Directory.systemTemp.createTemp('imap_mail_migration_test');
    addTearDown(() => dir.delete(recursive: true));
    final path = p.join(dir.path, 'test.db');

    // Simulate a pre-migration (version 3) database using the schema
    // AppDatabase.onCreate produced before message_count existed.
    final oldDb = await databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 3,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE folders (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              account_id INTEGER NOT NULL,
              name TEXT NOT NULL,
              path TEXT NOT NULL,
              type TEXT NOT NULL,
              unread_count INTEGER NOT NULL DEFAULT 0,
              is_local_only INTEGER NOT NULL DEFAULT 0,
              last_synced_uid INTEGER NOT NULL DEFAULT 0
            )
          ''');
        },
      ),
    );
    final folderId = await oldDb.insert('folders', {
      'account_id': 1,
      'name': 'Drafts',
      'path': 'Drafts',
      'type': 'other',
    });
    await oldDb.close();

    final upgradedDb = await databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 4,
        onCreate: AppDatabase.onCreate,
        onUpgrade: AppDatabase.onUpgrade,
      ),
    );
    addTearDown(upgradedDb.close);

    final rows = await upgradedDb.query('folders', where: 'id = ?', whereArgs: [folderId]);
    expect(rows, hasLength(1));
    expect(rows.first['message_count'], 0);
    expect(rows.first['name'], 'Drafts');
  });

  test('a fresh (onCreate) database already has the message_count column', () async {
    final db = await databaseFactory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(version: 4, onCreate: AppDatabase.onCreate),
    );
    addTearDown(db.close);

    final folderId = await db.insert('folders', {
      'account_id': 1,
      'name': 'Drafts',
      'path': 'Drafts',
      'type': 'drafts',
      'unread_count': 0,
      'is_local_only': 0,
      'last_synced_uid': 0,
      'message_count': 3,
    });

    final rows = await db.query('folders', where: 'id = ?', whereArgs: [folderId]);
    expect(rows.first['message_count'], 3);
  });
```

- [ ] **Step 2: Run to verify they fail**

Run: `flutter test test/data/local/app_database_test.dart`

Expected: both new tests FAIL — `message_count` column doesn't exist yet (schema version is still 3), and `'drafts'` isn't a valid `MailFolderType` name yet.

- [ ] **Step 3: Implement**

In `lib/models/enums.dart`:

```dart
enum MailFolderType { inbox, sent, drafts, trash, archive, other }
```

In `lib/models/mail_folder.dart` — add the field, constructor param, `copyWith` param, `toMap`/`fromMap` entries, and `props` entry, mirroring exactly how `unreadCount` is threaded through today:

```dart
  const MailFolder({
    this.id,
    required this.accountId,
    required this.name,
    required this.path,
    required this.type,
    this.unreadCount = 0,
    // Only ever populated for a `drafts`-typed folder (see
    // EnoughMailTransport.discoverFolders) — a scoped IMAP STATUS call,
    // not a general per-folder total. Stays 0 for every other folder type;
    // don't read it expecting a real count elsewhere.
    this.messageCount = 0,
    this.isLocalOnly = false,
    this.lastSyncedUid = 0,
  });

  final int messageCount;
```

`copyWith`: add `int? messageCount` param, `messageCount: messageCount ?? this.messageCount`.

`toMap`: add `'message_count': messageCount,`.

`fromMap`: add `messageCount: (map['message_count'] as int?) ?? 0,` (nullable-defensive, matching `lastSyncedUid`'s own fallback).

`props`: append `messageCount`.

In `lib/data/local/app_database.dart`:

```dart
    await db.execute('''
      CREATE TABLE folders (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        account_id INTEGER NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
        name TEXT NOT NULL,
        path TEXT NOT NULL,
        type TEXT NOT NULL,
        unread_count INTEGER NOT NULL DEFAULT 0,
        is_local_only INTEGER NOT NULL DEFAULT 0,
        last_synced_uid INTEGER NOT NULL DEFAULT 0,
        message_count INTEGER NOT NULL DEFAULT 0,
        UNIQUE(account_id, path)
      )
    ''');
```

```dart
  static Future<void> onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('ALTER TABLE messages ADD COLUMN is_flagged INTEGER NOT NULL DEFAULT 0');
    }
    if (oldVersion < 3) {
      await db.execute('ALTER TABLE messages ADD COLUMN from_name TEXT');
    }
    if (oldVersion < 4) {
      // Backs Drafts-tab promotion (see FolderViewScreen) — total message
      // count, only ever populated for a drafts-typed folder.
      await db.execute('ALTER TABLE folders ADD COLUMN message_count INTEGER NOT NULL DEFAULT 0');
    }
  }
```

```dart
  static Future<Database> open() async {
    final dir = await getApplicationDocumentsDirectory();
    final path = p.join(dir.path, 'imap_mail.db');
    return openDatabase(
      path,
      version: 4,
      onCreate: onCreate,
      onUpgrade: onUpgrade,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
    );
  }
```

- [ ] **Step 4: Run to verify they pass**

Run: `flutter test test/data/local/app_database_test.dart`

Expected: PASS — all tests in the file, including the two new ones.

- [ ] **Step 5: Run the model/DAO-adjacent suite**

Run: `flutter test test/data/`

Expected: PASS — `MailFolder`'s added field is additive (default `0`, named param), so no existing fixture construction breaks.

---

### Task 2: Transport — recognize Drafts, fetch its message count

**Files:**
- Modify: `lib/data/transport/enough_mail_transport.dart`

**Interfaces:**
- Consumes: `MailFolderType.drafts`, `MailFolder.messageCount` (Task 1).
- Produces: `discoverFolders` now returns a `drafts`-typed `MailFolder` with a real `messageCount` when the account has one, consumed by Task 3.

No automated test for this task — see spec §6: every existing test exercises `MailTransport` only through a hand-written fake/mock, never `EnoughMailTransport` itself, and none of the other special-use mappings (`isInbox`/`isSent`/`isTrash`/`isArchive`) have coverage either. Verify manually per Step 2 below.

- [ ] **Step 1: Implement**

In `lib/data/transport/enough_mail_transport.dart`, add the Drafts check to `_folderTypeFor`:

```dart
  MailFolderType _folderTypeFor(enough.Mailbox box) {
    if (box.isInbox) return MailFolderType.inbox;
    if (box.isSent) return MailFolderType.sent;
    if (box.isDrafts) return MailFolderType.drafts;
    if (box.isTrash) return MailFolderType.trash;
    if (box.isArchive) return MailFolderType.archive;
    return MailFolderType.other;
  }
```

Change `discoverFolders` from a `.map()` to a loop so it can conditionally issue the `STATUS` call for exactly the Drafts folder(s):

```dart
  @override
  Future<List<MailFolder>> discoverFolders(
    MailAccount account,
    String password,
    int accountId,
  ) async {
    final client = enough.MailClient(_toEnoughAccount(account, password));
    try {
      await client.connect();
      final mailboxes = await client.listMailboxes();
      final folders = <MailFolder>[];
      for (final box in mailboxes) {
        final type = _folderTypeFor(box);
        var messageCount = 0;
        // Scoped to Drafts only — see MailFolder.messageCount's doc comment
        // for why this isn't done for every folder.
        if (type == MailFolderType.drafts) {
          final lowLevel = client.lowLevelIncomingMailClient;
          if (lowLevel is enough.ImapClient) {
            final status = await lowLevel.statusMailbox(box, [enough.StatusFlags.messages]);
            messageCount = status.messagesExists;
          }
        }
        folders.add(MailFolder(
          accountId: accountId,
          name: box.name,
          path: box.path,
          type: type,
          messageCount: messageCount,
        ));
      }
      return folders;
    } finally {
      await client.disconnect();
    }
  }
```

- [ ] **Step 2: Manual verification**

Against a real IMAP account:
- One whose Drafts folder has at least one message — confirm (via Task 3's UI, once implemented) the Drafts tab appears in the primary row.
- One whose Drafts folder is empty (or has no special-use Drafts mailbox at all) — confirm nothing changes from today's behavior.

- [ ] **Step 3: Run the full suite**

Run: `flutter test`

Expected: PASS — this task changes production code only; nothing in the existing suite calls the real `EnoughMailTransport`.

---

### Task 3: `FolderViewScreen` — conditional promotion

**Files:**
- Modify: `lib/screens/folder_view_screen.dart`
- Test: `test/widget/folder_view_screen_test.dart`

**Interfaces:**
- Consumes: `MailFolderType.drafts`, `MailFolder.messageCount` (Task 1).

- [ ] **Step 1: Write the failing tests**

Add to `test/widget/folder_view_screen_test.dart`, alongside the existing `'shows Inbox/Sent/Trash by default, Archive hidden until expanded'` test (same file, reuses its `inbox`/`sent`/`trash` fixtures):

```dart
  testWidgets('keeps an empty Drafts folder behind "More folders"', (tester) async {
    final drafts = MailFolder(
      id: 5, accountId: accountId, name: 'Drafts', path: 'Drafts',
      type: MailFolderType.drafts, messageCount: 0,
    );
    await tester.pumpWidget(ProviderScope(
      overrides: [
        foldersProvider.overrideWith((ref, id) async => [inbox, sent, trash, drafts]),
        messagesProvider.overrideWith((ref, folder) async => const []),
        swipeActionConfigProvider.overrideWith(() => _FakeSwipeActionConfigNotifier(SwipeActionConfig.defaults)),
      ],
      child: const MaterialApp(home: FolderViewScreen(accountId: accountId)),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Drafts'), findsNothing);

    await tester.tap(find.text('More folders'));
    await tester.pumpAndSettle();

    expect(find.text('Drafts'), findsOneWidget);
  });

  testWidgets('promotes Drafts into the primary tab row when it has messages', (tester) async {
    final drafts = MailFolder(
      id: 5, accountId: accountId, name: 'Drafts', path: 'Drafts',
      type: MailFolderType.drafts, messageCount: 2,
    );
    await tester.pumpWidget(ProviderScope(
      overrides: [
        foldersProvider.overrideWith((ref, id) async => [inbox, sent, trash, drafts]),
        messagesProvider.overrideWith((ref, folder) async => const []),
        swipeActionConfigProvider.overrideWith(() => _FakeSwipeActionConfigNotifier(SwipeActionConfig.defaults)),
      ],
      child: const MaterialApp(home: FolderViewScreen(accountId: accountId)),
    ));
    await tester.pumpAndSettle();

    // Visible immediately — no "More folders" tap needed.
    expect(find.text('Drafts'), findsOneWidget);
  });
```

- [ ] **Step 2: Run to verify they fail**

Run: `flutter test test/widget/folder_view_screen_test.dart --plain-name "Drafts"`

Expected: both FAIL — `MailFolderType.drafts` doesn't exist yet (compile error) until Task 1 lands; once Task 1 is in, both fail on assertion (`'promotes Drafts...'` finds nothing since the type list is still hardcoded to inbox/sent/trash).

- [ ] **Step 3: Implement**

In `lib/screens/folder_view_screen.dart`, add a shared helper near `_currentFolder`:

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

Replace both hardcoded lists with calls to it. In `_currentFolder`:

```dart
  MailFolder? _currentFolder(List<MailFolder>? folders) {
    if (folders == null) return null;
    final defaults = <MailFolder>[
      for (final type in _primaryFolderTypes(folders))
        ...folders.where((f) => f.type == type),
    ];
    return _selected ??
        (defaults.isNotEmpty ? defaults.first : (folders.isNotEmpty ? folders.first : null));
  }
```

In `build`'s `data:` branch:

```dart
          final defaults = <MailFolder>[
            for (final type in _primaryFolderTypes(folders))
              for (final f in folders.where((f) => f.type == type))
                f.copyWith(unreadCount: localUnreadCounts[f.id] ?? f.unreadCount),
          ];
```

- [ ] **Step 4: Run to verify they pass**

Run: `flutter test test/widget/folder_view_screen_test.dart`

Expected: PASS — all tests in the file, including the two new ones and the pre-existing Archive case (unaffected — Archive is still `other`, still only ever in `rest`).

- [ ] **Step 5: Run the full suite**

Run: `flutter test`

Expected: PASS.

---

### Task 4: Commit

- [ ] **Step 1: Commit**

```bash
git add lib/models/enums.dart lib/models/mail_folder.dart lib/data/local/app_database.dart \
        lib/data/transport/enough_mail_transport.dart lib/screens/folder_view_screen.dart \
        test/data/local/app_database_test.dart test/widget/folder_view_screen_test.dart
git commit -m "feat: promote Drafts into the primary tab row when it has messages (#10)"
```
