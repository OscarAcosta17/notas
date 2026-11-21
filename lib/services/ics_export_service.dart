import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';

import '../models/clase_horario.dart';
import '../models/evaluacion.dart';
import '../utils/schedule_blocks.dart';
import 'app_cache_service.dart';

class IcsExportService {
  static String _formatLocalIcs(DateTime date) {
    return '${date.year.toString().padLeft(4, '0')}'
        '${date.month.toString().padLeft(2, '0')}'
        '${date.day.toString().padLeft(2, '0')}T'
        '${date.hour.toString().padLeft(2, '0')}'
        '${date.minute.toString().padLeft(2, '0')}'
        '${date.second.toString().padLeft(2, '0')}';
  }

  static String _formatUtcStamp(DateTime date) {
    final utc = date.toUtc();
    return '${utc.year.toString().padLeft(4, '0')}'
        '${utc.month.toString().padLeft(2, '0')}'
        '${utc.day.toString().padLeft(2, '0')}T'
        '${utc.hour.toString().padLeft(2, '0')}'
        '${utc.minute.toString().padLeft(2, '0')}'
        '${utc.second.toString().padLeft(2, '0')}Z';
  }

  /// Escapes text fields per RFC 5545 Section 3.3.11.
  static String escapeIcsText(String raw) {
    return raw
        .replaceAll(r'\', r'\\')
        .replaceAll('\r\n', r'\n')
        .replaceAll('\r', r'\n')
        .replaceAll('\n', r'\n')
        .replaceAll(';', r'\;')
        .replaceAll(',', r'\,');
  }

  static String buildAgendaIcsContent(
    List<Evaluacion> evaluaciones,
    Map<int, String> ramosNombres, {
    DateTime? stampNow,
  }) {
    final lines = <String>[
      'BEGIN:VCALENDAR',
      'VERSION:2.0',
      'PRODID:-//NotasApp//Agenda//ES',
    ];
    final dtStamp = _formatUtcStamp(stampNow ?? DateTime.now());

    for (final ev in evaluaciones) {
      final fecha = ev.fecha;
      if (fecha == null) continue;

      final dtStart = _formatLocalIcs(fecha);
      final dtEnd = _formatLocalIcs(fecha.add(const Duration(minutes: 90)));
      final nombreRamo = ramosNombres[ev.idCategoria] ?? 'Evaluación';
      final uidKey = ev.id?.toString() ??
          '${ev.idCategoria}_${fecha.millisecondsSinceEpoch}_${ev.nombre.codeUnits.fold<int>(0, (a, b) => (a * 31 + b) & 0x7FFFFFFF)}';

      lines.add('BEGIN:VEVENT');
      lines.add('UID:eval-$uidKey@notasapp');
      lines.add('DTSTAMP:$dtStamp');
      lines.add('DTSTART:$dtStart');
      lines.add('DTEND:$dtEnd');
      lines.add('SUMMARY:${escapeIcsText('${ev.nombre} - $nombreRamo')}');
      lines.add('END:VEVENT');
    }

    lines.add('END:VCALENDAR');
    return '${lines.join('\r\n')}\r\n';
  }

  static Future<String> generateAgendaIcsPath(
    List<Evaluacion> evaluaciones,
    Map<int, String> ramosNombres,
  ) async {
    final content = buildAgendaIcsContent(evaluaciones, ramosNombres);
    final dir = await AppCacheService.getCacheDirectory();
    final file = File(p.join(dir.path, 'Agenda.ics'));
    await file.writeAsString(content);
    return file.path;
  }

  static Future<void> exportAgenda(
    List<Evaluacion> evaluaciones,
    Map<int, String> ramosNombres,
  ) async {
    final path = await generateAgendaIcsPath(evaluaciones, ramosNombres);
    await Share.shareXFiles([XFile(path)], text: 'Mi Agenda de Evaluaciones');
  }

  static String buildHorarioIcsContent(
    List<ClaseHorario> clases,
    DateTime startDate,
    DateTime endDate, {
    DateTime? stampNow,
  }) {
    final lines = <String>[
      'BEGIN:VCALENDAR',
      'VERSION:2.0',
      'PRODID:-//NotasApp//Horario//ES',
    ];
    final dtStamp = _formatUtcStamp(stampNow ?? DateTime.now());

    const mapDays = {
      1: 'MO',
      2: 'TU',
      3: 'WE',
      4: 'TH',
      5: 'FR',
      6: 'SA',
      7: 'SU',
    };

    final endOfDay =
        DateTime(endDate.year, endDate.month, endDate.day, 23, 59, 59);
    final untilStr = _formatLocalIcs(endOfDay);

    for (final clase in clases) {
      if (!ScheduleBlocks.isValidWeekday(clase.diaSemana)) continue;
      final time = ScheduleBlocks.blockStartTimes[clase.bloque] ?? (8, 0);

      var firstOccurrence = DateTime(
        startDate.year,
        startDate.month,
        startDate.day,
        time.$1,
        time.$2,
      );
      for (var i = 0; i < 7; i++) {
        if (firstOccurrence.weekday == clase.diaSemana) break;
        firstOccurrence = firstOccurrence.add(const Duration(days: 1));
      }
      if (firstOccurrence.weekday != clase.diaSemana ||
          firstOccurrence.isAfter(endOfDay)) {
        continue;
      }

      final dtStart = _formatLocalIcs(firstOccurrence);
      final dtEnd =
          _formatLocalIcs(firstOccurrence.add(const Duration(minutes: 70)));
      final uidKey = clase.id?.toString() ??
          '${clase.semesterId}_${clase.diaSemana}_${clase.bloque}_${clase.subjectName.codeUnits.fold<int>(0, (a, b) => (a * 31 + b) & 0x7FFFFFFF)}';

      lines.add('BEGIN:VEVENT');
      lines.add('UID:class-$uidKey@notasapp');
      lines.add('DTSTAMP:$dtStamp');
      lines.add('DTSTART:$dtStart');
      lines.add('DTEND:$dtEnd');
      lines.add(
        'RRULE:FREQ=WEEKLY;UNTIL=$untilStr;BYDAY=${mapDays[clase.diaSemana]}',
      );
      lines.add('SUMMARY:${escapeIcsText(clase.subjectName)}');
      lines.add(
        'LOCATION:${escapeIcsText('Sala ${clase.sala}, Paralelo ${clase.paralelo}')}',
      );
      lines.add('END:VEVENT');
    }

    lines.add('END:VCALENDAR');
    return '${lines.join('\r\n')}\r\n';
  }

  static Future<String> generateHorarioIcsPath(
    List<ClaseHorario> clases,
    DateTime startDate,
    DateTime endDate,
  ) async {
    final content = buildHorarioIcsContent(clases, startDate, endDate);
    final dir = await AppCacheService.getCacheDirectory();
    final file = File(p.join(dir.path, 'Horario.ics'));
    await file.writeAsString(content);
    return file.path;
  }

  static Future<void> exportHorario(
    List<ClaseHorario> clases,
    DateTime startDate,
    DateTime endDate,
  ) async {
    final path = await generateHorarioIcsPath(clases, startDate, endDate);
    await Share.shareXFiles([XFile(path)], text: 'Mi Horario Semanal');
  }
}
