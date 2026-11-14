import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/aula_course.dart';
import '../models/categoria_evaluacion.dart';
import '../models/evaluacion.dart';
import '../models/ramo.dart';
import '../models/semestre.dart';
import 'database_helper.dart';
import 'notification_service.dart';

class AulaSessionData {
  final String token;
  final String moodleSession;
  final String sesskey;
  final String userName;
  final int? userId;

  const AulaSessionData({
    this.token = '',
    this.moodleSession = '',
    this.sesskey = '',
    this.userName = '',
    this.userId,
  });

  bool get hasCredentials => token.isNotEmpty || moodleSession.isNotEmpty;
}

class AulaDesktopImportResult {
  final bool foundSession;
  final bool foundSettings;
  final String sourcePath;
  final String? userName;
  final int mappedFoldersCount;

  const AulaDesktopImportResult({
    required this.foundSession,
    required this.foundSettings,
    required this.sourcePath,
    this.userName,
    this.mappedFoldersCount = 0,
  });
}

class AulaSettingsService {
  static const String keyToken = 'aula_token';
  static const String keyMoodleSession = 'aula_moodle_session';
  static const String keySesskey = 'aula_sesskey';
  static const String keyUserName = 'aula_user_name';
  static const String keyUserId = 'aula_user_id';
  static const String keyDownloadRoot = 'aula_download_root';
  static const String keyObsidianVaultPath = 'aula_obsidian_vault_path';
  static const String keyCourseFolders = 'aula_course_folders';
  static const String keyCourseSubfolders = 'aula_course_subfolders';
  static const String keyCourseOrgSections = 'aula_course_org_sections';
  static const String keyHiddenCourses = 'aula_hidden_courses';
  static const String keyCourseRamoLinks = 'aula_course_ramo_links';
  static const String keyNotifyNewFiles = 'aula_notify_new_files';
  static const String keyNotifyDeadlines = 'aula_notify_deadlines';
  static const String keyNotifyDeadlineHours = 'aula_notify_deadline_hours';
  static const String keyKnownItems = 'aula_known_items';

  /// Keys synced via CloudSyncService (GitHub Gist / Folder Sync).
  /// Machine-local directories like [keyDownloadRoot] stay local per OS.
  static const List<String> syncedPrefKeys = [
    keyToken,
    keyMoodleSession,
    keySesskey,
    keyUserName,
    keyUserId,
    keyCourseFolders,
    keyCourseSubfolders,
    keyCourseOrgSections,
    keyHiddenCourses,
    keyCourseRamoLinks,
    keyNotifyNewFiles,
    keyNotifyDeadlines,
    keyNotifyDeadlineHours,
  ];

  Future<AulaSessionData> loadSession() async {
    final prefs = await SharedPreferences.getInstance();
    return AulaSessionData(
      token: prefs.getString(keyToken) ?? '',
      moodleSession: prefs.getString(keyMoodleSession) ?? '',
      sesskey: prefs.getString(keySesskey) ?? '',
      userName: prefs.getString(keyUserName) ?? '',
      userId: prefs.getInt(keyUserId),
    );
  }

