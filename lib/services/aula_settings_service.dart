import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/aula_course.dart';
import 'secure_credential_store.dart';

class _Sha256Sink implements Sink<Digest> {
  Digest? value;

  @override
  void add(Digest data) {
    value = data;
  }

  @override
  void close() {}
}

class StoragePermissionException implements Exception {
  final String message;
  StoragePermissionException(this.message);
  @override
  String toString() => message;
}

class AulaSessionData {
  final String token;
  final String cookie;
  final String sesskey;
  final String userName;
  final int? userId;

  const AulaSessionData({
    this.token = '',
    this.cookie = '',
    this.sesskey = '',
    this.userName = '',
    this.userId,
  });

  String get userIdString => userId?.toString() ?? '';
  bool get isTokenAuth => token.trim().isNotEmpty;
  bool get hasCredentials =>
      token.trim().isNotEmpty || cookie.trim().isNotEmpty;
}

class AulaDesktopImportResult {
  final bool found;
  final bool importedSession;
  final int importedFolders;
  final String? downloadRoot;
  final String? sourceSummary;

  const AulaDesktopImportResult({
    this.found = false,
    this.importedSession = false,
    this.importedFolders = 0,
    this.downloadRoot,
    this.sourceSummary,
  });
}

class DownloadHistoryEntry {
  final String timestamp;
  final String course;
  final String title;
  final String fileName;
  final String savedPath;
  final int sizeBytes;

  const DownloadHistoryEntry({
    required this.timestamp,
    required this.course,
    required this.title,
    required this.fileName,
    required this.savedPath,
    required this.sizeBytes,
  });

  Map<String, dynamic> toJson() => {
        'timestamp': timestamp,
        'course': course,
        'title': title,
        'fileName': fileName,
        'savedPath': savedPath,
        'sizeBytes': sizeBytes,
      };

  factory DownloadHistoryEntry.fromJson(Map<String, dynamic> json) =>
      DownloadHistoryEntry(
        timestamp: json['timestamp']?.toString() ?? '',
        course: json['course']?.toString() ?? '',
        title: json['title']?.toString() ?? '',
        fileName: json['fileName']?.toString() ?? '',
        savedPath: json['savedPath']?.toString() ?? '',
        sizeBytes: (json['sizeBytes'] as num?)?.toInt() ?? 0,
      );
}

class AulaNotification {
  final String id;
  final String title;
  final String body;
  final String type; // new_file | deadline | download_done | info
  final int? courseId;
  final String? courseName;
  final String timestamp;
  bool read;

  AulaNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.type,
    this.courseId,
    this.courseName,
    required this.timestamp,
    this.read = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'body': body,
        'type': type,
        'courseId': courseId,
        'courseName': courseName,
        'timestamp': timestamp,
        'read': read,
      };

  factory AulaNotification.fromJson(Map<String, dynamic> json) =>
      AulaNotification(
        id: json['id']?.toString() ?? '',
        title: json['title']?.toString() ?? '',
        body: json['body']?.toString() ?? '',
        type: json['type']?.toString() ?? 'info',
        courseId: (json['courseId'] as num?)?.toInt(),
        courseName: json['courseName']?.toString(),
        timestamp: json['timestamp']?.toString() ?? '',
        read: json['read'] == true,
      );
}

class SettingsService {
  static final SettingsService instance = SettingsService._internal();
  factory SettingsService() => instance;
  SettingsService._internal();

  static const MethodChannel _storageChannel =
      MethodChannel('cl.usm.aulascrapt/storage');

  // SharedPreferences keys (Aula-Scrapt + NotasApp synced keys)
  static const String keyDownloadRoot = 'settings_download_root';
  static const String keyDefaultSubfolder = 'settings_default_subfolder';
  static const String keyDefaultOrgSection = 'settings_org_section';
  static const String keySkipDownloaded = 'settings_skip_downloaded';
  static const String keySkipSeenOnSelect = 'settings_skip_seen_on_select';
  static const String keyAutoExportLinks = 'settings_auto_export_links';
  static const String keyAutoExportForums = 'settings_auto_export_forums';
  static const String keyDefaultFilter = 'settings_default_filter';
  static const String keyHideEmptySections = 'settings_hide_empty_sections';
  static const String keyHiddenCourses = 'hidden_courses_json';
  static const String keyPreferredExtensions = 'settings_preferred_extensions';
  static const String keyMaxAutoSelectMb = 'settings_max_auto_select_mb';
  static const String keyNotifyNative = 'settings_notify_native';
  static const String keyNotifyNewFiles = 'settings_notify_new_files';
  static const String keyNotifyDeadlines = 'settings_notify_deadlines';
  static const String keyNotifyDownloadDone = 'settings_notify_download_done';
  static const String keyBackgroundSyncHours = 'settings_bg_sync_hours';
  static const String keyHistory = 'download_history_json';
  static const String keyNotifications = 'notifications_json';
  static const String keySeenIds = 'seen_item_ids_json';
  static const String keyScanCache = 'scan_cache_json';

  // Primary & NotasApp compatibility keys
  static const String keyCourseFolders = 'aula_course_folders';
  static const String keyCourseSubfolders = 'aula_course_subfolders';
  static const String keyCourseOrgSections = 'aula_course_org_sections';
  static const String keyCourseRamoLinks = 'aula_course_ramo_links';
  static const String keyLegacyCourseFolders = 'settings_course_folders';
  static const String keyLegacyCourseSubfolders = 'settings_course_subfolders';
  static const String keyLegacyCourseOrgSection = 'settings_course_org_section';

