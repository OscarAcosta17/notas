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
      List<String> items = [];
      if (upcoming.isEmpty) {
        // empty list handled by factory
      } else {
        for (int i = 0; i < upcoming.length && i < 10; i++) { // show top 10
          final eval = upcoming[i]['eval'] as Evaluacion;
          final subject = upcoming[i]['subjectName'] as String;
          final dayStr = "${eval.fecha!.day}/${eval.fecha!.month} ${eval.fecha!.hour.toString().padLeft(2,'0')}:${eval.fecha!.minute.toString().padLeft(2,'0')}";
          items.add("${eval.nombre} ($subject)###$dayStr");
        }
      }
      
      await HomeWidget.saveWidgetData<String>('evaluations_list', items.join("|||"));
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
      
      final weekDays = ["Lunes", "Martes", "Miércoles", "Jueves", "Viernes"];
      List<String> items = [];

      for (int d = 1; d <= 5; d++) {
        final clasesDia = clases.where((c) => c.diaSemana == d).toList();
        clasesDia.sort((a, b) => a.bloque.compareTo(b.bloque));

        if (clasesDia.isEmpty) {
          items.add("${weekDays[d-1]}###Ningún evento");
        } else {
          String content = clasesDia.map((c) => "Bloque ${c.bloque} - ${c.subjectName} (Sala: ${c.sala})").join("\n");
          items.add("${weekDays[d-1]}###$content");
        }
      }

      await HomeWidget.saveWidgetData<String>('horario_list', items.join("|||"));
      await HomeWidget.updateWidget(name: 'HorarioWidgetProvider');

    } catch (e) {
      print("Error updating horario widget: $e");
    }
  }
}
