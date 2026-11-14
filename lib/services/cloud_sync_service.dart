import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'database_helper.dart';

enum DriveSyncState {
  unconfigured,
  syncing,
  synced,
  tokenExpired,
  error,
}

class DriveSyncStatus {
  final DriveSyncState state;
  final String? lastSyncIso;
  final String? message;

  const DriveSyncStatus({
    this.state = DriveSyncState.unconfigured,
    this.lastSyncIso,
    this.message,
  });

  bool get isConfigured => state != DriveSyncState.unconfigured;
  bool get isExpired => state == DriveSyncState.tokenExpired;
  bool get isError => state == DriveSyncState.error;
}

class GoogleDriveTokenExpiredException implements Exception {
  final String message;
  const GoogleDriveTokenExpiredException(this.message);
  @override
  String toString() => message;
}

class CloudSyncConfig {
  final String? folderPath;
  final String? githubToken;
  final String? gistId;
  final String? googleDriveRefreshToken;
  final String? googleDriveFolderId;
  final String? googleDriveFileId;
  final String? googleDriveClientId;
  final String? googleDriveClientSecret;
  final String? googleDriveTokenUrl;
  final bool autoSyncEnabled;
  final String? lastSyncIso;

  const CloudSyncConfig({
    this.folderPath,
    this.githubToken,
    this.gistId,
    this.googleDriveRefreshToken,
    this.googleDriveFolderId,
    this.googleDriveFileId,
    this.googleDriveClientId,
    this.googleDriveClientSecret,
    this.googleDriveTokenUrl,
    this.autoSyncEnabled = false,
    this.lastSyncIso,
  });

  bool get hasFolder => folderPath != null && folderPath!.trim().isNotEmpty;
  bool get hasGistAuth => githubToken != null && githubToken!.trim().isNotEmpty;
  bool get hasGoogleDriveAuth =>
      googleDriveRefreshToken != null && googleDriveRefreshToken!.trim().isNotEmpty;
}

/// Obsidian-style multi-device synchronization service.
///
/// Packages SQLite academic data plus visual/app preferences into a portable
/// `notas_sync_bundle.json` file that syncs cleanly across Android and Desktop
/// via Google Drive (Obsidian-Google-Drive protocol), a private GitHub Gist, or
/// a linked Cloud Folder.
class CloudSyncService {
  static const String bundleFileName = 'notas_sync_bundle.json';
  static const int bundleFormatVersion = 1;
  static const String ogdAuthPortalUrl = 'https://ogd.richardxiong.com';
  static const String ogdDefaultTokenServerUrl =
      'https://ogd-server.richardxiong.com/api/access';
  static const String driveVaultName = 'NotasApp';

  static const _folderPathKey = 'sync_folder_path';
  static const _githubTokenKey = 'sync_github_token';
  static const _gistIdKey = 'sync_gist_id';
  static const _gdriveRefreshTokenKey = 'sync_gdrive_refresh_token';
  static const _gdriveFolderIdKey = 'sync_gdrive_folder_id';
  static const _gdriveFileIdKey = 'sync_gdrive_file_id';
  static const _gdriveClientIdKey = 'sync_gdrive_client_id';
  static const _gdriveClientSecretKey = 'sync_gdrive_client_secret';
  static const _gdriveTokenUrlKey = 'sync_gdrive_token_url';
  static const _gdriveTokenExpiredKey = 'sync_gdrive_token_expired';
  static const _gdriveLastErrorKey = 'sync_gdrive_last_error';
  static const _autoSyncKey = 'sync_auto_enabled';
  static const _lastSyncKey = 'sync_last_time';

  static final ValueNotifier<DriveSyncStatus> driveStatusNotifier =
      ValueNotifier<DriveSyncStatus>(const DriveSyncStatus());

  static String? _cachedDriveAccessToken;
  static int _cachedDriveTokenExpiresAtMs = 0;

