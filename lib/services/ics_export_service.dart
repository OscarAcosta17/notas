import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/evaluacion.dart';
import '../models/clase_horario.dart';

class IcsExportService {
  static String _formatDateIcs(DateTime date) {
    // Format to YYYYMMDDTHHMMSSZ (UTC)
    final utc = date.toUtc();
    return "${utc.year.toString().padLeft(4, '0')}"
        "${utc.month.toString().padLeft(2, '0')}"
        "${utc.day.toString().padLeft(2, '0')}T"
        "${utc.hour.toString().padLeft(2, '0')}"
        "${utc.minute.toString().padLeft(2, '0')}"
        "${utc.second.toString().padLeft(2, '0')}Z";
  }

  static Future<String> generateAgendaIcsPath(List<Evaluacion> evaluaciones, Map<int, String> ramosNombres) async {
    final buffer = StringBuffer();
    buffer.writeln('BEGIN:VCALENDAR');
    buffer.writeln('VERSION:2.0');
    buffer.writeln('PRODID:-//NotasApp//Agenda//ES');
    
    for (var ev in evaluaciones) {
      if (ev.fecha == null) continue;
      
      final dtStart = _formatDateIcs(ev.fecha!);
      // Evaluaciones don't have a specific duration natively, let's assume 1.5 hours
      final dtEnd = _formatDateIcs(ev.fecha!.add(const Duration(minutes: 90)));
      final nombreRamo = ramosNombres[ev.idCategoria] ?? 'Evaluación';

      buffer.writeln('BEGIN:VEVENT');
      buffer.writeln('UID:${ev.id}_${DateTime.now().millisecondsSinceEpoch}@notasapp');
      buffer.writeln('DTSTAMP:${_formatDateIcs(DateTime.now())}');
      buffer.writeln('DTSTART:$dtStart');
      buffer.writeln('DTEND:$dtEnd');
      buffer.writeln('SUMMARY:${ev.nombre} - $nombreRamo');
      buffer.writeln('END:VEVENT');
    }
    
    buffer.writeln('END:VCALENDAR');

    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/Agenda.ics');
    await file.writeAsString(buffer.toString());
    return file.path;
  }

  static Future<void> exportAgenda(List<Evaluacion> evaluaciones, Map<int, String> ramosNombres) async {
    final path = await generateAgendaIcsPath(evaluaciones, ramosNombres);
    await Share.shareXFiles([XFile(path)], text: 'Mi Agenda de Evaluaciones');
  }

  static Future<String> generateHorarioIcsPath(List<ClaseHorario> clases, DateTime startDate, DateTime endDate) async {
    final buffer = StringBuffer();
    buffer.writeln('BEGIN:VCALENDAR');
    buffer.writeln('VERSION:2.0');
    buffer.writeln('PRODID:-//NotasApp//Horario//ES');

    final blockTimes = {
      1: [8, 15],
      3: [9, 40],
      5: [11, 5],
      7: [12, 30],
      9: [14, 40],
      11: [16, 5],
      13: [17, 30],
      15: [18, 55],
    };

    final mapDays = {
      1: 'MO',
      2: 'TU',
      3: 'WE',
      4: 'TH',
      5: 'FR',
      6: 'SA',
      7: 'SU',
    };

    final untilStr = _formatDateIcs(DateTime(endDate.year, endDate.month, endDate.day, 23, 59, 59));

    for (var clase in clases) {
      final time = blockTimes[clase.bloque] ?? [8, 0];
      
      // Find the first occurrence of this weekday on or after startDate
      DateTime firstOccurrence = DateTime(startDate.year, startDate.month, startDate.day, time[0], time[1]);
      while (firstOccurrence.weekday != clase.diaSemana) {
        firstOccurrence = firstOccurrence.add(const Duration(days: 1));
      }

      if (firstOccurrence.isAfter(endDate)) {
        continue; // This class never happens within the selected range
      }

      final dtStart = _formatDateIcs(firstOccurrence);
      final dtEnd = _formatDateIcs(firstOccurrence.add(const Duration(minutes: 70)));
      
      buffer.writeln('BEGIN:VEVENT');
      buffer.writeln('UID:${clase.id}_${DateTime.now().millisecondsSinceEpoch}@notasapp');
      buffer.writeln('DTSTAMP:${_formatDateIcs(DateTime.now())}');
      buffer.writeln('DTSTART:$dtStart');
      buffer.writeln('DTEND:$dtEnd');
      buffer.writeln('RRULE:FREQ=WEEKLY;UNTIL=$untilStr;BYDAY=${mapDays[clase.diaSemana]}');
      buffer.writeln('SUMMARY:${clase.subjectName}');
      buffer.writeln('LOCATION:Sala ${clase.sala}, Paralelo ${clase.paralelo}');
      buffer.writeln('END:VEVENT');
    }
    
    buffer.writeln('END:VCALENDAR');

    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/Horario.ics');
    await file.writeAsString(buffer.toString());
    
    return file.path;
  }

  static Future<void> exportHorario(List<ClaseHorario> clases, DateTime startDate, DateTime endDate) async {
    final path = await generateHorarioIcsPath(clases, startDate, endDate);
    await Share.shareXFiles([XFile(path)], text: 'Mi Horario Semanal');
  }
}
