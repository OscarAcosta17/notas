import '../models/evaluacion.dart';
import '../models/ramo.dart';

/// Represents a downloadable resource, link, assignment, or activity inside Aula USM.
class MoodleItem {
  final String name;
  final String cleanName;
  final String type; // file, resource, url, folder, assignment, quiz, forum, page, other
  final String? url;
  final String? fileName;
  final String? mimeType;
  final int? fileSize;
  final DateTime? dueDate;
  final bool completed;
  final String? description;
  final String sectionName;
  final int sectionNumber;
  final List<MoodleItem> subFiles;
  final String? courseName;
  final String? courseShortName;

  String status; // pending, downloading, downloaded, skipped, error
  double downloadProgress;
  String? localPath;

  MoodleItem({
    required this.name,
    String? cleanName,
    required this.type,
    this.url,
    this.fileName,
    this.mimeType,
    this.fileSize,
    this.dueDate,
    this.completed = false,
    this.description,
    this.sectionName = 'General',
    this.sectionNumber = 0,
    this.subFiles = const [],
    this.courseName,
    this.courseShortName,
    this.status = 'pending',
    this.downloadProgress = 0.0,
    this.localPath,
  }) : cleanName = cleanName ?? cleanDisplayName(name);

  String get key => '$sectionNumber::${url ?? ''}::${fileName ?? name}';

  bool get isDownloadable =>
      ((type == 'file' || type == 'resource' || (type == 'folder' && subFiles.isNotEmpty)) &&
          ((url != null && url!.isNotEmpty) || subFiles.isNotEmpty));

  bool get isDownloaded => status == 'downloaded' || (localPath != null && localPath!.isNotEmpty);

  bool get isDownloading => status == 'downloading';

  bool get hasDeadline => (type == 'assignment' || type == 'quiz') && dueDate != null;

  bool get isPendingSubmission =>
      hasDeadline && !completed && dueDate!.isAfter(DateTime.now());

  bool get isOverdue =>
      hasDeadline && !completed && !dueDate!.isAfter(DateTime.now());

  String get normalizedExtension {
    final candidate = (fileName ?? url ?? name).split('?').first.split('#').first;
    final dot = candidate.lastIndexOf('.');
    if (dot < 0 || dot == candidate.length - 1) return '';
    return candidate.substring(dot + 1).toLowerCase().trim();
  }

  String get formattedSize {
    final bytes = fileSize;
    if (bytes == null || bytes <= 0) return '';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  Map<String, dynamic> toIndexJson() => {
        'name': name,
        'cleanName': cleanName,
        'type': type,
        'url': url,
        'fileName': fileName,
        'fileSize': fileSize,
        'dueDate': dueDate?.toIso8601String(),
        'completed': completed,
        'sectionName': sectionName,
        'sectionNumber': sectionNumber,
        'localPath': localPath,
        'status': status,
      };

  factory MoodleItem.fromIndexJson(Map<String, dynamic> json) {
    return MoodleItem(
      name: (json['name'] ?? '').toString(),
      cleanName: json['cleanName']?.toString(),
      type: (json['type'] ?? 'file').toString(),
      url: json['url']?.toString(),
      fileName: json['fileName']?.toString(),
      fileSize: (json['fileSize'] as num?)?.toInt(),
      dueDate: json['dueDate'] != null ? DateTime.tryParse(json['dueDate'].toString()) : null,
      completed: json['completed'] == true,
      sectionName: (json['sectionName'] ?? 'General').toString(),
      sectionNumber: (json['sectionNumber'] as num?)?.toInt() ?? 0,
      localPath: json['localPath']?.toString(),
      status: (json['status'] ?? 'pending').toString(),
    );
  }

  static String cleanDisplayName(String raw) {
    var text = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
    text = text.replaceFirst(
      RegExp(r'\s+(Archivo|Carpeta|URL|Tarea|Cuestionario|Foro|Página)$', caseSensitive: false),
      '',
    );
    return text.trim().isEmpty ? raw.trim() : text.trim();
  }

  static String sanitizeFileName(String raw) {
    var sanitized = raw
        .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    while (sanitized.endsWith('.') || sanitized.endsWith(' ')) {
      sanitized = sanitized.substring(0, sanitized.length - 1);
    }
    return sanitized.isEmpty ? 'archivo' : sanitized;
  }
}

/// Represents an Aula USM Moodle course and provides matching synergy helpers with NotasApp [Ramo].
class MoodleCourse {
  final int id;
  final String fullName;
  final String shortName;
  final String? summary;
  final List<MoodleItem> items;
  final bool isLoaded;
  bool isHidden;
  final bool? isCurrentSemester;
  final DateTime? startDate;
  final DateTime? endDate;