  Future<void> saveSession(AulaSessionData session) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(keyToken, session.token);
    await prefs.setString(keyMoodleSession, session.moodleSession);
    await prefs.setString(keySesskey, session.sesskey);
    await prefs.setString(keyUserName, session.userName);
    if (session.userId != null) {
      await prefs.setInt(keyUserId, session.userId!);
    } else {
      await prefs.remove(keyUserId);
    }
  }

  Future<void> clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(keyToken);
    await prefs.remove(keyMoodleSession);
    await prefs.remove(keySesskey);
    await prefs.remove(keyUserName);
    await prefs.remove(keyUserId);
  }

  Future<String> getDefaultDownloadRoot() async {
    if (Platform.environment.containsKey('FLUTTER_TEST')) {
      return 'Aula USM';
    }
    if (Platform.isAndroid) {
      const publicDir = '/storage/emulated/0/Download/Aula USM';
      return publicDir;
    }
    try {
      final downloads = await getDownloadsDirectory();
      if (downloads != null) {
        return p.join(downloads.path, 'Aula USM');
      }
    } catch (_) {}
    final docs = await getApplicationDocumentsDirectory();
    return p.join(docs.path, 'Aula USM');
  }

  Future<String> getDownloadRoot() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(keyDownloadRoot);
    if (saved != null && saved.trim().isNotEmpty) return saved.trim();
    return getDefaultDownloadRoot();
  }

  Future<void> setDownloadRoot(String path) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(keyDownloadRoot, path.trim());
  }

  Future<String?> getObsidianVaultPath() async {
    final prefs = await SharedPreferences.getInstance();
    final val = prefs.getString(keyObsidianVaultPath)?.trim();
    if (val == null || val.isEmpty) return null;
    return val;
  }

  Future<void> setObsidianVaultPath(String? path) async {
    final prefs = await SharedPreferences.getInstance();
    if (path == null || path.trim().isEmpty) {
      await prefs.remove(keyObsidianVaultPath);
    } else {
      await prefs.setString(keyObsidianVaultPath, path.trim());
    }
  }

  Future<Map<int, String>> getCourseFolders() async {
    return _readIntStringMap(keyCourseFolders);
  }

  Future<void> setCourseFolder(int courseId, String? folderName) async {
    final map = await getCourseFolders();
    if (folderName == null || folderName.trim().isEmpty) {
      map.remove(courseId);
    } else {
      map[courseId] = MoodleItem.sanitizeFileName(folderName.trim());
    }
    await _writeIntStringMap(keyCourseFolders, map);
  }

  Future<Map<int, String>> getCourseSubfolders() async {
    return _readIntStringMap(keyCourseSubfolders);
  }

  Future<void> setCourseSubfolder(int courseId, String? subfolder) async {
    final map = await getCourseSubfolders();
    if (subfolder == null || subfolder.trim().isEmpty) {
      map.remove(courseId);
    } else {
      map[courseId] = subfolder.trim();
    }
    await _writeIntStringMap(keyCourseSubfolders, map);
  }

  Future<Map<int, bool>> getCourseOrgSections() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(keyCourseOrgSections);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return {
        for (final entry in decoded.entries)
          if (int.tryParse(entry.key) != null)
            int.parse(entry.key): entry.value == true,
      };
    } catch (_) {
      return {};
    }
  }

  Future<void> setCourseOrgSections(int courseId, bool organizeBySection) async {
    final map = await getCourseOrgSections();
    map[courseId] = organizeBySection;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      keyCourseOrgSections,
      jsonEncode({for (final e in map.entries) e.key.toString(): e.value}),
    );
  }

  Future<Set<int>> getHiddenCourses() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(keyHiddenCourses) ?? const [];
    return list.map((e) => int.tryParse(e)).whereType<int>().toSet();
  }

  Future<void> setCourseHidden(int courseId, bool hidden) async {
    final set = await getHiddenCourses();
    if (hidden) {
      set.add(courseId);
    } else {
      set.remove(courseId);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(keyHiddenCourses, set.map((e) => e.toString()).toList());
  }

  Future<Map<int, int>> getCourseRamoLinks() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(keyCourseRamoLinks);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return {
        for (final entry in decoded.entries)
          if (int.tryParse(entry.key) != null && entry.value is num)
            int.parse(entry.key): (entry.value as num).toInt(),
      };
    } catch (_) {
      return {};
    }
  }

  Future<void> setCourseRamoLink(int courseId, int? ramoId) async {
    final map = await getCourseRamoLinks();
    if (ramoId == null) {
      map.remove(courseId);
    } else {
      map[courseId] = ramoId;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      keyCourseRamoLinks,
      jsonEncode({for (final e in map.entries) e.key.toString(): e.value}),
    );
  }

  Future<({bool notifyNewFiles, bool notifyDeadlines, int deadlineHours})>
      getNotificationSettings() async {
    final prefs = await SharedPreferences.getInstance();
    return (
      notifyNewFiles: prefs.getBool(keyNotifyNewFiles) ?? true,
      notifyDeadlines: prefs.getBool(keyNotifyDeadlines) ?? true,
      deadlineHours: prefs.getInt(keyNotifyDeadlineHours) ?? 24,
    );
  }

  Future<void> saveNotificationSettings({
    bool? notifyNewFiles,
    bool? notifyDeadlines,
    int? deadlineHours,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    if (notifyNewFiles != null) {
      await prefs.setBool(keyNotifyNewFiles, notifyNewFiles);
    }
    if (notifyDeadlines != null) {
      await prefs.setBool(keyNotifyDeadlines, notifyDeadlines);
    }
    if (deadlineHours != null) {
      await prefs.setInt(keyNotifyDeadlineHours, deadlineHours);
    }
  }

  Future<List<String>> detectNewItemsAndUpdateSnapshot(MoodleCourse course) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(keyKnownItems);
    final Map<String, dynamic> all =
        raw != null && raw.isNotEmpty ? (jsonDecode(raw) as Map<String, dynamic>) : {};
    final key = course.id.toString();
    final currentKeys = course.items.map((e) => e.key).toList();
    final previous = (all[key] as List<dynamic>? ?? const []).map((e) => e.toString()).toSet();

    final addedNames = <String>[];
    if (previous.isNotEmpty) {
      for (final item in course.items) {
        if (!previous.contains(item.key)) {
          addedNames.add(item.cleanName);
        }
      }
    }

    all[key] = currentKeys;
    await prefs.setString(keyKnownItems, jsonEncode(all));
    return addedNames;
  }

  /// Detects a standalone desktop Aula-Scrapt installation on Windows and imports its
  /// session cookies/token plus mapped course folders.
  Future<AulaDesktopImportResult?> detectAndImportLocalDesktopData({
    bool overwriteExistingSession = true,
  }) async {
    if (!Platform.isWindows) return null;
    final userProfile = Platform.environment['USERPROFILE'] ?? '';
    final candidates = <String>[
      if (userProfile.isNotEmpty) p.join(userProfile, 'OneDrive', 'Documentos', 'GitHub', 'Aula-Scrapt', 'data'),
      if (userProfile.isNotEmpty) p.join(userProfile, 'Documents', 'GitHub', 'Aula-Scrapt', 'data'),
      if (userProfile.isNotEmpty) p.join(userProfile, 'Aula-Scrapt', 'data'),
    ];

    Directory? foundDir;
    for (final dirPath in candidates) {
      final dir = Directory(dirPath);
      if (await dir.exists()) {
        final hasSession = await File(p.join(dir.path, 'session.json')).exists();
        final hasSettings = await File(p.join(dir.path, 'settings.json')).exists();
        if (hasSession || hasSettings) {
          foundDir = dir;
          break;
        }
      }
    }
    if (foundDir == null) return null;

    bool importedSession = false;
    bool importedSettings = false;
    String? userName;
    int mappedFoldersCount = 0;

    final sessionFile = File(p.join(foundDir.path, 'session.json'));
    if (await sessionFile.exists()) {
      try {
        final json = jsonDecode(await sessionFile.readAsString()) as Map<String, dynamic>;
        final existing = await loadSession();
        if (overwriteExistingSession || !existing.hasCredentials) {
          final cookies = json['cookies'] as Map<String, dynamic>?;
          final cookieSession = (cookies?['MoodleSession'] ?? json['moodle_session'] ?? '').toString();
          final token = (json['token'] ?? '').toString();
          final sesskey = (json['sesskey'] ?? '').toString();
          userName = json['user_name']?.toString();
          final userId = (json['user_id'] as num?)?.toInt();
          if (cookieSession.isNotEmpty || token.isNotEmpty) {
            await saveSession(AulaSessionData(
              token: token,
              moodleSession: cookieSession,
              sesskey: sesskey,
              userName: userName ?? '',
              userId: userId,
            ));
            importedSession = true;
          }
        }
      } catch (e) {
        debugPrint('Error reading Aula-Scrapt session.json: $e');
      }
    }

    final settingsFile = File(p.join(foundDir.path, 'settings.json'));
    if (await settingsFile.exists()) {
      try {
        final json = jsonDecode(await settingsFile.readAsString()) as Map<String, dynamic>;
        final dlRoot = json['download_root']?.toString();
        if (dlRoot != null && dlRoot.trim().isNotEmpty) {
          await setDownloadRoot(dlRoot.trim());
        }
        final folders = json['course_folders'] as Map<String, dynamic>?;
        if (folders != null) {
          final map = await getCourseFolders();
          for (final entry in folders.entries) {
            final cid = int.tryParse(entry.key);
            if (cid != null && entry.value != null) {
              map[cid] = entry.value.toString();
              mappedFoldersCount++;
            }
          }
          await _writeIntStringMap(keyCourseFolders, map);
        }
        final subfolders = json['course_subfolders'] as Map<String, dynamic>?;
        if (subfolders != null) {
          final map = await getCourseSubfolders();
          for (final entry in subfolders.entries) {
            final cid = int.tryParse(entry.key);
            if (cid != null && entry.value != null) {
              map[cid] = entry.value.toString();
            }
          }
          await _writeIntStringMap(keyCourseSubfolders, map);
        }
        final orgSections = json['course_org_sections'] as Map<String, dynamic>?;
        if (orgSections != null) {
          for (final entry in orgSections.entries) {
            final cid = int.tryParse(entry.key);
            if (cid != null) {
              await setCourseOrgSections(cid, entry.value == true);
            }
          }
        }
        final hidden = json['hidden_courses'] as List<dynamic>?;
        if (hidden != null) {
          for (final id in hidden) {
            final cid = int.tryParse(id.toString());
            if (cid != null) await setCourseHidden(cid, true);
          }
        }
        importedSettings = true;
      } catch (e) {
        debugPrint('Error reading Aula-Scrapt settings.json: $e');
      }
    }

    if (!importedSession && !importedSettings) return null;
    return AulaDesktopImportResult(
      foundSession: importedSession,
      foundSettings: importedSettings,
      sourcePath: foundDir.path,
      userName: userName,
      mappedFoldersCount: mappedFoldersCount,
    );
  }

  Future<Map<int, String>> _readIntStringMap(String prefKey) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(prefKey);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return {
        for (final entry in decoded.entries)
          if (int.tryParse(entry.key) != null && entry.value != null)
            int.parse(entry.key): entry.value.toString(),
      };
    } catch (_) {
      return {};
    }
  }

  Future<void> _writeIntStringMap(String prefKey, Map<int, String> map) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      prefKey,
      jsonEncode({for (final e in map.entries) e.key.toString(): e.value}),
    );
  }
}

class AulaMoodleService {
  static const String baseUrl = 'https://aula.usm.cl';
  static const String _browserUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';

  AulaSessionData session;
  final http.Client _client;

  AulaMoodleService({required this.session, http.Client? client})
      : _client = client ?? http.Client();

  bool get isAuthenticated => session.hasCredentials;

  Map<String, String> _webHeaders({String? accept}) => {
        'User-Agent': _browserUserAgent,
        if (session.moodleSession.isNotEmpty) 'Cookie': 'MoodleSession=${session.moodleSession}',
        'Accept': ?accept,
      };

