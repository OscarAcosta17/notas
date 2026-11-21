import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Manages app-scoped temporary files under a dedicated subdirectory so
/// cache inspection and clearing never touch shared OS temp folders (e.g. Windows %TEMP%).
class AppCacheService {
  static const String cacheFolderName = 'NotasApp_cache';

  /// Returns the app-scoped cache directory, creating it if needed.
  static Future<Directory> getCacheDirectory() async {
    final baseTemp = await getTemporaryDirectory();
    final cacheDir = Directory(p.join(baseTemp.path, cacheFolderName));
    if (!await cacheDir.exists()) {
      await cacheDir.create(recursive: true);
    }
    return cacheDir;
  }

  /// Calculates total bytes stored inside [cacheFolderName] asynchronously.
  static Future<int> calculateCacheSizeBytes() async {
    final cacheDir = await getCacheDirectory();
    if (!await cacheDir.exists()) return 0;

    int totalSize = 0;
    await for (final entity in cacheDir.list(recursive: true, followLinks: false)) {
      if (entity is File) {
        try {
          totalSize += await entity.length();
        } catch (_) {
          // Ignore individual inaccessible or deleted files.
        }
      }
    }
    return totalSize;
  }

  /// Deletes files inside [cacheFolderName] asynchronously without touching the parent temp folder.
  static Future<void> clearAppCache() async {
    final cacheDir = await getCacheDirectory();
    if (!await cacheDir.exists()) return;

    await for (final entity in cacheDir.list(recursive: true, followLinks: false)) {
      if (entity is File) {
        try {
          await entity.delete();
        } catch (_) {
          // Ignore locked/in-use files without aborting cleanup of remaining cache files.
        }
      }
    }
  }
}
