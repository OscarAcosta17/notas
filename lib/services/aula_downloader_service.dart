import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/aula_course.dart';
import '../models/categoria_evaluacion.dart';
import '../models/evaluacion.dart';
import '../models/ramo.dart';
import '../models/semestre.dart';
import 'aula_moodle_service.dart';
import 'aula_settings_service.dart';
import 'database_helper.dart';
import 'notification_service.dart';
import 'widget_service.dart';

class DownloadBatchResult {
  final int savedFiles;
  final int skipped;
  final int failed;
  final List<String> errors;

  const DownloadBatchResult({
    this.savedFiles = 0,
    this.skipped = 0,
    this.failed = 0,
    this.errors = const [],
  });
}

class DownloaderService {
  final MoodleService moodle;
  final SettingsService settings;

  DownloaderService({
    required this.moodle,
    required this.settings,
  });

  Future<DownloadBatchResult> downloadSelectedItems(
    List<MoodleCourse> courses, {
    void Function(int current, int total, MoodleItem item)? onProgress,
  }) async {
    final downloadRoot = await settings.getDownloadRoot();
    if (downloadRoot.isEmpty) {
      throw StoragePermissionException(
        'Selecciona una carpeta destino antes de descargar.',
      );
    }

    if (Platform.isAndroid && !await settings.hasStoragePermission()) {
      final granted = await settings.requestStoragePermission();
      if (!granted) {
        throw StoragePermissionException(
          'Permiso de almacenamiento denegado. Otorga acceso a archivos para guardar en $downloadRoot.',
        );
      }
    }

    final rootDir = Directory(downloadRoot);
    if (!await rootDir.exists()) {
      await rootDir.create(recursive: true);
    }
    final canonicalRoot = p.canonicalize(downloadRoot);

    final tasks = <({MoodleCourse course, MoodleItem item})>[];
    for (final c in courses) {
      for (final it in c.items) {
        if (it.downloadable && it.isSelected) {
          tasks.add((course: c, item: it));
        }
      }
    }

    if (tasks.isEmpty) {
      return const DownloadBatchResult();
    }

    final sharedIndex = await settings.loadSharedIndex(downloadRoot);
    final indexedFiles = Map<String, dynamic>.from(
      sharedIndex['files'] as Map? ?? {},
    );
    final newIndexEntries = <Map<String, dynamic>>[];
    final historyBatch = <DownloadHistoryEntry>[];

    var saved = 0;
    var skipped = 0;
    var failed = 0;
    final errors = <String>[];
    final touchedCourses = <MoodleCourse>{};
    final seenIdsBatch = <String>[];

    for (var i = 0; i < tasks.length; i++) {
      final pair = tasks[i];
      final course = pair.course;
      final item = pair.item;
      onProgress?.call(i + 1, tasks.length, item);

      if (settings.skipAlreadyDownloaded &&
          item.isDownloaded &&
          item.localPath != null &&
          await File(item.localPath!).exists()) {
        skipped++;
        seenIdsBatch.add(item.id);
        continue;
      }

      File? partFile;
      try {
        final targetDirPath = MoodleService.buildItemTargetDir(
          downloadRoot: downloadRoot,
          course: course,
          item: item,
        );
        if (!p.isWithin(canonicalRoot, p.canonicalize(targetDirPath))) {
          throw Exception('Ruta de destino fuera de la carpeta autorizada.');
        }
        final targetDir = Directory(targetDirPath);
        if (!await targetDir.exists()) {
          await targetDir.create(recursive: true);
        }

        final partName =
            '.${MoodleCourse.sanitizeFileName(item.id)}_${DateTime.now().microsecondsSinceEpoch}.part';
        partFile = File(p.join(targetDirPath, partName));

        final streamed = await moodle.downloadItemToFile(item, partFile);
        item.fileName = streamed.fileName;
        if (streamed.fileExt.isNotEmpty) item.fileExt = streamed.fileExt;
        item.sizeBytes = streamed.sizeBytes;
        final sha = streamed.sha256Hex;

        // Deduplicate against already indexed identical SHA files if enabled
        if (settings.skipAlreadyDownloaded &&
            sha.isNotEmpty &&
            indexedFiles.containsKey(sha)) {
          final existingEntry = indexedFiles[sha];
          if (existingEntry is Map) {
            final existingRel = existingEntry['relPath']?.toString() ?? '';
            final segs = existingRel
                .split(RegExp(r'[/\\]+'))
                .where((s) => s.isNotEmpty && s != '.')
                .toList();
            if (!segs.contains('..') && segs.isNotEmpty) {
              final existingFull = p.joinAll([downloadRoot, ...segs]);
              if (p.isWithin(canonicalRoot, p.canonicalize(existingFull)) &&
                  await File(existingFull).exists()) {
                item.isDownloaded = true;
                item.localPath = existingFull;
                item.isNew = false;
                item.isSelected = false;
                skipped++;
                seenIdsBatch.add(item.id);
                touchedCourses.add(course);
                continue;
              }
            }
          }
        }

        final cleanFileName = MoodleCourse.sanitizeFileName(streamed.fileName);
        var finalDestPath = p.join(targetDirPath, cleanFileName);
        if (!p.isWithin(canonicalRoot, p.canonicalize(finalDestPath))) {
          throw Exception('Archivo fuera de la carpeta autorizada.');
        }

        var alreadyIdentical = false;
        if (await File(finalDestPath).exists()) {
          final existingSha = await settings.computeFileSha256(finalDestPath);
          if (settings.skipAlreadyDownloaded &&
              existingSha != null &&
              existingSha.isNotEmpty &&
              existingSha == sha) {
            alreadyIdentical = true;
          } else {
            // Avoid overwriting unrelated unindexed files with the same name
            final base = p.basenameWithoutExtension(cleanFileName);
            final ext = p.extension(cleanFileName);
            var suffix = 2;
            while (await File(finalDestPath).exists()) {
              final candidateName =
                  MoodleCourse.sanitizeFileName('$base ($suffix)$ext');
              finalDestPath = p.join(targetDirPath, candidateName);
              suffix++;
            }
          }
        }

        if (alreadyIdentical) {
          item.isDownloaded = true;
          item.localPath = finalDestPath;
          item.isNew = false;
          item.isSelected = false;
          skipped++;
          seenIdsBatch.add(item.id);
          touchedCourses.add(course);
          continue;
        }

        await _moveFileReplacing(partFile, File(finalDestPath));
        partFile = null;

        final relPath = p
            .relative(finalDestPath, from: downloadRoot)
            .replaceAll('\\', '/');
        if (sha.isNotEmpty) {
          indexedFiles[sha] = {
            'relPath': relPath,
            'sizeBytes': streamed.sizeBytes,
            'title': item.title,
          };
        }

        newIndexEntries.add({
          'itemId': item.id,
          'sha256': sha,
          'fileName': p.basename(finalDestPath),
          'relPath': relPath,
          'sizeBytes': streamed.sizeBytes,
          'title': item.title,
        });

        item.isDownloaded = true;
        item.localPath = finalDestPath;
        item.isNew = false;
        item.isSelected = false;
        seenIdsBatch.add(item.id);
        touchedCourses.add(course);
        saved++;

        historyBatch.add(DownloadHistoryEntry(
          timestamp: DateTime.now().toIso8601String(),
          course: course.cleanName,
          title: item.title,
          fileName: p.basename(finalDestPath),
          savedPath: finalDestPath,
          sizeBytes: streamed.sizeBytes,
        ));
      } on SessionExpiredException {
        rethrow;
      } catch (e) {
        failed++;
        errors.add('${item.title}: $e');
      } finally {
        if (partFile != null) {
          try {
            if (await partFile.exists()) await partFile.delete();
          } catch (_) {}
        }
      }
    }

    if (historyBatch.isNotEmpty) {
      await settings.recordDownloadHistoryBatch(historyBatch);
    }

    if (newIndexEntries.isNotEmpty) {
      await settings.recordSharedIndexEntries(downloadRoot, newIndexEntries);
    }
    if (seenIdsBatch.isNotEmpty) {
      await settings.markIdsSeen(seenIdsBatch);
    }

    for (final course in touchedCourses) {
      await _rebuildCourseGraphMarkdown(downloadRoot, course);
    }

    if (saved > 0 && settings.notifyOnDownloadDone) {
      await settings.addNotification(AulaNotification(
        id: 'dl_${DateTime.now().millisecondsSinceEpoch}',
        title: 'Descarga completada ($saved archivo${saved == 1 ? "" : "s"})',
        body: skipped > 0
            ? 'Guardados en Obsidian/carpeta destino ($skipped omitidos por duplicado).'
            : 'Material organizado y notas de Obsidian actualizadas.',
        type: 'download_done',
        timestamp: DateTime.now().toIso8601String(),
      ));
      if (settings.notifyNativeEnabled) {
        await settings.showNativeNotification(
          id: 2001,
          title: 'Descarga Aula USM completada',
          body: '$saved archivo(s) guardado(s) correctamente.',
        );
      }
    }

    return DownloadBatchResult(
      savedFiles: saved,
      skipped: skipped,
      failed: failed,
      errors: errors,
    );
  }