  Future<dynamic> _restCall(
    String wsFunction, {
    Map<String, String> params = const {},
  }) async {
    if (session.token.isEmpty) {
      throw StateError('No hay token WebService configurado.');
    }
    final query = <String, String>{
      'wstoken': session.token,
      'wsfunction': wsFunction,
      'moodlewsrestformat': 'json',
      ...params,
    };
    final uri = Uri.parse('$baseUrl/webservice/rest/server.php').replace(queryParameters: query);
    final response = await _client.get(uri, headers: {'User-Agent': _browserUserAgent}).timeout(
      const Duration(seconds: 25),
    );
    if (response.statusCode != 200) {
      throw HttpException('HTTP ${response.statusCode} al consultar Aula USM');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is Map<String, dynamic> && decoded.containsKey('exception')) {
      throw Exception(decoded['message'] ?? decoded['errorcode'] ?? 'Error REST de Moodle');
    }
    return decoded;
  }

  /// Validates the stored session (token or cookie) and refreshes user info + sesskey.
  Future<AulaSessionData> validateSession() async {
    if (session.token.isNotEmpty) {
      try {
        final info = await _restCall('core_webservice_get_site_info');
        if (info is Map<String, dynamic>) {
          final updated = AulaSessionData(
            token: session.token,
            moodleSession: session.moodleSession,
            sesskey: session.sesskey,
            userName: (info['fullname'] ?? session.userName).toString(),
            userId: (info['userid'] as num?)?.toInt() ?? session.userId,
          );
          session = updated;
          return updated;
        }
      } catch (e) {
        if (session.moodleSession.isEmpty) rethrow;
      }
    }

    if (session.moodleSession.isNotEmpty) {
      final resp = await _client
          .get(Uri.parse('$baseUrl/my/'), headers: _webHeaders())
          .timeout(const Duration(seconds: 20));
      final body = resp.body;
      final isLoginPage = body.contains('login/index.php') && !body.contains('"sesskey"');
      if (resp.statusCode >= 400 || isLoginPage) {
        throw Exception('La cookie MoodleSession expiró o no es válida.');
      }
      final sesskeyMatch = RegExp(r'"sesskey"\s*:\s*"([^"]+)"').firstMatch(body) ??
          RegExp(r'name="sesskey"\s+value="([^"]+)"').firstMatch(body);
      final userIdMatch = RegExp(r'data-userid="(\d+)"').firstMatch(body);
      final doc = html_parser.parse(body);
      final nameNode = doc.querySelector('.usertext') ??
          doc.querySelector('[data-title="profile"]') ??
          doc.querySelector('.userfullname');

      final updated = AulaSessionData(
        token: session.token,
        moodleSession: session.moodleSession,
        sesskey: sesskeyMatch?.group(1) ?? session.sesskey,
        userName: nameNode?.text.trim().isNotEmpty == true
            ? nameNode!.text.trim()
            : (session.userName.isNotEmpty ? session.userName : 'Estudiante USM'),
        userId: int.tryParse(userIdMatch?.group(1) ?? '') ?? session.userId,
      );
      session = updated;
      return updated;
    }

    throw Exception('No hay credenciales activas para Aula USM.');
  }

  Future<List<MoodleCourse>> fetchCourses({Set<int> hiddenCourseIds = const {}}) async {
    final courses = <MoodleCourse>[];

    if (session.token.isNotEmpty) {
      var userId = session.userId;
      if (userId == null) {
        final info = await validateSession();
        userId = info.userId;
      }
      if (userId != null) {
        final rawList = await _restCall(
          'core_enrol_get_users_courses',
          params: {'userid': userId.toString()},
        );
        if (rawList is List) {
          for (final raw in rawList) {
            if (raw is! Map<String, dynamic>) continue;
            final id = (raw['id'] as num?)?.toInt();
            if (id == null) continue;
            final full = (raw['fullname'] ?? '').toString();
            final short = (raw['shortname'] ?? '').toString();
            final startTs = (raw['startdate'] as num?)?.toInt() ?? 0;
            final endTs = (raw['enddate'] as num?)?.toInt() ?? 0;
            final startDate = startTs > 0 ? DateTime.fromMillisecondsSinceEpoch(startTs * 1000) : null;
            final endDate = endTs > 0 ? DateTime.fromMillisecondsSinceEpoch(endTs * 1000) : null;
            final hidden = (raw['hidden'] == true) || hiddenCourseIds.contains(id);

            courses.add(MoodleCourse(
              id: id,
              fullName: full,
              shortName: short,
              summary: raw['summary']?.toString(),
              isHidden: hidden,
              isCurrentSemester: inferIsCurrentSemester(
                fullName: full,
                shortName: short,
                startDate: startDate,
                endDate: endDate,
              ),
              startDate: startDate,
              endDate: endDate,
            ));
          }
          return _sortCourses(courses);
        }
      }
    }

    // Fallback: Cookie AJAX / HTML scraping
    if (session.moodleSession.isNotEmpty) {
      if (session.sesskey.isEmpty) {
        await validateSession();
      }
      final viaAjax = await _fetchCoursesViaAjax(hiddenCourseIds);
      if (viaAjax.isNotEmpty) {
        return _sortCourses(viaAjax);
      }
      final viaHtml = await _fetchCoursesViaHtml(hiddenCourseIds);
      return _sortCourses(viaHtml);
    }

    return courses;
  }

  Future<List<MoodleCourse>> _fetchCoursesViaAjax(Set<int> hiddenCourseIds) async {
    if (session.sesskey.isEmpty) return [];
    final uri = Uri.parse('$baseUrl/lib/ajax/service.php?sesskey=${session.sesskey}');
    final payload = jsonEncode([
      {
        'index': 0,
        'methodname': 'core_course_get_enrolled_courses_by_timeline_classification',
        'args': {
          'offset': 0,
          'limit': 0,
          'classification': 'all',
          'sort': 'fullname',
        },
      }
    ]);
    try {
      final resp = await _client
          .post(
            uri,
            headers: {
              ..._webHeaders(),
              'Content-Type': 'application/json',
            },
            body: payload,
          )
          .timeout(const Duration(seconds: 20));
      if (resp.statusCode != 200) return [];
      final decoded = jsonDecode(resp.body);
      if (decoded is! List || decoded.isEmpty) return [];
      final first = decoded.first;
      if (first is! Map || first['error'] == true) return [];
      final rawCourses = (first['data']?['courses'] as List<dynamic>?) ?? const [];
      final result = <MoodleCourse>[];
      for (final raw in rawCourses) {
        if (raw is! Map<String, dynamic>) continue;
        final id = (raw['id'] as num?)?.toInt();
        if (id == null) continue;
        final full = (raw['fullname'] ?? '').toString();
        final short = (raw['shortname'] ?? '').toString();
        final startTs = (raw['startdate'] as num?)?.toInt() ?? 0;
        final endTs = (raw['enddate'] as num?)?.toInt() ?? 0;
        final startDate = startTs > 0 ? DateTime.fromMillisecondsSinceEpoch(startTs * 1000) : null;
        final endDate = endTs > 0 ? DateTime.fromMillisecondsSinceEpoch(endTs * 1000) : null;
        final category = (raw['coursecategory'] ?? '').toString();
        result.add(MoodleCourse(
          id: id,
          fullName: full,
          shortName: short.isNotEmpty ? short : category,
          isHidden: (raw['hidden'] == true) || hiddenCourseIds.contains(id),
          isCurrentSemester: inferIsCurrentSemester(
            fullName: full,
            shortName: short,
            startDate: startDate,
            endDate: endDate,
          ),
          startDate: startDate,
          endDate: endDate,
        ));
      }
      return result;
    } catch (e) {
      debugPrint('AJAX courses fallback error: $e');
      return [];
    }
  }

