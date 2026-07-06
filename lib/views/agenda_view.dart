import 'package:flutter/material.dart';
import '../models/evaluacion.dart';
import '../services/database_helper.dart';

class AgendaView extends StatefulWidget {
  const AgendaView({super.key});

  @override
  State<AgendaView> createState() => _AgendaViewState();
}

class _AgendaViewState extends State<AgendaView> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _evaluations = [];

  @override
  void initState() {
    super.initState();
    _loadAgenda();
  }

  Future<void> _loadAgenda() async {
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
            if (eval.fecha != null) {
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
      
    } catch (e) {
      debugPrint("Error loading agenda: $e");
    }

    if (mounted) {
      setState(() {
        _evaluations = upcoming;
        _isLoading = false;
      });
    }
  }

  String _formatDateTime(DateTime dt) {
    final days = ['Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'];
    final months = ['Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun', 'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic'];
    
    final dayStr = days[dt.weekday - 1];
    final monthStr = months[dt.month - 1];
    final hour = dt.hour.toString().padLeft(2, '0');
    final minute = dt.minute.toString().padLeft(2, '0');
    
    return '$dayStr ${dt.day} $monthStr • $hour:$minute';
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_evaluations.isEmpty) {
      return const Center(
        child: Text(
          'No hay evaluaciones con fechas programadas.',
          style: TextStyle(color: Colors.grey, fontSize: 16),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16).copyWith(bottom: 100),
      itemCount: _evaluations.length,
      itemBuilder: (context, index) {
        final data = _evaluations[index];
        final eval = data['eval'] as Evaluacion;
        final subjectName = data['subjectName'] as String;
        
        final isPast = eval.fecha!.isBefore(DateTime.now());

        return Card(
          elevation: 0,
          color: Theme.of(context).colorScheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: isPast 
                  ? Colors.red.withValues(alpha: 0.3)
                  : Theme.of(context).colorScheme.primary.withValues(alpha: 0.2),
              width: 1,
            ),
          ),
          margin: const EdgeInsets.only(bottom: 12),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            leading: Icon(
              Icons.event,
              color: isPast ? Colors.red : Theme.of(context).colorScheme.primary,
            ),
            title: Text(
              eval.nombre,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: Theme.of(context).colorScheme.onSurface,
                decoration: isPast ? TextDecoration.lineThrough : null,
              ),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                Text(
                  subjectName,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _formatDateTime(eval.fecha!),
                  style: TextStyle(
                    color: isPast ? Colors.red : Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
