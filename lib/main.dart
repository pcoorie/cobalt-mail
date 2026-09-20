import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app.dart';
import 'providers/theme_providers.dart';

Future<void> main() async {
  final widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  // Holds the native launch screen up past Flutter's first frame — without
  // this it's dismissed the instant that frame renders, which reads as far
  // too brief for a branded splash.
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);
  // Preloaded before the first frame so the persisted theme is available
  // synchronously — otherwise frame 1 renders ThemeMode.system and users who
  // overrode the OS theme see a flash of the wrong brightness.
  final prefs = await SharedPreferences.getInstance();
  runApp(
    ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: const ImapMailApp(),
    ),
  );
  Future.delayed(const Duration(seconds: 2), FlutterNativeSplash.remove);
}