  Future<List<MoodleCourse>> _fetchCoursesViaHtml(Set<int> hiddenCourseIds) async {
    final seen = <int, MoodleCourse>{};
    for (final path in ['/my/courses.php', '/my/']) {
      try {
        final resp = await _client
            .get(Uri.parse('$baseUrl$path'), headers: _webHeaders())
            .timeout(const Duration(seconds: 20));
        if (resp.statusCode != 200) continue;
        final doc = html_parser.parse(resp.body);
        for (final link in doc.querySelectorAll('a[href*="course/view.php?id="]')) {
          final href = link.attributes['href'] ?? '';
          final match = RegExp(r'[?&]id=(\d+)').firstMatch(href);
          if (match == null) continue;
          final id = int.tryParse(match.group(1)!);
          if (id == null || id <= 1) continue;
          final title = link.text.replaceAll(RegExp(r'\s+'), ' ').trim();
          if (title.isEmpty || title.toLowerCase() == 'ir al curso') continue;
          seen.putIfAbsent(
            id,
            () => MoodleCourse(
              id: id,
              fullName: title,
              shortName: '',
              isHidden: hiddenCourseIds.contains(id),
              isCurrentSemester: inferIsCurrentSemester(fullName: title, shortName: ''),
            ),
          );
        }
      } catch (_) {}
    }
    return seen.values.toList();
  }

  Future<MoodleCourse> fetchCourseContents(MoodleCourse course) async {
    final items = <MoodleItem>[];

    if (session.token.isNotEmpty) {
      final assignDates = await _fetchAssignmentDueDates(course.id);
      final quizDates = await _fetchQuizCloseDates(course.id);
      final rawSections = await _restCall(
        'core_course_get_contents',
        params: {'courseid': course.id.toString()},
      );

      if (rawSections is List) {
        for (final rawSec in rawSections) {
          if (rawSec is! Map<String, dynamic>) continue;
          final sectionNum = (rawSec['section'] as num?)?.toInt() ?? 0;
          final sectionName = (rawSec['name'] ?? 'General').toString().trim();
          final modules = (rawSec['modules'] as List<dynamic>?) ?? const [];

          for (final rawMod in modules) {
            if (rawMod is! Map<String, dynamic>) continue;
            final modType = (rawMod['modname'] ?? 'other').toString();
            final modName = _stripHtml((rawMod['name'] ?? '').toString());
            final modUrl = rawMod['url']?.toString();
            final instanceId = (rawMod['instance'] as num?)?.toInt();
            final cmId = (rawMod['id'] as num?)?.toInt();
            final completion = (rawMod['completiondata']?['state'] as num?)?.toInt() ?? 0;
            final completed = completion >= 1;

            DateTime? dueDate;
            final dates = rawMod['dates'] as List<dynamic>?;
            if (dates != null) {
              for (final d in dates) {
                if (d is Map<String, dynamic>) {
                  final label = (d['label'] ?? '').toString().toLowerCase();
                  final ts = (d['timestamp'] as num?)?.toInt();
                  if (ts != null &&
                      ts > 0 &&
                      (label.contains('due') ||
                          label.contains('entrega') ||
                          label.contains('cierra') ||
                          label.contains('close') ||
                          label.contains('venc'))) {
                    dueDate = DateTime.fromMillisecondsSinceEpoch(ts * 1000);
                    break;
                  }
                }
              }
            }
            if (dueDate == null && modType == 'assign') {
              dueDate = assignDates[cmId] ?? assignDates[instanceId];
            } else if (dueDate == null && modType == 'quiz') {
              dueDate = quizDates[cmId] ?? quizDates[instanceId];
            }

            final contents = (rawMod['contents'] as List<dynamic>?) ?? const [];

            if (modType == 'resource' && contents.isNotEmpty) {
              for (final rawFile in contents) {
                if (rawFile is! Map<String, dynamic>) continue;
                final fUrl = _withTokenUrl(rawFile['fileurl']?.toString() ?? '');
                final fName = rawFile['filename']?.toString();
                items.add(MoodleItem(
                  name: modName.isNotEmpty ? modName : (fName ?? 'Archivo'),
                  type: 'file',
                  url: fUrl.isNotEmpty ? fUrl : modUrl,
                  fileName: fName,
                  mimeType: rawFile['mimetype']?.toString(),
                  fileSize: (rawFile['filesize'] as num?)?.toInt(),
                  completed: completed,
                  sectionName: sectionName.isEmpty ? 'General' : sectionName,
                  sectionNumber: sectionNum,
                  courseName: course.cleanName,
                  courseShortName: course.shortName,
                ));
              }
              continue;
            }

            if (modType == 'folder' && contents.isNotEmpty) {
              final subFiles = <MoodleItem>[];
              for (final rawFile in contents) {
                if (rawFile is! Map<String, dynamic>) continue;
                final fUrl = _withTokenUrl(rawFile['fileurl']?.toString() ?? '');
                final fName = rawFile['filename']?.toString();
                if (fUrl.isEmpty) continue;
                subFiles.add(MoodleItem(
                  name: fName ?? 'Archivo',
                  type: 'file',
                  url: fUrl,
                  fileName: fName,
                  mimeType: rawFile['mimetype']?.toString(),
                  fileSize: (rawFile['filesize'] as num?)?.toInt(),
                  sectionName: sectionName.isEmpty ? 'General' : sectionName,
                  sectionNumber: sectionNum,
                  courseName: course.cleanName,
                  courseShortName: course.shortName,
                ));
              }
              items.add(MoodleItem(
                name: modName,
                type: 'folder',
                url: modUrl,
                completed: completed,
                sectionName: sectionName.isEmpty ? 'General' : sectionName,
                sectionNumber: sectionNum,
                subFiles: subFiles,
                courseName: course.cleanName,
                courseShortName: course.shortName,
              ));
              continue;
            }

            final mappedType = _mapModType(modType);
            items.add(MoodleItem(
              name: modName,
              type: mappedType,
              url: mappedType == 'file' ? _withTokenUrl(modUrl ?? '') : modUrl,
              dueDate: dueDate,
              completed: completed,
              description: rawMod['description'] != null
                  ? _stripHtml(rawMod['description'].toString())
                  : null,
              sectionName: sectionName.isEmpty ? 'General' : sectionName,
              sectionNumber: sectionNum,
              courseName: course.cleanName,
              courseShortName: course.shortName,
            ));
          }
        }
        return course.copyWith(items: items, isLoaded: true);
      }
    }

    if (session.moodleSession.isNotEmpty) {
      final htmlItems = await _fetchCourseContentsViaHtml(course);
      return course.copyWith(items: htmlItems, isLoaded: true);
    }

    return course.copyWith(items: items, isLoaded: true);
  }

  Future<Map<int, DateTime>> _fetchAssignmentDueDates(int courseId) async {
    final map = <int, DateTime>{};
    try {
      final res = await _restCall('mod_assign_get_assignments', params: {
        'courseids[0]': courseId.toString(),
      });
      if (res is Map<String, dynamic>) {
        final courses = res['courses'] as List<dynamic>? ?? const [];
        for (final c in courses) {
          if (c is! Map<String, dynamic>) continue;
          final assigns = c['assignments'] as List<dynamic>? ?? const [];
          for (final a in assigns) {
            if (a is! Map<String, dynamic>) continue;
            final dueTs = (a['duedate'] as num?)?.toInt() ?? 0;
            if (dueTs <= 0) continue;
            final dt = DateTime.fromMillisecondsSinceEpoch(dueTs * 1000);
            final cmId = (a['cmid'] as num?)?.toInt();
            final id = (a['id'] as num?)?.toInt();
            if (cmId != null) map[cmId] = dt;
            if (id != null) map[id] = dt;
          }
        }
      }
    } catch (_) {}
    return map;
  }