  Future<String> syncCourseObsidianIndex(MoodleCourse course) async {
    final downloadRoot = await settings.getDownloadRoot();
    if (downloadRoot.isEmpty) {
      throw StoragePermissionException('Define una carpeta destino primero.');
    }
    return _rebuildCourseGraphMarkdown(downloadRoot, course);
  }

  static Future<void> _moveFileReplacing(File source, File dest) async {
    try {
      await source.rename(dest.path);
    } on FileSystemException {
      await source.copy(dest.path);
      if (await source.exists()) {
        await source.delete();
      }
    }
  }

  static String _safeMarkdownLabel(String raw) {
    return raw
        .replaceAll(RegExp(r'[\r\n]+'), ' ')
        .replaceAll('[', r'\[')
        .replaceAll(']', r'\]')
        .trim();
  }

  static String _safeMarkdownLink(String label, String rawUrl) {
    final cleanLabel = _safeMarkdownLabel(label);
    final stripped = MoodleService.stripSensitiveQueryParams(rawUrl.trim());
    final uri = Uri.tryParse(stripped);
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
      return cleanLabel;
    }
    final encoded = stripped.replaceAll(' ', '%20').replaceAll(')', '%29');
    return '[$cleanLabel]($encoded)';
  }

  Future<String> _rebuildCourseGraphMarkdown(
    String downloadRoot,
    MoodleCourse course,
  ) async {
    final canonicalRoot = p.canonicalize(downloadRoot);
    final courseFolder = MoodleService.sanitizeDirSegment(
      course.obsidianFolder.isNotEmpty
          ? course.obsidianFolder
          : course.cleanName,
    );
    final baseParts = <String>[downloadRoot, courseFolder];
    if (course.targetSubfolder.trim().isNotEmpty) {
      for (final seg
          in course.targetSubfolder.trim().split(RegExp(r'[/\\]+'))) {
        if (seg.trim().isNotEmpty) {
          baseParts.add(MoodleService.sanitizeDirSegment(seg.trim()));
        }
      }
    }
    final courseBaseDirPath = p.joinAll(baseParts);
    if (!p.isWithin(canonicalRoot, p.canonicalize(courseBaseDirPath))) {
      throw Exception('Ruta de índice fuera de la carpeta destino.');
    }
    final courseBaseDir = Directory(courseBaseDirPath);
    if (!await courseBaseDir.exists()) {
      await courseBaseDir.create(recursive: true);
    }

    // Group items by top-level section (strip " / Subfolder" when grouping section notes)
    final groupedBySection = <String, List<MoodleItem>>{};
    for (final item in course.items) {
      final topSection = item.section.split('/').first.trim();
      final secKey = topSection.isEmpty ? 'General' : topSection;
      groupedBySection.putIfAbsent(secKey, () => []).add(item);
    }

    final nowIso = DateTime.now().toIso8601String();
    final sectionNoteLinks = <String>[];

    for (final entry in groupedBySection.entries) {
      final secTitle = entry.key;
      final secItems = entry.value;
      final cleanSecTitle = MoodleService.sanitizeDirSegment(secTitle);
      final secNoteName =
          MoodleCourse.sanitizeFileName('00 - Seccion - $cleanSecTitle.md');
      final secNoteDir = course.organizeBySection
          ? p.join(courseBaseDirPath, cleanSecTitle)
          : courseBaseDirPath;
      if (!p.isWithin(canonicalRoot, p.canonicalize(secNoteDir))) {
        continue;
      }
      final secDirObj = Directory(secNoteDir);
      if (!await secDirObj.exists()) {
        await secDirObj.create(recursive: true);
      }

      final buf = StringBuffer();
      buf.writeln('---');
      buf.writeln('curso: ${jsonEncode(course.cleanName)}');
      buf.writeln('seccion: ${jsonEncode(secTitle)}');
      buf.writeln('fuente: aula.usm.cl');
      buf.writeln('actualizado: ${jsonEncode(nowIso)}');
      buf.writeln('tags:');
      buf.writeln('  - aula-usm');
      buf.writeln(
        '  - ${MoodleCourse.normalizeForMatch(course.shortname.isNotEmpty ? course.shortname : course.cleanName).replaceAll(' ', '-')}',
      );
      buf.writeln('---');
      buf.writeln();
      buf.writeln('# ${secTitle.replaceAll(RegExp(r'[\r\n]+'), ' ')}');
      buf.writeln();
      buf.writeln(
        '[[00 - Indice Aula - $courseFolder|← Volver al índice de ${_safeMarkdownLabel(course.cleanName)}]]',
      );
      buf.writeln();

      final files = secItems.where((it) => it.downloadable).toList();
      final links = secItems
          .where((it) =>
              it.type == 'url' ||
              it.type == 'page' ||
              it.type == 'book' ||
              it.type == 'lesson')
          .toList();
      final forums = secItems.where((it) => it.type == 'forum').toList();
      final tasks = secItems
          .where((it) =>
              it.type == 'assign' ||
              it.type == 'assignment' ||
              it.type == 'quiz' ||
              it.hasDeadline)
          .toList();

      if (files.isNotEmpty) {
        buf.writeln('## Materiales y Archivos');
        for (final f in files) {
          final localName = f.localPath != null && f.localPath!.isNotEmpty
              ? p.basename(f.localPath!)
              : MoodleCourse.sanitizeFileName(
                  f.fileName.isNotEmpty ? f.fileName : f.title,
                );
          final status = f.isDownloaded ? '✅' : '⏳';
          final relFromNote = f.localPath != null && f.localPath!.isNotEmpty
              ? p.relative(f.localPath!, from: secNoteDir).replaceAll('\\', '/')
              : localName;
          final size = f.formattedSize.isNotEmpty ? ' (${f.formattedSize})' : '';
          buf.writeln(
            '- $status [[$relFromNote|${_safeMarkdownLabel(f.title)}]]$size',
          );
        }
        buf.writeln();
      }

      if (tasks.isNotEmpty) {
        buf.writeln('## Entregas y Evaluaciones');
        for (final t in tasks) {
          final due = t.formattedDueDate.isNotEmpty
              ? ' 📅 ${t.formattedDueDate}'
              : '';
          buf.writeln('- [ ] ${_safeMarkdownLink(t.title, t.url)}$due');
        }
        buf.writeln();
      }

      if (settings.autoExportLinksToObsidian && links.isNotEmpty) {
        buf.writeln('## Enlaces y Páginas');
        for (final l in links) {
          buf.writeln('- 🔗 ${_safeMarkdownLink(l.title, l.url)}');
        }
        buf.writeln();
      }

      if (settings.autoExportForumsToObsidian && forums.isNotEmpty) {
        buf.writeln('## Foros y Anuncios');
        for (final fo in forums) {
          buf.writeln('- 💬 ${_safeMarkdownLink(fo.title, fo.url)}');
        }
        buf.writeln();
      }

      await File(p.join(secNoteDir, secNoteName))
          .writeAsString(buf.toString(), flush: true);

      final relNotePath = course.organizeBySection
          ? '$cleanSecTitle/$secNoteName'
          : secNoteName;
      sectionNoteLinks.add(
        '- [[$relNotePath|${_safeMarkdownLabel(secTitle)}]] (${secItems.length})',
      );
    }

    // Main Course Index Note
    final indexFileName =
        MoodleCourse.sanitizeFileName('00 - Indice Aula - $courseFolder.md');
    final cleanCourseUrl =
        MoodleService.stripSensitiveQueryParams(course.url);
    final indexBuf = StringBuffer();
    indexBuf.writeln('---');
    indexBuf.writeln('curso: ${jsonEncode(course.cleanName)}');
    indexBuf.writeln('codigo: ${jsonEncode(course.shortname)}');
    indexBuf.writeln('aula_url: ${jsonEncode(cleanCourseUrl)}');
    indexBuf.writeln('actualizado: ${jsonEncode(nowIso)}');
    indexBuf.writeln('tags:');
    indexBuf.writeln('  - aula-usm');
    indexBuf.writeln('  - indice-curso');
    indexBuf.writeln('---');
    indexBuf.writeln();
    indexBuf.writeln('# ${course.cleanName.replaceAll(RegExp(r'[\r\n]+'), ' ')}');
    final openAulaLink = _safeMarkdownLink('Abrir en Aula USM', cleanCourseUrl);
    if (course.shortname.isNotEmpty) {
      final safeShort = course.shortname.replaceAll('`', '');
      indexBuf.writeln('> Código Aula: `$safeShort` · $openAulaLink');
    } else {
      indexBuf.writeln('> $openAulaLink');
    }
    indexBuf.writeln();

    final upcomingDeadlines = course.items
        .where((it) => it.hasDeadline && !it.isPastDeadline)
        .toList()
      ..sort((a, b) => (a.dueTimestamp ?? 0).compareTo(b.dueTimestamp ?? 0));

    if (upcomingDeadlines.isNotEmpty) {
      indexBuf.writeln('> [!warning] Próximas entregas');
      for (final d in upcomingDeadlines) {
        indexBuf.writeln(
          '> - [ ] **${_safeMarkdownLabel(d.title)}** — ${d.formattedDueDate} (${_safeMarkdownLink('Abrir', d.url)})',
        );
      }
      indexBuf.writeln();
    }

    indexBuf.writeln('## Secciones del Curso');
    for (final linkLine in sectionNoteLinks) {
      indexBuf.writeln(linkLine);
    }

    final indexFilePath = p.join(courseBaseDirPath, indexFileName);
    await File(indexFilePath).writeAsString(indexBuf.toString(), flush: true);
    return indexFilePath;
  }
}

