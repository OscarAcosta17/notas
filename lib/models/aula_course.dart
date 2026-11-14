import 'evaluacion.dart';
import 'ramo.dart';

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
        id = id ??
            '${courseId}_${(title ?? name ?? '').hashCode}_${url.hashCode}';

  // Aliases for NotasApp compatibility
  String get name => title;
  String get sectionName => section;
  bool get isDownloadable => downloadable;
  int? get fileSize => sizeBytes;
  DateTime? get dueDate => dueTimestamp != null && dueTimestamp! > 0
      ? DateTime.fromMillisecondsSinceEpoch(dueTimestamp! * 1000)
      : null;

  String get effectiveExt {
    if (fileExt.isNotEmpty) return fileExt.toLowerCase();
    final candidate = fileName.isNotEmpty ? fileName : url.split('?').first;
    final dot = candidate.lastIndexOf('.');
    if (dot != -1 && dot < candidate.length - 1) {
      final ext = candidate.substring(dot + 1).toLowerCase();
      if (ext.length <= 5 && RegExp(r'^[a-z0-9]+$').hasMatch(ext)) {
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

  factory MoodleItem.fromJson(Map<String, dynamic> json) => MoodleItem(
        id: json['id']?.toString() ?? '',
        courseId: json['courseId'] is int
            ? json['courseId'] as int
            : int.tryParse(json['courseId']?.toString() ?? '0') ?? 0,
        title: json['title']?.toString() ?? json['name']?.toString() ?? '',
        section:
            json['section']?.toString() ?? json['sectionName']?.toString() ?? 'General',
        type: json['type']?.toString() ?? 'resource',
        url: json['url']?.toString() ?? '',
        fileName: json['fileName']?.toString() ?? '',
        fileExt: json['fileExt']?.toString() ?? '',
        downloadable: (json['downloadable'] ?? json['isDownloadable']) == true,
        sizeBytes: json['sizeBytes'] as int? ?? json['fileSize'] as int?,
        isDownloaded: json['isDownloaded'] == true,
        isNew: json['isNew'] == true,
        localPath: json['localPath']?.toString(),
        dueTimestamp: json['dueTimestamp'] as int?,
        dueText: json['dueText']?.toString(),
      );

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
        id: json['id'] is int
            ? json['id'] as int
            : int.tryParse(json['id']?.toString() ?? '0') ?? 0,
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
        linkedRamoId: json['linkedRamoId'] as int?,
        items: (json['items'] as List? ?? [])
            .map((e) => MoodleItem.fromJson(Map<String, dynamic>.from(e as Map)))
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

  static String sanitizeFileName(String raw) {
    var clean = raw
        .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    clean = clean.replaceAll(RegExp(r'^\.+|[.\s]+$'), '');
    if (clean.isEmpty) return 'archivo';
    if (clean.length > 140) {
      clean = clean.substring(0, 140).trim();
    }
    return clean;
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