  Future<Map<int, DateTime>> _fetchQuizCloseDates(int courseId) async {
    final map = <int, DateTime>{};
    try {
      final res = await _restCall('mod_quiz_get_quizzes_by_courses', params: {
        'courseids[0]': courseId.toString(),
      });
      if (res is Map<String, dynamic>) {
        final quizzes = res['quizzes'] as List<dynamic>? ?? const [];
        for (final q in quizzes) {
          if (q is! Map<String, dynamic>) continue;
          final closeTs = (q['timeclose'] as num?)?.toInt() ?? 0;
          if (closeTs <= 0) continue;
          final dt = DateTime.fromMillisecondsSinceEpoch(closeTs * 1000);
          final cmId = (q['coursemodule'] as num?)?.toInt();
          final id = (q['id'] as num?)?.toInt();
          if (cmId != null) map[cmId] = dt;
          if (id != null) map[id] = dt;
        }
      }
    } catch (_) {}
    return map;
  }

  Future<List<MoodleItem>> _fetchCourseContentsViaHtml(MoodleCourse course) async {
    final resp = await _client
        .get(Uri.parse('$baseUrl/course/view.php?id=${course.id}'), headers: _webHeaders())
        .timeout(const Duration(seconds: 25));
    if (resp.statusCode != 200) {
      throw HttpException('No se pudo cargar el curso ${course.cleanName} (HTTP ${resp.statusCode})');
    }
    final doc = html_parser.parse(resp.body);
    final items = <MoodleItem>[];

    final sections = doc.querySelectorAll('li.section.main, [data-for="section"]');
    for (int secIdx = 0; secIdx < sections.length; secIdx++) {
      final sec = sections[secIdx];
      final secName =
          (sec.querySelector('.sectionname')?.text ?? sec.querySelector('h3')?.text ?? 'Sección $secIdx')
              .replaceAll(RegExp(r'\s+'), ' ')
              .trim();
      final activities = sec.querySelectorAll('li.activity, [data-for="cmitem"]');
      for (final act in activities) {
        final link = act.querySelector('a.aalink') ?? act.querySelector('a[href*="/mod/"]');
        if (link == null) continue;
        final href = link.attributes['href'] ?? '';
        final rawName =
            (act.querySelector('.instancename')?.text ?? link.text).replaceAll(RegExp(r'\s+'), ' ').trim();
        if (rawName.isEmpty) continue;

        final classes = act.classes.join(' ');
        String type = 'other';
        if (classes.contains('modtype_resource') || href.contains('/mod/resource/')) {
          type = 'file';
        } else if (classes.contains('modtype_assign') || href.contains('/mod/assign/')) {
          type = 'assignment';
        } else if (classes.contains('modtype_quiz') || href.contains('/mod/quiz/')) {
          type = 'quiz';
        } else if (classes.contains('modtype_folder') || href.contains('/mod/folder/')) {
          type = 'folder';
        } else if (classes.contains('modtype_url') || href.contains('/mod/url/')) {
          type = 'url';
        } else if (classes.contains('modtype_page') || href.contains('/mod/page/')) {
          type = 'page';
        } else if (classes.contains('modtype_forum') || href.contains('/mod/forum/')) {
          type = 'forum';
        }

        final actText = act.text;
        final completed = actText.contains('Hecho') ||
            actText.contains('Completado') ||
            actText.contains('Done') ||
            act.querySelector('.badge-success, .completion-state-1, [data-value="1"]') != null;

        DateTime? dueDate;
        final dateText = act.querySelector('.activity-dates, .description, [data-region="activity-dates"]')?.text ?? actText;
        dueDate = parseSpanishMoodleDate(dateText);

        List<MoodleItem> subFiles = const [];
        if (type == 'folder' && href.isNotEmpty) {
          subFiles = await _fetchFolderSubfiles(href, secName, secIdx, course);
        }

        items.add(MoodleItem(
          name: rawName,
          type: type,
          url: href.isNotEmpty ? href : null,
          dueDate: dueDate,
          completed: completed,
          sectionName: secName.isEmpty ? 'General' : secName,
          sectionNumber: secIdx,
          subFiles: subFiles,
          courseName: course.cleanName,
          courseShortName: course.shortName,
        ));
      }
    }
    return items;
  }

  Future<List<MoodleItem>> _fetchFolderSubfiles(
    String folderUrl,
    String sectionName,
    int sectionNumber,
    MoodleCourse course,
  ) async {
    try {
      final resp = await _client
          .get(Uri.parse(folderUrl), headers: _webHeaders())
          .timeout(const Duration(seconds: 15));
      if (resp.statusCode != 200) return const [];
      final doc = html_parser.parse(resp.body);
      final files = <MoodleItem>[];
      for (final a in doc.querySelectorAll('.fp-filename-icon a[href*="pluginfile.php"]')) {
        final fUrl = a.attributes['href'] ?? '';
        final fName = a.text.replaceAll(RegExp(r'\s+'), ' ').trim();
        if (fUrl.isEmpty) continue;
        files.add(MoodleItem(
          name: fName.isEmpty ? 'Archivo' : fName,
          type: 'file',
          url: fUrl,
          fileName: fName.isEmpty ? null : fName,
          sectionName: sectionName,
          sectionNumber: sectionNumber,
          courseName: course.cleanName,
          courseShortName: course.shortName,
        ));
      }
      return files;
    } catch (_) {
      return const [];
    }
  }

