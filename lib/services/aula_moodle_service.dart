import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

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

class StreamedFileDownload {
  final String fileName;
  final String fileExt;
  final int sizeBytes;
  final String sha256Hex;

  const StreamedFileDownload({
    required this.fileName,
    required this.fileExt,
    required this.sizeBytes,
    required this.sha256Hex,
  });
}

class _DigestSink implements Sink<Digest> {
  Digest? value;

  @override
  void add(Digest data) {
    value = data;
  }

  @override
  void close() {}
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

  void dispose() {
    _client.close();
  }

  static bool isTrustedAulaUri(Uri? uri) {
    if (uri == null || uri.scheme.toLowerCase() != 'https') return false;
    final host = uri.host.toLowerCase();
    return host == 'aula.usm.cl' || host.endsWith('.aula.usm.cl');
  }

  static String stripSensitiveQueryParams(String rawUrl) {
    final uri = Uri.tryParse(rawUrl);
    if (uri == null || uri.queryParametersAll.isEmpty) return rawUrl;
    const sensitive = {'token', 'wstoken', 'sesskey'};
    var changed = false;
    final cleaned = <String, List<String>>{};
    uri.queryParametersAll.forEach((k, v) {
      if (sensitive.contains(k.toLowerCase())) {
        changed = true;
      } else {
        cleaned[k] = v;
      }
    });
    if (!changed) return rawUrl;
    return Uri(
      scheme: uri.scheme,
      userInfo: uri.userInfo,
      host: uri.host,
      port: uri.hasPort ? uri.port : null,
      path: uri.path,
      queryParameters: cleaned.isEmpty ? null : cleaned,
      fragment: uri.hasFragment ? uri.fragment : null,
    ).toString();
  }

  static String _tryDecodeComponent(String raw) {
    try {
      return Uri.decodeComponent(raw);
    } catch (_) {
      return raw;
    }
  }

  static String _shortHash(String input) {
    return sha256.convert(utf8.encode(input)).toString().substring(0, 16);
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
    await _settings.clearWebViewCookies();
  }

  String _normalizeCookie(String raw) {
    var clean = raw.replaceAll(RegExp(r'[\x00-\x1F\x7F]+'), ' ').trim();
    if (clean.toLowerCase().startsWith('cookie:')) {
      clean = clean.substring(7).trim();
    }
    if (clean.isNotEmpty && !clean.contains('=')) {
      clean = 'MoodleSession=$clean';
    }
    return clean;
  }

  Map<String, String> _cookieHeaders([
    Map<String, String>? extra,
    String? cookieOverride,
    Uri? targetUri,
  ]) {
    final effectiveCookie = cookieOverride ?? cookie;
    final canSendCookie = effectiveCookie.isNotEmpty &&
        (targetUri == null || isTrustedAulaUri(targetUri));
    final headers = <String, String>{
      'User-Agent': userAgent,
      'Accept':
          'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
    };
    if (canSendCookie) {
      headers['Cookie'] = effectiveCookie;
    }
    if (extra != null) {
      headers.addAll(extra);
    }
    return headers;
  }

  Future<({http.StreamedResponse response, Uri finalUri, String updatedCookie})>
      _sendFollowingRedirects(
    String url, {
    String method = 'GET',
    Map<String, String>? extraHeaders,
    String? cookieOverride,
    bool persistCookies = true,
    int maxRedirects = 8,
    Duration requestTimeout = const Duration(seconds: 25),
  }) async {
    var currentUrl = url;
    var activeCookie = cookieOverride ?? cookie;

    for (var hop = 0; hop <= maxRedirects; hop++) {
      final uri = Uri.tryParse(currentUrl);
      if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
        throw Exception('URL inválida o esquema no soportado.');
      }
      final trusted = isTrustedAulaUri(uri);
      final req = http.Request(method, uri)..followRedirects = false;
      req.headers.addAll({
        'User-Agent': userAgent,
        'Accept': '*/*',
        if (trusted && activeCookie.isNotEmpty) 'Cookie': activeCookie,
        ...?extraHeaders,
      });

      final streamed = await _client.send(req).timeout(requestTimeout);
      final headers = streamed.headers;

      final setCookie = headers['set-cookie'];
      if (trusted && setCookie != null && setCookie.isNotEmpty) {
        activeCookie = _mergeCookieString(activeCookie, setCookie);
        if (persistCookies) {
          cookie = activeCookie;
        }
      }

      if (streamed.statusCode >= 300 &&
          streamed.statusCode < 400 &&
          headers['location'] != null) {
        try {
          await streamed.stream
              .drain<void>()
              .timeout(const Duration(seconds: 4));
        } catch (_) {}
        final nextUri = uri.resolve(headers['location']!);
        if (nextUri.scheme != 'http' && nextUri.scheme != 'https') {
          throw Exception('Redirección hacia esquema no permitido.');
        }
        currentUrl = nextUri.toString();
        continue;
      }

      return (
        response: streamed,
        finalUri: uri,
        updatedCookie: activeCookie,
      );
    }

