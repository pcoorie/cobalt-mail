import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'providers/account_providers.dart';
import 'providers/badge_providers.dart';
import 'providers/theme_providers.dart';
import 'providers/unified_inbox_providers.dart';
import 'screens/account_list_screen.dart';
import 'screens/account_email_screen.dart';
import 'screens/folder_view_screen.dart';
import 'theme/brand_colors.dart';

/// A solid, on-brand colored header for every screen's app bar (Gmail/
/// Outlook's full-saturation blue-header look). Uses `brandSeed` directly
/// rather than a scheme-derived tone so it stays the exact same blue as the
/// app icon in both light and dark mode.
AppBarTheme _appBarTheme() => const AppBarTheme(
  backgroundColor: brandSeed,
  foregroundColor: Colors.white,
);

class ImapMailApp extends ConsumerStatefulWidget {
  const ImapMailApp({super.key});

  @override
  ConsumerState<ImapMailApp> createState() => _ImapMailAppState();
}

class _ImapMailAppState extends ConsumerState<ImapMailApp> {
  @override
  void initState() {
    super.initState();
    // Foreground-only by design (see the design spec's Non-goals): this app
    // has no background sync, so the badge can only reflect the count as of
    // the last time the app was open. ref.listen only fires while this
    // widget is alive, which is exactly what makes that true without any
    // extra lifecycle plumbing. `ref.listen` is only usable inside `build`
    // (flutter_riverpod ^2.6.1) — `ref.listenManual` is the widget-lifecycle
    // counterpart meant for initState, and (unlike `ref.listen`) supports
    // `fireImmediately`. This registers the listener once for the app's
    // whole lifetime; the subscription is disposed automatically when this
    // widget is disposed, so no explicit cleanup is needed in `dispose()`.
    ref.listenManual<AsyncValue<int>>(totalUnreadCountProvider, (
      previous,
      next,
    ) {
      final count = next.valueOrNull;
      if (count != null) {
        ref.read(appIconBadgeProvider).setCount(count);
      }
    }, fireImmediately: true);
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeModeProvider);
    final lightScheme = ColorScheme.fromSeed(seedColor: brandSeed);
    final darkScheme = ColorScheme.fromSeed(
      seedColor: brandSeed,
      brightness: Brightness.dark,
    );
    return MaterialApp(
      title: 'Cobalt Mail',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: lightScheme,
        useMaterial3: true,
        appBarTheme: _appBarTheme(),
      ),
      darkTheme: ThemeData(
        colorScheme: darkScheme,
        useMaterial3: true,
        appBarTheme: _appBarTheme(),
      ),
      themeMode: themeMode,
      home: Consumer(
        builder: (context, ref, _) {
          final accountsAsync = ref.watch(accountsProvider);
          return accountsAsync.when(
            data: (accounts) => switch (accounts.length) {
              0 => const AccountEmailScreen(),
              1 => FolderViewScreen(accountId: accounts.single.id!),
              _ => const AccountListScreen(),
            },
            loading: () => const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            ),
            error: (error, _) => Scaffold(
              body: Center(child: Text('Failed to load accounts: $error')),
            ),
          );
        },
      ),
    );
  }
}