  /// Claims a PIN generated by a desktop `Aula-Scrapt` dashboard over local Wi-Fi.
  Future<({AulaSessionData session, Map<int, String> folders})> claimPairingPin({
    required String serverUrl,
    required String pin,
  }) async {
    var cleanBase = serverUrl.trim();
    if (!cleanBase.startsWith('http://') && !cleanBase.startsWith('https://')) {
      cleanBase = 'http://$cleanBase';
    }
    if (cleanBase.endsWith('/')) {
      cleanBase = cleanBase.substring(0, cleanBase.length - 1);
    }
    final uri = Uri.parse('$cleanBase/api/pair/claim');
    final resp = await _client
        .post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'pin': pin.trim()}),
        )
        .timeout(const Duration(seconds: 15));
    if (resp.statusCode != 200) {
      throw Exception('Código PIN inválido o expirado (HTTP ${resp.statusCode}).');
    }
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final rawSession = (data['session'] as Map<String, dynamic>?) ?? data;
    final cookies = rawSession['cookies'] as Map<String, dynamic>?;
    final parsedSession = AulaSessionData(
      token: (rawSession['token'] ?? '').toString(),
      moodleSession: (cookies?['MoodleSession'] ?? rawSession['moodle_session'] ?? '').toString(),
      sesskey: (rawSession['sesskey'] ?? '').toString(),
      userName: (rawSession['user_name'] ?? '').toString(),
      userId: (rawSession['user_id'] as num?)?.toInt(),
    );
    if (!parsedSession.hasCredentials) {
      throw Exception('El servidor no devolvió credenciales válidas.');
    }
    final parsedFolders = <int, String>{};
    final rawFolders = data['settings']?['course_folders'] as Map<String, dynamic>?;
    if (rawFolders != null) {
      for (final e in rawFolders.entries) {
        final cid = int.tryParse(e.key);
        if (cid != null && e.value != null) {
          parsedFolders[cid] = e.value.toString();
        }
      }
    }
    session = parsedSession;
    return (session: parsedSession, folders: parsedFolders);
  }

  String _withTokenUrl(String url) {
    if (url.isEmpty || session.token.isEmpty) return url;
    if (url.contains('token=')) return url;
    final sep = url.contains('?') ? '&' : '?';
    return '$url${sep}token=${Uri.encodeQueryComponent(session.token)}';
  }

  String _mapModType(String modName) {
    switch (modName) {
      case 'resource':
        return 'file';
      case 'assign':
        return 'assignment';
      case 'quiz':
        return 'quiz';
      case 'folder':
        return 'folder';
      case 'url':
        return 'url';
      case 'page':
        return 'page';
      case 'forum':
        return 'forum';
      default:
        return 'other';
    }
  }

  static String _stripHtml(String htmlText) {
    if (htmlText.isEmpty) return '';
    return dom.DocumentFragment.html(htmlText).text?.replaceAll(RegExp(r'\s+'), ' ').trim() ?? htmlText;
  }

  static DateTime? parseSpanishMoodleDate(String text) {
    const months = {
      'enero': 1,
      'ene': 1,
      'febrero': 2,
      'feb': 2,
      'marzo': 3,
      'mar': 3,
      'abril': 4,
      'abr': 4,
      'mayo': 5,
      'may': 5,
      'junio': 6,
      'jun': 6,
      'julio': 7,
      'jul': 7,
      'agosto': 8,
      'ago': 8,
      'septiembre': 9,
      'setiembre': 9,
      'sep': 9,
      'sept': 9,
      'octubre': 10,
      'oct': 10,
      'noviembre': 11,
      'nov': 11,
      'diciembre': 12,
      'dic': 12,
      'january': 1,
      'jan': 1,
      'february': 2,
      'march': 3,
      'april': 4,
      'apr': 4,
      'june': 6,
      'july': 7,
      'august': 8,
      'aug': 8,
      'september': 9,
      'october': 10,
      'november': 11,
      'december': 12,
      'dec': 12,
    };

    final lower = text.toLowerCase();
    // Look for "18 de noviembre de 2026, 23:59" or "18 nov 2026 23:59"
    final rx = RegExp(
      r'(\d{1,2})\s+(?:de\s+)?([a-záéíóú]+)\s+(?:de\s+)?(20\d{2})(?:[,\s]+(\d{1,2}):(\d{2}))?',
    );
    final m = rx.firstMatch(lower);
    if (m == null) return null;
    final day = int.tryParse(m.group(1)!);
    final month = months[m.group(2)!];
    final year = int.tryParse(m.group(3)!);
    if (day == null || month == null || year == null) return null;
    final hour = int.tryParse(m.group(4) ?? '') ?? 23;
    final minute = int.tryParse(m.group(5) ?? '') ?? 59;
    return DateTime(year, month, day, hour, minute);
  }

  static bool inferIsCurrentSemester({
    required String fullName,
    required String shortName,
    DateTime? startDate,
    DateTime? endDate,
  }) {
    final now = DateTime.now();
    final currentYear = now.year;
    final currentSem = now.month <= 7 ? 1 : 2;

    final combined = '$fullName $shortName'.toUpperCase();
    final semMatch = RegExp(r'(20\d{2})[-/\s]?([12])\b').firstMatch(combined);
    if (semMatch != null) {
      final y = int.tryParse(semMatch.group(1)!);
      final s = int.tryParse(semMatch.group(2)!);
      if (y != null && s != null) {
        return y == currentYear && s == currentSem;
      }
    }

    final yearMatch = RegExp(r'\b(20\d{2})\b').firstMatch(combined);
    if (yearMatch != null) {
      final y = int.tryParse(yearMatch.group(1)!);
      if (y != null && y < currentYear) return false;
      if (y != null && y > currentYear) return false;
    }

    if (endDate != null && endDate.isBefore(now.subtract(const Duration(days: 45)))) {
      return false;
    }
    if (startDate != null && startDate.isAfter(now.add(const Duration(days: 60)))) {
      return false;
    }
    return true;
  }

  List<MoodleCourse> _sortCourses(List<MoodleCourse> list) {
    final sorted = List<MoodleCourse>.from(list);
    sorted.sort((a, b) {
      if (a.isHidden != b.isHidden) return a.isHidden ? 1 : -1;
      final aCur = a.isCurrentSemester ?? false;
      final bCur = b.isCurrentSemester ?? false;
      if (aCur != bCur) return aCur ? -1 : 1;
      return a.cleanName.toLowerCase().compareTo(b.cleanName.toLowerCase());
    });
    return sorted;
  }
}

class AulaDownloaderService {
  static const String indexFileName = '.aula-scrapt-index.json';
  static const String _browserUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';

  Future<bool> ensureStoragePermissions() async {
    if (!Platform.isAndroid) return true;
    try {
      final manage = await Permission.manageExternalStorage.status;
      if (manage.isGranted) return true;
      final storage = await Permission.storage.status;
      if (storage.isGranted) return true;
      final reqManage = await Permission.manageExternalStorage.request();
      if (reqManage.isGranted) return true;
      final reqStorage = await Permission.storage.request();
      return reqStorage.isGranted;
    } catch (_) {
      return false;
    }
  }

