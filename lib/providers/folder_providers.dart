import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/mail_folder.dart';
import 'account_providers.dart';
import 'repository_providers.dart';
import 'sync_status_providers.dart';

final foldersProvider = FutureProvider.family<List<MailFolder>, int>((ref, accountId) async {
  final repository = await ref.watch(mailRepositoryProvider.future);
  final accounts = await ref.watch(accountsProvider.future);
  final account = accounts.firstWhere((a) => a.id == accountId);
  try {
    final folders = await repository.syncFolders(account);
    ref.read(syncErrorProvider(accountId).notifier).state = null;
    return folders;
  } catch (e) {
    final cached = await repository.getCachedFolders(accountId);
    if (cached.isEmpty) rethrow;
    ref.read(syncErrorProvider(accountId).notifier).state = e.toString();
    return cached;
  }
});

/// Fresh per-folder unread counts for [accountId], keyed by folder id.
///
/// `foldersProvider`'s own `MailFolder.unreadCount` goes stale the same way
/// `totalUnreadCountProvider`'s did (see `unreadCountRefreshTickProvider`'s
/// doc comment): `foldersProvider` is a cached FutureProvider that only
/// re-runs when explicitly invalidated, and nothing about a mark-read/
/// unread, archive, delete, or move tells it the local `unread_count`
/// column it read earlier has since changed underneath it — e.g. reading a
/// message via `MessageDetailScreen` updates the column but never
/// invalidates `foldersProvider`. Reading straight from
/// `MailRepository.getCachedFolders` instead is a plain local DB query — no
/// IMAP round trip — and `unreadCountRefreshTickProvider` is what tells this
/// provider *when* to re-read it. Consumers that render an unread badge
/// (e.g. `FolderTabBar`) should overlay this onto whatever `MailFolder` list
/// they already have rather than trusting its `unreadCount` field directly.
final localFolderUnreadCountsProvider =
    FutureProvider.family<Map<int, int>, int>((ref, accountId) async {
  ref.watch(unreadCountRefreshTickProvider);
  final repository = await ref.watch(mailRepositoryProvider.future);
  final folders = await repository.getCachedFolders(accountId);
  return {
    for (final folder in folders)
      if (folder.id != null) folder.id!: folder.unreadCount,
  };
});