  static Future<DriveSyncStatus> refreshStatusNotifier({
    DriveSyncState? overrideState,
    String? overrideMessage,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final cfg = await getConfig();
    final expired = prefs.getBool(_gdriveTokenExpiredKey) ?? false;
    final lastError = prefs.getString(_gdriveLastErrorKey);

    late DriveSyncStatus status;
    if (!cfg.hasGoogleDriveAuth) {
      status = const DriveSyncStatus(state: DriveSyncState.unconfigured);
    } else if (overrideState != null) {
      status = DriveSyncStatus(
        state: overrideState,
        lastSyncIso: cfg.lastSyncIso,
        message: overrideMessage,
      );
    } else if (expired) {
      status = DriveSyncStatus(
        state: DriveSyncState.tokenExpired,
        lastSyncIso: cfg.lastSyncIso,
        message: lastError ??
            'Tu token de Google Drive expiró. Toca para renovarlo.',
      );
    } else if (lastError != null && lastError.isNotEmpty) {
      status = DriveSyncStatus(
        state: DriveSyncState.error,
        lastSyncIso: cfg.lastSyncIso,
        message: lastError,
      );
    } else {
      status = DriveSyncStatus(
        state: DriveSyncState.synced,
        lastSyncIso: cfg.lastSyncIso,
        message: cfg.lastSyncIso != null
            ? 'Sincronizado con Google Drive'
            : 'Conectado a Google Drive',
      );
    }

    driveStatusNotifier.value = status;
    return status;
  }

  static Future<void> markDriveTokenExpired(String reason) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_gdriveTokenExpiredKey, true);
    await prefs.setString(_gdriveLastErrorKey, reason);
    await refreshStatusNotifier();
  }

  static Future<void> _clearDriveError() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_gdriveTokenExpiredKey);
    await prefs.remove(_gdriveLastErrorKey);
  }

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
    'aula_token',
    'aula_moodle_session',
    'aula_sesskey',
    'aula_user_name',
    'aula_user_id',
    'aula_course_folders',
    'aula_course_subfolders',
    'aula_course_org_sections',
    'aula_hidden_courses',
    'aula_course_ramo_links',
    'aula_notify_new_files',
    'aula_notify_deadlines',
    'aula_notify_deadline_hours',
    'settings_course_folders',
    'settings_course_subfolders',
    'settings_course_org_section',
    'hidden_courses_json',
    'settings_default_subfolder',
    'settings_org_section',
    'settings_skip_downloaded',
    'settings_auto_export_links',
    'settings_auto_export_forums',
    'settings_preferred_extensions',
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
      if (config.hasGoogleDriveAuth) {
        await uploadToGoogleDrive();
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
      googleDriveRefreshToken: prefs.getString(_gdriveRefreshTokenKey),
      googleDriveFolderId: prefs.getString(_gdriveFolderIdKey),
      googleDriveFileId: prefs.getString(_gdriveFileIdKey),
      googleDriveClientId: prefs.getString(_gdriveClientIdKey),
      googleDriveClientSecret: prefs.getString(_gdriveClientSecretKey),
      googleDriveTokenUrl: prefs.getString(_gdriveTokenUrlKey),
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

  static Future<void> setGoogleDriveCredentials({
    required String? refreshToken,
    String? clientId,
    String? clientSecret,
    String? tokenUrl,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    _cachedDriveAccessToken = null;
    _cachedDriveTokenExpiresAtMs = 0;

    if (refreshToken == null || refreshToken.trim().isEmpty) {
      await prefs.remove(_gdriveRefreshTokenKey);
      await prefs.remove(_gdriveFolderIdKey);
      await prefs.remove(_gdriveFileIdKey);
    } else {
      await prefs.setString(_gdriveRefreshTokenKey, refreshToken.trim());
    }

    if (clientId != null) {
      if (clientId.trim().isEmpty) {
        await prefs.remove(_gdriveClientIdKey);
      } else {
        await prefs.setString(_gdriveClientIdKey, clientId.trim());
      }
    }

    if (clientSecret != null) {
      if (clientSecret.trim().isEmpty) {
        await prefs.remove(_gdriveClientSecretKey);
      } else {
        await prefs.setString(_gdriveClientSecretKey, clientSecret.trim());
      }
    }

    if (tokenUrl != null) {
      if (tokenUrl.trim().isEmpty) {
        await prefs.remove(_gdriveTokenUrlKey);
      } else {
        await prefs.setString(_gdriveTokenUrlKey, tokenUrl.trim());
      }
    }

    await _clearDriveError();
    await refreshStatusNotifier();
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

  // --- Method 3: Google Drive Direct Sync (Obsidian-Google-Drive protocol) ---

  static String _escapeDriveQuery(String value) =>
      value.replaceAll('\\', '\\\\').replaceAll("'", "\\'");

  static Future<String> refreshGoogleDriveAccessToken([
    String? customRefreshToken,
  ]) async {
    final config = await getConfig();
    final refreshToken =
        (customRefreshToken ?? config.googleDriveRefreshToken)?.trim() ?? '';
    if (refreshToken.isEmpty) {
      throw Exception(
        'Configura primero tu Refresh Token de Google Drive (desde ogd.richardxiong.com).',
      );
    }

    if (customRefreshToken == null &&
        _cachedDriveAccessToken != null &&
        DateTime.now().millisecondsSinceEpoch <
            _cachedDriveTokenExpiresAtMs - 60000) {
      return _cachedDriveAccessToken!;
    }

    final clientId = config.googleDriveClientId?.trim() ?? '';
    final clientSecret = config.googleDriveClientSecret?.trim() ?? '';
    final hasCustomClient = clientId.isNotEmpty && clientSecret.isNotEmpty;

    final client = http.Client();
    try {
      final http.Response res;
      if (hasCustomClient) {
        res = await client
            .post(
              Uri.parse('https://oauth2.googleapis.com/token'),
              headers: {
                'Content-Type': 'application/x-www-form-urlencoded',
              },
              body: {
                'client_id': clientId,
                'client_secret': clientSecret,
                'grant_type': 'refresh_token',
                'refresh_token': refreshToken,
              },
            )
            .timeout(const Duration(seconds: 20));
      } else {
        final serverUrl = config.googleDriveTokenUrl?.trim().isNotEmpty == true
            ? config.googleDriveTokenUrl!.trim()
            : ogdDefaultTokenServerUrl;
        res = await client
            .post(
              Uri.parse(serverUrl),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({
                'refresh_token': refreshToken,
                'clientId': clientId,
                'clientSecret': clientSecret,
              }),
            )
            .timeout(const Duration(seconds: 20));
      }

      if (res.statusCode == 400 || res.statusCode == 401 || res.statusCode == 403) {
        _cachedDriveAccessToken = null;
        _cachedDriveTokenExpiresAtMs = 0;
        final bodyLower = res.body.toLowerCase();
        final isRevokedOrExpired = res.statusCode == 401 ||
            res.statusCode == 403 ||
            bodyLower.contains('invalid_grant') ||
            bodyLower.contains('expired') ||
            bodyLower.contains('revoked') ||
            bodyLower.contains('token');
        final msg =
            'El token de Google Drive expiró o fue revocado (HTTP ${res.statusCode}). Vuelve a iniciar sesión en $ogdAuthPortalUrl y pega el nuevo Refresh Token.';
        await markDriveTokenExpired(msg);
        if (isRevokedOrExpired) {
          throw GoogleDriveTokenExpiredException(msg);
        }
        throw Exception(msg);
      }

      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw Exception(
          'No se pudo obtener acceso a Google Drive (HTTP ${res.statusCode}).',
        );
      }

      final data = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      final accessToken = data['access_token']?.toString() ?? '';
      if (accessToken.isEmpty) {
        throw Exception('El servidor no devolvió un access_token válido.');
      }

      final expiresIn = (data['expires_in'] as num?)?.toInt() ?? 3600;
      _cachedDriveAccessToken = accessToken;
      _cachedDriveTokenExpiresAtMs =
          DateTime.now().millisecondsSinceEpoch + (expiresIn * 1000);
      return accessToken;
    } finally {
      client.close();
    }
  }

  static Future<String> getOrCreateDriveVaultFolderId(
    String accessToken, {
    bool verify = false,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final cachedId = prefs.getString(_gdriveFolderIdKey);
    if (!verify && cachedId != null && cachedId.trim().isNotEmpty) {
      return cachedId.trim();
    }

    final client = http.Client();
    try {
      final escapedVault = _escapeDriveQuery(driveVaultName);
      final query =
          "mimeType='application/vnd.google-apps.folder' and trashed=false and "
          "properties has { key='obsidian' and value='vault' } and "
          "properties has { key='vault' and value='$escapedVault' }";

      final searchUri = Uri.https('www.googleapis.com', '/drive/v3/files', {
        'q': query,
        'fields': 'files(id,name)',
        'pageSize': '10',
      });

      final searchRes = await client
          .get(
            searchUri,
            headers: {'Authorization': 'Bearer $accessToken'},
          )
          .timeout(const Duration(seconds: 20));

      if (searchRes.statusCode >= 200 && searchRes.statusCode < 300) {
        final decoded =
            jsonDecode(utf8.decode(searchRes.bodyBytes)) as Map<String, dynamic>;
        final files = (decoded['files'] as List?) ?? const [];
        if (files.isNotEmpty) {
          final existingId = (files.first as Map)['id']?.toString() ?? '';
          if (existingId.isNotEmpty) {
            await prefs.setString(_gdriveFolderIdKey, existingId);
            return existingId;
          }
        }
      }

      // Create the NotasApp root vault folder with Obsidian-Google-Drive metadata
      final createRes = await client
          .post(
            Uri.parse('https://www.googleapis.com/drive/v3/files'),
            headers: {
              'Authorization': 'Bearer $accessToken',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'name': driveVaultName,
              'mimeType': 'application/vnd.google-apps.folder',
              'description': 'Obsidian Vault: $driveVaultName',
              'properties': {
                'obsidian': 'vault',
                'vault': driveVaultName,
              },
            }),
          )
          .timeout(const Duration(seconds: 20));

      if (createRes.statusCode < 200 || createRes.statusCode >= 300) {
        throw Exception(
          'No se pudo crear la carpeta $driveVaultName en Google Drive (HTTP ${createRes.statusCode}).',
        );
      }

      final created =
          jsonDecode(utf8.decode(createRes.bodyBytes)) as Map<String, dynamic>;
      final newId = created['id']?.toString() ?? '';
      if (newId.isEmpty) {
        throw Exception('Google Drive no devolvió el ID de la carpeta $driveVaultName.');
      }
      await prefs.setString(_gdriveFolderIdKey, newId);
      return newId;
    } finally {
      client.close();
    }
  }

  static Future<String?> findDriveBundleFileId(
    String accessToken, {
    String? folderId,
  }) async {
    final client = http.Client();
    try {
      final escapedName = _escapeDriveQuery(bundleFileName);
      final escapedVault = _escapeDriveQuery(driveVaultName);

      Future<String?> runQuery(String q) async {
        final uri = Uri.https('www.googleapis.com', '/drive/v3/files', {
          'q': q,
          'orderBy': 'modifiedTime desc',
          'fields': 'files(id,name,modifiedTime)',
          'pageSize': '5',
        });
        final res = await client
            .get(uri, headers: {'Authorization': 'Bearer $accessToken'})
            .timeout(const Duration(seconds: 20));
        if (res.statusCode < 200 || res.statusCode >= 300) return null;
        final decoded =
            jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
        final files = (decoded['files'] as List?) ?? const [];
        if (files.isEmpty) return null;
        final id = (files.first as Map)['id']?.toString();
        return (id != null && id.isNotEmpty) ? id : null;
      }

      final primaryQ =
          "name='$escapedName' and trashed=false and "
          "properties has { key='vault' and value='$escapedVault' }";
      final primaryId = await runQuery(primaryQ);
      if (primaryId != null) return primaryId;

      if (folderId != null && folderId.isNotEmpty) {
        final escapedParent = _escapeDriveQuery(folderId);
        return await runQuery(
          "name='$escapedName' and '$escapedParent' in parents and trashed=false",
        );
      }
      return null;
    } finally {
      client.close();
    }
  }

  static Future<String> uploadToGoogleDrive() async {
    await refreshStatusNotifier(
      overrideState: DriveSyncState.syncing,
      overrideMessage: 'Subiendo respaldo a Google Drive...',
    );
    try {
      var accessToken = await refreshGoogleDriveAccessToken();
      final prefs = await SharedPreferences.getInstance();
      var folderId = await getOrCreateDriveVaultFolderId(accessToken);
      var fileId = prefs.getString(_gdriveFileIdKey)?.trim();
      if (fileId == null || fileId.isEmpty) {
        fileId = await findDriveBundleFileId(accessToken, folderId: folderId);
      }

      final bundle = await buildSyncBundle();
      const encoder = JsonEncoder.withIndent('  ');
      final jsonContent = encoder.convert(bundle);

      Future<http.Response> sendMultipart({
        required String? targetFileId,
        required String parentFolderId,
        required String bearerToken,
      }) {
        final boundary = 'notas_drive_${DateTime.now().millisecondsSinceEpoch}';
        final metadata = <String, dynamic>{
          'name': bundleFileName,
          'mimeType': 'application/json',
          'properties': {
            'vault': driveVaultName,
            'path': bundleFileName,
          },
        };
        if (targetFileId == null) {
          metadata['parents'] = [parentFolderId];
        }

        final payload = StringBuffer()
          ..write('--$boundary\r\n')
          ..write('Content-Type: application/json; charset=UTF-8\r\n\r\n')
          ..write(jsonEncode(metadata))
          ..write('\r\n--$boundary\r\n')
          ..write('Content-Type: application/json; charset=UTF-8\r\n\r\n')
          ..write(jsonContent)
          ..write('\r\n--$boundary--');

        final headers = {
          'Authorization': 'Bearer $bearerToken',
          'Content-Type': 'multipart/related; boundary=$boundary',
        };

        final bodyBytes = utf8.encode(payload.toString());
        if (targetFileId != null) {
          return http
              .patch(
                Uri.parse(
                  'https://www.googleapis.com/upload/drive/v3/files/$targetFileId?uploadType=multipart&fields=id',
                ),
                headers: headers,
                body: bodyBytes,
              )
              .timeout(const Duration(seconds: 25));
        }
        return http
            .post(
              Uri.parse(
                'https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart&fields=id',
              ),
              headers: headers,
              body: bodyBytes,
            )
            .timeout(const Duration(seconds: 25));
      }

      var res = await sendMultipart(
        targetFileId: fileId,
        parentFolderId: folderId,
        bearerToken: accessToken,
      );

      // Retry once if cached access token just expired
      if (res.statusCode == 401) {
        _cachedDriveAccessToken = null;
        _cachedDriveTokenExpiresAtMs = 0;
        accessToken = await refreshGoogleDriveAccessToken();
        res = await sendMultipart(
          targetFileId: fileId,
          parentFolderId: folderId,
          bearerToken: accessToken,
        );
      }

      // If cached fileId or folderId was deleted manually in Drive, re-verify and recreate cleanly
      if (res.statusCode == 404) {
        await prefs.remove(_gdriveFileIdKey);
        folderId = await getOrCreateDriveVaultFolderId(accessToken, verify: true);
        res = await sendMultipart(
          targetFileId: null,
          parentFolderId: folderId,
          bearerToken: accessToken,
        );
      }

      if (res.statusCode == 401 || res.statusCode == 403) {
        _cachedDriveAccessToken = null;
        _cachedDriveTokenExpiresAtMs = 0;
        final msg =
            'Sin permisos o sesión expirada en Google Drive (HTTP ${res.statusCode}). Renueva tu token.';
        await markDriveTokenExpired(msg);
        throw GoogleDriveTokenExpiredException(msg);
      }
      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw Exception(
          'Error al subir copia a Google Drive (HTTP ${res.statusCode}).',
        );
      }

      final decoded =
          jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      final savedFileId = decoded['id']?.toString() ?? fileId ?? '';
      if (savedFileId.isNotEmpty) {
        await prefs.setString(_gdriveFileIdKey, savedFileId);
      }
      await _clearDriveError();
      await _recordLastSync();
      await refreshStatusNotifier();
      return savedFileId;
    } on GoogleDriveTokenExpiredException {
      rethrow;
    } catch (e) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_gdriveLastErrorKey, e.toString());
      await refreshStatusNotifier();
      rethrow;
    }
  }

  static Future<Map<String, dynamic>> downloadFromGoogleDrive() async {
    await refreshStatusNotifier(
      overrideState: DriveSyncState.syncing,
      overrideMessage: 'Descargando respaldo de Google Drive...',
    );
    try {
      var accessToken = await refreshGoogleDriveAccessToken();
      final prefs = await SharedPreferences.getInstance();
      final folderId = await getOrCreateDriveVaultFolderId(accessToken);
      final fileId = await findDriveBundleFileId(accessToken, folderId: folderId);

      if (fileId == null || fileId.isEmpty) {
        throw Exception(
          'No se encontró "$bundleFileName" en tu carpeta NotasApp de Google Drive. Sube primero desde tu otro dispositivo.',
        );
      }

      var res = await http
          .get(
            Uri.parse(
              'https://www.googleapis.com/drive/v3/files/$fileId?alt=media&acknowledgeAbuse=true',
            ),
            headers: {'Authorization': 'Bearer $accessToken'},
          )
          .timeout(const Duration(seconds: 25));

      if (res.statusCode == 401) {
        _cachedDriveAccessToken = null;
        _cachedDriveTokenExpiresAtMs = 0;
        accessToken = await refreshGoogleDriveAccessToken();
        res = await http
            .get(
              Uri.parse(
                'https://www.googleapis.com/drive/v3/files/$fileId?alt=media&acknowledgeAbuse=true',
              ),
              headers: {'Authorization': 'Bearer $accessToken'},
            )
            .timeout(const Duration(seconds: 25));
      }

      if (res.statusCode == 401 || res.statusCode == 403) {
        _cachedDriveAccessToken = null;
        _cachedDriveTokenExpiresAtMs = 0;
        final msg =
            'Sesión de Google Drive expirada (HTTP ${res.statusCode}). Renueva tu Refresh Token.';
        await markDriveTokenExpired(msg);
        throw GoogleDriveTokenExpiredException(msg);
      }
      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw Exception(
          'No se pudo descargar de Google Drive (HTTP ${res.statusCode}).',
        );
      }

      final rawJson = utf8.decode(res.bodyBytes);
      if (rawJson.trim().isEmpty) {
        throw Exception('El archivo en Google Drive está vacío.');
      }

      final decoded = jsonDecode(rawJson) as Map<String, dynamic>;
      await prefs.setString(_gdriveFileIdKey, fileId);
      await applySyncBundle(decoded);
      await _clearDriveError();
      await refreshStatusNotifier();
      return decoded;
    } on GoogleDriveTokenExpiredException {
      rethrow;
    } catch (e) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_gdriveLastErrorKey, e.toString());
      await refreshStatusNotifier();
      rethrow;
    }
  }
}