  static const List<String> syncedPrefKeys = [
    keyCourseFolders,
    keyCourseSubfolders,
    keyCourseOrgSections,
    keyCourseRamoLinks,
    keyLegacyCourseFolders,
    keyLegacyCourseSubfolders,
    keyLegacyCourseOrgSection,
    keyHiddenCourses,
    keyDefaultSubfolder,
    keyDefaultOrgSection,
    keySkipDownloaded,
    keyAutoExportLinks,
    keyAutoExportForums,
    keyPreferredExtensions,
  ];

  String _downloadRoot = '';
  String defaultSubfolder = 'Aula';
  bool defaultOrganizeBySection = true;
  bool skipAlreadyDownloaded = true;
  bool skipSeenOnSelect = false;
  bool autoExportLinksToObsidian = true;
  bool autoExportForumsToObsidian = true;
  String defaultFilterKey = 'files';
  bool hideEmptySections = true;
  Set<int> hiddenCourseIds = {};
  List<String> preferredExtensions = [];
  int maxAutoSelectMb = 0;
  bool notifyNativeEnabled = false;
  bool notifyOnNewFiles = true;
  bool notifyOnDeadlines = true;
  bool notifyOnDownloadDone = true;
  int backgroundSyncHours = 0;

  final List<DownloadHistoryEntry> history = [];
  final List<AulaNotification> notifications = [];
  final ValueNotifier<int> notificationsNotifier = ValueNotifier<int>(0);

  Map<int, String> _courseFolders = {};
  Map<int, String> _courseSubfolders = {};
  Map<int, bool> _courseOrgSections = {};
  Map<int, int> _courseRamoLinks = {};

  int get unreadNotificationsCount =>
      notifications.where((n) => !n.read).length;

  String get downloadRoot => _downloadRoot;

  String get shortDownloadRoot {
    if (_downloadRoot.isEmpty) return 'Carpeta sin definir';
    if (_downloadRoot.startsWith('/storage/emulated/0/')) {
      return _downloadRoot.replaceFirst(
          '/storage/emulated/0/', 'Almacenamiento/');
    }
    if (_downloadRoot == '/storage/emulated/0') return 'Almacenamiento';
    final home = Platform.environment['USERPROFILE'];
    if (home != null && home.isNotEmpty && _downloadRoot.startsWith(home)) {
      return _downloadRoot.replaceFirst(home, '~');
    }
    return _downloadRoot;
  }

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();

    final savedRoot = prefs.getString(keyDownloadRoot) ??
        prefs.getString('aula_download_root') ??
        '';
    _downloadRoot =
        savedRoot.isNotEmpty ? savedRoot : await getDefaultDownloadRoot();

    defaultSubfolder = prefs.getString(keyDefaultSubfolder) ?? 'Aula';
    defaultOrganizeBySection = prefs.getBool(keyDefaultOrgSection) ?? true;
    skipAlreadyDownloaded = prefs.getBool(keySkipDownloaded) ?? true;
    skipSeenOnSelect = prefs.getBool(keySkipSeenOnSelect) ?? false;
    autoExportLinksToObsidian = prefs.getBool(keyAutoExportLinks) ?? true;
    autoExportForumsToObsidian = prefs.getBool(keyAutoExportForums) ?? true;
    defaultFilterKey = prefs.getString(keyDefaultFilter) ?? 'files';
    hideEmptySections = prefs.getBool(keyHideEmptySections) ?? true;

    hiddenCourseIds = {};
    final hiddenRaw = prefs.getString(keyHiddenCourses);
    if (hiddenRaw != null && hiddenRaw.isNotEmpty) {
      try {
        final decoded = jsonDecode(hiddenRaw) as List;
        hiddenCourseIds = decoded
            .map((e) => int.tryParse(e.toString()) ?? -1)
            .where((id) => id > 0)
            .toSet();
      } catch (_) {}
    }

    preferredExtensions = prefs.getStringList(keyPreferredExtensions) ?? [];
    maxAutoSelectMb = prefs.getInt(keyMaxAutoSelectMb) ?? 0;
    notifyNativeEnabled = prefs.getBool(keyNotifyNative) ?? false;
    notifyOnNewFiles = prefs.getBool(keyNotifyNewFiles) ?? true;
    notifyOnDeadlines = prefs.getBool(keyNotifyDeadlines) ?? true;
    notifyOnDownloadDone = prefs.getBool(keyNotifyDownloadDone) ?? true;
    backgroundSyncHours = prefs.getInt(keyBackgroundSyncHours) ?? 0;

    _courseFolders = _decodeStringIntMap(
      prefs.getString(keyCourseFolders) ??
          prefs.getString(keyLegacyCourseFolders),
    );
    _courseSubfolders = _decodeStringIntMap(
      prefs.getString(keyCourseSubfolders) ??
          prefs.getString(keyLegacyCourseSubfolders),
    );
    _courseOrgSections = _decodeBoolIntMap(
      prefs.getString(keyCourseOrgSections) ??
          prefs.getString(keyLegacyCourseOrgSection),
    );
    _courseRamoLinks = _decodeIntIntMap(prefs.getString(keyCourseRamoLinks));

    history.clear();
    final histRaw = prefs.getString(keyHistory);
    if (histRaw != null && histRaw.isNotEmpty) {
      try {
        final list = jsonDecode(histRaw) as List;
        for (final item in list) {
          if (item is Map) {
            history.add(
              DownloadHistoryEntry.fromJson(Map<String, dynamic>.from(item)),
            );
          }
        }
      } catch (_) {}
    }

