import 'dart:convert';
import 'dart:io';
import 'dart:ui' show PlatformDispatcher;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

class CapturedErrorLog {
  final String timestampIso;
  final String source;
  final String error;
  final String stackTrace;

  const CapturedErrorLog({
    required this.timestampIso,
    required this.source,
    required this.error,
    required this.stackTrace,
  });

  Map<String, dynamic> toJson() => {
        'timestampIso': timestampIso,
        'source': source,
        'error': error,
        'stackTrace': stackTrace,
      };

  factory CapturedErrorLog.fromJson(Map<String, dynamic> json) {
    return CapturedErrorLog(
      timestampIso: json['timestampIso']?.toString() ?? '',
      source: json['source']?.toString() ?? 'App',
      error: json['error']?.toString() ?? '',
      stackTrace: json['stackTrace']?.toString() ?? '',
    );
  }
}

class GitHubIssueResult {
  final int number;
  final String htmlUrl;

  const GitHubIssueResult({
    required this.number,
    required this.htmlUrl,
  });
}

/// Multiplatform bug-reporting and crash-log capture service.
///
/// Captures uncaught Flutter/platform errors in memory and SharedPreferences
/// and builds structured Markdown reports to open GitHub Issues on
/// `OscarAcosta17/notas` (via browser prefill URL or direct REST API with a
/// personal access token).
class BugReportService {
  static const String repoOwner = 'OscarAcosta17';
  static const String repoName = 'notas';
  static const String _errorLogsKey = 'bug_report_error_logs';
  static const int maxStoredErrors = 15;

  static final List<CapturedErrorLog> _memoryLogs = [];
  static bool _hooksInstalled = false;

