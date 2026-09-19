import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Wraps `PackageInfo.fromPlatform()` behind a provider — same reason
/// `documentsDirectoryProvider` wraps `getApplicationDocumentsDirectory()`:
/// its platform channel never settles under a widget test's async zone (no
/// real iOS/Android host), so tests override this with a fixed [PackageInfo]
/// instead of touching package_info_plus at all.
final packageInfoProvider = FutureProvider<PackageInfo>((ref) => PackageInfo.fromPlatform());
