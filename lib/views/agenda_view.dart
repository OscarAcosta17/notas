import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import '../models/evaluacion.dart';
import '../services/database_helper.dart';
import '../services/ics_export_service.dart';
import '../services/notification_service.dart';
import '../services/widget_service.dart';
import '../theme/app_theme.dart';
import '../theme/expressive_widgets.dart';
import 'settings_view.dart';

class AgendaView extends StatefulWidget {
  final int refreshTick;
  const AgendaView({super.key, this.refreshTick = 0});

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

  @override
  void didUpdateWidget(AgendaView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshTick != widget.refreshTick) {
      _loadAgenda();
    }
  }

  Future<void> _loadAgenda() async {
    final db = DatabaseHelper.instance;
    final List<Map<String, dynamic>> upcoming = [];

    try {
      final rows = await db.queryAllScheduledEvaluationsWithSubject();
      for (final row in rows) {
        final eval = Evaluacion.fromMap(row);
        if (eval.fecha != null) {
          upcoming.add({
            'eval': eval,
            'subjectName': (row['subject_name'] ?? '').toString(),
          });
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

    return '$dayStr ${dt.day} $monthStr · $hour:$minute';
  }

  String _getMonthName(int month) {
    final months = [
      'Enero',
      'Febrero',
      'Marzo',
      'Abril',
      'Mayo',
      'Junio',
      'Julio',
      'Agosto',
      'Septiembre',
      'Octubre',
      'Noviembre',
      'Diciembre',
    ];
    return months[month - 1];
  }

  void _showActionDialog(Evaluacion eval, String subjectName) {
    final tokens = context.visualTokens;

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
                  eval.nombre,
                  style: Theme.of(sheetContext).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(height: 4),
              ExpressiveGroupedSection(
                margin: EdgeInsets.zero,
                children: [
                  ListTile(
                    leading: const TonalIconBadge(icon: Icons.edit_rounded),
                    title: const Text('Editar fecha o nombre', style: TextStyle(fontWeight: FontWeight.w600)),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      _showEditDialog(eval, subjectName);
                    },
                  ),
                  ListTile(
                    leading: TonalIconBadge(icon: Icons.event_busy_rounded, color: tokens.failingColor),
                    title: Text(
                      'Eliminar de agenda',
                      style: TextStyle(color: tokens.failingColor, fontWeight: FontWeight.w600),
                    ),
                    onTap: () async {
                      Navigator.pop(sheetContext);
                      final updatedEval = eval.copyWith(clearFecha: true);
                      await DatabaseHelper.instance.updateEvaluation(updatedEval.toMap());
                      if (updatedEval.id != null) {
                        await NotificationService.cancelEvaluationReminder(updatedEval.id!);
                      }
                      WidgetService.updateAgendaWidget();
                      if (!mounted) return;
                      _loadAgenda();
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

  void _showEditDialog(Evaluacion eval, String subjectName) {
    showDialog(
      context: context,
      builder: (_) => _AgendaEditDialog(
        eval: eval,
        subjectName: subjectName,
        onSaved: () {
          if (mounted) _loadAgenda();
        },
      ),
    );
  }

  Future<void> _exportAgenda() async {
    if (_evaluations.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay evaluaciones para exportar.')),
      );
      return;
    }

    final subjects = _evaluations.map((e) => e['subjectName'] as String).toSet().toList();
    final selectedSubjects = Set<String>.from(subjects);

    showExpressiveModalSheet(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setStateSB) {
            return Padding(
              padding: EdgeInsets.fromLTRB(16, 4, 16, 16 + MediaQuery.of(context).viewInsets.bottom),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      'Exportar Agenda',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                  Text(
                    'Selecciona los ramos a incluir:',
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 8),
                  ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.34),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: subjects.length,
                      itemBuilder: (context, index) {
                        final subject = subjects[index];
                        return CheckboxListTile(
                          title: Text(subject, style: const TextStyle(fontWeight: FontWeight.w600)),
                          value: selectedSubjects.contains(subject),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          onChanged: (bool? value) {
                            setStateSB(() {
                              if (value == true) {
                                selectedSubjects.add(subject);
                              } else {
                                selectedSubjects.remove(subject);
                              }
                            });
                          },
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 8),
                  ExpressiveGroupedSection(
                    margin: EdgeInsets.zero,
                    children: [
                      ListTile(
                        leading: const TonalIconBadge(icon: Icons.share_rounded, color: Colors.green),
                        title: const Text('Enviar archivo .ics', style: TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: const Text('Comparte el archivo para importar en otro dispositivo'),
                        onTap: () async {
                          if (selectedSubjects.isEmpty) return;
                          Navigator.pop(sheetContext);
                          await _executeAgendaExport(false, selectedSubjects);
                        },
                      ),
                      ListTile(
                        leading: const TonalIconBadge(icon: Icons.calendar_month_rounded, color: Colors.orange),
                        title: const Text('Exportar a otra app (Calendario)', style: TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: const Text('Abre el archivo con Google Calendar o Outlook'),
                        onTap: () async {
                          if (selectedSubjects.isEmpty) return;
                          Navigator.pop(sheetContext);
                          await _executeAgendaExport(true, selectedSubjects);
                        },
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _executeAgendaExport(bool openWithExternalApp, Set<String> selectedSubjects) async {
    final filtered = _evaluations.where((e) => selectedSubjects.contains(e['subjectName'])).toList();
    final evs = filtered.map((e) => e['eval'] as Evaluacion).toList();
    final namesMap = <int, String>{};
    for (var e in filtered) {
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
    final scheme = Theme.of(context).colorScheme;
    final tokens = context.visualTokens;
    final topInset = MediaQuery.paddingOf(context).top + kToolbarHeight;
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;

    Widget content;
    if (_isLoading) {
      content = const Center(child: CircularProgressIndicator());
    } else if (_evaluations.isEmpty) {
      content = Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(AppTheme.radiusExtraLarge),
              border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.4)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const TonalIconBadge(icon: Icons.event_available_rounded, size: 58),
                const SizedBox(height: 14),
                Text(
                  'Sin evaluaciones agendadas',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  'Asigna fechas en la pestaña Fechas de cualquier ramo.',
                  style: TextStyle(color: scheme.onSurfaceVariant),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      );
    } else {
      // Group by Month/Year
      final Map<String, List<Map<String, dynamic>>> grouped = {};
      for (var data in _evaluations) {
        final eval = data['eval'] as Evaluacion;
        final key = '${_getMonthName(eval.fecha!.month)} ${eval.fecha!.year}';
        grouped.putIfAbsent(key, () => []).add(data);
      }

      final keys = grouped.keys.toList();

      content = ListView.builder(
        padding: EdgeInsets.fromLTRB(16, topInset + 12, 16, 112 + bottomInset),
        itemCount: keys.length,
        itemBuilder: (context, sectionIndex) {
          final monthKey = keys[sectionIndex];
          final items = grouped[monthKey]!;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 6, bottom: 10, left: 4),
                child: Row(
                  children: [
                    Text(
                      monthKey,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: tokens.accentColor,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(AppTheme.radiusFull),
                      ),
                      child: Text(
                        '${items.length}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              ...items.map((data) {
                final eval = data['eval'] as Evaluacion;
                final subjectName = data['subjectName'] as String;
                final isPast = eval.fecha!.isBefore(DateTime.now());
                final accent = isPast ? tokens.failingColor : tokens.accentColor;

                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  decoration: BoxDecoration(
                    color: isPast
                        ? Color.alphaBlend(tokens.failingColor.withValues(alpha: 0.05), scheme.surfaceContainerLow)
                        : scheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(tokens.cardRadius),
                    border: Border.all(
                      color: isPast
                          ? tokens.failingColor.withValues(alpha: 0.35)
                          : scheme.outlineVariant.withValues(alpha: 0.45),
                    ),
                  ),
                  child: ListTile(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(tokens.cardRadius)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    leading: TonalIconBadge(icon: Icons.event_rounded, color: accent),
                    title: Text(
                      eval.nombre,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                        color: scheme.onSurface,
                        decoration: isPast ? TextDecoration.lineThrough : null,
                      ),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 3),
                        Text(
                          subjectName,
                          style: TextStyle(
                            color: scheme.onSurfaceVariant,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                          decoration: BoxDecoration(
                            color: accent.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(AppTheme.radiusFull),
                          ),
                          child: Text(
                            _formatDateTime(eval.fecha!),
                            style: TextStyle(
                              fontSize: 12,
                              color: accent,
                              fontWeight: FontWeight.w700,
                              fontFeatures: const [FontFeature.tabularFigures()],
                            ),
                          ),
                        ),
                      ],
                    ),
                    onLongPress: () {
                      AppHaptics.selection(context);
                      _showActionDialog(eval, subjectName);
                    },
                  ),
                );
              }),
              const SizedBox(height: 12),
            ],
          );
        },
      );
    }

    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: scheme.surface,
      appBar: FrostedAppBar(
        title: const Text('Agenda de Evaluaciones'),
        actions: [
          IconButton(
            icon: const Icon(Icons.file_upload_outlined),
            tooltip: 'Exportar Agenda',
            onPressed: _exportAgenda,
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Configuración',
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

class _AgendaEditDialog extends StatefulWidget {
  final Evaluacion eval;
  final String subjectName;
  final VoidCallback onSaved;

  const _AgendaEditDialog({
    required this.eval,
    required this.subjectName,
    required this.onSaved,
  });

  @override
  State<_AgendaEditDialog> createState() => _AgendaEditDialogState();
}

class _AgendaEditDialogState extends State<_AgendaEditDialog> {
  late final TextEditingController _nameCtrl;
  DateTime? _selectedDate;
  TimeOfDay? _selectedTime;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.eval.nombre);
    _selectedDate = widget.eval.fecha;
    _selectedTime = widget.eval.fecha != null
        ? TimeOfDay.fromDateTime(widget.eval.fecha!)
        : null;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (!mounted || d == null) return;
    setState(() {
      _selectedDate = DateTime(
        d.year,
        d.month,
        d.day,
        _selectedTime?.hour ?? 0,
        _selectedTime?.minute ?? 0,
      );
    });
  }

  Future<void> _pickTime() async {
    final t = await showTimePicker(
      context: context,
      initialTime: _selectedTime ?? TimeOfDay.now(),
    );
    if (!mounted || t == null) return;
    setState(() {
      _selectedTime = t;
      if (_selectedDate != null) {
        _selectedDate = DateTime(
          _selectedDate!.year,
          _selectedDate!.month,
          _selectedDate!.day,
          t.hour,
          t.minute,
        );
      }
    });
  }

  Future<void> _save() async {
    final trimmedName = _nameCtrl.text.trim();
    if (trimmedName.isEmpty || _isSaving) return;

    setState(() => _isSaving = true);
    try {
      final updatedEval = widget.eval.copyWith(
        nombre: trimmedName,
        fecha: _selectedDate,
        clearFecha: _selectedDate == null,
      );
      await DatabaseHelper.instance.updateEvaluation(updatedEval.toMap());
      if (updatedEval.id != null) {
        await NotificationService.cancelEvaluationReminder(updatedEval.id!);
      }
      if (updatedEval.fecha != null) {
        await NotificationService.scheduleEvaluationReminder(
          updatedEval,
          widget.subjectName,
        );
      }

      WidgetService.updateAgendaWidget();
      widget.onSaved();
      if (!mounted) return;
      Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Editar Evaluación'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _nameCtrl,
            decoration: const InputDecoration(labelText: 'Nombre'),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.calendar_today_rounded, size: 18),
                  label: Text(
                    _selectedDate != null
                        ? '${_selectedDate!.day}/${_selectedDate!.month}/${_selectedDate!.year}'
                        : 'Fecha',
                  ),
                  onPressed: _isSaving ? null : _pickDate,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.access_time_rounded, size: 18),
                  label: Text(
                    _selectedTime != null ? _selectedTime!.format(context) : 'Hora',
                  ),
                  onPressed: _isSaving ? null : _pickTime,
                ),
              ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _isSaving ? null : _save,
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}