  Future<Directory> resolveCourseDirectory({
    required MoodleCourse course,
    required String downloadRoot,
    required Map<int, String> courseFolders,
    required Map<int, String> courseSubfolders,
  }) async {
    String rootPath = downloadRoot.trim();
    if (Platform.isAndroid && rootPath.startsWith('/storage/emulated/0')) {
      final hasPerm = await ensureStoragePermissions();
      if (!hasPerm) {
        final docs = await getApplicationDocumentsDirectory();
        rootPath = p.join(docs.path, 'Aula USM');
      }
    }

    final mappedFolder = courseFolders[course.id];
    final folderName = MoodleItem.sanitizeFileName(
      (mappedFolder != null && mappedFolder.trim().isNotEmpty)
          ? mappedFolder.trim()
          : course.cleanName,
    );

    final extraSub = courseSubfolders[course.id]?.trim();
    final fullPath = (extraSub != null && extraSub.isNotEmpty)
        ? p.joinAll([rootPath, folderName, ...extraSub.split(RegExp(r'[/\\]+'))])
        : p.join(rootPath, folderName);

    final dir = Directory(fullPath);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<void> scanDownloadedItems({
    required MoodleCourse course,
    required String downloadRoot,
    required Map<int, String> courseFolders,
    required Map<int, String> courseSubfolders,
    required Map<int, bool> courseOrgSections,
  }) async {
    try {
      final dir = await resolveCourseDirectory(
        course: course,
        downloadRoot: downloadRoot,
        courseFolders: courseFolders,
        courseSubfolders: courseSubfolders,
      );

      final indexFile = File(p.join(dir.path, indexFileName));
      final Map<String, String> indexedPaths = {};
      if (await indexFile.exists()) {
        try {
          final decoded = jsonDecode(await indexFile.readAsString()) as Map<String, dynamic>;
          final files = decoded['files'] as Map<String, dynamic>? ?? const {};
          for (final entry in files.entries) {
            final relOrAbs = entry.value?.toString();
            if (relOrAbs == null || relOrAbs.isEmpty) continue;
            final absPath = p.isAbsolute(relOrAbs) ? relOrAbs : p.join(dir.path, relOrAbs);
            if (await File(absPath).exists()) {
              indexedPaths[entry.key] = absPath;
            }
          }
        } catch (_) {}
      }

      final diskFilesByLowerName = <String, String>{};
      if (await dir.exists()) {
        await for (final entity in dir.list(recursive: true, followLinks: false)) {
          if (entity is File) {
            final base = p.basename(entity.path);
            if (base == indexFileName || base.endsWith('.md')) continue;
            diskFilesByLowerName[base.toLowerCase()] = entity.path;
          }
        }
      }

      for (final item in course.items) {
        if (!item.isDownloadable) continue;
        if (item.type == 'folder' && item.subFiles.isNotEmpty) {
          var allDone = true;
          for (final sub in item.subFiles) {
            final match = indexedPaths[sub.key] ??
                diskFilesByLowerName[MoodleItem.sanitizeFileName(sub.fileName ?? sub.cleanName).toLowerCase()];
            if (match != null) {
              sub.localPath = match;
              sub.status = 'downloaded';
            } else {
              allDone = false;
            }
          }
          if (allDone && item.subFiles.isNotEmpty) {
            item.status = 'downloaded';
            item.localPath = p.dirname(item.subFiles.first.localPath!);
          }
          continue;
        }

        final candidateNames = <String>[
          if (item.fileName != null) MoodleItem.sanitizeFileName(item.fileName!).toLowerCase(),
          MoodleItem.sanitizeFileName(item.cleanName).toLowerCase(),
        ];
        String? found = indexedPaths[item.key];
        for (final c in candidateNames) {
          found ??= diskFilesByLowerName[c];
          if (found == null) {
            for (final diskEntry in diskFilesByLowerName.entries) {
              if (diskEntry.key.startsWith(c) || c.startsWith(p.basenameWithoutExtension(diskEntry.key))) {
                found = diskEntry.value;
                break;
              }
            }
          }
        }
        if (found != null) {
          item.localPath = found;
          item.status = 'downloaded';
          item.downloadProgress = 1.0;
        }
      }
    } catch (e) {
      debugPrint('Error scanning course dir: $e');
    }
  }

  Future<String?> downloadItem({
    required MoodleCourse course,
    required MoodleItem item,
    required AulaSessionData session,
    required String downloadRoot,
    required Map<int, String> courseFolders,
    required Map<int, String> courseSubfolders,
    required Map<int, bool> courseOrgSections,
    void Function(double progress)? onProgress,
  }) async {
    final baseDir = await resolveCourseDirectory(
      course: course,
      downloadRoot: downloadRoot,
      courseFolders: courseFolders,
      courseSubfolders: courseSubfolders,
    );

    if (item.type == 'folder' && item.subFiles.isNotEmpty) {
      item.status = 'downloading';
      final folderDir = Directory(p.join(baseDir.path, MoodleItem.sanitizeFileName(item.cleanName)));
      if (!await folderDir.exists()) await folderDir.create(recursive: true);
      int done = 0;
      for (final sub in item.subFiles) {
        final subPath = await _downloadSingleFile(
          targetDir: folderDir,
          courseDir: baseDir,
          item: sub,
          session: session,
        );
        done++;
        if (subPath != null) {
          sub.localPath = subPath;
          sub.status = 'downloaded';
          sub.downloadProgress = 1.0;
        }
        item.downloadProgress = done / item.subFiles.length;
        onProgress?.call(item.downloadProgress);
      }
      item.status = 'downloaded';
      item.localPath = folderDir.path;
      await _writeIndex(baseDir, course);
      return folderDir.path;
    }

    final orgBySec = courseOrgSections[course.id] ?? false;
    final targetDir = orgBySec
        ? Directory(p.join(baseDir.path, MoodleItem.sanitizeFileName(item.sectionName)))
        : baseDir;
    if (!await targetDir.exists()) await targetDir.create(recursive: true);

    item.status = 'downloading';
    item.downloadProgress = 0.0;
    try {
      final path = await _downloadSingleFile(
        targetDir: targetDir,
        courseDir: baseDir,
        item: item,
        session: session,
        onProgress: (prog) {
          item.downloadProgress = prog;
          onProgress?.call(prog);
        },
      );
      if (path != null) {
        item.localPath = path;
        item.status = 'downloaded';
        item.downloadProgress = 1.0;
        await _writeIndex(baseDir, course);
      } else {
        item.status = 'error';
      }
      return path;
    } catch (e) {
      item.status = 'error';
      rethrow;
    }
  }

  Future<String?> _downloadSingleFile({
    required Directory targetDir,
    required Directory courseDir,
    required MoodleItem item,
    required AulaSessionData session,
    void Function(double progress)? onProgress,
  }) async {
    var rawUrl = item.url;
    if (rawUrl == null || rawUrl.isEmpty) return null;

    if (session.token.isNotEmpty &&
        rawUrl.contains('pluginfile.php') &&
        !rawUrl.contains('token=')) {
      final sep = rawUrl.contains('?') ? '&' : '?';
      rawUrl = '$rawUrl${sep}token=${Uri.encodeQueryComponent(session.token)}';
    }

    final client = HttpClient();
    try {
      Uri uri = Uri.parse(rawUrl);
      // Resolve /mod/resource/view.php -> pluginfile redirect if cookie session is used
      HttpClientRequest request = await client.getUrl(uri);
      request.followRedirects = true;
      request.headers.set(HttpHeaders.userAgentHeader, _browserUserAgent);
      if (session.moodleSession.isNotEmpty) {
        request.headers.set(HttpHeaders.cookieHeader, 'MoodleSession=${session.moodleSession}');
      }
      HttpClientResponse response = await request.close();

      if (response.statusCode >= 400) {
        throw HttpException('HTTP ${response.statusCode} descargando ${item.cleanName}');
      }

      final contentType = response.headers.contentType?.mimeType ?? '';
      // If Moodle returned HTML wrapper page for mod/resource/view.php, try finding pluginfile link inside
      if (contentType.contains('text/html') && !rawUrl.contains('pluginfile.php')) {
        final htmlBytes = await response.fold<List<int>>([], (a, b) => a..addAll(b));
        final doc = html_parser.parse(utf8.decode(htmlBytes, allowMalformed: true));
        final pdfEmbed = doc.querySelector('a[href*="pluginfile.php"], iframe[src*="pluginfile.php"], object[data*="pluginfile.php"]');
        final resolvedUrl = pdfEmbed?.attributes['href'] ??
            pdfEmbed?.attributes['src'] ??
            pdfEmbed?.attributes['data'];
        if (resolvedUrl == null || resolvedUrl.isEmpty) {
          throw Exception('El recurso requiere inicio de sesión web actualizado.');
        }
        uri = Uri.parse(resolvedUrl);
        request = await client.getUrl(uri);
        request.followRedirects = true;
        request.headers.set(HttpHeaders.userAgentHeader, _browserUserAgent);
        if (session.moodleSession.isNotEmpty) {
          request.headers.set(HttpHeaders.cookieHeader, 'MoodleSession=${session.moodleSession}');
        }
        response = await request.close();
      }

      String fileName = item.fileName ?? '';
      final cd = response.headers.value('content-disposition') ?? '';
      final cdUtf8 = RegExp(r"filename\*=UTF-8''([^;]+)", caseSensitive: false).firstMatch(cd);
      final cdStd = RegExp(r'filename="?([^";]+)"?', caseSensitive: false).firstMatch(cd);
      if (cdUtf8 != null) {
        fileName = Uri.decodeComponent(cdUtf8.group(1)!);
      } else if (cdStd != null) {
        fileName = cdStd.group(1)!;
      }
      if (fileName.trim().isEmpty) {
        final pathSeg = uri.pathSegments.isNotEmpty ? uri.pathSegments.last : '';
        fileName = pathSeg.contains('.') ? Uri.decodeComponent(pathSeg) : item.cleanName;
      }
      fileName = MoodleItem.sanitizeFileName(fileName);
      if (!fileName.contains('.') && response.headers.contentType?.subType != null) {
        final sub = response.headers.contentType!.subType.toLowerCase();
        if (sub == 'pdf') fileName = '$fileName.pdf';
      }

      final filePath = p.join(targetDir.path, fileName);
      final tempFile = File('$filePath.part');
      final sink = tempFile.openWrite();
      final total = response.contentLength;
      int received = 0;

      await for (final chunk in response) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) {
          onProgress?.call((received / total).clamp(0.0, 1.0));
        }
      }
      await sink.flush();
      await sink.close();

      final targetFile = File(filePath);
      if (await targetFile.exists()) await targetFile.delete();
      await tempFile.rename(filePath);
      return filePath;
    } finally {
      client.close(force: true);
    }
  }

  Future<void> _writeIndex(Directory courseDir, MoodleCourse course) async {
    final indexFile = File(p.join(courseDir.path, indexFileName));
    final map = <String, String>{};
    for (final item in course.items) {
      if (item.localPath != null && item.localPath!.isNotEmpty) {
        final rel = p.relative(item.localPath!, from: courseDir.path);
        map[item.key] = rel;
      }
      for (final sub in item.subFiles) {
        if (sub.localPath != null && sub.localPath!.isNotEmpty) {
          final rel = p.relative(sub.localPath!, from: courseDir.path);
          map[sub.key] = rel;
        }
      }
    }
    await indexFile.writeAsString(jsonEncode({
      'courseId': course.id,
      'courseName': course.cleanName,
      'updatedAt': DateTime.now().toIso8601String(),
      'files': map,
    }));
  }

  /// Exports a linked Obsidian Knowledge Graph for a course (index + per-section notes).
  Future<String> exportCourseToObsidian({
    required MoodleCourse course,
    required String vaultOrRootPath,
  }) async {
    final folderName = MoodleItem.sanitizeFileName(course.cleanName);
    final courseNotesDir = Directory(p.join(vaultOrRootPath, folderName));
    if (!await courseNotesDir.exists()) {
      await courseNotesDir.create(recursive: true);
    }

    final sections = <String, List<MoodleItem>>{};
    for (final item in course.items) {
      sections.putIfAbsent(item.sectionName, () => []).add(item);
    }

    final indexFileName = '00 - Indice Aula - $folderName.md';
    final indexFile = File(p.join(courseNotesDir.path, indexFileName));
    String preservedNotes = '';
    if (await indexFile.exists()) {
      final old = await indexFile.readAsString();
      final idx = old.indexOf('## Notas Personales');
      if (idx >= 0) {
        preservedNotes = '\n${old.substring(idx)}';
      }
    }

    final sb = StringBuffer()
      ..writeln('# ${course.cleanName}')
      ..writeln()
      ..writeln('- **Sigla**: `${course.courseCode ?? course.shortName}`')
      ..writeln('- **Archivos**: ${course.downloadedCount}/${course.downloadableCount} descargados')
      ..writeln('- **Entregas con fecha**: ${course.deadlineCount}')
      ..writeln()
      ..writeln('## Secciones')
      ..writeln();

    int secCounter = 1;
    for (final entry in sections.entries) {
      final secSafe = MoodleItem.sanitizeFileName(entry.key);
      final secDocName = '${secCounter.toString().padLeft(2, '0')} - $secSafe.md';
      sb.writeln('- [[${p.basenameWithoutExtension(secDocName)}]] (${entry.value.length} elementos)');

      final secSb = StringBuffer()
        ..writeln('# ${entry.key}')
        ..writeln()
        ..writeln('← Volver a [[${p.basenameWithoutExtension(indexFileName)}]]')
        ..writeln();
      for (final item in entry.value) {
        final mark = item.hasDeadline ? (item.completed ? '[x]' : '[ ]') : '-';
        final due = item.dueDate != null ? ' (Vence ${item.dueDate!.day}/${item.dueDate!.month})' : '';
        final target = item.localPath != null
            ? '[Local](${Uri.file(item.localPath!).toString()})'
            : (item.url != null ? '[Aula](${item.url!})' : '');
        secSb.writeln('$mark **${item.cleanName}**$due $target');
      }
      await File(p.join(courseNotesDir.path, secDocName)).writeAsString(secSb.toString());
      secCounter++;
    }

    if (preservedNotes.isNotEmpty) {
      sb.write(preservedNotes);
    } else {
      sb
        ..writeln()
        ..writeln('## Notas Personales')
        ..writeln()
        ..writeln('- ');
    }

    await indexFile.writeAsString(sb.toString());
    return indexFile.path;
  }
}