  MoodleCourse({
    required this.id,
    required this.fullName,
    required this.shortName,
    this.summary,
    this.items = const [],
    this.isLoaded = false,
    this.isHidden = false,
    this.isCurrentSemester,
    this.startDate,
    this.endDate,
  });

  String get cleanName {
    var s = fullName.replaceAll(RegExp(r'\s+'), ' ').trim();
    // Strip trailing semester suffixes like "- 2026-2", "(2026-1)", "[S2-2026]"
    s = s.replaceAll(RegExp(r'\s*[-–]\s*20\d{2}[-/]\d+.*$'), '');
    s = s.replaceAll(RegExp(r'\s*\((?:20\d{2}|[12]S\s*20\d{2}|S[12]\s*20\d{2})[^)]*\)\s*$'), '');
    // Strip duplicated leading short code like "[INF-253] " or "INF253 - "
    s = s.replaceFirst(RegExp(r'^\[?[A-Z]{2,5}[-\s]?\d{3}[A-Z]?\]?\s*[-–:]\s*'), '');
    return s.trim().isEmpty ? fullName.trim() : s.trim();
  }

  String? get courseCode {
    final sources = [shortName, fullName];
    final codeRegex = RegExp(r'\b([A-Z]{2,5}[-\s]?\d{3}[A-Z]?)\b', caseSensitive: false);
    for (final src in sources) {
      final m = codeRegex.firstMatch(src);
      if (m != null) {
        return m.group(1)!.toUpperCase().replaceAll(RegExp(r'\s+'), '');
      }
    }
    return null;
  }

  List<MoodleItem> get downloadableItems => items.where((i) => i.isDownloadable).toList();
  int get downloadableCount => downloadableItems.length;
  int get downloadedCount => downloadableItems.where((i) => i.isDownloaded).length;

  List<MoodleItem> get upcomingDeadlines =>
      items.where((i) => i.hasDeadline).toList()
        ..sort((a, b) => a.dueDate!.compareTo(b.dueDate!));

  int get deadlineCount => items.where((i) => i.hasDeadline).length;
  int get pendingDeadlineCount => items.where((i) => i.isPendingSubmission).length;

  MoodleCourse copyWith({
    String? fullName,
    String? shortName,
    String? summary,
    List<MoodleItem>? items,
    bool? isLoaded,
    bool? isHidden,
    bool? isCurrentSemester,
    DateTime? startDate,
    DateTime? endDate,
  }) {
    return MoodleCourse(
      id: id,
      fullName: fullName ?? this.fullName,
      shortName: shortName ?? this.shortName,
      summary: summary ?? this.summary,
      items: items ?? this.items,
      isLoaded: isLoaded ?? this.isLoaded,
      isHidden: isHidden ?? this.isHidden,
      isCurrentSemester: isCurrentSemester ?? this.isCurrentSemester,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
    );
  }