class AulaNotasSynergyService {
  final DatabaseHelper _db = DatabaseHelper.instance;
  final SettingsService _settings = SettingsService.instance;

  Future<Semestre> ensureActiveSemester([int? preferredSemesterId]) async {
    final rows = await _db.queryAllSemesters();
    final semesters = rows.map(Semestre.fromMap).toList();
    if (preferredSemesterId != null) {
      for (final s in semesters) {
        if (s.id == preferredSemesterId) return s;
      }
    }
    if (semesters.isNotEmpty) return semesters.last;
    final id = await _db.insertSemester(
      Semestre(nombre: 'Semestre Actual').toMap(),
    );
    return Semestre(id: id, nombre: 'Semestre Actual');
  }

  Future<List<Ramo>> loadRamosForSemester(int semesterId) async {
    final rows = await _db.querySubjectsBySemester(semesterId);
    final ramos = rows.map(Ramo.fromMap).toList();
    for (final r in ramos) {
      if (r.id == null) continue;
      final grouped = await _db.queryCategoriesWithEvaluationsBySubject(r.id!);
      r.categorias = grouped.map((entry) {
        final cat = CategoriaEvaluacion.fromMap(entry.category);
        cat.evaluaciones = entry.evaluations.map(Evaluacion.fromMap).toList();
        return cat;
      }).toList();
    }
    return ramos;
  }

