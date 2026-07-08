import 'package:home_widget/home_widget.dart';
import '../models/evaluacion.dart';
import '../models/clase_horario.dart';
import '../services/database_helper.dart';

class WidgetService {
  static Future<void> updateAgendaWidget() async {
    final db = DatabaseHelper.instance;
    List<Map<String, dynamic>> upcoming = [];
    
    try {
      final subjects = await db.database.then((db) => db.query('subjects'));
      for (var sub in subjects) {
        final subjectId = sub['id'] as int;
        final subjectName = sub['name'] as String;
        
        final cats = await db.queryCategoriesBySubject(subjectId);
        for (var cat in cats) {
          final catId = cat['id'] as int;
          
          final evs = await db.queryEvaluationsByCategory(catId);
          for (var ev in evs) {
            final eval = Evaluacion.fromMap(ev);
            if (eval.fecha != null && eval.fecha!.isAfter(DateTime.now().subtract(const Duration(days: 1)))) {
              upcoming.add({
                'eval': eval,
                'subjectName': subjectName,
              });
            }
          }
        }
      }
      
      upcoming.sort((a, b) {
        final evalA = a['eval'] as Evaluacion;
        final evalB = b['eval'] as Evaluacion;
        return evalA.fecha!.compareTo(evalB.fecha!);
      });
      
      String text = "";
      if (upcoming.isEmpty) {
        text = "No hay evaluaciones próximas.";
      } else {
        for (int i = 0; i < upcoming.length && i < 3; i++) { // show top 3
          final eval = upcoming[i]['eval'] as Evaluacion;
          final subject = upcoming[i]['subjectName'] as String;
          text += "• ${eval.nombre} ($subject)\n  ${eval.fecha!.day}/${eval.fecha!.month} ${eval.fecha!.hour.toString().padLeft(2,'0')}:${eval.fecha!.minute.toString().padLeft(2,'0')}\n";
        }
      }
      
      await HomeWidget.saveWidgetData<String>('evaluations', text.trim());
      await HomeWidget.updateWidget(name: 'AppWidgetProvider');

    } catch (e) {
      print("Error updating agenda widget: $e");
    }
  }

  static Future<void> updateHorarioWidget() async {
    final db = DatabaseHelper.instance;
    try {
      // Find current semester
      final semesters = await db.queryAllSemesters();
      if (semesters.isEmpty) return;
      final currentSem = semesters.last; // Assuming last is current, or active
      final semId = currentSem['id'] as int;
      
      final maps = await db.queryHorariosBySemester(semId);
      final clases = maps.map((e) => ClaseHorario.fromMap(e)).toList();
      
      // Get today's classes
      final today = DateTime.now().weekday; // 1 = Monday, 5 = Friday
      final clasesDia = clases.where((c) => c.diaSemana == today).toList();
      clasesDia.sort((a, b) => a.bloque.compareTo(b.bloque));
      
      String text = "";
      if (clasesDia.isEmpty) {
        text = "No hay clases programadas para hoy.";
      } else {
        for (int i = 0; i < clasesDia.length; i++) {
          final c = clasesDia[i];
          text += "• ${c.subjectName}\n  Bloque ${c.bloque} | Sala: ${c.sala}\n";
        }
      }

      await HomeWidget.saveWidgetData<String>('horario_text', text.trim());
      await HomeWidget.updateWidget(name: 'HorarioWidgetProvider');

    } catch (e) {
      print("Error updating horario widget: $e");
    }
  }
}