  static String normalizeAcademicText(String input) {
    const accents = {
      'á': 'a',
      'à': 'a',
      'ä': 'a',
      'â': 'a',
      'é': 'e',
      'è': 'e',
      'ë': 'e',
      'ê': 'e',
      'í': 'i',
      'ì': 'i',
      'ï': 'i',
      'î': 'i',
      'ó': 'o',
      'ò': 'o',
      'ö': 'o',
      'ô': 'o',
      'ú': 'u',
      'ù': 'u',
      'ü': 'u',
      'û': 'u',
      'ñ': 'n',
    };
    final sb = StringBuffer();
    for (final rune in input.toLowerCase().runes) {
      final ch = String.fromCharCode(rune);
      sb.write(accents[ch] ?? ch);
    }
    var clean = sb.toString();
    clean = clean.replaceAll(RegExp(r'[^a-z0-9\s]'), ' ');
    clean = clean.replaceAll(RegExp(r'\b(20\d{2}|s[12]|[12]s|paralelo|par|grupo|aula)\b'), ' ');
    return clean.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static String? normalizeCourseCode(String input) {
    final m = RegExp(r'([A-Za-z]{2,5})[-\s]?(\d{3}[A-Za-z]?)').firstMatch(input);
    if (m == null) return null;
    return '${m.group(1)!.toLowerCase()}${m.group(2)!.toLowerCase()}';
  }

  /// Finds the best matching [Ramo] from NotasApp's active semester for an Aula course.
  static Ramo? findMatchingRamo(MoodleCourse course, List<Ramo> ramos) {
    if (ramos.isEmpty) return null;

    final targetNames = {
      normalizeAcademicText(course.cleanName),
      normalizeAcademicText(course.fullName),
      normalizeAcademicText(course.shortName),
    }..removeWhere((s) => s.isEmpty);

    final targetCode = course.courseCode != null ? normalizeCourseCode(course.courseCode!) : null;

    // 1. Exact normalized name or exact course code match
    for (final ramo in ramos) {
      final rNorm = normalizeAcademicText(ramo.nombre);
      if (rNorm.isNotEmpty && targetNames.contains(rNorm)) {
        return ramo;
      }
      if (targetCode != null) {
        final rCode = normalizeCourseCode(ramo.nombre);
        if (rCode != null && rCode == targetCode) {
          return ramo;
        }
      }
    }

    // 2. Containment or token overlap
    Ramo? best;
    double bestScore = 0.0;
    final courseTokens = normalizeAcademicText(course.cleanName)
        .split(' ')
        .where((t) => t.length >= 3)
        .toSet();

    for (final ramo in ramos) {
      final rNorm = normalizeAcademicText(ramo.nombre);
      if (rNorm.isEmpty) continue;

      for (final tName in targetNames) {
        if (tName.length >= 4 && rNorm.length >= 4 && (tName.contains(rNorm) || rNorm.contains(tName))) {
          return ramo;
        }
      }

      if (courseTokens.isNotEmpty) {
        final rTokens = rNorm.split(' ').where((t) => t.length >= 3).toSet();
        if (rTokens.isEmpty) continue;
        final common = courseTokens.intersection(rTokens).length;
        final union = courseTokens.union(rTokens).length;
        final jaccard = union > 0 ? common / union : 0.0;
        final minCoverage = common / (courseTokens.length < rTokens.length ? courseTokens.length : rTokens.length);
        final score = jaccard > minCoverage ? jaccard : minCoverage;
        if (common >= 1 && score >= 0.65 && score > bestScore) {
          bestScore = score;
          best = ramo;
        }
      }
    }
    return best;
  }

  /// Checks whether an Aula assignment/quiz was already imported into a [Ramo].
  static Evaluacion? findMatchingEvaluacion(MoodleItem item, List<Evaluacion> existing) {
    final itemNorm = normalizeAcademicText(item.cleanName);
    if (itemNorm.isEmpty) return null;

    for (final ev in existing) {
      final evNorm = normalizeAcademicText(
        ev.nombre.replaceFirst(RegExp(r'^Aula:\s*', caseSensitive: false), ''),
      );
      if (evNorm == itemNorm ||
          (itemNorm.length >= 5 && evNorm.contains(itemNorm)) ||
          (evNorm.length >= 5 && itemNorm.contains(evNorm))) {
        if (item.dueDate == null || ev.fecha == null) return ev;
        if (ev.fecha!.difference(item.dueDate!).abs().inHours <= 24) {
          return ev;
        }
      }
    }
    return null;
  }
}
