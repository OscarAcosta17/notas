import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'database_helper.dart';

class CloudSyncConfig {
  final String? folderPath;
  final String? githubToken;
  final String? gistId;
  final bool autoSyncEnabled;
  final String? lastSyncIso;

  const CloudSyncConfig({
    this.folderPath,
    this.githubToken,
    this.gistId,
    this.autoSyncEnabled = false,
    this.lastSyncIso,
  });

  bool get hasFolder => folderPath != null && folderPath!.trim().isNotEmpty;
  bool get hasGistAuth => githubToken != null && githubToken!.trim().isNotEmpty;
}

/// Obsidian-style multi-device synchronization service.
///
/// Packages SQLite academic data plus visual/app preferences into a portable
/// `notas_sync_bundle.json` file that syncs cleanly across Android and Desktop
/// via either a linked Cloud Folder (Google Drive Desktop / OneDrive / local)
/// or a private GitHub Secret Gist.
class CloudSyncService {
  static const String bundleFileName = 'notas_sync_bundle.json';
  static const int bundleFormatVersion = 1;

  static const _folderPathKey = 'sync_folder_path';
  static const _githubTokenKey = 'sync_github_token';
  static const _gistIdKey = 'sync_gist_id';
  static const _autoSyncKey = 'sync_auto_enabled';
  static const _lastSyncKey = 'sync_last_time';

  static const List<String> _syncedPrefKeys = [
    'isDarkMode',
    'useDynamicColor',
    'frostedGlassIntensity',
    'bottomNavStyle',
    'navLabelMode',
    'semesterSelectorStyle',
    'enableHorizontalSwipe',
    'surfaceStyle',
    'cardRadiusStyle',
    'subjectColorStyle',
    'hapticsEnabled',
    'escalaNotas',
    'notificationsEnabled',
    'minutosAntesClase',
    'horasAntesEvaluacion',
    'subjectViewMode',
    'isCompactList',
    'gridCrossAxisCount',
    'tertiaryColor',
    'last_semester_id',
  ];

  static Timer? _autoSyncTimer;
  static bool _isAutoSyncing = false;

  static bool get isAutoSyncHookAttached =>
      DatabaseHelper.onDatabaseMutated != null;

  static void initAutoSyncHook() {
    DatabaseHelper.onDatabaseMutated = scheduleAutoSync;
  }

  static void scheduleAutoSync() {
    _autoSyncTimer?.cancel();
    _autoSyncTimer = Timer(const Duration(seconds: 2), () {
      runAutoSyncIfEnabled();
    });
  }

  static Future<void> runAutoSyncIfEnabled() async {
    if (_isAutoSyncing) return;
    _isAutoSyncing = true;
    try {
      final config = await getConfig();
      if (!config.autoSyncEnabled) return;
      if (config.hasFolder) {
        await syncToFolder(config.folderPath);
      }
      if (config.hasGistAuth) {
        await uploadToGist();
      }
    } catch (e) {
      debugPrint('AutoSync omitido por error: $e');
    } finally {
      _isAutoSyncing = false;
    }
  }

  static Future<CloudSyncConfig> getConfig() async {
    final prefs = await SharedPreferences.getInstance();
    return CloudSyncConfig(
      folderPath: prefs.getString(_folderPathKey),
      githubToken: prefs.getString(_githubTokenKey),
      gistId: prefs.getString(_gistIdKey),
      autoSyncEnabled: prefs.getBool(_autoSyncKey) ?? false,
      lastSyncIso: prefs.getString(_lastSyncKey),
    );
  }

  static Future<void> setFolderPath(String? path) async {
    final prefs = await SharedPreferences.getInstance();
    if (path == null || path.trim().isEmpty) {
      await prefs.remove(_folderPathKey);
    } else {
      await prefs.setString(_folderPathKey, path.trim());
    }
  }