  Future<Ramo> createRamoFromCourse(
    MoodleCourse course, {
    required int semesterId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final escala = prefs.getString('escalaNotas') ?? '0 a 100';
    final passing = escala == '1 a 7' ? 4.0 : 55.0;

    final ramo = Ramo(
      idSemestre: semesterId,
      nombre: course.cleanName,
      tipoPromedio: 'Aritmetico',
      tieneGlobal: false,
      reemplazaPeorNota: false,
      notaAprobacion: passing,
    );
    final newId = await _db.insertSubject(ramo.toMap());
    ramo.id = newId;

    // Keep synced Aula tasks in a 0% bucket so they don't overwrite real grade weights.
    final cat = CategoriaEvaluacion(
      idRamo: newId,
      nombre: 'Aula USM',
      porcentajeTotal: 0.0,
    );
    final catId = await _db.insertCategory(cat.toMap());
    cat.id = catId;
    ramo.categorias = [cat];

    course.linkedRamoId = newId;
    await _settings.setCourseRamoLink(course.id, newId);
    return ramo;
  }

  Future<int> syncCourseDeadlinesToRamo({
    required MoodleCourse course,
    required Ramo ramo,
    List<MoodleItem>? specificItems,
  }) async {
    if (ramo.id == null) return 0;

    final grouped = await _db.queryCategoriesWithEvaluationsBySubject(ramo.id!);
    var cats = grouped.map((entry) {
      final cat = CategoriaEvaluacion.fromMap(entry.category);
      cat.evaluaciones = entry.evaluations.map(Evaluacion.fromMap).toList();
      return cat;
    }).toList();

    CategoriaEvaluacion targetCat;
    if (cats.isEmpty) {
      final created = CategoriaEvaluacion(
        idRamo: ramo.id!,
        nombre: 'Aula USM',
        porcentajeTotal: 0.0,
      );
      created.id = await _db.insertCategory(created.toMap());
      targetCat = created;
      cats = [created];
    } else {
      targetCat = cats.first;
    }

    final existingAll = cats.expand((c) => c.evaluaciones).toList();
    final sourceItems = specificItems ??
        course.items.where((it) => it.isAssessableActivity && it.dueDate != null).toList();

    var added = 0;
    final scheduledEvals = <Evaluacion>[];
    for (final item in sourceItems) {
      final due = item.dueDate;
      if (due == null) continue;
      final match = MoodleCourse.findMatchingEvaluacion(item, existingAll);
      if (match != null) {
        // Update missing date on matching evaluation
        if (match.fecha == null && match.id != null) {
          match.fecha = due;
          await _db.updateEvaluation(match.toMap());
          scheduledEvals.add(match);
          added++;
        }
        continue;
      }

      // Pick best matching category if keywords match (e.g. Certamen, Control, Tarea, Lab)
      final bestCat = _pickBestCategoryForItem(item, cats) ?? targetCat;
      if (bestCat.id == null) continue;
      final newEval = Evaluacion(
        idCategoria: bestCat.id!,
        nombre: item.title,
        fecha: due,
      );
      newEval.id = await _db.insertEvaluation(newEval.toMap());
      existingAll.add(newEval);
      scheduledEvals.add(newEval);
      added++;
    }

    for (final ev in scheduledEvals) {
      try {
        await NotificationService.scheduleEvaluationReminder(ev, ramo.nombre);
      } catch (_) {}
    }
    if (added > 0) {
      try {
        await WidgetService.updateAgendaWidget();
      } catch (_) {}
    }

    return added;
  }

  CategoriaEvaluacion? _pickBestCategoryForItem(
    MoodleItem item,
    List<CategoriaEvaluacion> cats,
  ) {
    final norm = MoodleCourse.normalizeAcademicText(item.title);
    for (final c in cats) {
      final cNorm = MoodleCourse.normalizeAcademicText(c.nombre);
      if (cNorm.contains('tarea') && norm.contains('tarea')) return c;
      if (cNorm.contains('certamen') && norm.contains('certamen')) return c;
      if (cNorm.contains('control') &&
          (norm.contains('control') || norm.contains('quiz') || item.type == 'quiz')) {
        return c;
      }
      if (cNorm.contains('lab') && norm.contains('lab')) return c;
    }
    return null;
  }
}
