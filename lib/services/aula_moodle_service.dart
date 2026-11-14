import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'dart:io';

import '../models/aula_course.dart';
import 'aula_settings_service.dart';

class SessionExpiredException implements Exception {
  final String message;
  SessionExpiredException([
    this.message = 'Tu sesión en Aula USM expiró. Inicia sesión nuevamente.',
  ]);
  @override
  String toString() => message;
}

class DownloadedFileData {
  final Uint8List bytes;
  final String fileName;
  final String fileExt;

  const DownloadedFileData({
    required this.bytes,
    required this.fileName,
    required this.fileExt,
  });
}

class MoodleService {
  static const String baseUrl = 'https://aula.usm.cl';
  static const String userAgent =
      'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36';

  final http.Client _client;
  final SettingsService _settings = SettingsService.instance;

  String token = '';
  String cookie = '';
  String sesskey = '';
  String userName = '';
  String userId = '';

  MoodleService({
    AulaSessionData? session,
    http.Client? client,
  }) : _client = client ?? http.Client() {
    if (session != null) {
      applySession(session);
    }
  }

  bool get isAuthenticated => token.isNotEmpty || cookie.isNotEmpty;
  bool get isTokenAuth => token.isNotEmpty;

  AulaSessionData get session => AulaSessionData(
        token: token,
        cookie: cookie,
        sesskey: sesskey,
        userName: userName,
        userId: int.tryParse(userId),
      );

  void applySession(AulaSessionData s) {
    token = s.token.trim();
    cookie = _normalizeCookie(s.cookie);
    sesskey = s.sesskey.trim();
    userName = s.userName.trim();
    userId = s.userIdString;
  }

  Future<AulaSessionData> loadSession() async {
    final s = await _settings.loadSession();
    applySession(s);
    return s;
  }

  Future<void> saveSession() async {
    await _settings.saveSession(session);
  }

  Future<void> logout() async {
    token = '';
    cookie = '';
    sesskey = '';
    userName = '';
    userId = '';
    await _settings.clearSession();
  }

  String _normalizeCookie(String raw) {
    var clean = raw.trim();
    if (clean.toLowerCase().startsWith('cookie:')) {
      clean = clean.substring(7).trim();
    }
    if (clean.isNotEmpty && !clean.contains('=')) {
      clean = 'MoodleSession=$clean';
    }
    return clean;
  }

  Map<String, String> _cookieHeaders([Map<String, String>? extra]) {
    final headers = <String, String>{
      'User-Agent': userAgent,
      'Accept':
          'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
    };
    if (cookie.isNotEmpty) {
      headers['Cookie'] = cookie;
    }
    if (extra != null) {
      headers.addAll(extra);
    }
    return headers;
  }

  /// Follows HTTP redirects manually while preserving Moodle cookies and updating Set-Cookie values.
  Future<
      ({
        int statusCode,
        Map<String, String> headers,
        Uint8List bodyBytes,
        String finalUrl,
      })> _getFollowingRedirects(
    String url, {
    Map<String, String>? extraHeaders,
    int maxRedirects = 8,
  }) async {
    var currentUrl = url;
    var activeCookie = cookie;

    for (var hop = 0; hop <= maxRedirects; hop++) {
      final uri = Uri.parse(currentUrl);
      final req = http.Request('GET', uri)..followRedirects = false;
      req.headers.addAll({
        'User-Agent': userAgent,
        'Accept': '*/*',
        if (activeCookie.isNotEmpty) 'Cookie': activeCookie,
        ...?extraHeaders,
      });

      final streamed =
          await _client.send(req).timeout(const Duration(seconds: 25));
      final bodyBytes = await streamed.stream.toBytes();
      final headers = streamed.headers;

      final setCookie = headers['set-cookie'];
      if (setCookie != null && setCookie.isNotEmpty) {
        activeCookie = _mergeCookieString(activeCookie, setCookie);
        if (uri.host.endsWith('aula.usm.cl')) {
          cookie = activeCookie;
        }
      }

      if (streamed.statusCode >= 300 &&
          streamed.statusCode < 400 &&
          headers['location'] != null) {
        final next = uri.resolve(headers['location']!).toString();
        currentUrl = next;
        continue;
      }

      return (
        statusCode: streamed.statusCode,
        headers: headers,
        bodyBytes: bodyBytes,
        finalUrl: currentUrl,
      );
    }

    throw Exception('Demasiadas redirecciones al acceder a Aula USM.');
  }

  String _mergeCookieString(String existing, String setCookieHeader) {
    final jar = <String, String>{};
    for (final part in existing.split(';')) {
      final eq = part.indexOf('=');
      if (eq > 0) {
        jar[part.substring(0, eq).trim()] = part.substring(eq + 1).trim();
      }
    }
    // Extract key=val from Set-Cookie segments
    final regex = RegExp(r'(?:^|,)\s*([^=;\s]+)=([^;]*)');
    for (final m in regex.allMatches(setCookieHeader)) {
      final k = m.group(1)?.trim() ?? '';
      final v = m.group(2)?.trim() ?? '';
      if (k.isEmpty) continue;
      final lower = k.toLowerCase();
      if (const {
        'path',
        'domain',
        'expires',
        'max-age',
        'samesite',
        'priority',
      }.contains(lower)) {
        continue;
      }
      jar[k] = v;
    }
    return jar.entries.map((e) => '${e.key}=${e.value}').join('; ');
  }

  static bool isAuthenticatedMoodleHtml(String html) {
    final lower = html.toLowerCase();
    if (lower.contains('name="logintoken"') ||
        lower.contains('login.microsoftonline.com') ||
        lower.contains('action="https://aula.usm.cl/login/index.php"')) {
      if (!lower.contains('login/logout.php')) return false;
    }
    return lower.contains('login/logout.php') ||
        lower.contains('"sesskey"') ||
        lower.contains('m.cfg') ||
        lower.contains('usermenu');
  }

  void extractSessionDetails(String html) {
    final sessMatch =
        RegExp(r'"sesskey"\s*:\s*"([^"]+)"').firstMatch(html) ??
            RegExp(r'sesskey=([A-Za-z0-9]+)').firstMatch(html);
    if (sessMatch != null) {
      sesskey = sessMatch.group(1)?.trim() ?? sesskey;
    }

    final uidMatch =
        RegExp(r'"userId"\s*:\s*(\d+)').firstMatch(html) ??
            RegExp(r'data-userid="(\d+)"').firstMatch(html) ??
            RegExp(r'/user/profile\.php\?id=(\d+)').firstMatch(html);
    if (uidMatch != null) {
      userId = uidMatch.group(1)?.trim() ?? userId;
    }

    try {
      final doc = html_parser.parse(html);
      final nameEl = doc.querySelector('.usertext') ??
          doc.querySelector('.usermenu .userbutton .usertext') ??
          doc.querySelector('[data-region="usermenu"] .userinitials') ??
          doc.querySelector('.page-header-headings h1');
      final candidate = nameEl?.text.trim() ?? '';
      if (candidate.isNotEmpty &&
          candidate.length < 80 &&
          !candidate.toLowerCase().contains('área personal')) {
        userName = candidate;
      }
    } catch (_) {}
  }

