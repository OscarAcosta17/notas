import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import '../models/clase_horario.dart';
import '../services/database_helper.dart';
import '../services/ics_export_service.dart';
import '../services/notification_service.dart';
import '../services/schedule_image_exporter.dart';
import '../services/widget_service.dart';
import '../theme/app_theme.dart';
import '../theme/expressive_widgets.dart';

class HorarioView extends StatefulWidget {
  final int semesterId;
  const HorarioView({super.key, required this.semesterId});

  @override
  State<HorarioView> createState() => _HorarioViewState();
}

class _HorarioViewState extends State<HorarioView> {
  bool _isLoading = true;
  List<ClaseHorario> _clases = [];
  bool _notificationsEnabled = true;
  String _semesterName = '';
  List<Map<String, dynamic>> _subjects = [];

  final List<String> _dias = ['Lunes', 'Martes', 'Miércoles', 'Jueves', 'Viernes'];

  @override
  void initState() {
    super.initState();
    _loadHorario();
    NotificationService.requestPermissions();
  }

  @override
  void didUpdateWidget(HorarioView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.semesterId != widget.semesterId) {
      _loadHorario();
    }
  }

  Future<void> _loadHorario() async {
    final db = DatabaseHelper.instance;
    final maps = await db.queryHorariosBySemester(widget.semesterId);

    final semesters = await db.queryAllSemesters();
    final currentSem = semesters.firstWhere((s) => s['id'] == widget.semesterId, orElse: () => {'name': ''});

    final subjects = await db.querySubjectsBySemester(widget.semesterId);

    if (mounted) {
      setState(() {
        _clases = maps.map((e) => ClaseHorario.fromMap(e)).toList();
        _semesterName = currentSem['name'] as String;
        _subjects = subjects;
        _isLoading = false;
      });
    }
  }

  String _formatBlock(int bloque) {
    switch (bloque) {
      case 1:
        return '08:15 - 09:25';
      case 3:
        return '09:40 - 10:50';
      case 5:
        return '11:05 - 12:15';
      case 7:
        return '12:30 - 13:40';
      case 9:
        return '14:40 - 15:50';
      case 11:
        return '16:05 - 17:15';
      case 13:
        return '17:30 - 18:40';
      case 15:
        return '18:55 - 20:05';
      default:
        return 'Desconocido';
    }
  }

  Future<void> _saveClase(String subjectName, int diaSemana, int bloque, String sala, String paralelo, [int? existingId]) async {
    final nueva = ClaseHorario(
      id: existingId,
      semesterId: widget.semesterId,
      subjectName: subjectName,
      diaSemana: diaSemana,
      bloque: bloque,
      sala: sala,
      paralelo: paralelo,
    );
    if (existingId == null) {
      final id = await DatabaseHelper.instance.insertHorario(nueva.toMap());
      nueva.id = id;
    } else {
      await DatabaseHelper.instance.updateHorario(nueva.toMap());
      await NotificationService.cancelClassReminder(existingId);
    }

    if (_notificationsEnabled) {
      await NotificationService.scheduleClassReminder(nueva);
    }
    WidgetService.updateHorarioWidget();
    _loadHorario();
  }

  Future<void> _deleteClase(ClaseHorario clase) async {
    await DatabaseHelper.instance.deleteHorario(clase.id!);
    await NotificationService.cancelClassReminder(clase.id!);
    WidgetService.updateHorarioWidget();
    _loadHorario();
  }

  void _showAddEditDialog(int diaSemana, [ClaseHorario? existingClase]) {
    if (_subjects.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Crea al menos un ramo en este semestre primero.')),
      );
      return;
    }

    String selectedSubjectName = existingClase?.subjectName ?? _subjects.first['name'] as String;
    if (!_subjects.any((s) => s['name'] == selectedSubjectName)) {
      selectedSubjectName = _subjects.first['name'] as String;
    }

    final salaCtrl = TextEditingController(text: existingClase?.sala ?? '');
    final paraleloCtrl = TextEditingController(text: existingClase?.paralelo ?? '');
    int selectedBloque = existingClase?.bloque ?? 1;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateSB) {
            return AlertDialog(
              title: Text(existingClase == null ? 'Añadir clase al ${_dias[diaSemana - 1]}' : 'Editar clase'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue: selectedSubjectName,
                      decoration: const InputDecoration(labelText: 'Ramo'),
                      items: _subjects.map((s) {
                        final name = s['name'] as String;
                        return DropdownMenuItem<String>(
                          value: name,
                          child: Text(name),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) setStateSB(() => selectedSubjectName = val);
                      },
                    ),
                    const SizedBox(height: 14),
                    DropdownButtonFormField<int>(
                      initialValue: selectedBloque,
                      decoration: const InputDecoration(labelText: 'Bloque'),
                      items: [1, 3, 5, 7, 9, 11, 13, 15].map((b) {
                        return DropdownMenuItem(
                          value: b,
                          child: Text('Bloque $b-${b + 1} (${_formatBlock(b)})'),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) setStateSB(() => selectedBloque = val);
                      },
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: salaCtrl,
                      decoration: const InputDecoration(labelText: 'Sala'),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: paraleloCtrl,
                      decoration: const InputDecoration(labelText: 'Paralelo'),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: () {
                    _saveClase(
                      selectedSubjectName,
                      diaSemana,
                      selectedBloque,
                      salaCtrl.text.trim(),
                      paraleloCtrl.text.trim(),
                      existingClase?.id,
                    );
                    Navigator.pop(context);
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

  void _toggleNotifications() async {
    if (!_notificationsEnabled) {
      final granted = await NotificationService.requestPermissions();
      if (!granted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Permiso denegado. Habilítalo en ajustes.')),
          );
        }
        return;
      }
    }

    setState(() {
      _notificationsEnabled = !_notificationsEnabled;
    });

    for (var c in _clases) {
      if (_notificationsEnabled) {
        await NotificationService.scheduleClassReminder(c);
      } else {
        await NotificationService.cancelClassReminder(c.id!);
      }
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_notificationsEnabled ? 'Notificaciones activadas' : 'Notificaciones desactivadas')),
      );
    }
  }

  Future<void> _exportHorario() async {
    if (_clases.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay clases para exportar.')),
      );
      return;
    }

    showExpressiveModalSheet(
      context: context,
      builder: (sheetContext) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'Opciones de Exportación',
                  style: Theme.of(sheetContext).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(height: 6),
              ExpressiveGroupedSection(
                margin: EdgeInsets.zero,
                children: [
                  ListTile(
                    leading: const TonalIconBadge(icon: Icons.image_rounded, color: Colors.blue),
                    title: const Text('Compartir como Imagen', style: TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: const Text('Genera una cuadrícula visual de tu horario'),
                    onTap: () async {
                      Navigator.pop(sheetContext);
                      await ScheduleImageExporter.exportHorarioImage(_clases, _semesterName);
                    },
                  ),
                  ListTile(
                    leading: const TonalIconBadge(icon: Icons.share_rounded, color: Colors.green),
                    title: const Text('Enviar archivo .ics', style: TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: const Text('Comparte el archivo para importar en otro dispositivo'),
                    onTap: () async {
                      Navigator.pop(sheetContext);
                      await _exportIcs(false);
                    },
                  ),
                  ListTile(
                    leading: const TonalIconBadge(icon: Icons.calendar_month_rounded, color: Colors.orange),
                    title: const Text('Exportar a otra app (Calendario)', style: TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: const Text('Abre el archivo con Google Calendar o Outlook'),
                    onTap: () async {
                      Navigator.pop(sheetContext);
                      await _exportIcs(true);
                    },
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _exportIcs(bool openWithExternalApp) async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      initialDateRange: DateTimeRange(
        start: DateTime.now(),
        end: DateTime.now().add(const Duration(days: 120)),
      ),
      helpText: 'Selecciona la duración del semestre',
      saveText: 'Continuar',
    );

    if (picked != null) {
      if (openWithExternalApp) {
        final filePath = await IcsExportService.generateHorarioIcsPath(_clases, picked.start, picked.end);
        await OpenFilex.open(filePath);
      } else {
        await IcsExportService.exportHorario(_clases, picked.start, picked.end);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());

    final scheme = Theme.of(context).colorScheme;
    final tokens = context.visualTokens;
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;

    return DefaultTabController(
      length: 5,
      child: Scaffold(
        backgroundColor: scheme.surface,
        appBar: AppBar(
          backgroundColor: scheme.surface,
          title: Text(
            'Horario · $_semesterName',
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 19),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.file_upload_outlined),
              tooltip: 'Exportar Horario',
              onPressed: _exportHorario,
            ),
            IconButton(
              icon: Icon(_notificationsEnabled ? Icons.notifications_active_rounded : Icons.notifications_off_outlined),
              color: _notificationsEnabled ? scheme.primary : scheme.onSurfaceVariant,
              tooltip: _notificationsEnabled ? 'Silenciar horario' : 'Activar alertas',
              onPressed: _toggleNotifications,
            ),
          ],
          bottom: const PreferredSize(
            preferredSize: Size.fromHeight(56),
            child: ExpressivePillTabBar(
              labels: ['Lun', 'Mar', 'Mié', 'Jue', 'Vie'],
              padding: EdgeInsets.fromLTRB(16, 4, 16, 10),
            ),
          ),
        ),
        body: TabBarView(
          children: List.generate(5, (index) {
            final dia = index + 1; // 1 to 5
            final clasesDia = _clases.where((c) => c.diaSemana == dia).toList()
              ..sort((a, b) => a.bloque.compareTo(b.bloque));

            return Stack(
              children: [
                if (clasesDia.isEmpty)
                  Center(
                    child: Text(
                      'No hay clases este día.',
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                  )
                else
                  ListView.builder(
                    padding: EdgeInsets.fromLTRB(16, 12, 16, 148 + bottomInset),
                    itemCount: clasesDia.length,
                    itemBuilder: (context, i) {
                      final c = clasesDia[i];
                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
                          border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.45)),
                        ),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
                          onLongPress: () => _showAddEditDialog(dia, c),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(16, 14, 10, 14),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: scheme.primaryContainer,
                                          borderRadius: BorderRadius.circular(AppTheme.radiusFull),
                                        ),
                                        child: Text(
                                          'Bloque ${c.bloque}-${c.bloque + 1} · ${_formatBlock(c.bloque)}',
                                          style: TextStyle(
                                            color: scheme.onPrimaryContainer,
                                            fontWeight: FontWeight.w700,
                                            fontSize: 12,
                                            fontFeatures: const [FontFeature.tabularFigures()],
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        c.subjectName,
                                        style: TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 17,
                                          color: scheme.onSurface,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Sala: ${c.sala.isEmpty ? '-' : c.sala}  ·  Paralelo: ${c.paralelo.isEmpty ? '-' : c.paralelo}',
                                        style: TextStyle(
                                          fontSize: 13.5,
                                          color: scheme.onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  icon: Icon(Icons.delete_outline_rounded, color: tokens.failingColor),
                                  onPressed: () => _deleteClase(c),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                Positioned(
                  bottom: 92 + bottomInset,
                  right: 20,
                  child: FloatingActionButton(
                    heroTag: 'fab_add_clase_$dia',
                    onPressed: () => _showAddEditDialog(dia),
                    child: const Icon(Icons.add_rounded),
                  ),
                ),
              ],
            );
          }),
        ),
      ),
    );
  }
}