    notifications.clear();
    final notifRaw = prefs.getString(keyNotifications);
    if (notifRaw != null && notifRaw.isNotEmpty) {
      try {
        final list = jsonDecode(notifRaw) as List;
        for (final item in list) {
          if (item is Map) {
            notifications.add(
              AulaNotification.fromJson(Map<String, dynamic>.from(item)),
            );
          }
        }
      } catch (_) {}
    }
    notificationsNotifier.value = unreadNotificationsCount;
  }

  Map<int, String> _decodeStringIntMap(String? raw) {
    final result = <int, String>{};
    if (raw == null || raw.isEmpty) return result;
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      decoded.forEach((k, v) {
        final id = int.tryParse(k);
        if (id != null && v != null && v.toString().isNotEmpty) {
          result[id] = v.toString();
        }
      });
    } catch (_) {}
    return result;
  }

  Map<int, bool> _decodeBoolIntMap(String? raw) {
    final result = <int, bool>{};
    if (raw == null || raw.isEmpty) return result;
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      decoded.forEach((k, v) {
        final id = int.tryParse(k);
        if (id != null && v is bool) {
          result[id] = v;
        }
      });
    } catch (_) {}
    return result;
  }

  Map<int, int> _decodeIntIntMap(String? raw) {
    final result = <int, int>{};
    if (raw == null || raw.isEmpty) return result;
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      decoded.forEach((k, v) {
        final cid = int.tryParse(k);
        final rid = int.tryParse(v.toString());
        if (cid != null && rid != null) {
          result[cid] = rid;
        }
      });
    } catch (_) {}
    return result;
  }

  Future<String> getDefaultDownloadRoot() async {
    if (Platform.environment.containsKey('FLUTTER_TEST')) {
      return p.join(Directory.current.path, 'Aula-USM');
    }
    if (Platform.isAndroid) {
      final extRoot = await getExternalRootPath();
      final obsidianDocs = Directory(p.join(extRoot, 'Documents', 'Obsidian'));
      if (await obsidianDocs.exists()) return obsidianDocs.path;

      final obsidianRoot = Directory(p.join(extRoot, 'Obsidian'));
      if (await obsidianRoot.exists()) return obsidianRoot.path;

      return p.join(extRoot, 'Documents', 'Aula-USM');
    }

    try {
      final docs = await getApplicationDocumentsDirectory();
      final obsidianDir = Directory(p.join(docs.path, 'Obsidian'));
      if (await obsidianDir.exists()) return obsidianDir.path;
      return p.join(docs.path, 'Aula-USM');
    } catch (_) {
      return p.join(Directory.current.path, 'Aula-USM');
    }
  }

  Future<String> getDownloadRoot() async {
    if (_downloadRoot.isEmpty) {
      await load();
    }
    return _downloadRoot;
  }

  Future<void> setDownloadRoot(String path) async {
    final clean = path.trim().replaceAll(RegExp(r'[/\\]+$'), '');
    _downloadRoot = clean;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(keyDownloadRoot, clean);
    await prefs.setString('aula_download_root', clean);
  }

  Future<String> getExternalRootPath() async {
    if (!Platform.isAndroid) {
      try {
        final docs = await getApplicationDocumentsDirectory();
        return docs.path;
      } catch (_) {
        return Directory.current.path;
      }
    }
    try {
      final res = await _storageChannel.invokeMethod<String>('getExternalRoot');
      if (res != null && res.isNotEmpty) return res;
    } catch (_) {}
    return '/storage/emulated/0';
  }

  Future<int> getAndroidSdkInt() async {
    if (!Platform.isAndroid) return 0;
    try {
      return await _storageChannel.invokeMethod<int>('getSdkInt') ?? 33;
    } catch (_) {
      return 33;
    }
  }

  Future<bool> hasStoragePermission() async {
    if (!Platform.isAndroid) return true;
    final sdk = await getAndroidSdkInt();
    if (sdk >= 30) {
      try {
        return await Permission.manageExternalStorage.isGranted;
      } catch (_) {
        return false;
      }
    }
    try {
      return await Permission.storage.isGranted;
    } catch (_) {
      return false;
    }
  }

  Future<bool> requestStoragePermission() async {
    if (!Platform.isAndroid) return true;
    try {
      final sdk = await getAndroidSdkInt();
      if (sdk >= 30) {
        final status = await Permission.manageExternalStorage.request();
        return status.isGranted;
      }
      final status = await Permission.storage.request();
      return status.isGranted;
    } catch (_) {
      return false;
    }
  }

  Future<bool> openAppAllFilesSettings() async {
    if (!Platform.isAndroid) return false;
    try {
      return await openAppSettings();
    } catch (_) {
      return false;
    }
  }

  Future<String?> pickFolderWithSystemPicker() async {
    if (Platform.isAndroid) {
      try {
        final picked =
            await _storageChannel.invokeMethod<String>('pickDirectory');
        if (picked != null && picked.isNotEmpty) return picked;
      } catch (_) {}
    }
    try {
      return await FilePicker.getDirectoryPath(
        dialogTitle: 'Elegir carpeta destino de descargas',
      );
    } catch (_) {
      return null;
    }
  }

  Future<bool> hasNotificationPermission() async {
    if (!Platform.isAndroid) return true;
    try {
      return await _storageChannel
              .invokeMethod<bool>('hasNotificationPermission') ??
          true;
    } catch (_) {
      return true;
    }
  }

  Future<bool> requestNotificationPermission() async {
    if (!Platform.isAndroid) return true;
    try {
      return await _storageChannel
              .invokeMethod<bool>('requestNotificationPermission') ??
          false;
    } catch (_) {
      return false;
    }
  }

  static const Set<String> dangerousExtensions = {
    'apk',
    'exe',
    'msi',
    'bat',
    'cmd',
    'ps1',
    'vbs',
    'vbe',
    'js',
    'jse',
    'wsf',
    'wsh',
    'scr',
    'pif',
    'com',
    'hta',
    'lnk',
    'reg',
    'sh',
    'bash',
    'appimage',
    'deb',
    'rpm',
    'jar',
    'dll',
    'so',
    'dylib',
  };

  static bool isDangerousFile(String path) {
    final ext = p.extension(path).toLowerCase().replaceFirst('.', '');
    return ext.isNotEmpty && dangerousExtensions.contains(ext);
  }

  Future<void> showNativeNotification({
    required int id,
    required String title,
    required String body,
    String channelId = 'aula_updates',
  }) async {
    if (!Platform.isAndroid || !notifyNativeEnabled) return;
    try {
      await _storageChannel.invokeMethod('showNativeNotification', {
        'id': id,
        'channelId': channelId,
        'title': title,
        'body': body,
      });
    } catch (_) {}
  }

  Future<void> clearWebViewCookies() async {
    if (!Platform.isAndroid) return;
    try {
      await _storageChannel.invokeMethod<void>('clearWebViewCookies');
    } catch (_) {}
  }

  Future<void> setBackgroundSyncHours(int hours) async {
    backgroundSyncHours = hours;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(keyBackgroundSyncHours, hours);
    if (Platform.isAndroid) {
      try {
        await _storageChannel.invokeMethod('scheduleBackgroundSync', {
          'hours': hours,
        });
      } catch (_) {}
    }
  }

  Future<String?> scanQrCode() async {
    if (!Platform.isAndroid) return null;
    try {
      return await _storageChannel.invokeMethod<String>('scanQrCode');
    } catch (_) {
      return null;
    }
  }

  Future<String?> computeFileSha256(String path) async {
    final file = File(path);
    if (!await file.exists()) return null;
    if (Platform.isAndroid) {
      try {
        final res = await _storageChannel.invokeMethod<String>(
          'computeFileSha256',
          {'path': path},
        );
        if (res != null && res.isNotEmpty) return res;
      } catch (_) {}
    }
    try {
      final digestSink = _Sha256Sink();
      final hashSink = sha256.startChunkedConversion(digestSink);
      await for (final chunk in file.openRead()) {
        hashSink.add(chunk);
      }
      hashSink.close();
      return digestSink.value?.toString();
    } catch (_) {
      return null;
    }
  }

  Future<bool> openLocalFile(
    String path, {
    bool allowDangerous = false,
  }) async {
    final file = File(path);
    if (!await file.exists()) return false;
    if (!allowDangerous && isDangerousFile(path)) {
      return false;
    }
    final root = await getDownloadRoot();
    if (root.isNotEmpty) {
      final canonicalRoot = p.canonicalize(root);
      final canonicalPath = p.canonicalize(path);
      if (!p.isWithin(canonicalRoot, canonicalPath)) {
        return false;
      }
    }
    if (Platform.isAndroid) {
      try {
        final ok = await _storageChannel.invokeMethod<bool>(
          'openLocalFile',
          {'path': path},
        );
        if (ok == true) return true;
      } catch (_) {}
    }
    try {
      final res = await OpenFilex.open(path);
      return res.type == ResultType.done;
    } catch (_) {
      return false;
    }
  }

  static const String _secTokenKey = 'aula_sec_moodle_token';
  static const String _secCookieKey = 'aula_sec_moodle_cookie';
  static const String _secSesskeyKey = 'aula_sec_moodle_sesskey';

  Future<AulaSessionData> loadSession() async {
    final prefs = await SharedPreferences.getInstance();

    var token = await SecureCredentialStore.read(_secTokenKey) ?? '';
    var cookie = await SecureCredentialStore.read(_secCookieKey) ?? '';
    var sesskey = await SecureCredentialStore.read(_secSesskeyKey) ?? '';

    final legacyToken = prefs.getString('moodle_token') ?? '';
    final legacyCookie = prefs.getString('moodle_cookie') ?? '';
    final legacySesskey = prefs.getString('moodle_sesskey') ?? '';

    var migrated = false;
    if (token.isEmpty && legacyToken.isNotEmpty) {
      token = legacyToken;
      await SecureCredentialStore.write(_secTokenKey, token);
      migrated = true;
    }
    if (cookie.isEmpty && legacyCookie.isNotEmpty) {
      cookie = legacyCookie;
      await SecureCredentialStore.write(_secCookieKey, cookie);
      migrated = true;
    }
    if (sesskey.isEmpty && legacySesskey.isNotEmpty) {
      sesskey = legacySesskey;
      await SecureCredentialStore.write(_secSesskeyKey, sesskey);
      migrated = true;
    }
    if (migrated ||
        prefs.containsKey('moodle_token') ||
        prefs.containsKey('moodle_cookie') ||
        prefs.containsKey('moodle_sesskey')) {
      await prefs.remove('moodle_token');
      await prefs.remove('moodle_cookie');
      await prefs.remove('moodle_sesskey');
    }

    final uidRaw = prefs.get('moodle_user_id')?.toString() ?? '';
    return AulaSessionData(
      token: token,
      cookie: cookie,
      sesskey: sesskey,
      userName: prefs.getString('moodle_user_name') ?? '',
      userId: int.tryParse(uidRaw),
    );
  }

  Future<void> saveSession(AulaSessionData session) async {
    final prefs = await SharedPreferences.getInstance();

    if (session.token.isNotEmpty) {
      await SecureCredentialStore.write(_secTokenKey, session.token);
    } else {
      await SecureCredentialStore.delete(_secTokenKey);
    }
    if (session.cookie.isNotEmpty) {
      await SecureCredentialStore.write(_secCookieKey, session.cookie);
    } else {
      await SecureCredentialStore.delete(_secCookieKey);
    }
    if (session.sesskey.isNotEmpty) {
      await SecureCredentialStore.write(_secSesskeyKey, session.sesskey);
    } else {
      await SecureCredentialStore.delete(_secSesskeyKey);
    }

    await prefs.remove('moodle_token');
    await prefs.remove('moodle_cookie');
    await prefs.remove('moodle_sesskey');
    await prefs.setString('moodle_user_name', session.userName);
    await prefs.setString('moodle_user_id', session.userIdString);
  }

  Future<void> clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    await SecureCredentialStore.delete(_secTokenKey);
    await SecureCredentialStore.delete(_secCookieKey);
    await SecureCredentialStore.delete(_secSesskeyKey);

    for (final k in const [
      'moodle_token',
      'moodle_cookie',
      'moodle_sesskey',
      'moodle_user_name',
      'moodle_user_id',
      'aula_token',
      'aula_cookie',
      'aula_sesskey',
      'aula_moodle_token',
      'aula_moodle_cookie',
      keyScanCache,
    ]) {
      await prefs.remove(k);
    }
  }

  String getCourseFolder(int courseId, [String fallback = '']) =>
      _courseFolders[courseId] ?? fallback;

  String getCourseSubfolder(int courseId) =>
      _courseSubfolders[courseId] ?? defaultSubfolder;

  bool getCourseOrganizeBySection(int courseId) =>
      _courseOrgSections[courseId] ?? defaultOrganizeBySection;

  static const int unlinkedRamoSentinel = -1;

  int? getCourseRamoLink(int courseId) {
    final val = _courseRamoLinks[courseId];
    if (val == null || val == unlinkedRamoSentinel) return null;
    return val;
  }

  Future<Map<int, String>> getCourseFolders() async {
    final prefs = await SharedPreferences.getInstance();
    _courseFolders = _decodeStringIntMap(
      prefs.getString(keyCourseFolders) ??
          prefs.getString(keyLegacyCourseFolders),
    );
    return Map<int, String>.from(_courseFolders);
  }

  Future<Map<int, int>> getCourseRamoLinks() async {
    final prefs = await SharedPreferences.getInstance();
    _courseRamoLinks = _decodeIntIntMap(prefs.getString(keyCourseRamoLinks));
    return Map<int, int>.from(_courseRamoLinks);
  }

  Future<void> _persistCourseFolders() async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(
      _courseFolders.map((k, v) => MapEntry(k.toString(), v)),
    );
    await prefs.setString(keyCourseFolders, encoded);
    await prefs.setString(keyLegacyCourseFolders, encoded);
  }

  Future<void> _persistCourseSubfolders() async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(
      _courseSubfolders.map((k, v) => MapEntry(k.toString(), v)),
    );
    await prefs.setString(keyCourseSubfolders, encoded);
    await prefs.setString(keyLegacyCourseSubfolders, encoded);
  }

  Future<void> _persistCourseOrgSections() async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(
      _courseOrgSections.map((k, v) => MapEntry(k.toString(), v)),
    );
    await prefs.setString(keyCourseOrgSections, encoded);
    await prefs.setString(keyLegacyCourseOrgSection, encoded);
  }

  Future<void> _persistCourseRamoLinks() async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(
      _courseRamoLinks.map((k, v) => MapEntry(k.toString(), v)),
    );
    await prefs.setString(keyCourseRamoLinks, encoded);
  }

  Future<void> setCourseConfig(
    int courseId, {
    String? folder,
    String? subfolder,
    bool? organizeBySection,
  }) async {
    if (folder != null) {
      if (folder.trim().isEmpty) {
        _courseFolders.remove(courseId);
      } else {
        _courseFolders[courseId] = folder.trim();
      }
      await _persistCourseFolders();
    }
    if (subfolder != null) {
      _courseSubfolders[courseId] = subfolder.trim();
      await _persistCourseSubfolders();
    }
    if (organizeBySection != null) {
      _courseOrgSections[courseId] = organizeBySection;
      await _persistCourseOrgSections();
    }
  }

  Future<void> setCourseFolder(int courseId, String folder) =>
      setCourseConfig(courseId, folder: folder);

  Future<void> setCourseSubfolder(int courseId, String subfolder) =>
      setCourseConfig(courseId, subfolder: subfolder);

  Future<void> setCourseOrganizeBySection(int courseId, bool organize) =>
      setCourseConfig(courseId, organizeBySection: organize);

  Future<void> setCourseRamoLink(int courseId, int? ramoId) async {
    await getCourseRamoLinks();
    if (ramoId == null || ramoId == unlinkedRamoSentinel) {
      _courseRamoLinks[courseId] = unlinkedRamoSentinel;
    } else {
      _courseRamoLinks[courseId] = ramoId;
    }
    await _persistCourseRamoLinks();
  }

  Future<void> setDefaultSubfolder(String val) async {
    defaultSubfolder = val.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(keyDefaultSubfolder, defaultSubfolder);
  }

  Future<void> setDefaultOrganizeBySection(bool val) async {
    defaultOrganizeBySection = val;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(keyDefaultOrgSection, val);
  }

  Future<void> setSkipAlreadyDownloaded(bool val) async {
    skipAlreadyDownloaded = val;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(keySkipDownloaded, val);
  }

  Future<void> setSkipSeenOnSelect(bool val) async {
    skipSeenOnSelect = val;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(keySkipSeenOnSelect, val);
  }

  Future<void> setAutoExportLinksToObsidian(bool val) async {
    autoExportLinksToObsidian = val;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(keyAutoExportLinks, val);
  }

  Future<void> setAutoExportForumsToObsidian(bool val) async {
    autoExportForumsToObsidian = val;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(keyAutoExportForums, val);
  }

  Future<void> setDefaultFilterKey(String val) async {
    defaultFilterKey = val;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(keyDefaultFilter, val);
  }

  Future<void> setHideEmptySections(bool val) async {
    hideEmptySections = val;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(keyHideEmptySections, val);
  }

  Future<void> toggleCourseHidden(int courseId, bool hide) async {
    if (hide) {
      hiddenCourseIds.add(courseId);
    } else {
      hiddenCourseIds.remove(courseId);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      keyHiddenCourses,
      jsonEncode(hiddenCourseIds.toList()),
    );
  }

  Future<void> setPreferredExtensions(List<String> exts) async {
    preferredExtensions =
        exts.map((e) => e.trim().toLowerCase()).where((e) => e.isNotEmpty).toList();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(keyPreferredExtensions, preferredExtensions);
  }

  Future<void> setMaxAutoSelectMb(int mb) async {
    maxAutoSelectMb = mb < 0 ? 0 : mb;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(keyMaxAutoSelectMb, maxAutoSelectMb);
  }

  Future<void> setNotifyNativeEnabled(bool val) async {
    notifyNativeEnabled = val;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(keyNotifyNative, val);
  }

  Future<void> setNotifyOnNewFiles(bool val) async {
    notifyOnNewFiles = val;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(keyNotifyNewFiles, val);
  }

  Future<void> setNotifyOnDeadlines(bool val) async {
    notifyOnDeadlines = val;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(keyNotifyDeadlines, val);
  }

  Future<void> setNotifyOnDownloadDone(bool val) async {
    notifyOnDownloadDone = val;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(keyNotifyDownloadDone, val);
  }

  Future<void> applyPairedSettings(
    Map<String, dynamic> data,
    Map<int, String> courseFolders,
  ) async {
    if (data['default_subfolder'] is String) {
      await setDefaultSubfolder(data['default_subfolder'] as String);
    }
    if (data['organize_by_section'] is bool) {
      await setDefaultOrganizeBySection(data['organize_by_section'] as bool);
    }
    if (data['skip_downloaded'] is bool) {
      await setSkipAlreadyDownloaded(data['skip_downloaded'] as bool);
    }
    if (data['auto_export_links'] is bool) {
      await setAutoExportLinksToObsidian(data['auto_export_links'] as bool);
    }
    if (data['auto_export_forums'] is bool) {
      await setAutoExportForumsToObsidian(data['auto_export_forums'] as bool);
    }
    for (final entry in courseFolders.entries) {
      if (entry.value.trim().isNotEmpty) {
        _courseFolders[entry.key] = entry.value.trim();
      }
    }
    await _persistCourseFolders();
  }

  Future<void> recordDownloadHistory(DownloadHistoryEntry entry) =>
      recordDownloadHistoryBatch([entry]);

  Future<void> recordDownloadHistoryBatch(
    List<DownloadHistoryEntry> entries,
  ) async {
    if (entries.isEmpty) return;
    for (final entry in entries.reversed) {
      history.insert(0, entry);
    }
    if (history.length > 200) {
      history.removeRange(200, history.length);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      keyHistory,
      jsonEncode(history.map((e) => e.toJson()).toList()),
    );
  }

  Future<void> clearHistory() async {
    history.clear();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(keyHistory);
  }

  Future<void> addNotification(AulaNotification notification) async {
    notifications.insert(0, notification);
    if (notifications.length > 100) {
      notifications.removeRange(100, notifications.length);
    }
    await _persistNotifications();
  }

  Future<bool> addNotificationUnique(AulaNotification notification) async {
    if (notifications.any((n) => n.id == notification.id)) return false;
    await addNotification(notification);
    return true;
  }

  Future<void> markAllNotificationsRead() async {
    for (final n in notifications) {
      n.read = true;
    }
    await _persistNotifications();
  }

  Future<void> clearNotifications() async {
    notifications.clear();
    await _persistNotifications();
  }

  Future<void> _persistNotifications() async {
    notificationsNotifier.value = unreadNotificationsCount;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      keyNotifications,
      jsonEncode(notifications.map((e) => e.toJson()).toList()),
    );
  }

  Future<Set<String>> loadSeenIds() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(keySeenIds);
    if (raw == null || raw.isEmpty) return {};
    try {
      final list = jsonDecode(raw) as List;
      return list.map((e) => e.toString()).toSet();
    } catch (_) {
      return {};
    }
  }

  Future<void> markIdsSeen(Iterable<String> ids) async {
    final prefs = await SharedPreferences.getInstance();
    final existing = await loadSeenIds();
    existing.addAll(ids);
    final list = existing.toList();
    if (list.length > 5000) {
      list.removeRange(0, list.length - 5000);
    }
    await prefs.setString(keySeenIds, jsonEncode(list));
  }

  Future<Map<String, dynamic>> loadSharedIndex(String rootDir) async {
    final indexFile = File(p.join(rootDir, '.aula-scrapt-index.json'));
    if (!await indexFile.exists()) {
      return {'files': <String, dynamic>{}, 'items': <String, dynamic>{}};
    }
    try {
      final decoded =
          jsonDecode(await indexFile.readAsString()) as Map<String, dynamic>;
      return {
        'files': Map<String, dynamic>.from(decoded['files'] as Map? ?? {}),
        'items': Map<String, dynamic>.from(decoded['items'] as Map? ?? {}),
      };
    } catch (_) {
      return {'files': <String, dynamic>{}, 'items': <String, dynamic>{}};
    }
  }

  Future<void> recordSharedIndexEntries(
    String rootDir,
    List<Map<String, dynamic>> entries,
  ) async {
    if (entries.isEmpty) return;
    final indexFile = File(p.join(rootDir, '.aula-scrapt-index.json'));
    final data = await loadSharedIndex(rootDir);
    final filesMap = Map<String, dynamic>.from(data['files'] as Map);
    final itemsMap = Map<String, dynamic>.from(data['items'] as Map);

    for (final e in entries) {
      final sha = e['sha256']?.toString() ?? '';
      final itemId = e['itemId']?.toString() ?? '';
      if (sha.isNotEmpty) {
        filesMap[sha] = {
          'relPath': e['relPath'],
          'sizeBytes': e['sizeBytes'],
          'title': e['title'],
          'updatedAt': DateTime.now().toIso8601String(),
        };
      }
      if (itemId.isNotEmpty) {
        itemsMap[itemId] = {
          'relPath': e['relPath'],
          'sha256': sha,
          'fileName': e['fileName'],
          'updatedAt': DateTime.now().toIso8601String(),
        };
      }
    }

    try {
      if (!await indexFile.parent.exists()) {
        await indexFile.parent.create(recursive: true);
      }
      await indexFile.writeAsString(
        const JsonEncoder.withIndent('  ').convert({
          'version': 1,
          'updatedAt': DateTime.now().toIso8601String(),
          'files': filesMap,
          'items': itemsMap,
        }),
      );
    } catch (_) {}
  }

  Future<void> saveScanCache(List<MoodleCourse> courses) async {
    final prefs = await SharedPreferences.getInstance();
    try {
      await prefs.setString(
        keyScanCache,
        jsonEncode(courses.map((c) => c.toJson()).toList()),
      );
    } catch (_) {}
  }

  Future<List<MoodleCourse>> loadScanCache() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(keyScanCache);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .whereType<Map>()
          .map((e) => MoodleCourse.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<List<String>> listExistingSubfolders({String? rootPath}) async {
    final root = rootPath ?? await getDownloadRoot();
    if (root.isEmpty) return [];
    final dir = Directory(root);
    if (!await dir.exists()) return [];
    try {
      final result = <String>[];
      await for (final entity in dir.list(followLinks: false)) {
        if (entity is Directory) {
          final name = p.basename(entity.path);
          if (!name.startsWith('.') && name != '_gsdata_') {
            result.add(name);
          }
        }
      }
      result.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      return result;
    } catch (_) {
      return [];
    }
  }

  String? resolveCourseFolderSync({
    required int courseId,
    required String fullname,
    required String cleanName,
    required String shortname,
    required List<String> existingFolders,
  }) {
    final saved = _courseFolders[courseId];
    if (saved != null && saved.trim().isNotEmpty) {
      return saved.trim();
    }
    if (existingFolders.isEmpty) return null;

    final cleanNorm = MoodleCourse.normalizeForMatch(cleanName);
    final shortNorm = MoodleCourse.normalizeForMatch(shortname);
    final fullNorm = MoodleCourse.normalizeForMatch(fullname);

    // 1) Exact normalized match
    for (final folder in existingFolders) {
      final fNorm = MoodleCourse.normalizeForMatch(folder);
      if (fNorm == cleanNorm || fNorm == shortNorm || fNorm == fullNorm) {
        return folder;
      }
    }

    // 2) USM course code match (e.g., INF-253 / INF253)
    final codeMatches = RegExp(
      r'\b([A-Za-z]{2,5})\s*-?\s*(\d{3})\b',
    ).allMatches('$shortname $fullname');
    final courseCodes = codeMatches
        .map((m) => '${m.group(1)!.toUpperCase()}${m.group(2)!}')
        .toSet();
    if (courseCodes.isNotEmpty) {
      for (final folder in existingFolders) {
        final fCodes = RegExp(
          r'\b([A-Za-z]{2,5})\s*-?\s*(\d{3})\b',
        ).allMatches(folder);
        for (final fm in fCodes) {
          final code = '${fm.group(1)!.toUpperCase()}${fm.group(2)!}';
          if (courseCodes.contains(code)) return folder;
        }
      }
    }

    // 3) Token overlap
    final courseTokens = cleanNorm
        .split(' ')
        .where((t) => t.length >= 3 && !_matchStopWords.contains(t))
        .toSet();
    if (courseTokens.isEmpty) return null;

    String? bestFolder;
    double bestScore = 0;
    for (final folder in existingFolders) {
      final fNorm = MoodleCourse.normalizeForMatch(folder);
      if (fNorm.length >= 4 &&
          (cleanNorm.contains(fNorm) || fNorm.contains(cleanNorm))) {
        return folder;
      }
      final fTokens = fNorm
          .split(' ')
          .where((t) => t.length >= 3 && !_matchStopWords.contains(t))
          .toSet();
      if (fTokens.isEmpty) continue;
      final common = courseTokens.intersection(fTokens).length;
      final union = courseTokens.union(fTokens).length;
      final score = union > 0 ? common / union : 0.0;
      if (score >= 0.5 && score > bestScore) {
        bestScore = score;
        bestFolder = folder;
      }
    }
    return bestFolder;
  }

  Future<String> computeUniqueCourseSubdir(String root, String baseName) async {
    final cleanBase = MoodleCourse.sanitizeFileName(baseName);
    var candidate = cleanBase;
    var suffix = 2;
    while (await Directory(p.join(root, candidate)).exists()) {
      candidate = '$cleanBase ($suffix)';
      suffix++;
    }
    return candidate;
  }

  /// Imports local config & session from Aula-Scrapt Desktop (Windows/macOS/Linux) if present.
  Future<AulaDesktopImportResult> detectAndImportLocalDesktopData() async {
    if (!Platform.isWindows && !Platform.isLinux && !Platform.isMacOS) {
      return const AulaDesktopImportResult();
    }

    final candidates = <String>[];
    final appData = Platform.environment['APPDATA'];
    final localAppData = Platform.environment['LOCALAPPDATA'];
    final home = Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'];

    for (final base in [appData, localAppData, home]) {
      if (base == null || base.isEmpty) continue;
      candidates.add(p.join(base, 'Aula-Scrapt', 'config.json'));
      candidates.add(p.join(base, 'aula-scrapt', 'config.json'));
      candidates.add(p.join(base, '.aula-scrapt', 'config.json'));
    }
    if (home != null && home.isNotEmpty) {
      candidates.add(p.join(home, 'Documents', 'Aula-Scrapt', 'config.json'));
    }

    for (final path in candidates) {
      final f = File(path);
      if (!await f.exists()) continue;
      try {
        final decoded = jsonDecode(await f.readAsString());
        if (decoded is! Map) continue;
        final map = Map<String, dynamic>.from(decoded);

        String? importedRoot;
        final rawRoot = map['download_root'] ?? map['obsidian_vault'] ?? map['vault_path'];
        if (rawRoot is String && rawRoot.trim().isNotEmpty) {
          final candidateRoot = p.canonicalize(rawRoot.trim());
          if (!candidateRoot.contains('\x00') &&
              await Directory(candidateRoot).exists()) {
            importedRoot = candidateRoot;
            await setDownloadRoot(importedRoot);
          }
        }

        int foldersCount = 0;
        final rawFolders = map['course_folders'];
        if (rawFolders is Map) {
          rawFolders.forEach((k, v) {
            final cid = int.tryParse(k.toString());
            final rawName = v?.toString().trim() ?? '';
            if (cid != null && rawName.isNotEmpty) {
              _courseFolders[cid] = MoodleCourse.sanitizeFileName(rawName);
              foldersCount++;
            }
          });
          await _persistCourseFolders();
        }

        final rawSubfolders = map['course_subfolders'];
        if (rawSubfolders is Map) {
          rawSubfolders.forEach((k, v) {
            final cid = int.tryParse(k.toString());
            if (cid != null && v != null) {
              final cleanSegments = v
                  .toString()
                  .trim()
                  .split(RegExp(r'[/\\]+'))
                  .where((s) => s.trim().isNotEmpty)
                  .map((s) => MoodleCourse.sanitizeFileName(s.trim()))
                  .toList();
              _courseSubfolders[cid] = cleanSegments.join('/');
            }
          });
          await _persistCourseSubfolders();
        }

        bool importedSession = false;
        final token = (map['moodle_token'] ?? map['token'] ?? '').toString().trim();
        final cookie = (map['moodle_cookie'] ?? map['cookie'] ?? '').toString().trim();
        if (token.isNotEmpty || cookie.isNotEmpty) {
          await saveSession(AulaSessionData(
            token: token,
            cookie: cookie,
            sesskey: (map['moodle_sesskey'] ?? map['sesskey'] ?? '').toString(),
            userName: (map['user_name'] ?? map['moodle_user_name'] ?? '').toString(),
            userId: int.tryParse(
              (map['user_id'] ?? map['moodle_user_id'] ?? '').toString(),
            ),
          ));
          importedSession = true;
        }

        return AulaDesktopImportResult(
          found: true,
          importedSession: importedSession,
          importedFolders: foldersCount,
          downloadRoot: importedRoot,
          sourceSummary: path,
        );
      } catch (_) {}
    }

    return const AulaDesktopImportResult();
  }

  static const Set<String> _matchStopWords = {
    'de',
    'del',
    'la',
    'las',
    'los',
    'el',
    'y',
    'en',
    'para',
    'por',
    'con',
  };
}

