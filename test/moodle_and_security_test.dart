import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:notas/models/aula_course.dart';
import 'package:notas/services/aula_moodle_service.dart';
import 'package:notas/services/aula_settings_service.dart';
import 'package:notas/services/bug_report_service.dart';
import 'package:notas/services/secure_credential_store.dart';
import 'package:notas/services/updater_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('MoodleItem & MoodleCourse hardening', () {
    test('generates deterministic SHA-256 fallback ID and ignores php/aspx extensions', () {
      final a = MoodleItem(
        courseId: 42,
        title: 'Certamen 1 Pauta',
        url: 'https://aula.usm.cl/mod/resource/view.php?id=999',
      );
      final b = MoodleItem(
        courseId: 42,
        title: 'Certamen 1 Pauta',
        url: 'https://aula.usm.cl/mod/resource/view.php?id=999',
      );

      expect(a.id, equals(b.id));
      expect(a.id, startsWith('42_'));
      expect(a.effectiveExt, isEmpty);

      final pdfItem = MoodleItem(
        courseId: 42,
        title: 'Guía 1',
        fileName: 'Guia_1.PDF',
        url: 'https://aula.usm.cl/pluginfile.php/123/mod_resource/content/1/Guia_1.PDF',
      );
      expect(pdfItem.effectiveExt, 'pdf');
    });

    test('sanitizeFileName blocks path traversal, reserved Windows names, and overlong stems', () {
      expect(MoodleCourse.sanitizeFileName('...'), 'archivo');
      expect(MoodleCourse.sanitizeFileName('..'), 'archivo');
      expect(MoodleCourse.sanitizeFileName('CON.txt'), '_CON.txt');
      expect(MoodleCourse.sanitizeFileName('lpt1.pdf'), '_lpt1.pdf');
      expect(MoodleCourse.sanitizeFileName('nul'), '_nul');

      final longStem = 'A' * 150;
      final sanitized = MoodleCourse.sanitizeFileName('$longStem.pdf');
      expect(sanitized.length, lessThanOrEqualTo(120));
      expect(sanitized.endsWith('.pdf'), isTrue);
      expect(sanitized.contains('..pdf'), isFalse);
    });

    test('fromJson tolerates string and double numeric fields safely', () {
      final course = MoodleCourse.fromJson({
        'id': '305',
        'fullname': '[INF-253] Lenguajes de Programación (2026-1)',
        'linkedRamoId': '12',
        'items': [
          {
            'courseId': '305',
            'title': 'Tarea 1',
            'sizeBytes': 4096.0,
            'dueTimestamp': '1775000000',
          },
        ],
      });

      expect(course.id, 305);
      expect(course.linkedRamoId, 12);
      expect(course.items.single.sizeBytes, 4096);
      expect(course.items.single.dueTimestamp, 1775000000);
    });
  });

  group('MoodleService & SettingsService security boundaries', () {
    test('isTrustedAulaUri enforces HTTPS and strict aula.usm.cl host matching', () {
      expect(MoodleService.isTrustedAulaUri(Uri.parse('https://aula.usm.cl/my/')), isTrue);
      expect(MoodleService.isTrustedAulaUri(Uri.parse('https://api.aula.usm.cl/login')), isTrue);
      expect(MoodleService.isTrustedAulaUri(Uri.parse('http://aula.usm.cl/my/')), isFalse);
      expect(MoodleService.isTrustedAulaUri(Uri.parse('https://evil-aula.usm.cl/my/')), isFalse);
      expect(MoodleService.isTrustedAulaUri(Uri.parse('https://attacker.com/aula.usm.cl')), isFalse);
    });

    test('stripSensitiveQueryParams removes token, wstoken, and sesskey from URLs', () {
      const raw =
          'https://aula.usm.cl/webservice/pluginfile.php/10/mod_resource/content/1/doc.pdf?token=secret123&forcedownload=1&wstoken=abc&sesskey=xyz#page=2';
      final stripped = MoodleService.stripSensitiveQueryParams(raw);

      expect(stripped, isNot(contains('secret123')));
      expect(stripped, isNot(contains('token=')));
      expect(stripped, isNot(contains('sesskey=')));
      expect(stripped, contains('forcedownload=1'));
      expect(stripped, endsWith('#page=2'));
    });

    test('SettingsService flags dangerous executable extensions and persists unlinked Ramo sentinel', () async {
      expect(SettingsService.isDangerousFile('script.ps1'), isTrue);
      expect(SettingsService.isDangerousFile('payload.EXE'), isTrue);
      expect(SettingsService.isDangerousFile('installer.apk'), isTrue);
      expect(SettingsService.isDangerousFile('apuntes.pdf'), isFalse);
      expect(SettingsService.isDangerousFile('resumen.md'), isFalse);

      SharedPreferences.setMockInitialValues({});
      final settings = SettingsService();
      await settings.setCourseRamoLink(777, null);
      final links = await settings.getCourseRamoLinks();
      expect(links[777], SettingsService.unlinkedRamoSentinel);
    });
  });

  group('BugReportService, UpdaterService & SecureCredentialStore', () {
    test('BugReportService.redactSensitiveText scrubs tokens, cookies, and OS user paths', () {
      const sample =
          'Error calling https://aula.usm.cl/api?wstoken=my_secret_ws&sesskey=sess_999 '
          'Cookie: MoodleSession=cookie_abc123; Authorization: Bearer eyJhbGciOi.test '
          'ghp_1234567890abcdefghijklmnopqrstuvwx 1//0gabcdef1234567890 '
          r'at C:\Users\oscar\OneDrive\Documentos\notas and /home/oscar/vault/note.md';

      final redacted = BugReportService.redactSensitiveText(sample);

      expect(redacted, isNot(contains('my_secret_ws')));
      expect(redacted, isNot(contains('sess_999')));
      expect(redacted, isNot(contains('cookie_abc123')));
      expect(redacted, isNot(contains('eyJhbGciOi.test')));
      expect(redacted, isNot(contains('ghp_1234567890')));
      expect(redacted, isNot(contains('1//0gabcdef1234567890')));
      expect(redacted, isNot(contains(r'C:\Users\oscar')));
      expect(redacted, isNot(contains('/home/oscar')));
      expect(redacted, contains('wstoken=[REDACTED]'));
      expect(redacted, contains('MoodleSession=[REDACTED]'));
      expect(redacted, contains(r'C:\Users\<USER>'));
      expect(redacted, contains('/home/<USER>'));
    });

    test('UpdaterService validates trusted GitHub HTTPS hosts and parses SHA256SUMS.txt', () {
      expect(
        UpdaterService.isTrustedDownloadUrl(
          'https://github.com/OscarAcosta17/notas/releases/download/v1.3.0/app-release.apk',
        ),
        isTrue,
      );
      expect(
        UpdaterService.isTrustedDownloadUrl(
          'https://objects.githubusercontent.com/github-production-release-asset/app.apk',
        ),
        isTrue,
      );
      expect(
        UpdaterService.isTrustedDownloadUrl('http://github.com/OscarAcosta17/notas/app.apk'),
        isFalse,
      );
      expect(
        UpdaterService.isTrustedDownloadUrl('https://evil-github.com/app.apk'),
        isFalse,
      );

      const sums = '''
e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855  *app-release.apk
0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef  dist/Notas-Setup.exe
''';
      expect(
        UpdaterService.parseSha256ForAsset(sums, 'app-release.apk'),
        'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
      );
      expect(
        UpdaterService.parseSha256ForAsset(sums, 'Notas-Setup.exe'),
        '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef',
      );
      expect(UpdaterService.parseSha256ForAsset(sums, 'missing.zip'), isNull);
    });

    test('SecureCredentialStore migrates plaintext and roundtrips encrypted credentials', () async {
      SharedPreferences.setMockInitialValues({
        'legacy_token_key': 'legacy_secret_value',
      });

      final migrated = await SecureCredentialStore.read('legacy_token_key');
      expect(migrated, 'legacy_secret_value');

      await SecureCredentialStore.write('aula_token', 'super_secret_token');
      expect(await SecureCredentialStore.read('aula_token'), 'super_secret_token');

      await SecureCredentialStore.delete('aula_token');
      expect(await SecureCredentialStore.read('aula_token'), isNull);

      if (Platform.isWindows) {
        SecureCredentialStore.allowDpapiInTests = true;
        addTearDown(() => SecureCredentialStore.allowDpapiInTests = false);

        await SecureCredentialStore.write('dpapi_key', 'windows_dpapi_secret_123');
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString('dpapi_key'), startsWith('dpapi_v1:'));
        expect(await SecureCredentialStore.read('dpapi_key'), 'windows_dpapi_secret_123');
      }
    });
  });
}
