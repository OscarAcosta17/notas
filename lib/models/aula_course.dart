import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'evaluacion.dart';
import 'ramo.dart';

int? _parseIntNullable(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value == null) return null;
  return int.tryParse(value.toString().trim());
}

class MoodleItem {
  final String id;
  final int courseId;
  final String title;
  final String section;
  final String type; // resource, assign, quiz, url, folder, forum, page, label
  final String url;
  String fileName;
  String fileExt;
  final bool downloadable;
  int? sizeBytes;
  bool isDownloaded;
  bool isNew;
  String? localPath;
  bool isSelected;
  int? dueTimestamp; // Unix seconds
  String? dueText;

  MoodleItem({
    String? id,
    this.courseId = 0,
    String? title,
    String? name,
    String? section,
    String? sectionName,
    this.type = 'resource',
    this.url = '',
    this.fileName = '',
    this.fileExt = '',
    bool? downloadable,
    bool? isDownloadable,
    int? sizeBytes,
    int? fileSize,
    this.isDownloaded = false,
    this.isNew = false,
    this.localPath,
    this.isSelected = false,
    int? dueTimestamp,
    DateTime? dueDate,
    this.dueText,
  })  : title = title ?? name ?? '',
        section = section ?? sectionName ?? 'General',
        downloadable = downloadable ?? isDownloadable ?? false,
        sizeBytes = sizeBytes ?? fileSize,
        dueTimestamp = dueTimestamp ??
            (dueDate != null ? dueDate.millisecondsSinceEpoch ~/ 1000 : null),
        id = (id != null && id.isNotEmpty)
            ? id
            : _deterministicId(courseId, title ?? name ?? '', url);

  static String _deterministicId(int courseId, String title, String url) {
    final digest =
        sha256.convert(utf8.encode('$courseId|$title|$url')).toString();
    return '${courseId}_${digest.substring(0, 16)}';
  }

  // Aliases for NotasApp compatibility
  String get name => title;
  String get sectionName => section;
  bool get isDownloadable => downloadable;
  int? get fileSize => sizeBytes;
  DateTime? get dueDate => dueTimestamp != null && dueTimestamp! > 0
      ? DateTime.fromMillisecondsSinceEpoch(dueTimestamp! * 1000)
      : null;

  static const Set<String> _ignoredWebExts = {'php', 'aspx'};

  String get effectiveExt {
    if (fileExt.isNotEmpty) {
      final lower = fileExt.toLowerCase();
      if (!_ignoredWebExts.contains(lower)) return lower;
    }
    final candidate = fileName.isNotEmpty ? fileName : url.split('?').first;
    final dot = candidate.lastIndexOf('.');
    if (dot != -1 && dot < candidate.length - 1) {
      final ext = candidate.substring(dot + 1).toLowerCase();
      if (ext.length <= 5 &&
          !_ignoredWebExts.contains(ext) &&
          RegExp(r'^[a-z0-9]+$').hasMatch(ext)) {
        return ext;
      }
    }
    return '';
  }

  bool get hasDeadline =>
      (dueTimestamp != null && dueTimestamp! > 0) ||
      (dueText != null && dueText!.trim().isNotEmpty);

  bool get isUrgentDeadline {
    if (dueTimestamp == null || dueTimestamp! <= 0) return false;
    final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final diff = dueTimestamp! - nowSec;
    return diff >= 0 && diff <= 7 * 24 * 3600;
  }

  bool get isPastDeadline {
    if (dueTimestamp == null || dueTimestamp! <= 0) return false;
    final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    return dueTimestamp! < nowSec;
  }

  bool get isAssessableActivity {
    final t = type.toLowerCase();
    return t == 'assign' ||
        t == 'assignment' ||
        t == 'quiz' ||
        t == 'workshop' ||
        t == 'lti' ||
        hasDeadline;
  }

  String get formattedSize => formatFileSize(sizeBytes);

  String get formattedDueDate {
    final dt = dueDate;
    if (dt != null) {
      final d = dt.day.toString().padLeft(2, '0');
      final m = dt.month.toString().padLeft(2, '0');
      final h = dt.hour.toString().padLeft(2, '0');
      final min = dt.minute.toString().padLeft(2, '0');
      return '$d/$m $h:$min';
    }
    return dueText ?? '';
  }

