import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/clase_horario.dart';
import '../models/evaluacion.dart';
import '../services/database_helper.dart';

class WidgetService {
  static Future<void> updateAgendaWidget() async {
    if (!Platform.isAndroid) return;
    final db = DatabaseHelper.instance;
    try {
      final rows = await db.queryAllScheduledEvaluationsWithSubject();
      final threshold = DateTime.now().subtract(const Duration(days: 1));
      final upcoming = <({Evaluacion eval, String subjectName})>[];

      for (final row in rows) {
        final eval = Evaluacion.fromMap(row);
        final fecha = eval.fecha;
        if (fecha != null && fecha.isAfter(threshold)) {
          upcoming.add((
            eval: eval,
            subjectName: row['subject_name']?.toString() ?? '',
          ));
        }
      }

      upcoming.sort((a, b) => a.eval.fecha!.compareTo(b.eval.fecha!));

      final items = <Map<String, String>>[];
      for (var i = 0; i < upcoming.length && i < 10; i++) {
        final entry = upcoming[i];
        final d = entry.eval.fecha!;
        final dayStr =
            '${d.day}/${d.month} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
        items.add({
          'title': '${entry.eval.nombre} (${entry.subjectName})',
          'subtitle': dayStr,
        });
      }

      await HomeWidget.saveWidgetData<String>(
        'evaluations_list',
        jsonEncode(items),
      );
      await HomeWidget.updateWidget(name: 'AppWidgetProvider');
    } catch (e) {
      debugPrint('Error updating agenda widget: $e');
    }
  }

  static Future<void> updateHorarioWidget() async {
    if (!Platform.isAndroid) return;
    final db = DatabaseHelper.instance;
    try {
      final semesters = await db.queryAllSemesters();
      if (semesters.isEmpty) {
        await HomeWidget.saveWidgetData<String>(
          'horario_list',
          jsonEncode(const <Map<String, String>>[]),
        );
        await HomeWidget.updateWidget(name: 'HorarioWidgetProvider');
        return;
      }

      final prefs = await SharedPreferences.getInstance();
      final lastSemId = prefs.getInt('last_semester_id');
      final activeSem = lastSemId != null
          ? semesters.firstWhere(
              (s) => s['id'] == lastSemId,
              orElse: () => semesters.last,
            )
          : semesters.last;
      final semId = activeSem['id'] as int;

      final maps = await db.queryHorariosBySemester(semId);
      final clases = maps.map((e) => ClaseHorario.fromMap(e)).toList();

      const weekDays = [
        'Lunes',
        'Martes',
        'Miércoles',
        'Jueves',
        'Viernes',
        'Sábado',
        'Domingo',
      ];
      final items = <Map<String, String>>[];

      for (var d = 1; d <= 7; d++) {
        final clasesDia = clases.where((c) => c.diaSemana == d).toList()
          ..sort((a, b) => a.bloque.compareTo(b.bloque));
        if (d > 5 && clasesDia.isEmpty) continue;

        final content = clasesDia.isEmpty
            ? 'Ningún evento'
            : clasesDia
                .map((c) => 'Bloque ${c.bloque} - ${c.subjectName} (Sala: ${c.sala})')
                .join('\n');
        items.add({
          'day': weekDays[d - 1],
          'content': content,
        });
      }

      await HomeWidget.saveWidgetData<String>(
        'horario_list',
        jsonEncode(items),
      );
      await HomeWidget.updateWidget(name: 'HorarioWidgetProvider');
    } catch (e) {
      debugPrint('Error updating horario widget: $e');
    }
  }
}