  static Future<void> setGithubCredentials({
    required String? token,
    String? gistId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    if (token == null || token.trim().isEmpty) {
      await prefs.remove(_githubTokenKey);
    } else {
      await prefs.setString(_githubTokenKey, token.trim());
    }
    if (gistId != null && gistId.trim().isNotEmpty) {
      await prefs.setString(_gistIdKey, gistId.trim());
    } else if (gistId != null) {
      await prefs.remove(_gistIdKey);
    }
  }

  static Future<void> setAutoSyncEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_autoSyncKey, enabled);
  }

  static Future<void> _recordLastSync() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastSyncKey, DateTime.now().toIso8601String());
  }

  static Future<Map<String, dynamic>> buildSyncBundle({
    Map<String, dynamic>? databaseOverride,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final Map<String, dynamic> settingsMap = {};
    for (final key in _syncedPrefKeys) {
      final val = prefs.get(key);
      if (val != null) {
        settingsMap[key] = val;
      }
    }

    final dbSnapshot =
        databaseOverride ?? await DatabaseHelper.instance.exportFullSnapshot();

    return {
      'formatVersion': bundleFormatVersion,
      'app': 'NotasApp',
      'platform': Platform.operatingSystem,
      'updatedAt': DateTime.now().toIso8601String(),
      'settings': settingsMap,
      'database': dbSnapshot,
    };
  }

  static Future<void> applySyncBundle(
    Map<String, dynamic> bundle, {
    bool restoreDatabase = true,
  }) async {
    if (!bundle.containsKey('database') && !bundle.containsKey('settings')) {
      throw const FormatException('El archivo no es un paquete válido de NotasApp.');
    }

    if (restoreDatabase && bundle['database'] is Map) {
      final dbMap = Map<String, dynamic>.from(bundle['database'] as Map);
      await DatabaseHelper.instance.restoreFullSnapshot(dbMap);
    }

    final prefs = await SharedPreferences.getInstance();
    final rawSettings = bundle['settings'];
    if (rawSettings is Map) {
      for (final key in _syncedPrefKeys) {
        if (!rawSettings.containsKey(key)) {
          if (key == 'tertiaryColor') {
            await prefs.remove(key);
          }
          continue;
        }
        final val = rawSettings[key];
        if (val is bool) {
          await prefs.setBool(key, val);
        } else if (val is int) {
          await prefs.setInt(key, val);
        } else if (val is double) {
          await prefs.setDouble(key, val);
        } else if (val is String) {
          await prefs.setString(key, val);
        }
      }
    }

    await _recordLastSync();
  }

  // --- Method 1: Local Synced Folder (Google Drive Desktop / OneDrive / Local) ---

  static Future<File> syncToFolder([String? customFolderPath]) async {
    final config = await getConfig();
    final folderPath = (customFolderPath ?? config.folderPath)?.trim();
    if (folderPath == null || folderPath.isEmpty) {
      throw Exception('No hay ninguna carpeta sincronizada configurada.');
    }

    final dir = Directory(folderPath);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    final bundle = await buildSyncBundle();
    const encoder = JsonEncoder.withIndent('  ');
    final targetFile = File(p.join(dir.path, bundleFileName));
    await targetFile.writeAsString(encoder.convert(bundle), encoding: utf8);
    await _recordLastSync();
    return targetFile;
  }

  static Future<Map<String, dynamic>> restoreFromFolder([
    String? customFolderPath,
  ]) async {
    final config = await getConfig();
    final folderPath = (customFolderPath ?? config.folderPath)?.trim();
    if (folderPath == null || folderPath.isEmpty) {
      throw Exception('No hay ninguna carpeta sincronizada configurada.');
    }

    final targetFile = File(p.join(folderPath, bundleFileName));
    if (!await targetFile.exists()) {
      throw Exception('No se encontró $bundleFileName en la carpeta seleccionada.');
    }

    final raw = await targetFile.readAsString(encoding: utf8);
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    await applySyncBundle(decoded);
    return decoded;
  }

  // --- Method 2: GitHub Private Secret Gist (Obsidian Git style) ---

  static Map<String, String> _githubHeaders(String token) => {
        'Authorization': 'Bearer $token',
        'Accept': 'application/vnd.github+json',
        'Content-Type': 'application/json',
        'X-GitHub-Api-Version': '2022-11-28',
      };

  static Future<String?> discoverExistingGistId(String token) async {
    final client = http.Client();
    try {
      final uri = Uri.parse('https://api.github.com/gists?per_page=100');
      final res = await client
          .get(uri, headers: _githubHeaders(token))
          .timeout(const Duration(seconds: 15));

      if (res.statusCode == 401 || res.statusCode == 403) {
        throw Exception('Token de GitHub inválido o sin permiso "gist".');
      }
      if (res.statusCode != 200) {
        throw Exception('Error consultando Gists (HTTP ${res.statusCode}).');
      }

      final list = jsonDecode(res.body) as List<dynamic>;
      for (final item in list) {
        if (item is Map<String, dynamic>) {
          final files = item['files'];
          if (files is Map && files.containsKey(bundleFileName)) {
            final id = item['id']?.toString();
            if (id != null && id.isNotEmpty) {
              return id;
            }
          }
        }
      }
      return null;
    } finally {
      client.close();
    }
  }

  static Future<String> uploadToGist() async {
    final config = await getConfig();
    final token = config.githubToken?.trim();
    if (token == null || token.isEmpty) {
      throw Exception('Configura primero tu Token de GitHub (con permiso gist).');
    }

    String? gistId = config.gistId?.trim();
    if (gistId == null || gistId.isEmpty) {
      gistId = await discoverExistingGistId(token);
      if (gistId != null) {
        await setGithubCredentials(token: token, gistId: gistId);
      }
    }

    final bundle = await buildSyncBundle();
    const encoder = JsonEncoder.withIndent('  ');
    final content = encoder.convert(bundle);

    final client = http.Client();
    try {
      final payload = jsonEncode({
        'description': 'NotasApp Cloud Sync (Privado)',
        'public': false,
        'files': {
          bundleFileName: {'content': content},
        },
      });

      final http.Response res;
      if (gistId != null && gistId.isNotEmpty) {
        res = await client
            .patch(
              Uri.parse('https://api.github.com/gists/$gistId'),
              headers: _githubHeaders(token),
              body: payload,
            )
            .timeout(const Duration(seconds: 20));
      } else {
        res = await client
            .post(
              Uri.parse('https://api.github.com/gists'),
              headers: _githubHeaders(token),
              body: payload,
            )
            .timeout(const Duration(seconds: 20));
      }

      if (res.statusCode == 401 || res.statusCode == 403) {
        throw Exception('Token sin permisos para escribir Gists (HTTP ${res.statusCode}).');
      }
      if (res.statusCode == 404 && gistId != null) {
        // Stored Gist ID no longer exists; recreate cleanly
        await setGithubCredentials(token: token, gistId: '');
        return await uploadToGist();
      }
      if (res.statusCode != 200 && res.statusCode != 201) {
        throw Exception('Error al subir a GitHub Gist (HTTP ${res.statusCode}).');
      }

      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final savedId = data['id']?.toString() ?? gistId ?? '';
      if (savedId.isNotEmpty) {
        await setGithubCredentials(token: token, gistId: savedId);
      }
      await _recordLastSync();
      return savedId;
    } finally {
      client.close();
    }
  }

  static Future<Map<String, dynamic>> downloadFromGist() async {
    final config = await getConfig();
    final token = config.githubToken?.trim();
    if (token == null || token.isEmpty) {
      throw Exception('Configura primero tu Token de GitHub (con permiso gist).');
    }

    String? gistId = config.gistId?.trim();
    if (gistId == null || gistId.isEmpty) {
      gistId = await discoverExistingGistId(token);
      if (gistId != null) {
        await setGithubCredentials(token: token, gistId: gistId);
      }
    }

    if (gistId == null || gistId.isEmpty) {
      throw Exception('No existe todavía ninguna copia en tu cuenta de GitHub Gist.');
    }

    final client = http.Client();
    try {
      final res = await client
          .get(
            Uri.parse('https://api.github.com/gists/$gistId'),
            headers: _githubHeaders(token),
          )
          .timeout(const Duration(seconds: 20));

      if (res.statusCode == 401 || res.statusCode == 403) {
        throw Exception('Token de GitHub inválido o expirado.');
      }
      if (res.statusCode != 200) {
        throw Exception('No se pudo leer el Gist (HTTP ${res.statusCode}).');
      }

      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final files = data['files'] as Map<String, dynamic>?;
      final entry = files?[bundleFileName] as Map<String, dynamic>?;
      if (entry == null) {
        throw Exception('El Gist no contiene $bundleFileName.');
      }

      String? rawJson = entry['content']?.toString();
      if (entry['truncated'] == true && entry['raw_url'] != null) {
        final rawRes = await client
            .get(Uri.parse(entry['raw_url'].toString()), headers: _githubHeaders(token))
            .timeout(const Duration(seconds: 20));
        if (rawRes.statusCode == 200) {
          rawJson = rawRes.body;
        }
      }

      if (rawJson == null || rawJson.trim().isEmpty) {
        throw Exception('La copia en la nube está vacía.');
      }

      final decoded = jsonDecode(rawJson) as Map<String, dynamic>;
      await applySyncBundle(decoded);
      return decoded;
    } finally {
      client.close();
    }
  }
}
