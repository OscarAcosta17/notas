import 'package:home_widget/home_widget.dart';
import '../models/evaluacion.dart';
import '../services/database_helper.dart';

class HomeWidgetService {
  static Future<void> updateWidget() async {
    List<Evaluacion> proximas = [];
    
    // Load data from DB directly
    final db = DatabaseHelper.instance;
    final subjects = await db.database.then((db) => db.query('subjects'));
    
    for (var sub in subjects) {
      final subjectId = sub['id'] as int;
      final cats = await db.queryCategoriesBySubject(subjectId);
      for (var cat in cats) {
        final catId = cat['id'] as int;
        final evs = await db.queryEvaluationsByCategory(catId);
        for (var ev in evs) {
          final eval = Evaluacion.fromMap(ev);
          if (eval.fecha != null && eval.fecha!.isAfter(DateTime.now())) {
            proximas.add(eval);
          }
        }
      }
    }
    
    // Removed the other loop since we replaced it
    
    proximas.sort((a, b) => a.fecha!.compareTo(b.fecha!));
    
    String widgetText = "";
    if (proximas.isEmpty) {
      widgetText = "No hay evaluaciones próximas.";
    } else {
      for (int i = 0; i < proximas.length && i < 3; i++) {
        final ev = proximas[i];
        widgetText += "• ${ev.nombre} (${ev.fecha!.day}/${ev.fecha!.month})\n";
      }
    }

    await HomeWidget.saveWidgetData<String>('evaluations', widgetText.trim());
    await HomeWidget.updateWidget(name: 'AppWidgetProvider');
  }
}