  Future<bool> verifySessionLive() async {
    if (!isAuthenticated) return false;
    try {
      if (isTokenAuth) {
        final info = await _callWs('core_webservice_get_site_info', {});
        if (info is Map) {
          userName = (info['fullname'] ?? userName).toString();
          userId = (info['userid'] ?? userId).toString();
          await saveSession();
          return true;
        }
        return false;
      }
      final res = await _getFollowingRedirects('$baseUrl/my/');
      final html = utf8.decode(res.bodyBytes, allowMalformed: true);
      if (res.statusCode == 200 && isAuthenticatedMoodleHtml(html)) {
        extractSessionDetails(html);
        await saveSession();
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<AulaSessionData> validateSession() async {
    final ok = await verifySessionLive();
    if (!ok) {
      throw SessionExpiredException();
    }
    return session;
  }

  Future<AulaSessionData> loginWithToken(String rawToken) async {
    final cleanToken = rawToken.trim();
    if (cleanToken.isEmpty) {
      throw Exception('Ingresa un Token de WebService válido.');
    }
    token = cleanToken;
    cookie = '';
    try {
      final info = await _callWs('core_webservice_get_site_info', {});
      if (info is! Map || info['userid'] == null) {
        token = '';
        throw Exception('El token de Aula USM no es válido o expiró.');
      }
      userName = (info['fullname'] ?? 'Estudiante USM').toString();
      userId = info['userid'].toString();
      await saveSession();
      return session;
    } catch (e) {
      token = '';
      rethrow;
    }
  }

  Future<AulaSessionData> loginWithCookie(String rawCookie) async {
    final normalized = _normalizeCookie(rawCookie);
    if (normalized.isEmpty) {
      throw Exception('Ingresa una cookie de sesión válida.');
    }
    cookie = normalized;
    token = '';
    try {
      final res = await _getFollowingRedirects('$baseUrl/my/');
      final html = utf8.decode(res.bodyBytes, allowMalformed: true);
      if (res.statusCode != 200 || !isAuthenticatedMoodleHtml(html)) {
        cookie = '';
        throw SessionExpiredException(
          'La cookie ingresada expiró o no corresponde a una sesión activa en Aula USM.',
        );
      }
      extractSessionDetails(html);
      if (userName.isEmpty) {
        userName = 'Estudiante USM';
      }
      await saveSession();
      return session;
    } catch (e) {
      cookie = '';
      rethrow;
    }
  }

  Future<({AulaSessionData session, Map<int, String> folders})>
      loginFromPairingClaim(
    String serverBaseUrl,
    String pin,
  ) async {
    var cleanBase = serverBaseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    if (!cleanBase.startsWith('http://') && !cleanBase.startsWith('https://')) {
      cleanBase = 'http://$cleanBase';
    }
    final cleanPin = pin.trim().toUpperCase();
    final uri = Uri.parse(
      '$cleanBase/api/pair/claim?pin=${Uri.encodeQueryComponent(cleanPin)}',
    );
    final resp = await _client.get(uri).timeout(const Duration(seconds: 12));
    if (resp.statusCode != 200) {
      throw Exception(
        'No se pudo emparejar con el PC (HTTP ${resp.statusCode}). Verifica el PIN e IP.',
      );
    }

    final map = jsonDecode(resp.body) as Map<String, dynamic>;
    final sessJson = map['session'] is Map
        ? Map<String, dynamic>.from(map['session'] as Map)
        : map;

    final pairedToken =
        (sessJson['token'] ?? sessJson['moodle_token'] ?? '').toString().trim();
    final pairedCookie =
        (sessJson['cookie'] ?? sessJson['moodle_cookie'] ?? '')
            .toString()
            .trim();
    final pairedSesskey =
        (sessJson['sesskey'] ?? sessJson['moodle_sesskey'] ?? '')
            .toString()
            .trim();
    final pairedUser =
        (sessJson['userName'] ?? sessJson['user_name'] ?? '').toString().trim();
    final pairedUid =
        (sessJson['userId'] ?? sessJson['user_id'] ?? '').toString().trim();

    if (pairedToken.isEmpty && pairedCookie.isEmpty) {
      throw Exception('El PC no envió credenciales de Aula válidas.');
    }

    applySession(AulaSessionData(
      token: pairedToken,
      cookie: pairedCookie,
      sesskey: pairedSesskey,
      userName: pairedUser,
      userId: int.tryParse(pairedUid),
    ));
    await saveSession();

    final folders = <int, String>{};
    final rawFolders = map['course_folders'] ?? map['courseFolders'];
    if (rawFolders is Map) {
      rawFolders.forEach((k, v) {
        final cid = int.tryParse(k.toString());
        if (cid != null && v != null && v.toString().trim().isNotEmpty) {
          folders[cid] = v.toString().trim();
        }
      });
    }

    final settingsMap = map['settings'] is Map
        ? Map<String, dynamic>.from(map['settings'] as Map)
        : <String, dynamic>{};
    await _settings.applyPairedSettings(settingsMap, folders);

    return (session: session, folders: folders);
  }

  Future<dynamic> _callWs(
    String wsfunction,
    Map<String, String> params,
  ) async {
    final uri = Uri.parse('$baseUrl/webservice/rest/server.php').replace(
      queryParameters: {
        'wstoken': token,
        'wsfunction': wsfunction,
        'moodlewsrestformat': 'json',
        ...params,
      },
    );
    final res = await _client.get(uri).timeout(const Duration(seconds: 25));
    if (res.statusCode != 200) {
      throw Exception('Error Aula WebService (${res.statusCode})');
    }
    final decoded = jsonDecode(utf8.decode(res.bodyBytes));
    if (decoded is Map && decoded['exception'] != null) {
      final errCode = decoded['errorcode']?.toString() ?? '';
      if (errCode == 'invalidtoken' || errCode == 'accessexception') {
        throw SessionExpiredException(
          decoded['message']?.toString() ?? 'Token inválido o expirado.',
        );
      }
      throw Exception(decoded['message']?.toString() ?? 'Error en Aula');
    }
    return decoded;
  }

  Future<List<MoodleCourse>> getCourses() async {
    if (!isAuthenticated) throw SessionExpiredException();

    if (isTokenAuth) {
      if (userId.isEmpty) {
        await verifySessionLive();
      }
      final rawList = await _callWs('core_enrol_get_users_courses', {
        'userid': userId,
      });
      final courses = <MoodleCourse>[];
      if (rawList is List) {
        for (final item in rawList) {
          if (item is! Map) continue;
          final id = (item['id'] as num?)?.toInt() ?? 0;
          if (id <= 1) continue;
          final full = item['fullname']?.toString() ?? 'Curso $id';
          final short = item['shortname']?.toString() ?? '';
          courses.add(MoodleCourse(
            id: id,
            fullname: full,
            shortname: short,
            url: '$baseUrl/course/view.php?id=$id',
          ));
        }
      }
      return courses;
    }

    // Cookie auth: parse both /my/courses.php and /my/ + AJAX timeline
    final byId = <int, MoodleCourse>{};
    for (final path in ['/my/courses.php', '/my/']) {
      try {
        final res = await _getFollowingRedirects('$baseUrl$path');
        final html = utf8.decode(res.bodyBytes, allowMalformed: true);
        if (!isAuthenticatedMoodleHtml(html)) {
          if (path == '/my/courses.php') continue;
          throw SessionExpiredException();
        }
        extractSessionDetails(html);
        final doc = html_parser.parse(html);
        for (final a in doc.querySelectorAll('a[href*="course/view.php?id="]')) {
          final href = a.attributes['href'] ?? '';
          final idMatch = RegExp(r'id=(\d+)').firstMatch(href);
          if (idMatch == null) continue;
          final cid = int.tryParse(idMatch.group(1)!) ?? 0;
          if (cid <= 1) continue;
          final rawText = _cleanMoodleTitle(a.text);
          if (rawText.isEmpty ||
              rawText.toLowerCase() == 'ir al curso' ||
              rawText.toLowerCase() == 'ver') {
            continue;
          }
          byId.putIfAbsent(
            cid,
            () => MoodleCourse(
              id: cid,
              fullname: rawText,
              shortname: a.attributes['data-shortname'] ?? '',
              url: '$baseUrl/course/view.php?id=$cid',
            ),
          );
        }
      } catch (e) {
        if (e is SessionExpiredException) rethrow;
      }
    }

    // Also try Moodle AJAX enrolled courses endpoint if sesskey is known
    if (sesskey.isNotEmpty) {
      try {
        final ajaxRes = await _client
            .post(
              Uri.parse('$baseUrl/lib/ajax/service.php?sesskey=$sesskey'),
              headers: _cookieHeaders({'Content-Type': 'application/json'}),
              body: jsonEncode([
                {
                  'index': 0,
                  'methodname':
                      'core_course_get_enrolled_courses_by_timeline_classification',
                  'args': {
                    'offset': 0,
                    'limit': 100,
                    'classification': 'all',
                    'sort': 'fullname',
                  },
                }
              ]),
            )
            .timeout(const Duration(seconds: 15));
        if (ajaxRes.statusCode == 200) {
          final decoded = jsonDecode(utf8.decode(ajaxRes.bodyBytes));
          if (decoded is List &&
              decoded.isNotEmpty &&
              decoded[0] is Map &&
              decoded[0]['error'] != true) {
            final coursesJson =
                decoded[0]['data']?['courses'] as List? ?? const [];
            for (final c in coursesJson) {
              if (c is! Map) continue;
              final cid = (c['id'] as num?)?.toInt() ?? 0;
              if (cid <= 1) continue;
              final full = c['fullname']?.toString() ?? 'Curso $cid';
              final short = c['shortname']?.toString() ?? '';
              byId[cid] = MoodleCourse(
                id: cid,
                fullname: full,
                shortname: short,
                url: '$baseUrl/course/view.php?id=$cid',
              );
            }
          }
        }
      } catch (_) {}
    }

    await saveSession();
    final list = byId.values.toList()
      ..sort((a, b) => a.cleanName.toLowerCase().compareTo(b.cleanName.toLowerCase()));
    return list;
  }

  Future<List<MoodleItem>> scanCourseContents(MoodleCourse course) async {
    if (!isAuthenticated) throw SessionExpiredException();
    if (isTokenAuth) {
      return _scanContentsWithToken(course);
    }
    return _scanContentsWithCookie(course);
  }

  Future<List<MoodleItem>> _scanContentsWithToken(MoodleCourse course) async {
    final sectionsRaw = await _callWs('core_course_get_contents', {
      'courseid': course.id.toString(),
    });
    final items = <MoodleItem>[];
    final seenUrls = <String>{};

    if (sectionsRaw is List) {
      for (final sec in sectionsRaw) {
        if (sec is! Map) continue;
        final secName =
            _cleanMoodleTitle(sec['name']?.toString() ?? 'General');
        final effectiveSection = secName.isEmpty ? 'General' : secName;
        final modules = sec['modules'] as List? ?? const [];

        for (final mod in modules) {
          if (mod is! Map) continue;
          final modId = (mod['id'] as num?)?.toInt() ?? 0;
          final modName = mod['modname']?.toString() ?? 'resource';
          final modTitle =
              _cleanMoodleTitle(mod['name']?.toString() ?? 'Recurso');
          final modUrl = mod['url']?.toString() ?? '';
          final contents = mod['contents'] as List? ?? const [];

          if (modName == 'folder') {
            var idx = 0;
            for (final c in contents) {
              if (c is! Map) continue;
              final fileUrl = c['fileurl']?.toString() ?? '';
              if (fileUrl.isEmpty) continue;
              final fname = c['filename']?.toString() ?? 'archivo';
              final ext = inferFileExt(fname, fileUrl);
              final size = (c['filesize'] as num?)?.toInt();
              seenUrls.add(fileUrl);
              items.add(MoodleItem(
                id: '${course.id}_${modId}_f$idx',
                courseId: course.id,
                title: fname,
                section: '$effectiveSection / $modTitle',
                type: 'resource',
                url: _appendToken(fileUrl),
                fileName: fname,
                fileExt: ext,
                downloadable: true,
                sizeBytes: size,
              ));
              idx++;
            }
            if (idx == 0 && modUrl.isNotEmpty) {
              items.add(MoodleItem(
                id: '${course.id}_$modId',
                courseId: course.id,
                title: modTitle,
                section: effectiveSection,
                type: 'folder',
                url: modUrl,
                fileName: '${MoodleCourse.sanitizeFileName(modTitle)}.zip',
                fileExt: 'zip',
                downloadable: true,
              ));
            }
            continue;
          }

          if (modName == 'url') {
            final extUrl = contents.isNotEmpty && contents[0] is Map
                ? (contents[0]['fileurl']?.toString() ?? modUrl)
                : modUrl;
            items.add(MoodleItem(
              id: '${course.id}_$modId',
              courseId: course.id,
              title: modTitle,
              section: effectiveSection,
              type: 'url',
              url: extUrl,
              downloadable: false,
            ));
            continue;
          }

          if (contents.isNotEmpty && modName == 'resource') {
            var idx = 0;
            for (final c in contents) {
              if (c is! Map) continue;
              final fUrl = c['fileurl']?.toString() ?? '';
              if (fUrl.isEmpty) continue;
              final fname = c['filename']?.toString() ?? '$modTitle.pdf';
              final ext = inferFileExt(fname, fUrl);
              final size = (c['filesize'] as num?)?.toInt();
              final itemTitle = contents.length == 1 ? modTitle : fname;
              seenUrls.add(fUrl);
              items.add(MoodleItem(
                id: '${course.id}_${modId}_$idx',
                courseId: course.id,
                title: itemTitle,
                section: effectiveSection,
                type: 'resource',
                url: _appendToken(fUrl),
                fileName: fname,
                fileExt: ext,
                downloadable: true,
                sizeBytes: size,
              ));
              idx++;
            }
            continue;
          }

          // Activity (assign, quiz, forum, page, etc.)
          final dueInfo = _extractDatesFromWsModule(mod);
          items.add(MoodleItem(
            id: '${course.id}_$modId',
            courseId: course.id,
            title: modTitle,
            section: effectiveSection,
            type: modName,
            url: modUrl,
            downloadable: false,
            dueTimestamp: dueInfo.ts,
            dueText: dueInfo.text,
          ));

          // Also include any embedded resource files inside assign/page description
          for (var cIdx = 0; cIdx < contents.length; cIdx++) {
            final c = contents[cIdx];
            if (c is! Map) continue;
            final fUrl = c['fileurl']?.toString() ?? '';
            if (fUrl.isEmpty || seenUrls.contains(fUrl)) continue;
            seenUrls.add(fUrl);
            final fname = c['filename']?.toString() ?? '';
            items.add(MoodleItem(
              id: '${course.id}_${modId}_emb_$cIdx',
              courseId: course.id,
              title: fname.isNotEmpty ? '$modTitle — $fname' : modTitle,
              section: effectiveSection,
              type: 'resource',
              url: _appendToken(fUrl),
              fileName: fname,
              fileExt: inferFileExt(fname, fUrl),
              downloadable: true,
              sizeBytes: (c['filesize'] as num?)?.toInt(),
            ));
          }
        }
      }
    }

    await _attachWebServiceDeadlines(course.id, items);
    return items;
  }

  ({int? ts, String? text}) _extractDatesFromWsModule(Map mod) {
    final dates = mod['dates'] as List? ?? const [];
    int? foundTs;
    String? foundLabel;
    for (final d in dates) {
      if (d is! Map) continue;
      final dataId = (d['dataid'] ?? d['label'] ?? '').toString().toLowerCase();
      final ts = (d['timestamp'] as num?)?.toInt();
      if (ts != null &&
          ts > 0 &&
          (dataId.contains('due') ||
              dataId.contains('close') ||
              dataId.contains('venc') ||
              dataId.contains('cierr'))) {
        foundTs = ts;
        foundLabel = d['label']?.toString();
      }
    }
    if (foundTs != null) {
      return (ts: foundTs, text: foundLabel);
    }
    return (ts: null, text: null);
  }

  Future<void> _attachWebServiceDeadlines(
    int courseId,
    List<MoodleItem> items,
  ) async {
    try {
      final assignsRaw = await _callWs('mod_assign_get_assignments', {
        'courseids[0]': courseId.toString(),
      });
      if (assignsRaw is Map && assignsRaw['courses'] is List) {
        for (final c in assignsRaw['courses'] as List) {
          if (c is! Map) continue;
          for (final a in (c['assignments'] as List? ?? const [])) {
            if (a is! Map) continue;
            final cmid = (a['cmid'] as num?)?.toInt();
            final due = (a['duedate'] as num?)?.toInt();
            final name = a['name']?.toString() ?? '';
            if (due != null && due > 0) {
              for (final item in items) {
                if (item.id == '${courseId}_$cmid' ||
                    (name.isNotEmpty &&
                        normalizeMatchKey(item.title) ==
                            normalizeMatchKey(name))) {
                  item.dueTimestamp ??= due;
                }
              }
            }
          }
        }
      }
    } catch (_) {}

    try {
      final quizzesRaw = await _callWs('mod_quiz_get_quizzes_by_courses', {
        'courseids[0]': courseId.toString(),
      });
      if (quizzesRaw is Map && quizzesRaw['quizzes'] is List) {
        for (final q in quizzesRaw['quizzes'] as List) {
          if (q is! Map) continue;
          final cmid = (q['coursemodule'] as num?)?.toInt();
          final close = (q['timeclose'] as num?)?.toInt();
          final name = q['name']?.toString() ?? '';
          if (close != null && close > 0) {
            for (final item in items) {
              if (item.id == '${courseId}_$cmid' ||
                  (name.isNotEmpty &&
                      normalizeMatchKey(item.title) ==
                          normalizeMatchKey(name))) {
                item.dueTimestamp ??= close;
              }
            }
          }
        }
      }
    } catch (_) {}
  }

  Future<List<MoodleItem>> _scanContentsWithCookie(MoodleCourse course) async {
    final mainUrl = '$baseUrl/course/view.php?id=${course.id}';
    final mainRes = await _getFollowingRedirects(mainUrl);
    final mainHtml = utf8.decode(mainRes.bodyBytes, allowMalformed: true);
    if (!isAuthenticatedMoodleHtml(mainHtml)) {
      throw SessionExpiredException();
    }
    extractSessionDetails(mainHtml);
    final mainDoc = html_parser.parse(mainHtml);

    // Collect additional tabbed/single-section pages (onetopic, tiles, flexible format)
    final sectionUrls = <String>{};
    for (final a in mainDoc.querySelectorAll(
      '.nav-tabs a[href*="course/view.php"], '
      '.nav-pills a[href*="course/view.php"], '
      'ul.topics a[href*="section="], '
      '.course-content a[href*="section="], '
      'a[href*="sectionid="]',
    )) {
      final href = a.attributes['href'] ?? '';
      if (href.contains('id=${course.id}') &&
          (href.contains('section=') || href.contains('sectionid='))) {
        final resolved = Uri.parse(mainUrl).resolve(href).toString().split('#').first;
        sectionUrls.add(resolved);
      }
    }

    final parsedItems = <MoodleItem>[];
    final folderItems = <MoodleItem>[];
    final seenUrls = <String>{};
    final seenModIds = <String>{};

    void absorbDoc(dom.Document doc) {
      final (items, folders) = _parseActivitiesFromDoc(
        doc,
        course.id,
        seenUrls,
        seenModIds,
      );
      parsedItems.addAll(items);
      folderItems.addAll(folders);
    }

    absorbDoc(mainDoc);

    // Crawl section tabs with bounded concurrency (4)
    final tabList = sectionUrls.toList();
    for (var i = 0; i < tabList.length; i += 4) {
      final batch = tabList.sublist(
        i,
        i + 4 > tabList.length ? tabList.length : i + 4,
      );
      await Future.wait(batch.map((secUrl) async {
        try {
          final r = await _getFollowingRedirects(secUrl);
          final h = utf8.decode(r.bodyBytes, allowMalformed: true);
          if (r.statusCode == 200 && isAuthenticatedMoodleHtml(h)) {
            absorbDoc(html_parser.parse(h));
          }
        } catch (_) {}
      }));
    }

    // Flatten Moodle /mod/folder/ resources concurrently (max 4)
    final finalItems = <MoodleItem>[...parsedItems];
    for (var i = 0; i < folderItems.length; i += 4) {
      final batch = folderItems.sublist(
        i,
        i + 4 > folderItems.length ? folderItems.length : i + 4,
      );
      final expandedLists = await Future.wait(
        batch.map((folderItem) => _extractFolderFiles(folderItem, seenUrls)),
      );
      for (final expanded in expandedLists) {
        finalItems.addAll(expanded);
      }
    }

    // Deduplicate while maintaining order
    final unique = <MoodleItem>[];
    final seenIds = <String>{};
    for (final it in finalItems) {
      if (seenIds.add(it.id)) {
        unique.add(it);
      }
    }

    return unique;
  }

  (List<MoodleItem>, List<MoodleItem>) _parseActivitiesFromDoc(
    dom.Document doc,
    int courseId,
    Set<String> seenUrls,
    Set<String> seenModIds,
  ) {
    final items = <MoodleItem>[];
    final folders = <MoodleItem>[];

    // Check active tab name fallback (Onetopic)
    final activeTabName = _cleanMoodleTitle(
      doc.querySelector('.nav-tabs .nav-link.active')?.text ??
          doc.querySelector('.nav-pills .nav-link.active')?.text ??
          '',
    );

    var sectionEls = doc.querySelectorAll(
      'li.section.main, div.section.main, li[id^="section-"]',
    );
    if (sectionEls.isEmpty) {
      sectionEls = doc.querySelectorAll('.course-content .section');
    }

    for (final secEl in sectionEls) {
      var secTitle = _cleanMoodleTitle(
        secEl.querySelector('.sectionname')?.text ??
            secEl.querySelector('h3.sectionname')?.text ??
            secEl.querySelector('.section-title')?.text ??
            '',
      );
      if (secTitle.isEmpty) {
        secTitle = activeTabName.isNotEmpty ? activeTabName : 'General';
      }

      // Extract activities in this section
      final activities = secEl.querySelectorAll(
        'li.activity, .activity-item[data-activityname], div.activity[id^="module-"]',
      );

      for (final act in activities) {
        final modAttrId = act.attributes['id'] ?? '';
        final dataId = act.attributes['data-id'] ?? '';
        var modNum = '';
        final idMatch = RegExp(r'module-(\d+)').firstMatch(modAttrId);
        if (idMatch != null) {
          modNum = idMatch.group(1)!;
        } else if (dataId.isNotEmpty) {
          modNum = dataId;
        }

        // Determine modtype from classes or link
        var modType = 'resource';
        for (final cls in act.classes) {
          if (cls.startsWith('modtype_')) {
            modType = cls.substring(8);
            break;
          }
        }

        final mainLink = act.querySelector('a.aalink') ??
            act.querySelector('.activityname a') ??
            act.querySelector('.activity-instance a[href*="/mod/"]') ??
            act.querySelector('a[href*="/mod/"]');

        if (mainLink != null) {
          final href = mainLink.attributes['href'] ?? '';
          if (href.isNotEmpty) {
            if (modNum.isEmpty) {
              final linkIdMatch = RegExp(r'id=(\d+)').firstMatch(href);
              if (linkIdMatch != null) modNum = linkIdMatch.group(1)!;
            }
            if (modType == 'resource') {
              final modMatch = RegExp(r'/mod/([a-z0-9_]+)/').firstMatch(href);
              if (modMatch != null) modType = modMatch.group(1)!;
            }

            final modKey = '${courseId}_${modNum.isNotEmpty ? modNum : href.hashCode}';
            if (!seenModIds.add(modKey)) continue;

            // Clean title ignoring .accesshide
            final titleClone = mainLink.clone(true);
            for (final hidden in titleClone.querySelectorAll('.accesshide')) {
              hidden.remove();
            }
            var title = _cleanMoodleTitle(
              titleClone.querySelector('.instancename')?.text ??
                  act.attributes['data-activityname'] ??
                  titleClone.text,
            );
            if (title.isEmpty) title = 'Recurso $modNum';

            final resolvedUrl = Uri.parse(baseUrl).resolve(href).toString();
            seenUrls.add(resolvedUrl);

            // Deadlines from activity-dates
            final datesText = _cleanMoodleTitle(
              act.querySelector('.activity-dates')?.text ??
                  act.querySelector('[data-region="activity-dates"]')?.text ??
                  act.querySelector('.description-inner')?.text ??
                  '',
            );
            final dueTs = parseDueTimestamp(datesText);

            final isResource = modType == 'resource';
            final ext = isResource ? inferFileExt(title, resolvedUrl) : '';

            final item = MoodleItem(
              id: modKey,
              courseId: courseId,
              title: title,
              section: secTitle,
              type: modType,
              url: resolvedUrl,
              fileName: isResource ? '$title${ext.isNotEmpty ? ".$ext" : ""}' : '',
              fileExt: ext,
              downloadable: isResource,
              dueTimestamp: dueTs,
              dueText: dueTs != null ? _extractShortDateLine(datesText) : null,
            );

            if (modType == 'folder') {
              folders.add(item);
            } else {
              items.add(item);
            }
          }
        }

        // Also scan for embedded pluginfile links inside activity description/label
        _extractEmbeddedPluginFiles(
          act,
          courseId,
          secTitle,
          items,
          seenUrls,
        );
      }

      // Scan section summary embedded pluginfiles as well
      final summary = secEl.querySelector('.summary');
      if (summary != null) {
        _extractEmbeddedPluginFiles(
          summary,
          courseId,
          secTitle,
          items,
          seenUrls,
        );
      }
    }

    return (items, folders);
  }

  void _extractEmbeddedPluginFiles(
    dom.Element root,
    int courseId,
    String sectionTitle,
    List<MoodleItem> out,
    Set<String> seenUrls,
  ) {
    final mediaEls = root.querySelectorAll(
      'a[href*="pluginfile.php"], video source[src*="pluginfile.php"], audio source[src*="pluginfile.php"], iframe[src*="pluginfile.php"]',
    );
    for (final el in mediaEls) {
      final rawHref = el.attributes['href'] ?? el.attributes['src'] ?? '';
      if (rawHref.isEmpty) continue;
      final cleanUrl = Uri.parse(baseUrl).resolve(rawHref).toString();
      if (!seenUrls.add(cleanUrl)) continue;

      final uriPath = Uri.tryParse(cleanUrl)?.path ?? '';
      final urlBaseName = uriPath.isNotEmpty
          ? Uri.decodeComponent(p.basename(uriPath))
          : '';
      var label = _cleanMoodleTitle(el.text);
      if (label.isEmpty || label.length > 100) {
        label = urlBaseName.isNotEmpty ? urlBaseName : 'Archivo adjunto';
      }
      final fname = urlBaseName.isNotEmpty ? urlBaseName : label;
      final ext = inferFileExt(fname, cleanUrl);
      if (ext.isEmpty && !cleanUrl.contains('pluginfile.php')) continue;

      out.add(MoodleItem(
        id: '${courseId}_emb_${cleanUrl.hashCode.abs()}',
        courseId: courseId,
        title: label,
        section: sectionTitle,
        type: 'resource',
        url: cleanUrl,
        fileName: fname,
        fileExt: ext,
        downloadable: true,
      ));
    }
  }

  Future<List<MoodleItem>> _extractFolderFiles(
    MoodleItem folderItem,
    Set<String> seenUrls,
  ) async {
    try {
      final res = await _getFollowingRedirects(folderItem.url);
      final html = utf8.decode(res.bodyBytes, allowMalformed: true);
      if (res.statusCode != 200 || !isAuthenticatedMoodleHtml(html)) {
        return [folderItem];
      }

      final doc = html_parser.parse(html);
      final extracted = <MoodleItem>[];

      void walkTree(dom.Element ulOrContainer, String subPath) {
        for (final li in ulOrContainer.children) {
          if (li.localName != 'li') {
            walkTree(li, subPath);
            continue;
          }
          // Check if subfolder
          final nestedUl = li.querySelector(':scope > ul');
          final link = li.querySelector(':scope a[href*="pluginfile.php"]') ??
              li.querySelector('.fp-filename-icon a[href*="pluginfile.php"]');

          if (nestedUl != null && link == null) {
            final dirLabel = _cleanMoodleTitle(
              li.querySelector('.fp-filename')?.text ??
                  li.querySelector('span')?.text ??
                  '',
            );
            final nextSub = dirLabel.isNotEmpty
                ? (subPath.isEmpty ? dirLabel : '$subPath / $dirLabel')
                : subPath;
            walkTree(nestedUl, nextSub);
          } else {
            for (final a in li.querySelectorAll('a[href*="pluginfile.php"]')) {
              final href = a.attributes['href'] ?? '';
              if (href.isEmpty) continue;
              final cleanUrl = _ensureForcedDownload(
                Uri.parse(folderItem.url).resolve(href).toString(),
              );
              if (!seenUrls.add(cleanUrl)) continue;
              final rawName = _cleanMoodleTitle(
                a.querySelector('.fp-filename')?.text ?? a.text,
              );
              final urlName = Uri.decodeComponent(
                p.basename(Uri.tryParse(cleanUrl)?.path ?? ''),
              );
              final fname = rawName.isNotEmpty ? rawName : urlName;
              final ext = inferFileExt(fname, cleanUrl);
              final fullSection = subPath.isEmpty
                  ? '${folderItem.section} / ${folderItem.title}'
                  : '${folderItem.section} / ${folderItem.title} / $subPath';

              extracted.add(MoodleItem(
                id: '${folderItem.id}_f_${cleanUrl.hashCode.abs()}',
                courseId: folderItem.courseId,
                title: fname,
                section: fullSection,
                type: 'resource',
                url: cleanUrl,
                fileName: fname,
                fileExt: ext,
                downloadable: true,
              ));
            }
            if (nestedUl != null) {
              walkTree(nestedUl, subPath);
            }
          }
        }
      }

      final treeRoot = doc.querySelector('.foldertree') ??
          doc.querySelector('[role="main"]') ??
          doc.body;
      if (treeRoot != null) {
        final topUl = treeRoot.querySelector('ul');
        if (topUl != null) {
          walkTree(topUl, '');
        }
      }

      // Fallback flat search in case Moodle theme uses divs/tables inside mod_folder
      if (extracted.isEmpty) {
        for (final a in doc.querySelectorAll('a[href*="pluginfile.php"]')) {
          final href = a.attributes['href'] ?? '';
          if (href.isEmpty) continue;
          final cleanUrl = _ensureForcedDownload(
            Uri.parse(folderItem.url).resolve(href).toString(),
          );
          if (!seenUrls.add(cleanUrl)) continue;
          final rawName = _cleanMoodleTitle(
            a.querySelector('.fp-filename')?.text ?? a.text,
          );
          final urlName = Uri.decodeComponent(
            p.basename(Uri.tryParse(cleanUrl)?.path ?? ''),
          );
          final fname = rawName.isNotEmpty ? rawName : urlName;
          final ext = inferFileExt(fname, cleanUrl);
          extracted.add(MoodleItem(
            id: '${folderItem.id}_f_${cleanUrl.hashCode.abs()}',
            courseId: folderItem.courseId,
            title: fname,
            section: '${folderItem.section} / ${folderItem.title}',
            type: 'resource',
            url: cleanUrl,
            fileName: fname,
            fileExt: ext,
            downloadable: true,
          ));
        }
      }

      if (extracted.isNotEmpty) {
        return extracted;
      }

      // Check ZIP download form in folder view
      final zipBtn = doc.querySelector('form[action*="download_folder.php"]');
      if (zipBtn != null) {
        final zipAction = zipBtn.attributes['action'] ?? '';
        final idInput =
            zipBtn.querySelector('input[name="id"]')?.attributes['value'] ?? '';
        if (zipAction.isNotEmpty && idInput.isNotEmpty) {
          final zipUrl = Uri.parse(folderItem.url)
              .resolve('$zipAction?id=$idInput')
              .toString();
          return [
            MoodleItem(
              id: folderItem.id,
              courseId: folderItem.courseId,
              title: folderItem.title,
              section: folderItem.section,
              type: 'folder',
              url: zipUrl,
              fileName: '${MoodleCourse.sanitizeFileName(folderItem.title)}.zip',
              fileExt: 'zip',
              downloadable: true,
            ),
          ];
        }
      }

      return [
        MoodleItem(
          id: folderItem.id,
          courseId: folderItem.courseId,
          title: folderItem.title,
          section: folderItem.section,
          type: 'folder',
          url: folderItem.url,
          downloadable: false,
        ),
      ];
    } catch (_) {
      return [
        MoodleItem(
          id: folderItem.id,
          courseId: folderItem.courseId,
          title: folderItem.title,
          section: folderItem.section,
          type: 'folder',
          url: folderItem.url,
          downloadable: false,
        ),
      ];
    }
  }

  Future<void> enrichItemsWithLocalStatus(
    List<MoodleCourse> courses,
    SettingsService settings,
  ) async {
    final root = await settings.getDownloadRoot();
    final seenIds = await settings.loadSeenIds();
    final sharedIndex = root.isNotEmpty
        ? await settings.loadSharedIndex(root)
        : <String, dynamic>{'items': <String, dynamic>{}};
    final indexedItems = Map<String, dynamic>.from(
      sharedIndex['items'] as Map? ?? {},
    );

    for (final course in courses) {
      final courseFolder =
          course.obsidianFolder.isNotEmpty ? course.obsidianFolder : course.cleanName;
      final sub = course.targetSubfolder.trim();
      final baseCoursePath = sub.isNotEmpty
          ? p.join(root, courseFolder, sub)
          : p.join(root, courseFolder);

      for (final item in course.items) {
        item.isNew = item.downloadable && !seenIds.contains(item.id);
        item.isDownloaded = false;
        item.localPath = null;

        if (!item.downloadable) continue;

        // 1. Check shared index
        final idxEntry = indexedItems[item.id];
        if (idxEntry is Map) {
          final relPath = idxEntry['relPath']?.toString() ?? '';
          if (relPath.isNotEmpty && root.isNotEmpty) {
            final full = p.joinAll([root, ...relPath.split('/')]);
            if (await File(full).exists()) {
              item.isDownloaded = true;
              item.localPath = full;
              if ((idxEntry['fileName']?.toString() ?? '').isNotEmpty) {
                item.fileName = idxEntry['fileName'].toString();
              }
              continue;
            }
          }
        }

        // 2. Check expected filesystem path
        if (root.isNotEmpty) {
          final expectedDir = buildItemTargetDir(
            downloadRoot: root,
            course: course,
            item: item,
          );
          final candidates = <String>[
            if (item.fileName.isNotEmpty)
              p.join(expectedDir, MoodleCourse.sanitizeFileName(item.fileName)),
            if (item.effectiveExt.isNotEmpty)
              p.join(
                expectedDir,
                '${MoodleCourse.sanitizeFileName(item.title)}.${item.effectiveExt}',
              ),
            p.join(expectedDir, MoodleCourse.sanitizeFileName(item.title)),
          ];

          for (final cand in candidates) {
            if (await File(cand).exists()) {
              item.isDownloaded = true;
              item.localPath = cand;
              break;
            }
          }

          // Fallback check at course base folder
          if (!item.isDownloaded && item.fileName.isNotEmpty) {
            final flat = p.join(
              baseCoursePath,
              MoodleCourse.sanitizeFileName(item.fileName),
            );
            if (await File(flat).exists()) {
              item.isDownloaded = true;
              item.localPath = flat;
            }
          }
        }
      }
    }
  }

  static String buildItemTargetDir({
    required String downloadRoot,
    required MoodleCourse course,
    required MoodleItem item,
  }) {
    final courseFolder = MoodleCourse.sanitizeFileName(
      course.obsidianFolder.isNotEmpty
          ? course.obsidianFolder
          : course.cleanName,
    );
    final parts = <String>[downloadRoot, courseFolder];
    if (course.targetSubfolder.trim().isNotEmpty) {
      for (final seg in course.targetSubfolder.trim().split(RegExp(r'[/\\]+'))) {
        if (seg.trim().isNotEmpty) {
          parts.add(MoodleCourse.sanitizeFileName(seg.trim()));
        }
      }
    }
    if (course.organizeBySection) {
      for (final seg in item.section.split('/')) {
        if (seg.trim().isNotEmpty) {
          parts.add(MoodleCourse.sanitizeFileName(seg.trim()));
        }
      }
    }
    return p.joinAll(parts);
  }

  Future<void> fetchMissingFileSizes(MoodleCourse course) async {
    final targets = course.items
        .where((it) => it.downloadable && it.sizeBytes == null && it.url.isNotEmpty)
        .toList();
    if (targets.isEmpty) return;

    for (var i = 0; i < targets.length; i += 5) {
      final batch = targets.sublist(i, i + 5 > targets.length ? targets.length : i + 5);
      await Future.wait(batch.map((item) async {
        try {
          var url = item.url;
          if (isTokenAuth) url = _appendToken(url);
          final req = http.Request('HEAD', Uri.parse(url))
            ..followRedirects = true
            ..headers.addAll(isTokenAuth
                ? {'User-Agent': userAgent}
                : _cookieHeaders());
          final streamed =
              await _client.send(req).timeout(const Duration(seconds: 8));
          await streamed.stream.drain<void>();
          final lenStr = streamed.headers['content-length'];
          if (lenStr != null) {
            final len = int.tryParse(lenStr);
            if (len != null && len > 0) item.sizeBytes = len;
          }
          final extractedName = _extractFilenameFromResponse(
            streamed.headers,
            url,
            item.title,
          );
          if (extractedName.isNotEmpty) {
            item.fileName = extractedName;
            final ext = inferFileExt(extractedName, url);
            if (ext.isNotEmpty) item.fileExt = ext;
          }
        } catch (_) {}
      }));
    }
  }

  Future<DownloadedFileData> downloadItemData(MoodleItem item) async {
    if (!isAuthenticated) throw SessionExpiredException();

    var targetUrl = _ensureForcedDownload(item.url);
    if (isTokenAuth) {
      targetUrl = _appendToken(targetUrl);
    }

    for (var unwrapHop = 0; unwrapHop < 3; unwrapHop++) {
      final res = await _getFollowingRedirects(targetUrl);
      if (res.statusCode == 401 || res.statusCode == 403) {
        throw SessionExpiredException();
      }
      if (res.statusCode < 200 || res.statusCode >= 400) {
        throw Exception('Error HTTP ${res.statusCode} al descargar ${item.title}');
      }

      final contentType = (res.headers['content-type'] ?? '').toLowerCase();
      if (!contentType.contains('text/html')) {
        final rawName = _extractFilenameFromResponse(
          res.headers,
          res.finalUrl,
          item.fileName.isNotEmpty ? item.fileName : item.title,
        );
        final ext = _resolveExtension(
          rawName,
          res.finalUrl,
          contentType,
          item.effectiveExt,
        );
        final finalName = _ensureFilenameHasExt(rawName, ext);
        return DownloadedFileData(
          bytes: res.bodyBytes,
          fileName: finalName,
          fileExt: ext,
        );
      }

      // Inspect HTML wrapper returned by Moodle
      final html = utf8.decode(res.bodyBytes, allowMalformed: true);
      if (!isAuthenticatedMoodleHtml(html) &&
          (html.contains('login/index.php') ||
              html.contains('login.microsoftonline.com'))) {
        throw SessionExpiredException();
      }

      final doc = html_parser.parse(html);
      final nextHref = doc.querySelector('.resourceworkaround a')?.attributes['href'] ??
          doc.querySelector('.resourcecontent a[href*="pluginfile.php"]')?.attributes['href'] ??
          doc.querySelector('.resourcepdf object')?.attributes['data'] ??
          doc.querySelector('iframe[src*="pluginfile.php"]')?.attributes['src'] ??
          doc.querySelector('embed[src*="pluginfile.php"]')?.attributes['src'] ??
          doc.querySelector('video source[src*="pluginfile.php"]')?.attributes['src'] ??
          doc.querySelector('audio source[src*="pluginfile.php"]')?.attributes['src'] ??
          doc.querySelector('a[href*="pluginfile.php"]')?.attributes['href'] ??
          doc.querySelector('.urlworkaround a')?.attributes['href'];

      if (nextHref != null && nextHref.isNotEmpty) {
        targetUrl = _ensureForcedDownload(
          Uri.parse(res.finalUrl).resolve(nextHref).toString(),
        );
        if (isTokenAuth && targetUrl.contains('aula.usm.cl')) {
          targetUrl = _appendToken(targetUrl);
        }
        continue;
      }

      // No file inside HTML -> export clean HTML or URL note if mod/page or mod/url
      final safeBase = MoodleCourse.sanitizeFileName(item.title);
      return DownloadedFileData(
        bytes: res.bodyBytes,
        fileName: '$safeBase.html',
        fileExt: 'html',
      );
    }

    throw Exception('No se pudo extraer el archivo real desde ${item.title}');
  }

  Future<int> processScanNotifications({
    required List<MoodleCourse> courses,
    required SettingsService settings,
  }) async {
    var created = 0;
    final nowIso = DateTime.now().toIso8601String();

    for (final course in courses) {
      if (settings.hiddenCourseIds.contains(course.id)) continue;

      if (settings.notifyOnNewFiles) {
        final newCount = course.newFilesCount;
        if (newCount > 0) {
          final nid = 'new_${course.id}_$newCount';
          final added = await settings.addNotificationUnique(
            AulaNotification(
              id: nid,
              title: 'Nuevos archivos en ${course.cleanName}',
              body: '$newCount recurso(s) nuevo(s) disponibles para descargar.',
              type: 'new_file',
              courseId: course.id,
              courseName: course.cleanName,
              timestamp: nowIso,
            ),
          );
          if (added) created++;
        }
      }

      if (settings.notifyOnDeadlines) {
        for (final item in course.items) {
          if (item.isUrgentDeadline) {
            final nid = 'due_${item.id}_${item.dueTimestamp}';
            final added = await settings.addNotificationUnique(
              AulaNotification(
                id: nid,
                title: 'Entrega próxima: ${item.title}',
                body:
                    '${course.cleanName}${item.formattedDueDate.isNotEmpty ? " · ${item.formattedDueDate}" : ""}',
                type: 'deadline',
                courseId: course.id,
                courseName: course.cleanName,
                timestamp: nowIso,
              ),
            );
            if (added) created++;
          }
        }
      }
    }

    if (created > 0 && settings.notifyNativeEnabled) {
      await settings.showNativeNotification(
        id: 1001,
        title: 'Aula USM · Novedades detectadas',
        body: 'Hay $created novedad(es) nueva(s) en tus ramos.',
      );
    }
    return created;
  }

  String _appendToken(String url) {
    if (token.isEmpty || url.contains('token=') || url.contains('wstoken=')) {
      return url;
    }
    var updated = url;
    if (updated.contains('/pluginfile.php/') &&
        !updated.contains('/webservice/pluginfile.php/')) {
      updated = updated.replaceFirst(
        '/pluginfile.php/',
        '/webservice/pluginfile.php/',
      );
    }
    final sep = updated.contains('?') ? '&' : '?';
    return '$updated${sep}token=${Uri.encodeQueryComponent(token)}';
  }

  String _ensureForcedDownload(String url) {
    if (!url.contains('pluginfile.php')) return url;
    if (url.contains('forcedownload=')) return url;
    final sep = url.contains('?') ? '&' : '?';
    return '$url${sep}forcedownload=1';
  }

  String _extractFilenameFromResponse(
    Map<String, String> headers,
    String finalUrl,
    String fallback,
  ) {
    final cd = headers['content-disposition'] ?? '';
    if (cd.isNotEmpty) {
      // RFC 5987 filename*=UTF-8''...
      final starMatch = RegExp(
        r"filename\*\s*=\s*(?:UTF-8''|utf-8'')([^;]+)",
      ).firstMatch(cd);
      if (starMatch != null) {
        try {
          final decoded = Uri.decodeComponent(starMatch.group(1)!.trim());
          return _fixLatin1Utf8(decoded);
        } catch (_) {}
      }
      final quotedMatch = RegExp(r'filename\s*=\s*"([^"]+)"').firstMatch(cd) ??
          RegExp(r'filename\s*=\s*([^;\s]+)').firstMatch(cd);
      if (quotedMatch != null) {
        return _fixLatin1Utf8(quotedMatch.group(1)!.trim());
      }
    }

    final uri = Uri.tryParse(finalUrl);
    if (uri != null && uri.pathSegments.isNotEmpty) {
      final last = uri.pathSegments.last;
      if (last.isNotEmpty &&
          !last.endsWith('.php') &&
          last != 'view' &&
          last.contains('.')) {
        try {
          return _fixLatin1Utf8(Uri.decodeComponent(last));
        } catch (_) {
          return _fixLatin1Utf8(last);
        }
      }
    }

    return fallback;
  }

  String _fixLatin1Utf8(String input) {
    if (!input.contains('Ã') && !input.contains('Â')) return input;
    try {
      final latinBytes = latin1.encode(input);
      final fixed = utf8.decode(latinBytes, allowMalformed: false);
      return fixed;
    } catch (_) {
      return input;
    }
  }

  String _resolveExtension(
    String fileName,
    String finalUrl,
    String contentType,
    String fallbackExt,
  ) {
    final fromName = inferFileExt(fileName, '');
    if (fromName.isNotEmpty) return fromName;
    final fromUrl = inferFileExt('', finalUrl);
    if (fromUrl.isNotEmpty) return fromUrl;

    if (contentType.contains('pdf')) return 'pdf';
    if (contentType.contains('presentation') ||
        contentType.contains('powerpoint')) {
      return 'pptx';
    }
    if (contentType.contains('wordprocessingml')) return 'docx';
    if (contentType.contains('msword')) return 'doc';
    if (contentType.contains('spreadsheetml')) return 'xlsx';
    if (contentType.contains('ms-excel')) return 'xls';
    if (contentType.contains('zip')) return 'zip';
    if (contentType.contains('x-rar')) return 'rar';
    if (contentType.contains('image/png')) return 'png';
    if (contentType.contains('image/jpeg')) return 'jpg';
    if (contentType.contains('video/mp4')) return 'mp4';
    if (contentType.contains('text/plain')) return 'txt';
    if (contentType.contains('text/markdown')) return 'md';
    return fallbackExt;
  }

  String _ensureFilenameHasExt(String rawName, String ext) {
    final sanitized = MoodleCourse.sanitizeFileName(rawName);
    if (ext.isEmpty) return sanitized;
    if (sanitized.toLowerCase().endsWith('.${ext.toLowerCase()}')) {
      return sanitized;
    }
    return '$sanitized.$ext';
  }

  static String normalizeMatchKey(String raw) =>
      MoodleCourse.normalizeForMatch(raw);

  static String inferFileExt(String fileName, String url) {
    final candidates = [fileName, url.split('?').first];
    for (final c in candidates) {
      final dot = c.lastIndexOf('.');
      if (dot != -1 && dot < c.length - 1) {
        final ext = c.substring(dot + 1).toLowerCase().trim();
        if (ext.length <= 5 &&
            ext != 'php' &&
            ext != 'aspx' &&
            RegExp(r'^[a-z0-9]+$').hasMatch(ext)) {
          return ext;
        }
      }
    }
    return '';
  }

  static String _cleanMoodleTitle(String raw) {
    return raw.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static String _extractShortDateLine(String raw) {
    final m = RegExp(
      r'(?:vence|cierre|cierr[ae]|entrega|apertura)[^,\n]*(?:,\s*\d{1,2}\s+de\s+[a-záéíóú]+\s+de\s+\d{4}(?:,\s*\d{1,2}:\d{2})?)',
      caseSensitive: false,
    ).firstMatch(raw);
    return m?.group(0)?.trim() ??
        (raw.length > 60 ? '${raw.substring(0, 60)}...' : raw);
  }

  static int? parseDueTimestamp(String raw) {
    final dt = parseSpanishMoodleDate(raw);
    if (dt == null) return null;
    return dt.millisecondsSinceEpoch ~/ 1000;
  }

  static DateTime? parseSpanishMoodleDate(String rawText) {
    if (rawText.trim().isEmpty) return null;
    const months = {
      'enero': 1,
      'febrero': 2,
      'marzo': 3,
      'abril': 4,
      'mayo': 5,
      'junio': 6,
      'julio': 7,
      'agosto': 8,
      'septiembre': 9,
      'setiembre': 9,
      'octubre': 10,
      'noviembre': 11,
      'diciembre': 12,
    };

    final lower = rawText.toLowerCase();
    final esRegex = RegExp(
      r'(\d{1,2})\s+de\s+([a-záéíóú]+)\s+de\s+(\d{4})(?:,?\s*(?:a\s+las\s+)?(\d{1,2}):(\d{2}))?',
    );
    final matches = esRegex.allMatches(lower).toList();
    // Prefer the last date match if "Vence" / "Cierre" appears right before it
    RegExpMatch? chosen;
    for (final m in matches) {
      final prefixStart = m.start - 40 < 0 ? 0 : m.start - 40;
      final prefix = lower.substring(prefixStart, m.start);
      if (prefix.contains('vence') ||
          prefix.contains('cierre') ||
          prefix.contains('cierra') ||
          prefix.contains('entrega') ||
          prefix.contains('hasta')) {
        chosen = m;
      }
    }
    chosen ??= matches.isNotEmpty ? matches.last : null;

    if (chosen != null) {
      final day = int.tryParse(chosen.group(1)!) ?? 1;
      final monthName = chosen.group(2)!;
      final month = months[monthName];
      final year = int.tryParse(chosen.group(3)!) ?? DateTime.now().year;
      final hour = int.tryParse(chosen.group(4) ?? '23') ?? 23;
      final min = int.tryParse(chosen.group(5) ?? '59') ?? 59;
      if (month != null) {
        return DateTime(year, month, day, hour, min);
      }
    }

    // Numeric dd/mm/yyyy HH:mm
    final numMatch = RegExp(
      r'(\d{1,2})[/-](\d{1,2})[/-](\d{4})(?:\s+(\d{1,2}):(\d{2}))?',
    ).firstMatch(lower);
    if (numMatch != null) {
      final day = int.tryParse(numMatch.group(1)!) ?? 1;
      final month = int.tryParse(numMatch.group(2)!) ?? 1;
      final year = int.tryParse(numMatch.group(3)!) ?? DateTime.now().year;
      final hour = int.tryParse(numMatch.group(4) ?? '23') ?? 23;
      final min = int.tryParse(numMatch.group(5) ?? '59') ?? 59;
      if (month >= 1 && month <= 12 && day >= 1 && day <= 31) {
        return DateTime(year, month, day, hour, min);
      }
    }

    return null;
  }
}

typedef AulaMoodleService = MoodleService;