  String get typeLabel {
    switch (type.toLowerCase()) {
      case 'resource':
        return effectiveExt.isNotEmpty ? effectiveExt.toUpperCase() : 'Archivo';
      case 'folder':
        return 'Carpeta';
      case 'assign':
      case 'assignment':
        return 'Tarea';
      case 'quiz':
        return 'Cuestionario';
      case 'url':
        return 'Enlace';
      case 'forum':
        return 'Foro';
      case 'page':
        return 'Página';
      case 'book':
        return 'Libro';
      case 'lesson':
        return 'Lección';
      case 'feedback':
      case 'questionnaire':
        return 'Encuesta';
      case 'choice':
        return 'Consulta';
      case 'workshop':
        return 'Taller';
      case 'data':
        return 'Base de datos';
      case 'glossary':
        return 'Glosario';
      case 'wiki':
        return 'Wiki';
      case 'scorm':
        return 'SCORM';
      case 'lti':
        return 'Herramienta Externa';
      case 'h5pactivity':
        return 'Actividad H5P';
      case 'zoom':
      case 'bigbluebuttonbn':
        return 'Videollamada';
      default:
        return type.isNotEmpty ? type : 'Recurso';
    }
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'courseId': courseId,
        'title': title,
        'section': section,
        'type': type,
        'url': url,
        'fileName': fileName,
        'fileExt': fileExt,
        'downloadable': downloadable,
        'sizeBytes': sizeBytes,
        'isDownloaded': isDownloaded,
        'isNew': isNew,
        'localPath': localPath,
        'dueTimestamp': dueTimestamp,
        'dueText': dueText,
      };

  factory MoodleItem.fromJson(Map<String, dynamic> json) {
    final rawId = json['id']?.toString().trim();
    return MoodleItem(
      id: (rawId != null && rawId.isNotEmpty) ? rawId : null,
      courseId: _parseIntNullable(json['courseId']) ?? 0,
      title: json['title']?.toString() ?? json['name']?.toString() ?? '',
      section:
          json['section']?.toString() ?? json['sectionName']?.toString() ?? 'General',
      type: json['type']?.toString() ?? 'resource',
      url: json['url']?.toString() ?? '',
      fileName: json['fileName']?.toString() ?? '',
      fileExt: json['fileExt']?.toString() ?? '',
      downloadable: (json['downloadable'] ?? json['isDownloadable']) == true,
      sizeBytes: _parseIntNullable(json['sizeBytes']) ??
          _parseIntNullable(json['fileSize']),
      isDownloaded: json['isDownloaded'] == true,
      isNew: json['isNew'] == true,
      localPath: json['localPath']?.toString(),
      dueTimestamp: _parseIntNullable(json['dueTimestamp']),
      dueText: json['dueText']?.toString(),
    );
  }

  static String formatFileSize(int? bytes) {
    if (bytes == null || bytes <= 0) return '';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  static String sanitizeFileName(String raw) => MoodleCourse.sanitizeFileName(raw);
}

class MoodleCourse {
  final int id;
  final String fullname;
  final String cleanName;
  final String shortname;
  final String url;
  String obsidianFolder;
  String targetSubfolder;
  bool organizeBySection;
  List<MoodleItem> items;
  bool isLoadingContents;
  String? scanError;
  bool isHidden;
  int? linkedRamoId;

  MoodleCourse({
    required this.id,
    String? fullname,
    String? fullName,
    String? cleanName,
    String? shortname,
    String? shortName,
    this.url = '',
    this.obsidianFolder = '',
    this.targetSubfolder = 'Aula',
    this.organizeBySection = true,
    List<MoodleItem>? items,
    this.isLoadingContents = false,
    this.scanError,
    this.isHidden = false,
    this.linkedRamoId,
  })  : fullname = fullname ?? fullName ?? cleanName ?? 'Curso $id',
        shortname = shortname ?? shortName ?? '',
        cleanName = (cleanName != null && cleanName.trim().isNotEmpty)
            ? cleanName.trim()
            : cleanCourseName(
                fullname ?? fullName ?? shortname ?? shortName ?? 'Curso $id'),
        items = items ?? [];

  // Aliases for NotasApp compatibility
  String get fullName => fullname;
  String get shortName => shortname;

  int get deadlinesCount => items.where((i) => i.hasDeadline && !i.isPastDeadline).length;
  int get urgentDeadlinesCount => items.where((i) => i.isUrgentDeadline).length;
  int get downloadableCount => items.where((i) => i.downloadable).length;
  int get newFilesCount =>
      items.where((i) => i.downloadable && !i.isDownloaded && i.isNew).length;
  int get pendingCount =>
      items.where((i) => i.downloadable && !i.isDownloaded).length;
  int get downloadedCount =>
      items.where((i) => i.downloadable && i.isDownloaded).length;

