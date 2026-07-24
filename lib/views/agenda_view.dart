import 'package:flutter/material.dart';
import '../models/evaluacion.dart';
import '../services/database_helper.dart';
import '../services/notification_service.dart';
import '../services/widget_service.dart';
import '../services/ics_export_service.dart';
import 'package:open_filex/open_filex.dart';
import 'settings_view.dart';
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
    NotificationService.requestPermissions();
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

  String _getMonthName(int month) {
    final months = ['Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio', 'Julio', 'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre'];
    return months[month - 1];
  }

  void _showActionDialog(Evaluacion eval, String subjectName) {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.edit),
                title: const Text('Editar fecha o nombre'),
                onTap: () {
                  Navigator.pop(context);
                  _showEditDialog(eval, subjectName);
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete, color: Colors.red),
                title: const Text('Eliminar de agenda', style: TextStyle(color: Colors.red)),
                onTap: () async {
                  Navigator.pop(context);
                  eval.fecha = null; // Removing date removes it from agenda, keeping the evaluation itself
                  await DatabaseHelper.instance.updateEvaluation(eval.toMap());
                  await NotificationService.cancelEvaluationReminder(eval.id!);
                  WidgetService.updateAgendaWidget();
                  _loadAgenda();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _showEditDialog(Evaluacion eval, String subjectName) {
    final nameCtrl = TextEditingController(text: eval.nombre);
    DateTime? selectedDate = eval.fecha;
    TimeOfDay? selectedTime = eval.fecha != null ? TimeOfDay.fromDateTime(eval.fecha!) : null;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateSB) {
            return AlertDialog(
              title: const Text('Editar Evaluación'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(labelText: 'Nombre'),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: TextButton.icon(
                          icon: const Icon(Icons.calendar_today),
                          label: Text(selectedDate != null ? '${selectedDate!.day}/${selectedDate!.month}/${selectedDate!.year}' : 'Fecha'),
                          onPressed: () async {
                            final d = await showDatePicker(
                              context: context,
                              initialDate: selectedDate ?? DateTime.now(),
                              firstDate: DateTime(2000),
                              lastDate: DateTime(2100),
                            );
                            if (d != null) {
                              setStateSB(() {
                                selectedDate = DateTime(d.year, d.month, d.day, selectedTime?.hour ?? 0, selectedTime?.minute ?? 0);
                              });
                            }
                          },
                        ),
                      ),
                      Expanded(
                        child: TextButton.icon(
                          icon: const Icon(Icons.access_time),
                          label: Text(selectedTime != null ? selectedTime!.format(context) : 'Hora'),
                          onPressed: () async {
                            final t = await showTimePicker(
                              context: context,
                              initialTime: selectedTime ?? TimeOfDay.now(),
                            );
                            if (t != null) {
                              setStateSB(() {
                                selectedTime = t;
                                if (selectedDate != null) {
                                  selectedDate = DateTime(selectedDate!.year, selectedDate!.month, selectedDate!.day, t.hour, t.minute);
                                }
                              });
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
                ElevatedButton(
                  onPressed: () async {
                    if (nameCtrl.text.isNotEmpty) {
                      eval.nombre = nameCtrl.text;
                      eval.fecha = selectedDate;
                      await DatabaseHelper.instance.updateEvaluation(eval.toMap());
                      
                      await NotificationService.cancelEvaluationReminder(eval.id!);
                      if (eval.fecha != null) {
                        await NotificationService.scheduleEvaluationReminder(eval, subjectName);
                      }
                      
                      WidgetService.updateAgendaWidget();
                      _loadAgenda();
                      if (context.mounted) Navigator.pop(context);
                    }
                  },
                  child: const Text('Guardar'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _exportAgenda() async {
    if (_evaluations.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay evaluaciones para exportar.')),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text('Opciones de Exportación', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ),
              ListTile(
                leading: const Icon(Icons.share, color: Colors.green),
                title: const Text('Enviar archivo .ics'),
                subtitle: const Text('Comparte el archivo para importar en otro dispositivo'),
                onTap: () async {
                  Navigator.pop(context);
                  await _executeAgendaExport(false);
                },
              ),
              ListTile(
                leading: const Icon(Icons.calendar_month, color: Colors.orange),
                title: const Text('Exportar a otra app (Calendario)'),
                subtitle: const Text('Abre el archivo con Google Calendar o Outlook'),
                onTap: () async {
                  Navigator.pop(context);
                  await _executeAgendaExport(true);
                },
              ),
              const SizedBox(height: 10),
            ],
          ),
        );
      }
    );
  }

  Future<void> _executeAgendaExport(bool openWithExternalApp) async {
    final evs = _evaluations.map((e) => e['eval'] as Evaluacion).toList();
    final namesMap = <int, String>{};
    for (var e in _evaluations) {
      final eval = e['eval'] as Evaluacion;
      namesMap[eval.idCategoria] = e['subjectName'] as String;
    }

    if (openWithExternalApp) {
      final filePath = await IcsExportService.generateAgendaIcsPath(evs, namesMap);
      await OpenFilex.open(filePath);
    } else {
      await IcsExportService.exportAgenda(evs, namesMap);
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget content;
    if (_isLoading) {
      content = const Center(child: CircularProgressIndicator());
    } else if (_evaluations.isEmpty) {
      content = const Center(
        child: Text(
          'No hay evaluaciones con fechas programadas.',
          style: TextStyle(color: Colors.grey, fontSize: 16),
        ),
      );
    } else {
      // Group by Month/Year
      Map<String, List<Map<String, dynamic>>> grouped = {};
      for (var data in _evaluations) {
        final eval = data['eval'] as Evaluacion;
        final key = '${_getMonthName(eval.fecha!.month)} ${eval.fecha!.year}';
        if (!grouped.containsKey(key)) {
          grouped[key] = [];
        }
        grouped[key]!.add(data);
      }

      final keys = grouped.keys.toList();

      content = ListView.builder(
      padding: const EdgeInsets.all(16).copyWith(bottom: 100),
      itemCount: keys.length,
      itemBuilder: (context, sectionIndex) {
        final monthKey = keys[sectionIndex];
        final items = grouped[monthKey]!;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 12, left: 4),
              child: Text(
                monthKey,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
            ...items.map((data) {
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
                onLongPress: () => _showActionDialog(eval, subjectName),
                ),
              );
            }),
            const SizedBox(height: 16),
          ],
        );
      },
    );
    } // End of else

    return Scaffold(
      appBar: AppBar(
        title: Text('Agenda de Evaluaciones', style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.bold)),
        backgroundColor: Theme.of(context).colorScheme.surface,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.file_upload_outlined),
            tooltip: 'Exportar Agenda',
            onPressed: _exportAgenda,
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const SettingsView()),
              );
            },
          ),
        ],
      ),
      body: content,
    );
  }
}