/// Bridges Aula USM courses & deadlines directly into NotasApp's SQLite Semestres, Ramos, and Agenda.
class AulaNotasSynergyService {
  static const List<int> _palette = [
    0xFF3F51B5,
    0xFF00897B,
    0xFFE65100,
    0xFF8E24AA,
    0xFF1E88E5,
    0xFFD81B60,
    0xFF43A047,
    0xFFF4511E,
  ];

  static Future<int> ensureActiveSemester({
    int? currentSemesterId,
    required List<Semestre> semestres,
  }) async {
    if (currentSemesterId != null && semestres.any((s) => s.id == currentSemesterId)) {
      return currentSemesterId;
    }
    if (semestres.isNotEmpty && semestres.first.id != null) {
      return semestres.first.id!;
    }
    final now = DateTime.now();
    final semNum = now.month <= 7 ? 1 : 2;
    return DatabaseHelper.instance.insertSemester(
      Semestre(nombre: '${now.year}-$semNum').toMap(),
    );
  }

  static Future<Ramo> createRamoFromCourse({
    required MoodleCourse course,
    required int semesterId,
    required String escalaNotas,
    required int orderIndex,
  }) async {
    final colorValue = _palette[course.id.abs() % _palette.length];
    final ramo = Ramo(
      idSemestre: semesterId,
      nombre: course.cleanName,
      tipoPromedio: 'Aritmetico',
      tieneGlobal: false,
      reemplazaPeorNota: false,
      notaAprobacion: escalaNotas == '0 a 100' ? 55.0 : 4.0,
      orderIndex: orderIndex,
      color: colorValue,
    );
    final insertedId = await DatabaseHelper.instance.insertSubject(ramo.toMap());
    ramo.id = insertedId;
    return ramo;
  }

  static Future<({int added, int skipped})> importDeadlinesToAgenda({
    required List<MoodleItem> items,
    required Ramo ramo,
  }) async {
    if (ramo.id == null) return (added: 0, skipped: 0);
    final withDates = items.where((i) => i.hasDeadline).toList();
    if (withDates.isEmpty) return (added: 0, skipped: 0);

    final db = DatabaseHelper.instance;
    final catsRaw = await db.queryCategoriesBySubject(ramo.id!);
    int? aulaCategoryId;
    final existingEvals = <Evaluacion>[];

    for (final cMap in catsRaw) {
      final cat = CategoriaEvaluacion.fromMap(cMap);
      final evRaw = await db.queryEvaluationsByCategory(cat.id!);
      existingEvals.addAll(evRaw.map(Evaluacion.fromMap));
      if (cat.nombre.toLowerCase() == 'aula usm' || cat.nombre.toLowerCase() == 'aula') {
        aulaCategoryId = cat.id;
      }
    }

    aulaCategoryId ??= await db.insertCategory(
      CategoriaEvaluacion(
        idRamo: ramo.id!,
        nombre: 'Aula USM',
        // Weight 0% keeps the user's weighted grade calculation untouched while placing due dates into Agenda.
        porcentajeTotal: 0.0,
      ).toMap(),
    );

    int added = 0;
    int skipped = 0;
    for (final item in withDates) {
      if (MoodleCourse.findMatchingEvaluacion(item, existingEvals) != null) {
        skipped++;
        continue;
      }
      final ev = Evaluacion(
        idCategoria: aulaCategoryId,
        nombre: 'Aula: ${item.cleanName}',
        fecha: item.dueDate,
      );
      final evId = await db.insertEvaluation(ev.toMap());
      ev.id = evId;
      existingEvals.add(ev);
      if (ev.fecha != null && ev.fecha!.isAfter(DateTime.now())) {
        await NotificationService.scheduleEvaluationReminder(ev, ramo.nombre);
      }
      added++;
    }
    return (added: added, skipped: skipped);
  }
}