  Map<String, dynamic> toJson() => {
        'id': id,
        'fullname': fullname,
        'cleanName': cleanName,
        'shortname': shortname,
        'url': url,
        'obsidianFolder': obsidianFolder,
        'targetSubfolder': targetSubfolder,
        'organizeBySection': organizeBySection,
        'isHidden': isHidden,
        'linkedRamoId': linkedRamoId,
        'items': items.map((e) => e.toJson()).toList(),
      };

  factory MoodleCourse.fromJson(Map<String, dynamic> json) => MoodleCourse(
        id: _parseIntNullable(json['id']) ?? 0,
        fullname:
            json['fullname']?.toString() ?? json['fullName']?.toString() ?? '',
        cleanName: json['cleanName']?.toString() ?? '',
        shortname:
            json['shortname']?.toString() ?? json['shortName']?.toString() ?? '',
        url: json['url']?.toString() ?? '',
        obsidianFolder: json['obsidianFolder']?.toString() ?? '',
        targetSubfolder: json['targetSubfolder']?.toString() ?? 'Aula',
        organizeBySection: json['organizeBySection'] != false,
        isHidden: json['isHidden'] == true,
        linkedRamoId: _parseIntNullable(json['linkedRamoId']),
        items: (json['items'] as List? ?? [])
            .whereType<Map>()
            .map((e) => MoodleItem.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
      );

  static String cleanCourseName(String raw) {
    var name = raw.trim();
    name = name.replaceAll(RegExp(r'^\[[^\]]+\]\s*'), '');
    name = name.replaceAll(RegExp(r'\s*\[[^\]]+\]$'), '');
    name = name.replaceAll(RegExp(r'\s*\([S12\-/0-9]+\)\s*$'), '');
    name = name.replaceAll(
      RegExp(r'\s*-\s*Paralelo.*$', caseSensitive: false),
      '',
    );
    return name.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static final RegExp _reservedWindowsNames = RegExp(
    r'^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])$',
    caseSensitive: false,
  );

  static String sanitizeFileName(String raw) {
    var clean = raw
        .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    clean = clean.replaceAll(RegExp(r'^\.+|[.\s]+$'), '');
    if (clean.isEmpty || clean == '.' || clean == '..') return 'archivo';

    String truncateStem(String stem, int maxLen) {
      if (stem.length <= maxLen) {
        return stem.replaceAll(RegExp(r'^\.+|[.\s]+$'), '');
      }
      return stem.substring(0, maxLen).replaceAll(RegExp(r'^\.+|[.\s]+$'), '');
    }

    final extMatch = RegExp(r'^(.+?)\.([a-zA-Z0-9]{1,8})$').firstMatch(clean);
    if (clean.length > 120) {
      if (extMatch != null) {
        final ext = extMatch.group(2)!;
        final suffix = '.$ext';
        final maxStem = 120 - suffix.length;
        final truncatedStem = truncateStem(extMatch.group(1)!, maxStem);
        clean = truncatedStem.isEmpty ? 'archivo$suffix' : '$truncatedStem$suffix';
      } else {
        clean = truncateStem(clean, 120);
      }
    }

    clean = clean.replaceAll(RegExp(r'^\.+|[.\s]+$'), '');
    if (clean.isEmpty || clean == '.' || clean == '..') return 'archivo';

    final dotIdx = clean.indexOf('.');
    final baseName = (dotIdx >= 0 ? clean.substring(0, dotIdx) : clean).trim();
    if (_reservedWindowsNames.hasMatch(baseName)) {
      clean = '_$clean';
      if (clean.length > 120) {
        if (extMatch != null) {
          final ext = extMatch.group(2)!;
          final suffix = '.$ext';
          final maxStem = 120 - suffix.length;
          final dotAfterPrefix = clean.lastIndexOf('.');
          final stem = dotAfterPrefix > 0 ? clean.substring(0, dotAfterPrefix) : clean;
          final truncatedStem = truncateStem(stem, maxStem);
          clean = truncatedStem.isEmpty ? '_archivo$suffix' : '$truncatedStem$suffix';
        } else {
          clean = truncateStem(clean, 120);
        }
      }
    }
    return clean.isEmpty ? 'archivo' : clean;
  }

  static String normalizeForMatch(String raw) {
    var s = raw.toLowerCase().trim();
    const map = {
      'á': 'a',
      'é': 'e',
      'í': 'i',
      'ó': 'o',
      'ú': 'u',
      'ü': 'u',
      'ñ': 'n',
      'à': 'a',
      'è': 'e',
      'ì': 'i',
      'ò': 'o',
      'ù': 'u',
    };
    map.forEach((k, v) => s = s.replaceAll(k, v));
    s = s.replaceAll(RegExp(r'[^a-z0-9\s]'), ' ');
    return s.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static String normalizeAcademicText(String raw) => normalizeForMatch(raw);

  static List<String> _extractCourseCodes(String raw) {
    final matches = RegExp(
      r'\b([A-Za-z]{2,5})\s*-?\s*(\d{3})\b',
    ).allMatches(raw);
    return matches
        .map((m) => '${m.group(1)!.toUpperCase()}${m.group(2)!}')
        .toList();
  }

  static Ramo? findMatchingRamo(MoodleCourse course, List<Ramo> ramos) {
    if (ramos.isEmpty) return null;

    if (course.linkedRamoId != null) {
      for (final r in ramos) {
        if (r.id == course.linkedRamoId) return r;
      }
    }

    final courseCodes = {
      ..._extractCourseCodes(course.shortname),
      ..._extractCourseCodes(course.fullname),
    };
    if (courseCodes.isNotEmpty) {
      for (final r in ramos) {
        final ramoCodes = _extractCourseCodes(r.nombre);
        if (ramoCodes.any(courseCodes.contains)) {
          return r;
        }
      }
    }

    final courseNorm = normalizeAcademicText(course.cleanName);
    if (courseNorm.isEmpty) return null;

    Ramo? best;
    double bestScore = 0;

    final courseTokens = courseNorm
        .split(' ')
        .where((t) => t.length >= 3 && !_stopWords.contains(t))
        .toSet();

    for (final r in ramos) {
      final ramoNorm = normalizeAcademicText(r.nombre);
      if (ramoNorm.isEmpty) continue;
      if (ramoNorm == courseNorm ||
          courseNorm.contains(ramoNorm) ||
          ramoNorm.contains(courseNorm)) {
        return r;
      }
      final ramoTokens = ramoNorm
          .split(' ')
          .where((t) => t.length >= 3 && !_stopWords.contains(t))
          .toSet();
      if (courseTokens.isEmpty || ramoTokens.isEmpty) continue;
      final intersection = courseTokens.intersection(ramoTokens).length;
      final union = courseTokens.union(ramoTokens).length;
      final jaccard = union > 0 ? intersection / union : 0.0;
      if (jaccard > bestScore) {
        bestScore = jaccard;
        best = r;
      }
    }

    return bestScore >= 0.45 ? best : null;
  }

  static Evaluacion? findMatchingEvaluacion(
    MoodleItem item,
    List<Evaluacion> evaluaciones,
  ) {
    if (evaluaciones.isEmpty) return null;
    final rawNorm = _stripMoodleActivityNoise(normalizeAcademicText(item.title));
    if (rawNorm.isEmpty) return null;

    final itemTokens = rawNorm
        .split(' ')
        .where((t) => t.isNotEmpty && !_stopWords.contains(t))
        .toSet();

    Evaluacion? best;
    double bestScore = 0;

    for (final ev in evaluaciones) {
      final evNorm = _stripMoodleActivityNoise(normalizeAcademicText(ev.nombre));
      if (evNorm.isEmpty) continue;

      if (evNorm == rawNorm ||
          rawNorm.contains(evNorm) ||
          evNorm.contains(rawNorm)) {
        return ev;
      }

      final evTokens = evNorm
          .split(' ')
          .where((t) => t.isNotEmpty && !_stopWords.contains(t))
          .toSet();
      if (evTokens.isEmpty || itemTokens.isEmpty) continue;

      final common = evTokens.intersection(itemTokens).length;
      final coverage = common / evTokens.length;
      if (coverage >= 0.75 && coverage > bestScore) {
        bestScore = coverage;
        best = ev;
      }
    }

    return best;
  }

  static String _stripMoodleActivityNoise(String normalized) {
    return normalized
        .replaceAll(
          RegExp(
            r'\b(tarea|cuestionario|quiz|entrega|subida|foro|modulo|actividad)\b$',
          ),
          '',
        )
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static const Set<String> _stopWords = {
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
    'sin',
    'sobre',
    'a',
    'al',
  };
}