    throw Exception('Demasiadas redirecciones al acceder a Aula USM.');
  }

  /// Follows HTTP redirects manually while preserving Moodle cookies only on trusted Aula hosts.
  Future<
      ({
        int statusCode,
        Map<String, String> headers,
        Uint8List bodyBytes,
        String finalUrl,
      })> _getFollowingRedirects(
    String url, {
    Map<String, String>? extraHeaders,
    String? cookieOverride,
    bool persistCookies = true,
    int maxRedirects = 8,
  }) async {
    final result = await _sendFollowingRedirects(
      url,
      method: 'GET',
      extraHeaders: extraHeaders,
      cookieOverride: cookieOverride,
      persistCookies: persistCookies,
      maxRedirects: maxRedirects,
    );
    final bodyBytes = await result.response.stream
        .toBytes()
        .timeout(const Duration(seconds: 60));
    return (
      statusCode: result.response.statusCode,
      headers: result.response.headers,
      bodyBytes: bodyBytes,
      finalUrl: result.finalUri.toString(),
    );
  }

  String _mergeCookieString(String existing, String setCookieHeader) {
    final cleanExisting = existing.replaceAll(RegExp(r'[\x00-\x1F\x7F]+'), ' ');
    final cleanHeader =
        setCookieHeader.replaceAll(RegExp(r'[\x00-\x1F\x7F]+'), ' ');
    final jar = <String, String>{};
    for (final part in cleanExisting.split(';')) {
      final eq = part.indexOf('=');
      if (eq > 0) {
        final k = part.substring(0, eq).trim();
        final v = part.substring(eq + 1).trim();
        if (k.isNotEmpty) jar[k] = v;
      }
    }
    const cookieAttrs = {
      'path',
      'domain',
      'expires',
      'max-age',
      'samesite',
      'priority',
      'secure',
      'httponly',
    };
    final validCookieName = RegExp(r"^[!#$%&'*+\-.^_`|~0-9A-Za-z]+$");
    final regex = RegExp(r'(?:^|[;,])\s*([^=;\s,]+)=([^;]*)');
    for (final m in regex.allMatches(cleanHeader)) {
      final k = m.group(1)?.trim() ?? '';
      final v = m.group(2)?.trim() ?? '';
      if (k.isEmpty || !validCookieName.hasMatch(k)) continue;
      if (cookieAttrs.contains(k.toLowerCase())) continue;
      jar[k] = v;
    }
    return jar.entries.map((e) => '${e.key}=${e.value}').join('; ');
  }

  static bool isAuthenticatedMoodleHtml(String html) {
    final lower = html.toLowerCase();
    final isLoginForm = lower.contains('name="logintoken"') ||
        lower.contains('login.microsoftonline.com') ||
        lower.contains('/login/index.php"') ||
        (lower.contains('name="username"') && lower.contains('name="password"'));
    if (isLoginForm && !lower.contains('login/logout.php')) {
      return false;
    }
    if (lower.contains('login/logout.php')) return true;
    if (RegExp(r'data-userid="([1-9]\d*)"').hasMatch(lower)) return true;
    if (RegExp(r'"userId"\s*:\s*[1-9]\d*').hasMatch(html)) return true;
    if (lower.contains('/user/profile.php?id=')) return true;
    return false;
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
          doc.querySelector('[data-region="usermenu"] .usertext');
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
    final info = await _callWs(
      'core_webservice_get_site_info',
      {},
      tokenOverride: cleanToken,
    );
    if (info is! Map || info['userid'] == null) {
      throw Exception('El token de Aula USM no es válido o expiró.');
    }
    token = cleanToken;
    cookie = '';
    sesskey = '';
    userName = (info['fullname'] ?? 'Estudiante USM').toString();
    userId = info['userid'].toString();
    await saveSession();
    return session;
  }

  Future<AulaSessionData> loginWithCookie(String rawCookie) async {
    final normalized = _normalizeCookie(rawCookie);
    if (normalized.isEmpty) {
      throw Exception('Ingresa una cookie de sesión válida.');
    }
    final res = await _getFollowingRedirects(
      '$baseUrl/my/',
      cookieOverride: normalized,
      persistCookies: false,
    );
    final html = utf8.decode(res.bodyBytes, allowMalformed: true);
    if (res.statusCode != 200 || !isAuthenticatedMoodleHtml(html)) {
      throw SessionExpiredException(
        'La cookie ingresada expiró o no corresponde a una sesión activa en Aula USM.',
      );
    }
    cookie = _mergeCookieString(
      normalized,
      res.headers['set-cookie'] ?? '',
    );
    token = '';
    sesskey = '';
    userId = '';
    extractSessionDetails(html);
    if (userName.isEmpty) {
      userName = 'Estudiante USM';
    }
    await saveSession();
    return session;
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
    final parsedBase = Uri.tryParse(cleanBase);
    if (parsedBase == null ||
        (parsedBase.scheme != 'http' && parsedBase.scheme != 'https') ||
        parsedBase.host.isEmpty) {
      throw Exception('URL de servidor de emparejamiento inválida.');
    }
    final cleanPin = pin.trim().toUpperCase();
    final uri = parsedBase.replace(
      path: '${parsedBase.path}/api/pair/claim',
      queryParameters: {'pin': cleanPin},
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

    // Verify paired credentials live against Aula USM before mutating local state.
    if (pairedToken.isNotEmpty) {
      await loginWithToken(pairedToken);
    } else {
      await loginWithCookie(pairedCookie);
      if (pairedSesskey.isNotEmpty && sesskey.isEmpty) {
        sesskey = pairedSesskey;
      }
      if (pairedUser.isNotEmpty && userName == 'Estudiante USM') {
        userName = pairedUser;
      }
      if (pairedUid.isNotEmpty && userId.isEmpty) {
        userId = pairedUid;
      }
      await saveSession();
    }

    final folders = <int, String>{};
    final rawFolders = map['course_folders'] ?? map['courseFolders'];
    if (rawFolders is Map) {
      rawFolders.forEach((k, v) {
        final cid = int.tryParse(k.toString());
        final rawFolder = v?.toString().trim() ?? '';
        if (cid != null && rawFolder.isNotEmpty) {
          folders[cid] = MoodleCourse.sanitizeFileName(rawFolder);
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
    Map<String, String> params, {
    String? tokenOverride,
  }) async {
    final activeToken = tokenOverride ?? token;
    final uri = Uri.parse('$baseUrl/webservice/rest/server.php');
    final res = await _client
        .post(
          uri,
          headers: {
            'User-Agent': userAgent,
            'Content-Type': 'application/x-www-form-urlencoded',
          },
          body: {
            'wstoken': activeToken,
            'wsfunction': wsfunction,
            'moodlewsrestformat': 'json',
            ...params,
          },
        )
        .timeout(const Duration(seconds: 25));
    if (res.statusCode != 200) {
      throw Exception('Error Aula WebService (${res.statusCode})');
    }
    final decoded = jsonDecode(utf8.decode(res.bodyBytes));
    if (decoded is Map && decoded['exception'] != null) {
      final errCode = decoded['errorcode']?.toString().toLowerCase() ?? '';
      final msg = decoded['message']?.toString() ?? 'Error en Aula';
      if (errCode == 'invalidtoken' ||
          errCode == 'expiredtoken' ||
          msg.toLowerCase().contains('invalid token')) {
        throw SessionExpiredException(msg);
      }
      if (errCode == 'accessexception') {
        throw Exception('Sin permisos para este recurso en Aula USM ($msg)');
      }
      throw Exception(msg);
    }
    return decoded;
  }

  Future<List<MoodleCourse>> getCourses() async {
    if (!isAuthenticated) throw SessionExpiredException();

    if (isTokenAuth) {
      if (userId.isEmpty) {
        final ok = await verifySessionLive();
        if (!ok || userId.isEmpty) {
          throw SessionExpiredException();
        }
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
    var anyPageSucceeded = false;
    Object? lastNetworkError;

    for (final path in ['/my/courses.php', '/my/']) {
      try {
        final res = await _getFollowingRedirects('$baseUrl$path');
        final html = utf8.decode(res.bodyBytes, allowMalformed: true);
        if (!isAuthenticatedMoodleHtml(html)) {
          if (path == '/my/courses.php') continue;
          throw SessionExpiredException();
        }
        anyPageSucceeded = true;
        extractSessionDetails(html);
        final doc = html_parser.parse(html);
        for (final a in doc.querySelectorAll('a[href*="course/view.php?id="]')) {
          final href = a.attributes['href'] ?? '';
          final cidStr = Uri.tryParse(href)?.queryParameters['id'] ?? '';
          final cid = int.tryParse(cidStr) ??
              int.tryParse(RegExp(r'id=(\d+)').firstMatch(href)?.group(1) ?? '') ??
              0;
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
        lastNetworkError = e;
      }
    }

    if (!anyPageSucceeded && lastNetworkError != null) {
      throw lastNetworkError;
    }

    // Also try Moodle AJAX enrolled courses endpoint if sesskey is known
    if (sesskey.isNotEmpty) {
      try {
        final ajaxUri = Uri.parse('$baseUrl/lib/ajax/service.php');
        final ajaxRes = await _client
            .post(
              ajaxUri.replace(queryParameters: {'sesskey': sesskey}),
              headers: _cookieHeaders(
                {'Content-Type': 'application/json'},
                null,
                ajaxUri,
              ),
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
          final modUrl = stripSensitiveQueryParams(mod['url']?.toString() ?? '');
          final contents = mod['contents'] as List? ?? const [];

          if (modName == 'folder') {
            var idx = 0;
            for (final c in contents) {
              if (c is! Map) continue;
              final rawFileUrl = c['fileurl']?.toString() ?? '';
              if (rawFileUrl.isEmpty) continue;
              final fileUrl = stripSensitiveQueryParams(rawFileUrl);
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
                url: fileUrl,
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
                ? stripSensitiveQueryParams(
                    contents[0]['fileurl']?.toString() ?? modUrl,
                  )
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
              final rawFUrl = c['fileurl']?.toString() ?? '';
              if (rawFUrl.isEmpty) continue;
              final fUrl = stripSensitiveQueryParams(rawFUrl);
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
                url: fUrl,
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
            final rawFUrl = c['fileurl']?.toString() ?? '';
            if (rawFUrl.isEmpty) continue;
            final fUrl = stripSensitiveQueryParams(rawFUrl);
            if (!seenUrls.add(fUrl)) continue;
            final fname = c['filename']?.toString() ?? '';
            items.add(MoodleItem(
              id: '${course.id}_${modId}_emb_$cIdx',
              courseId: course.id,
              title: fname.isNotEmpty ? '$modTitle — $fname' : modTitle,
              section: effectiveSection,
              type: 'resource',
              url: fUrl,
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
    final mainUri = Uri.tryParse(mainUrl);

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
      if (href.isEmpty) continue;
      final resolvedUri = mainUri?.resolve(href);
      if (resolvedUri == null || !isTrustedAulaUri(resolvedUri)) continue;
      final cidParam = resolvedUri.queryParameters['id'];
      final hasSectionParam = resolvedUri.queryParameters.containsKey('section') ||
          resolvedUri.queryParameters.containsKey('sectionid');
      if (cidParam == '${course.id}' && hasSectionParam) {
        sectionUrls.add(resolvedUri.removeFragment().toString());
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

    // Crawl section tabs with bounded concurrency (4), parsing sequentially to avoid races
    final tabList = sectionUrls.toList();
    for (var i = 0; i < tabList.length; i += 4) {
      final batch = tabList.sublist(
        i,
        i + 4 > tabList.length ? tabList.length : i + 4,
      );
      final tabDocs = await Future.wait(batch.map((secUrl) async {
        try {
          final r = await _getFollowingRedirects(secUrl);
          final h = utf8.decode(r.bodyBytes, allowMalformed: true);
          if (!isAuthenticatedMoodleHtml(h)) {
            throw SessionExpiredException();
          }
          return r.statusCode == 200 ? html_parser.parse(h) : null;
        } on SessionExpiredException {
          rethrow;
        } catch (_) {
          return null;
        }
      }));
      for (final doc in tabDocs) {
        if (doc != null) {
          absorbDoc(doc);
        }
      }
    }

    // Flatten Moodle /mod/folder/ resources concurrently (max 4), deduplicating sequentially
    final finalItems = <MoodleItem>[...parsedItems];
    for (var i = 0; i < folderItems.length; i += 4) {
      final batch = folderItems.sublist(
        i,
        i + 4 > folderItems.length ? folderItems.length : i + 4,
      );
      final expandedLists = await Future.wait(
        batch.map((folderItem) => _extractFolderFiles(folderItem)),
      );
      for (final expanded in expandedLists) {
        for (final entry in expanded) {
          if (entry.url.isEmpty || seenUrls.add(entry.url) || entry.type == 'folder') {
            finalItems.add(entry);
          }
        }
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
    final baseUri = Uri.tryParse(baseUrl);

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
          final resolvedUri = href.isNotEmpty ? baseUri?.resolve(href) : null;
          if (resolvedUri != null) {
            if (modNum.isEmpty) {
              modNum = resolvedUri.queryParameters['id'] ??
                  RegExp(r'id=(\d+)').firstMatch(href)?.group(1) ??
                  '';
            }
            if (modType == 'resource') {
              final modMatch = RegExp(r'/mod/([a-z0-9_]+)/').firstMatch(href);
              if (modMatch != null) modType = modMatch.group(1)!;
            }

            final modKey =
                '${courseId}_${modNum.isNotEmpty ? modNum : _shortHash(href)}';
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

            final resolvedUrl = stripSensitiveQueryParams(resolvedUri.toString());
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
            final fileNameWithExt = isResource
                ? (ext.isNotEmpty &&
                        !title.toLowerCase().endsWith('.${ext.toLowerCase()}')
                    ? '$title.$ext'
                    : title)
                : '';

            final item = MoodleItem(
              id: modKey,
              courseId: courseId,
              title: title,
              section: secTitle,
              type: modType,
              url: resolvedUrl,
              fileName: fileNameWithExt,
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
    final baseUri = Uri.tryParse(baseUrl);
    final mediaEls = root.querySelectorAll(
      'a[href*="pluginfile.php"], video source[src*="pluginfile.php"], audio source[src*="pluginfile.php"], iframe[src*="pluginfile.php"]',
    );
    for (final el in mediaEls) {
      final rawHref = el.attributes['href'] ?? el.attributes['src'] ?? '';
      if (rawHref.isEmpty) continue;
      final resolved = baseUri?.resolve(rawHref);
      if (resolved == null) continue;
      final cleanUrl = stripSensitiveQueryParams(resolved.toString());
      if (!seenUrls.add(cleanUrl)) continue;

      final uriPath = Uri.tryParse(cleanUrl)?.path ?? '';
      final urlBaseName =
          uriPath.isNotEmpty ? _tryDecodeComponent(p.basename(uriPath)) : '';
      var label = _cleanMoodleTitle(el.text);
      if (label.isEmpty || label.length > 100) {
        label = urlBaseName.isNotEmpty ? urlBaseName : 'Archivo adjunto';
      }
      final fname = urlBaseName.isNotEmpty ? urlBaseName : label;
      final ext = inferFileExt(fname, cleanUrl);
      if (ext.isEmpty && !cleanUrl.contains('pluginfile.php')) continue;

      out.add(MoodleItem(
        id: '${courseId}_emb_${_shortHash(cleanUrl)}',
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

  Future<List<MoodleItem>> _extractFolderFiles(MoodleItem folderItem) async {
    try {
      final res = await _getFollowingRedirects(folderItem.url);
      final html = utf8.decode(res.bodyBytes, allowMalformed: true);
      if (!isAuthenticatedMoodleHtml(html)) {
        throw SessionExpiredException();
      }
      if (res.statusCode != 200) {
        return [folderItem];
      }

      final doc = html_parser.parse(html);
      final extracted = <MoodleItem>[];
      final localSeen = <String>{};
      final folderUri =
          Uri.tryParse(res.finalUrl) ?? Uri.tryParse(folderItem.url);

      void addPluginLink(dom.Element a, String subPath) {
        final href = a.attributes['href'] ?? '';
        if (href.isEmpty || folderUri == null) return;
        final resolved = folderUri.resolve(href);
        final cleanUrl = stripSensitiveQueryParams(
          _ensureForcedDownload(resolved.toString()),
        );
        if (!localSeen.add(cleanUrl)) return;
        final rawName = _cleanMoodleTitle(
          a.querySelector('.fp-filename')?.text ?? a.text,
        );
        final urlName = _tryDecodeComponent(
          p.basename(Uri.tryParse(cleanUrl)?.path ?? ''),
        );
        final fname = rawName.isNotEmpty ? rawName : urlName;
        final ext = inferFileExt(fname, cleanUrl);
        final fullSection = subPath.isEmpty
            ? '${folderItem.section} / ${folderItem.title}'
            : '${folderItem.section} / ${folderItem.title} / $subPath';

        extracted.add(MoodleItem(
          id: '${folderItem.id}_f_${_shortHash(cleanUrl)}',
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

      List<dom.Element> directPluginLinksOutsideNestedUl(dom.Element li) {
        final links = <dom.Element>[];
        void scanNonUl(dom.Element el) {
          for (final child in el.children) {
            if (child.localName == 'ul') continue;
            if (child.localName == 'a' &&
                (child.attributes['href'] ?? '').contains('pluginfile.php')) {
              links.add(child);
            } else {
              scanNonUl(child);
            }
          }
        }
        scanNonUl(li);
        return links;
      }

      String extractDirectFolderLabel(dom.Element li) {
        for (final child in li.children) {
          if (child.localName == 'ul') continue;
          final fp = child.querySelector('.fp-filename')?.text ??
              (child.classes.contains('fp-filename') ? child.text : null) ??
              child.querySelector('span')?.text ??
              (child.localName == 'span' ? child.text : null);
          final cleaned = _cleanMoodleTitle(fp ?? '');
          if (cleaned.isNotEmpty) return cleaned;
        }
        return '';
      }

      void walkTree(dom.Element ulOrContainer, String subPath) {
        for (final li in ulOrContainer.children) {
          if (li.localName != 'li') {
            walkTree(li, subPath);
            continue;
          }
          final nestedUls =
              li.children.where((c) => c.localName == 'ul').toList();
          final directLinks = directPluginLinksOutsideNestedUl(li);

          if (directLinks.isNotEmpty) {
            for (final a in directLinks) {
              addPluginLink(a, subPath);
            }
            for (final nestedUl in nestedUls) {
              walkTree(nestedUl, subPath);
            }
          } else if (nestedUls.isNotEmpty) {
            final dirLabel = extractDirectFolderLabel(li);
            final nextSub = dirLabel.isNotEmpty
                ? (subPath.isEmpty ? dirLabel : '$subPath / $dirLabel')
                : subPath;
            for (final nestedUl in nestedUls) {
              walkTree(nestedUl, nextSub);
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
          addPluginLink(a, '');
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
        if (zipAction.isNotEmpty && idInput.isNotEmpty && folderUri != null) {
          final actionUri = folderUri.resolve(zipAction);
          final mergedParams = Map<String, String>.from(actionUri.queryParameters)
            ..['id'] = idInput;
          final zipUrl = actionUri.replace(queryParameters: mergedParams).toString();
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
    } on SessionExpiredException {
      rethrow;
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

    final canonicalRoot =
        root.isNotEmpty ? p.canonicalize(root) : '';

    for (final course in courses) {
      final courseFolder = sanitizeDirSegment(
        course.obsidianFolder.isNotEmpty ? course.obsidianFolder : course.cleanName,
      );
      final subSegments = course.targetSubfolder
          .trim()
          .split(RegExp(r'[/\\]+'))
          .where((s) => s.trim().isNotEmpty)
          .map((s) => sanitizeDirSegment(s.trim()))
          .toList();
      final baseCoursePath = p.joinAll([root, courseFolder, ...subSegments]);

      for (final item in course.items) {
        item.isNew = item.downloadable && !seenIds.contains(item.id);
        item.isDownloaded = false;
        item.localPath = null;

        if (!item.downloadable) continue;

        // 1. Check shared index (verify canonical path stays inside downloadRoot)
        final idxEntry = indexedItems[item.id];
        if (idxEntry is Map) {
          final relPath = idxEntry['relPath']?.toString() ?? '';
          if (relPath.isNotEmpty && canonicalRoot.isNotEmpty) {
            final segments = relPath
                .split(RegExp(r'[/\\]+'))
                .where((s) => s.isNotEmpty && s != '.')
                .toList();
            if (!segments.contains('..') && segments.isNotEmpty) {
              final full = p.joinAll([root, ...segments]);
              if (p.isWithin(canonicalRoot, p.canonicalize(full)) &&
                  await File(full).exists()) {
                item.isDownloaded = true;
                item.localPath = full;
                if ((idxEntry['fileName']?.toString() ?? '').isNotEmpty) {
                  item.fileName = idxEntry['fileName'].toString();
                }
                continue;
              }
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

  static String sanitizeDirSegment(String raw) {
    final clean = MoodleCourse.sanitizeFileName(raw);
    if (clean.length <= 60) return clean;
    final trimmed = clean.substring(0, 60).replaceAll(RegExp(r'^\.+|[.\s]+$'), '');
    return trimmed.isEmpty ? 'dir' : trimmed;
  }

  static String buildItemTargetDir({
    required String downloadRoot,
    required MoodleCourse course,
    required MoodleItem item,
  }) {
    final courseFolder = sanitizeDirSegment(
      course.obsidianFolder.isNotEmpty
          ? course.obsidianFolder
          : course.cleanName,
    );
    final parts = <String>[downloadRoot, courseFolder];
    if (course.targetSubfolder.trim().isNotEmpty) {
      for (final seg in course.targetSubfolder.trim().split(RegExp(r'[/\\]+'))) {
        if (seg.trim().isNotEmpty) {
          parts.add(sanitizeDirSegment(seg.trim()));
        }
      }
    }
    if (course.organizeBySection) {
      for (final seg in item.section.split('/')) {
        if (seg.trim().isNotEmpty) {
          parts.add(sanitizeDirSegment(seg.trim()));
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
      final batch =
          targets.sublist(i, i + 5 > targets.length ? targets.length : i + 5);
      await Future.wait(batch.map((item) async {
        try {
          var url = item.url;
          if (isTokenAuth) url = _appendToken(url);
          final result = await _sendFollowingRedirects(
            url,
            method: 'HEAD',
            persistCookies: false,
            requestTimeout: const Duration(seconds: 8),
          );
          try {
            await result.response.stream
                .drain<void>()
                .timeout(const Duration(seconds: 4));
          } catch (_) {}

          final lenStr = result.response.headers['content-length'];
          if (lenStr != null) {
            final len = int.tryParse(lenStr);
            if (len != null && len > 0) item.sizeBytes = len;
          }
          final extractedName = _extractFilenameFromResponse(
            result.response.headers,
            result.finalUri.toString(),
            item.title,
          );
          if (extractedName.isNotEmpty) {
            item.fileName = extractedName;
            final ext = inferFileExt(extractedName, result.finalUri.toString());
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
        final nextResolved = Uri.tryParse(res.finalUrl)?.resolve(nextHref);
        if (nextResolved == null) break;
        targetUrl = _ensureForcedDownload(nextResolved.toString());
        if (isTokenAuth) {
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

  /// Streams a Moodle resource directly to [destinationFile] while computing SHA-256 on the fly.
  Future<StreamedFileDownload> downloadItemToFile(
    MoodleItem item,
    File destinationFile, {
    void Function(int received, int? total)? onProgress,
  }) async {
    if (!isAuthenticated) throw SessionExpiredException();

    var targetUrl = _ensureForcedDownload(item.url);
    if (isTokenAuth) {
      targetUrl = _appendToken(targetUrl);
    }

    for (var unwrapHop = 0; unwrapHop < 3; unwrapHop++) {
      final result = await _sendFollowingRedirects(
        targetUrl,
        method: 'GET',
        requestTimeout: const Duration(seconds: 30),
      );
      final streamed = result.response;
      final finalUrl = result.finalUri.toString();

      if (streamed.statusCode == 401 || streamed.statusCode == 403) {
        try {
          await streamed.stream.drain<void>();
        } catch (_) {}
        throw SessionExpiredException();
      }
      if (streamed.statusCode < 200 || streamed.statusCode >= 400) {
        try {
          await streamed.stream.drain<void>();
        } catch (_) {}
        throw Exception(
          'Error HTTP ${streamed.statusCode} al descargar ${item.title}',
        );
      }

      final contentType =
          (streamed.headers['content-type'] ?? '').toLowerCase();
      if (!contentType.contains('text/html')) {
        final rawName = _extractFilenameFromResponse(
          streamed.headers,
          finalUrl,
          item.fileName.isNotEmpty ? item.fileName : item.title,
        );
        final ext = _resolveExtension(
          rawName,
          finalUrl,
          contentType,
          item.effectiveExt,
        );
        final finalName = _ensureFilenameHasExt(rawName, ext);

        await destinationFile.parent.create(recursive: true);
        final digestSink = _DigestSink();
        final hashSink = sha256.startChunkedConversion(digestSink);
        final total = int.tryParse(streamed.headers['content-length'] ?? '');
        var received = 0;
        final sink = destinationFile.openWrite();
        try {
          await for (final chunk in streamed.stream
              .timeout(const Duration(seconds: 60))) {
            sink.add(chunk);
            hashSink.add(chunk);
            received += chunk.length;
            onProgress?.call(received, total);
          }
          await sink.flush();
          hashSink.close();
        } finally {
          await sink.close();
        }
        return StreamedFileDownload(
          fileName: finalName,
          fileExt: ext,
          sizeBytes: received,
          sha256Hex: digestSink.value?.toString() ?? '',
        );
      }

      // Inspect HTML wrapper returned by Moodle
      final bodyBytes =
          await streamed.stream.toBytes().timeout(const Duration(seconds: 30));
      final html = utf8.decode(bodyBytes, allowMalformed: true);
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
        final nextResolved = Uri.tryParse(finalUrl)?.resolve(nextHref);
        if (nextResolved == null) break;
        targetUrl = _ensureForcedDownload(nextResolved.toString());
        if (isTokenAuth) {
          targetUrl = _appendToken(targetUrl);
        }
        continue;
      }

      // No file inside HTML -> write HTML page directly
      await destinationFile.parent.create(recursive: true);
      await destinationFile.writeAsBytes(bodyBytes, flush: true);
      final digest = sha256.convert(bodyBytes).toString();
      final safeBase = MoodleCourse.sanitizeFileName(item.title);
      return StreamedFileDownload(
        fileName: '$safeBase.html',
        fileExt: 'html',
        sizeBytes: bodyBytes.length,
        sha256Hex: digest,
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
    final uri = Uri.tryParse(url);
    if (token.isEmpty || uri == null || !isTrustedAulaUri(uri)) {
      return url;
    }
    if (uri.queryParameters.containsKey('token') ||
        uri.queryParameters.containsKey('wstoken')) {
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
    final parsed = Uri.tryParse(updated);
    if (parsed == null) return updated;
    final params = Map<String, String>.from(parsed.queryParameters)
      ..['token'] = token;
    return parsed.replace(queryParameters: params).toString();
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
      'ene': 1,
      'january': 1,
      'jan': 1,
      'febrero': 2,
      'feb': 2,
      'february': 2,
      'marzo': 3,
      'mar': 3,
      'march': 3,
      'abril': 4,
      'abr': 4,
      'april': 4,
      'apr': 4,
      'mayo': 5,
      'may': 5,
      'junio': 6,
      'jun': 6,
      'june': 6,
      'julio': 7,
      'jul': 7,
      'july': 7,
      'agosto': 8,
      'ago': 8,
      'august': 8,
      'aug': 8,
      'septiembre': 9,
      'setiembre': 9,
      'sep': 9,
      'sept': 9,
      'september': 9,
      'octubre': 10,
      'oct': 10,
      'october': 10,
      'noviembre': 11,
      'nov': 11,
      'november': 11,
      'diciembre': 12,
      'dic': 12,
      'december': 12,
      'dec': 12,
    };

    const dueMarkers = [
      'vence',
      'vencimiento',
      'cierre',
      'cierra',
      'entrega',
      'hasta',
      'due',
      'closes',
      'close',
      'cutoff',
    ];
    const openMarkers = [
      'apertura',
      'abierto',
      'abre',
      'opens',
      'opened',
    ];

    final lower = rawText.toLowerCase();
    bool hasDuePrefix(String prefix) =>
        dueMarkers.any((k) => prefix.contains(k));
    bool hasOpenPrefix(String prefix) =>
        openMarkers.any((k) => prefix.contains(k));

    // Matches both Spanish ("15 de abril de 2026, 23:59") and English ("15 April 2026, 23:59" or "April 15, 2026, 23:59")
    final dateCandidates = <({int start, int day, int month, int year, int hour, int min})>[];

    final esOrEnDayFirst = RegExp(
      r'(\d{1,2})\s+(?:de\s+)?([a-záéíóú]+)\s+(?:de\s+)?(\d{4})(?:,?\s*(?:a\s+las\s+)?(\d{1,2}):(\d{2}))?',
    );
    for (final m in esOrEnDayFirst.allMatches(lower)) {
      final month = months[m.group(2)!];
      if (month == null) continue;
      final day = int.tryParse(m.group(1)!) ?? 0;
      final year = int.tryParse(m.group(3)!) ?? DateTime.now().year;
      final hour = int.tryParse(m.group(4) ?? '23') ?? 23;
      final min = int.tryParse(m.group(5) ?? '59') ?? 59;
      if (day >= 1 && day <= 31) {
        dateCandidates.add((
          start: m.start,
          day: day,
          month: month,
          year: year,
          hour: hour,
          min: min,
        ));
      }
    }

    final enMonthFirst = RegExp(
      r'([a-záéíóú]+)\s+(\d{1,2}),?\s+(\d{4})(?:,?\s*(\d{1,2}):(\d{2}))?',
    );
    for (final m in enMonthFirst.allMatches(lower)) {
      final month = months[m.group(1)!];
      if (month == null) continue;
      final day = int.tryParse(m.group(2)!) ?? 0;
      final year = int.tryParse(m.group(3)!) ?? DateTime.now().year;
      final hour = int.tryParse(m.group(4) ?? '23') ?? 23;
      final min = int.tryParse(m.group(5) ?? '59') ?? 59;
      if (day >= 1 && day <= 31) {
        dateCandidates.add((
          start: m.start,
          day: day,
          month: month,
          year: year,
          hour: hour,
          min: min,
        ));
      }
    }

    if (dateCandidates.isNotEmpty) {
      dateCandidates.sort((a, b) => a.start.compareTo(b.start));
      ({int start, int day, int month, int year, int hour, int min})? chosen;
      for (final cand in dateCandidates) {
        final prefixStart = cand.start - 40 < 0 ? 0 : cand.start - 40;
        final prefix = lower.substring(prefixStart, cand.start);
        if (hasDuePrefix(prefix)) {
          chosen = cand;
        }
      }
      if (chosen == null) {
        final onlyCand = dateCandidates.length == 1 ? dateCandidates.first : null;
        if (onlyCand != null) {
          final prefixStart = onlyCand.start - 40 < 0 ? 0 : onlyCand.start - 40;
          final prefix = lower.substring(prefixStart, onlyCand.start);
          if (hasOpenPrefix(prefix) && !dueMarkers.any(lower.contains)) {
            return null;
          }
        }
        chosen = dateCandidates.last;
      }
      return DateTime(
        chosen.year,
        chosen.month,
        chosen.day,
        chosen.hour,
        chosen.min,
      );
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