/// Alias wrapper preserving NotasApp compatibility for tests & existing callers.
class AulaSettingsService {
  static const String keyCourseFolders = SettingsService.keyCourseFolders;
  static const String keyCourseSubfolders = SettingsService.keyCourseSubfolders;
  static const String keyCourseOrgSections = SettingsService.keyCourseOrgSections;
  static const String keyCourseRamoLinks = SettingsService.keyCourseRamoLinks;
  static const List<String> syncedPrefKeys = SettingsService.syncedPrefKeys;

  final SettingsService _inner = SettingsService.instance;

  Future<void> load() => _inner.load();
  Future<AulaSessionData> loadSession() => _inner.loadSession();
  Future<void> saveSession(AulaSessionData s) => _inner.saveSession(s);
  Future<void> clearSession() => _inner.clearSession();
  Future<String> getDownloadRoot() => _inner.getDownloadRoot();
  Future<void> setDownloadRoot(String path) => _inner.setDownloadRoot(path);
  Future<void> setCourseFolder(int id, String f) =>
      _inner.setCourseFolder(id, f);
  Future<void> setCourseSubfolder(int id, String sf) =>
      _inner.setCourseSubfolder(id, sf);
  Future<void> setCourseOrganizeBySection(int id, bool org) =>
      _inner.setCourseOrganizeBySection(id, org);
  Future<void> setCourseRamoLink(int id, int? rid) =>
      _inner.setCourseRamoLink(id, rid);
  Future<Map<int, String>> getCourseFolders() => _inner.getCourseFolders();
  Future<Map<int, int>> getCourseRamoLinks() => _inner.getCourseRamoLinks();
  Future<AulaDesktopImportResult> detectAndImportLocalDesktopData() =>
      _inner.detectAndImportLocalDesktopData();
}
