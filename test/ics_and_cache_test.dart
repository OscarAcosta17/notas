import 'package:flutter_test/flutter_test.dart';
import 'package:notas/models/clase_horario.dart';
import 'package:notas/models/evaluacion.dart';
import 'package:notas/services/ics_export_service.dart';
import 'package:notas/utils/schedule_blocks.dart';

void main() {
  group('ScheduleBlocks canonical definitions', () {
    test('exposes USM valid blocks, time ranges, row indices, and weekday checks', () {
      expect(ScheduleBlocks.validBlocks, const [1, 3, 5, 7, 9, 11, 13, 15]);
      expect(ScheduleBlocks.formatBlockRange(1), '08:15 - 09:25');
      expect(ScheduleBlocks.formatBlockRange(15), '18:55 - 20:05');
      expect(ScheduleBlocks.formatBlockRange(2), 'Desconocido');

      expect(ScheduleBlocks.rowIndexForBlock(1), 0);
      expect(ScheduleBlocks.rowIndexForBlock(15), 7);
      expect(ScheduleBlocks.rowIndexForBlock(4), isNull);

      expect(ScheduleBlocks.isValidWeekday(1), isTrue);
      expect(ScheduleBlocks.isValidWeekday(7), isTrue);
      expect(ScheduleBlocks.isValidWeekday(0), isFalse);
      expect(ScheduleBlocks.isValidWeekday(8), isFalse);
    });
  });

  group('IcsExportService RFC 5545 formatting', () {
    test('escapes backslashes, semicolons, commas, and newlines', () {
      const raw = 'Certamen 1, Sala A; Pabellón B\\C\r\nSegunda línea\nTercera';
      final escaped = IcsExportService.escapeIcsText(raw);
      expect(
        escaped,
        r'Certamen 1\, Sala A\; Pabellón B\\C\nSegunda línea\nTercera',
      );
    });

    test('builds Agenda ICS with CRLF line endings, UTC DTSTAMP, and collision-safe UIDs', () {
      final stamp = DateTime.utc(2026, 3, 10, 12, 0, 0);
      final evalDate = DateTime(2026, 4, 15, 14, 30, 0);
      final evals = [
        Evaluacion(
          idCategoria: 5,
          nombre: 'Certamen 1, Parte A',
          fecha: evalDate,
        ),
        Evaluacion(
          idCategoria: 5,
          nombre: 'Certamen 1, Parte B',
          fecha: evalDate,
        ),
        Evaluacion(
          id: 99,
          idCategoria: 5,
          nombre: 'Sin Fecha',
        ),
      ];

      final ics = IcsExportService.buildAgendaIcsContent(
        evals,
        {5: 'Física; General'},
        stampNow: stamp,
      );

      expect(ics.contains('\r\n'), isTrue);
      expect(ics, contains('DTSTAMP:20260310T120000Z'));
      expect(ics, contains('DTSTART:20260415T143000'));
      expect(ics, contains('DTEND:20260415T160000'));
      expect(ics, contains(r'SUMMARY:Certamen 1\, Parte A - Física\; General'));
      expect(ics, isNot(contains('Sin Fecha')));

      final uidMatches = RegExp(r'UID:(eval-[^\r\n]+)').allMatches(ics).map((m) => m.group(1)).toSet();
      expect(uidMatches.length, 2);
    });

    test('builds Horario ICS aligning firstOccurrence to target weekday and skipping out-of-range classes', () {
      final stamp = DateTime.utc(2026, 3, 1, 9, 0, 0);
      // 2026-03-04 is a Wednesday (weekday = 3)
      final start = DateTime(2026, 3, 4);
      final end = DateTime(2026, 3, 20);

      final clases = [
        // Monday class (weekday = 1): first occurrence after Wed Mar 4 is Mon Mar 9
        ClaseHorario(
          id: 1,
          semesterId: 1,
          subjectName: 'Estructuras, Datos',
          diaSemana: 1,
          bloque: 3, // 09:40 - 10:50
          sala: 'B-201; Lab',
          paralelo: '200',
        ),
        // Invalid weekday -> skipped
        ClaseHorario(
          id: 2,
          semesterId: 1,
          subjectName: 'Invalida',
          diaSemana: 9,
          bloque: 1,
          sala: 'X',
          paralelo: '1',
        ),
      ];

      final ics = IcsExportService.buildHorarioIcsContent(
        clases,
        start,
        end,
        stampNow: stamp,
      );

      expect(ics, contains('UID:class-1@notasapp'));
      expect(ics, contains('DTSTART:20260309T094000'));
      expect(ics, contains('DTEND:20260309T105000'));
      expect(ics, contains('RRULE:FREQ=WEEKLY;UNTIL:20260320T235959;BYDAY=MO'.replaceFirst('UNTIL:', 'UNTIL=')));
      expect(ics, contains(r'SUMMARY:Estructuras\, Datos'));
      expect(ics, contains(r'LOCATION:Sala B-201\; Lab\, Paralelo 200'));
      expect(ics, isNot(contains('Invalida')));
    });
  });
}