  /// Installs global Flutter UI and async platform error hooks once.
  static void initErrorHooks() {
    if (_hooksInstalled) return;
    _hooksInstalled = true;

    final previousFlutterError = FlutterError.onError;
    FlutterError.onError = (FlutterErrorDetails details) {
      if (previousFlutterError != null) {
        previousFlutterError(details);
      } else {
        FlutterError.presentError(details);
      }
      recordError(
        details.exceptionAsString(),
        details.stack?.toString() ?? '',
        source: 'FlutterUI',
      );
    };

    PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
      recordError(
        error.toString(),
        stack.toString(),
        source: 'AsyncPlatform',
      );
      return false;
    };
  }

  /// Records a runtime error log in memory and persists the latest entries.
  static Future<void> recordError(
    String error,
    String stackTrace, {
    String source = 'App',
  }) async {
    final entry = CapturedErrorLog(
      timestampIso: DateTime.now().toUtc().toIso8601String(),
      source: source,
      error: error.trim(),
      stackTrace: stackTrace.trim(),
    );

    _memoryLogs.insert(0, entry);
    if (_memoryLogs.length > maxStoredErrors) {
      _memoryLogs.removeRange(maxStoredErrors, _memoryLogs.length);
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final existing = _decodeStoredLogs(prefs.getString(_errorLogsKey));
      final combined = <CapturedErrorLog>[
        entry,
        ...existing.where(
          (e) =>
              e.timestampIso != entry.timestampIso ||
              e.error != entry.error ||
              e.source != entry.source,
        ),
      ];
      if (combined.length > maxStoredErrors) {
        combined.removeRange(maxStoredErrors, combined.length);
      }
      await prefs.setString(
        _errorLogsKey,
        jsonEncode(combined.map((e) => e.toJson()).toList()),
      );
    } catch (e) {
      debugPrint('No se pudo persistir el log de error: $e');
    }
  }

  /// Returns stored and in-memory error logs, newest first.
  static Future<List<CapturedErrorLog>> getErrorLogs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = _decodeStoredLogs(prefs.getString(_errorLogsKey));
      if (stored.isEmpty) {
        return List<CapturedErrorLog>.unmodifiable(_memoryLogs);
      }
      final merged = <CapturedErrorLog>[..._memoryLogs];
      for (final log in stored) {
        final duplicate = merged.any(
          (m) =>
              m.timestampIso == log.timestampIso &&
              m.error == log.error &&
              m.source == log.source,
        );
        if (!duplicate) {
          merged.add(log);
        }
      }
      if (merged.length > maxStoredErrors) {
        merged.removeRange(maxStoredErrors, merged.length);
      }
      return List<CapturedErrorLog>.unmodifiable(merged);
    } catch (_) {
      return List<CapturedErrorLog>.unmodifiable(_memoryLogs);
    }
  }

  /// Clears captured runtime error logs from memory and storage.
  static Future<void> clearErrorLogs() async {
    _memoryLogs.clear();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_errorLogsKey);
    } catch (_) {
      // Ignore in headless/mocked environments
    }
  }

  static List<CapturedErrorLog> _decodeStoredLogs(String? raw) {
    if (raw == null || raw.trim().isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return decoded
          .whereType<Map>()
          .map((item) => CapturedErrorLog.fromJson(Map<String, dynamic>.from(item)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static String labelForCategory(String category) {
    switch (category) {
      case 'enhancement':
        return 'enhancement';
      case 'ui':
        return 'ui';
      case 'bug':
      default:
        return 'bug';
    }
  }

  static String titlePrefixForCategory(String category) {
    switch (category) {
      case 'bug':
        return '[BUG]';
      case 'enhancement':
        return '[SUGERENCIA]';
      case 'ui':
        return '[UI]';
      default:
        return '[REPORTE]';
    }
  }

  /// Builds a GitHub-ready Markdown diagnostic report with environment metadata and logs.
  static Future<String> buildDiagnosticReport({
    required String title,
    required String description,
    String stepsToReproduce = '',
    String category = 'bug',
    bool includeLogs = true,
    String? appVersionOverride,
  }) async {
    String versionText = appVersionOverride ?? 'v1.3.1+27';
    if (appVersionOverride == null) {
      try {
        final info = await PackageInfo.fromPlatform();
        versionText = 'v${info.version}+${info.buildNumber}';
      } catch (_) {
        versionText = 'v1.3.1+27';
      }
    }

    String escala = '0 a 100';
    String navStyle = 'm3_expressive';
    String surfaceStyle = 'tonal';
    String darkMode = 'false';
    String colorStyle = 'mixto';
    String semesterStyle = 'header';

    try {
      final prefs = await SharedPreferences.getInstance();
      escala = prefs.getString('escalaNotas') ?? escala;
      navStyle = prefs.getString('bottomNavStyle') ?? navStyle;
      surfaceStyle = prefs.getString('surfaceStyle') ?? surfaceStyle;
      darkMode = (prefs.getBool('isDarkMode') ?? false).toString();
      colorStyle = prefs.getString('subjectColorStyle') ?? colorStyle;
      semesterStyle = prefs.getString('semesterSelectorStyle') ?? semesterStyle;
    } catch (_) {
      // Fall back to defaults
    }

    final buffer = StringBuffer()
      ..writeln('### Reporte: ${titlePrefixForCategory(category)} ${title.trim()}')
      ..writeln()
      ..writeln('#### Descripción')
      ..writeln(description.trim().isEmpty ? '_Sin descripción adicional._' : description.trim())
      ..writeln();

    if (stepsToReproduce.trim().isNotEmpty) {
      buffer
        ..writeln('#### Pasos para reproducir')
        ..writeln(stepsToReproduce.trim())
        ..writeln();
    }

    buffer
      ..writeln('#### Ficha Técnica')
      ..writeln('| Campo | Valor |')
      ..writeln('| :--- | :--- |')
      ..writeln('| **Versión App** | `$versionText` |')
      ..writeln('| **Plataforma** | `${Platform.operatingSystem}` (`${Platform.operatingSystemVersion}`) |')
      ..writeln('| **Tema Oscuro / Superficie** | `$darkMode` / `$surfaceStyle` |')
      ..writeln('| **Barra Nav / Semestre** | `$navStyle` / `$semesterStyle` |')
      ..writeln('| **Estilo Tarjetas / Escala** | `$colorStyle` / `$escala` |')
      ..writeln();

    if (includeLogs) {
      final logs = await getErrorLogs();
      if (logs.isEmpty) {
        buffer.writeln('#### Registro de Errores\nSin excepciones registradas recientemente.');
      } else {
        buffer
          ..writeln('<details>')
          ..writeln('<summary>Stack traces capturados (${logs.length})</summary>')
          ..writeln();
        for (var i = 0; i < logs.length; i++) {
          final log = logs[i];
          final clippedStack = log.stackTrace.length > 600
              ? '${log.stackTrace.substring(0, 600)}\n... [truncado]'
              : log.stackTrace;
          buffer
            ..writeln('**#${i + 1} [${log.source}] — ${log.timestampIso}**')
            ..writeln('```text')
            ..writeln(log.error);
          if (clippedStack.isNotEmpty) {
            buffer.writeln(clippedStack);
          }
          buffer
            ..writeln('```')
            ..writeln();
        }
        buffer.writeln('</details>');
      }
    }

    return buffer.toString().trim();
  }

  /// Constructs a pre-filled GitHub New Issue URI for browser submission.
  static Uri buildGitHubIssueUri({
    required String title,
    required String markdownBody,
    String category = 'bug',
  }) {
    final cleanTitle = '${titlePrefixForCategory(category)} ${title.trim()}'.trim();
    final safeBody = markdownBody.length > 6000
        ? '${markdownBody.substring(0, 6000)}\n\n... [reporte recortado por longitud de URL]'
        : markdownBody;

    return Uri.https(
      'github.com',
      '/$repoOwner/$repoName/issues/new',
      {
        'title': cleanTitle,
        'labels': labelForCategory(category),
        'body': safeBody,
      },
    );
  }

  /// Opens the pre-filled GitHub Issue form in the system browser.
  static Future<bool> openGitHubIssueInBrowser({
    required String title,
    required String markdownBody,
    String category = 'bug',
  }) async {
    final uri = buildGitHubIssueUri(
      title: title,
      markdownBody: markdownBody,
      category: category,
    );
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  /// Directly creates a GitHub Issue via REST API using a user-provided token.
  static Future<GitHubIssueResult> createGitHubIssueDirect({
    required String token,
    required String title,
    required String markdownBody,
    String category = 'bug',
  }) async {
    final cleanToken = token.trim();
    if (cleanToken.isEmpty) {
      throw Exception('Debes ingresar un token personal de GitHub válido.');
    }

    final endpoint = Uri.parse('https://api.github.com/repos/$repoOwner/$repoName/issues');
    final headers = {
      'Authorization': 'Bearer $cleanToken',
      'Accept': 'application/vnd.github+json',
      'X-GitHub-Api-Version': '2022-11-28',
      'User-Agent': 'NotasApp-BugReporter',
      'Content-Type': 'application/json',
    };

    final fullTitle = '${titlePrefixForCategory(category)} ${title.trim()}'.trim();
    var response = await http
        .post(
          endpoint,
          headers: headers,
          body: jsonEncode({
            'title': fullTitle,
            'body': markdownBody,
            'labels': [labelForCategory(category)],
          }),
        )
        .timeout(const Duration(seconds: 20));

    // Retry without labels if non-collaborators lack label assignment permission
    if (response.statusCode == 403 || response.statusCode == 422) {
      response = await http
          .post(
            endpoint,
            headers: headers,
            body: jsonEncode({
              'title': fullTitle,
              'body': markdownBody,
            }),
          )
          .timeout(const Duration(seconds: 20));
    }

    if (response.statusCode == 201) {
      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      return GitHubIssueResult(
        number: (decoded['number'] as num?)?.toInt() ?? 0,
        htmlUrl: decoded['html_url']?.toString() ?? '',
      );
    }

    throw Exception(
      'GitHub rechazó el ticket (${response.statusCode}): ${response.body}',
    );
  }
}
