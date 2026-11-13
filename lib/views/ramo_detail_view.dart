import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/evaluacion.dart';
import '../models/ramo.dart';
import '../services/home_widget_service.dart';
import '../services/notification_service.dart';
import '../theme/app_theme.dart';
import '../theme/expressive_widgets.dart';
import '../viewmodels/categoria_provider.dart';

import 'add_categoria_dialog.dart';
import 'add_evaluacion_dialog.dart';
import 'edit_categoria_dialog.dart';
import 'edit_evaluacion_dialog.dart';
import 'grade_input_field.dart';

class RamoDetailView extends ConsumerStatefulWidget {
  final Ramo ramo;
  const RamoDetailView({super.key, required this.ramo});

  @override
  ConsumerState<RamoDetailView> createState() => _RamoDetailViewState();
}

class _RamoDetailViewState extends ConsumerState<RamoDetailView> {
  @override
  Widget build(BuildContext context) {
    final categorias = ref.watch(categoriaProvider(widget.ramo.id!));
    widget.ramo.categorias = categorias;
    final scheme = Theme.of(context).colorScheme;

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: scheme.surface,
        appBar: AppBar(
          backgroundColor: scheme.surface,
          title: Row(
            children: [
              if (widget.ramo.color != null) ...[
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: Color(widget.ramo.color!),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Text(
                  widget.ramo.nombre,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          bottom: const PreferredSize(
            preferredSize: Size.fromHeight(58),
            child: ExpressivePillTabBar(
              labels: ['Notas', 'Fechas'],
              icons: [Icons.calculate_rounded, Icons.calendar_month_rounded],
            ),
          ),
        ),
        body: TabBarView(
          children: [
            _buildNotasTab(context, categorias),
            _buildFechasTab(context, categorias),
          ],
        ),
        floatingActionButton: FloatingActionButton(
          tooltip: 'Añadir grupo de evaluación',
          child: const Icon(Icons.create_new_folder_rounded),
          onPressed: () {
            showDialog(
              context: context,
              builder: (context) => AddCategoriaDialog(ramoId: widget.ramo.id!),
            );
          },
        ),
      ),
    );
  }

  Widget _buildNotasTab(BuildContext context, List<dynamic> categorias) {
    final notaActual = widget.ramo.calcularNotaActual();
    final scheme = Theme.of(context).colorScheme;
    final tokens = context.visualTokens;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    Color notaColor = notaActual >= widget.ramo.notaAprobacion
        ? tokens.passingColor
        : tokens.failingColor;
    if (notaActual == 0.0) notaColor = tokens.neutralColor;

    final heroTint = Color.alphaBlend(
      notaColor.withValues(alpha: isDark ? 0.12 : 0.07),
      isDark ? scheme.surfaceContainerLow : scheme.surfaceContainerLowest,
    );
    double evaluado = 0.0;
    for (final c in categorias) {
      if (c.calcularPromedio() != null) {
        evaluado += (c.porcentajeTotal as num).toDouble();
      }
    }
    final evaluadoClamped = evaluado.clamp(0.0, 100.0);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
            decoration: BoxDecoration(
              color: heroTint,
              borderRadius: BorderRadius.circular((tokens.cardRadius + 6).clamp(16.0, 28.0)),
              border: Border.all(
                color: notaColor.withValues(alpha: 0.55),
                width: 1.8,
              ),
            ),
            child: Column(
              children: [
                Text(
                  'NOTA ACTUAL',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.0,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  notaActual.toStringAsFixed(2),
                  style: TextStyle(
                    color: notaColor,
                    fontSize: 38,
                    fontWeight: FontWeight.w800,
                    fontFeatures: const [FontFeature.tabularFigures()],
                    height: 1.1,
                  ),
                ),
                if (categorias.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(AppTheme.radiusFull),
                          child: LinearProgressIndicator(
                            value: evaluadoClamped / 100.0,
                            minHeight: 5,
                            backgroundColor: scheme.surfaceContainerHighest.withValues(alpha: 0.75),
                            color: tokens.accentColor,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                        decoration: BoxDecoration(
                          color: tokens.accentContainer,
                          borderRadius: BorderRadius.circular(AppTheme.radiusFull),
                        ),
                        child: Text(
                          '${evaluadoClamped.toStringAsFixed(0)}% evaluado',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: tokens.onAccentContainer,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
        Expanded(
          child: categorias.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'No hay grupos de evaluaciones creados.',
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                  itemCount: categorias.length,
                  itemBuilder: (context, index) {
                    final cat = categorias[index];
                    final promedioCat = cat.calcularPromedio() ?? 0.0;
                    final bool catFailed = cat.notaAprobacion != null && promedioCat < cat.notaAprobacion!;
                    final Color catPromColor = catFailed ? tokens.failingColor : tokens.passingColor;
                    final rowSurface = isDark ? scheme.surfaceContainer : scheme.surfaceContainerLowest;

                    return Container(
                      margin: const EdgeInsets.only(bottom: 14),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(tokens.cardRadius),
                        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.4)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Wrap(
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  spacing: 8,
                                  runSpacing: 4,
                                  children: [
                                    Text(
                                      cat.nombre,
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 17.5,
                                        color: scheme.onSurface,
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: scheme.surfaceContainerHighest,
                                        borderRadius: BorderRadius.circular(AppTheme.radiusFull),
                                      ),
                                      child: Text(
                                        '${cat.porcentajeTotal % 1 == 0 ? cat.porcentajeTotal.toInt() : cat.porcentajeTotal}%',
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
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: catPromColor.withValues(alpha: 0.14),
                                  borderRadius: BorderRadius.circular(AppTheme.radiusFull),
                                ),
                                child: Text(
                                  promedioCat.toStringAsFixed(2),
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 15,
                                    color: catPromColor,
                                    fontFeatures: const [FontFeature.tabularFigures()],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 4),
                              IconButton(
                                icon: Icon(Icons.edit_outlined, color: scheme.onSurfaceVariant, size: 20),
                                visualDensity: VisualDensity.compact,
                                onPressed: () {
                                  showDialog(
                                    context: context,
                                    builder: (context) => EditCategoriaDialog(
                                      ramoId: widget.ramo.id!,
                                      categoria: cat,
                                    ),
                                  );
                                },
                              ),
                              IconButton(
                                icon: Icon(Icons.delete_outline_rounded, color: scheme.onSurfaceVariant, size: 20),
                                visualDensity: VisualDensity.compact,
                                onPressed: () {
                                  ref.read(categoriaProvider(widget.ramo.id!).notifier).eliminarCategoria(cat.id!);
                                },
                              ),
                            ],
                          ),
                          if (cat.notaAprobacion != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              'Requiere mínimo: ${cat.notaAprobacion}',
                              style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
                            ),
                          ],
                          const SizedBox(height: 10),
                          ...cat.evaluaciones.map((ev) {
                            final isDropped = cat.droppedEvaluacionId == ev.id;
                            return Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
                              decoration: BoxDecoration(
                                color: rowSurface,
                                borderRadius: BorderRadius.circular((tokens.cardRadius - 4).clamp(10.0, 18.0)),
                                border: Border.all(
                                  color: isDropped
                                      ? tokens.failingColor.withValues(alpha: 0.45)
                                      : scheme.outlineVariant.withValues(alpha: 0.35),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(10),
                                      onLongPress: () {
                                        showDialog(
                                          context: context,
                                          builder: (context) => EditEvaluacionDialog(
                                            ramoId: widget.ramo.id!,
                                            evaluacion: ev,
                                          ),
                                        );
                                      },
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(vertical: 4),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              ev.nombre,
                                              style: TextStyle(
                                                fontWeight: FontWeight.w600,
                                                color: isDropped ? tokens.failingColor : scheme.onSurface,
                                                decoration: isDropped ? TextDecoration.lineThrough : null,
                                              ),
                                            ),
                                            if (ev.porcentajePeso != null)
                                              Text(
                                                'Peso: ${ev.porcentajePeso}%',
                                                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                                              ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  SizedBox(
                                    width: 82,
                                    child: GradeInputField(ramoId: widget.ramo.id!, evaluacion: ev),
                                  ),
                                  IconButton(
                                    icon: Icon(Icons.close_rounded, color: scheme.onSurfaceVariant, size: 18),
                                    visualDensity: VisualDensity.compact,
                                    onPressed: () {
                                      ref.read(categoriaProvider(widget.ramo.id!).notifier).eliminarEvaluacion(ev.id!);
                                    },
                                  ),
                                ],
                              ),
                            );
                          }),
                          const SizedBox(height: 4),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.tonalIcon(
                              onPressed: () {
                                showDialog(
                                  context: context,
                                  builder: (context) => AddEvaluacionDialog(
                                    categoriaId: cat.id!,
                                    ramoId: widget.ramo.id!,
                                  ),
                                );
                              },
                              icon: const Icon(Icons.add_rounded, size: 18),
                              label: const Text('Añadir Evaluación'),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildFechasTab(BuildContext context, List<dynamic> categorias) {
    final scheme = Theme.of(context).colorScheme;
    final tokens = context.visualTokens;

    if (categorias.isEmpty) {
      return Center(
        child: Text(
          'Agrega evaluaciones primero en la pestaña Notas.',
          style: TextStyle(color: scheme.onSurfaceVariant),
        ),
      );
    }

    final List<Evaluacion> todas = [];
    for (var cat in categorias) {
      todas.addAll(cat.evaluaciones);
    }
    todas.sort((a, b) {
      if (a.fecha == null && b.fecha == null) return 0;
      if (a.fecha == null) return 1;
      if (b.fecha == null) return -1;
      return a.fecha!.compareTo(b.fecha!);
    });

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
      itemCount: todas.length,
      itemBuilder: (context, index) {
        final ev = todas[index];
        final fechaStr = ev.fecha != null
            ? "${ev.fecha!.day}/${ev.fecha!.month}/${ev.fecha!.year} ${ev.fecha!.hour.toString().padLeft(2, '0')}:${ev.fecha!.minute.toString().padLeft(2, '0')}"
            : "Sin fecha asignada";

        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(tokens.cardRadius),
            border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.4)),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            leading: TonalIconBadge(
              icon: Icons.event_rounded,
              color: ev.fecha != null ? tokens.accentColor : scheme.onSurfaceVariant,
            ),
            title: Text(ev.nombre, style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(
              fechaStr,
              style: TextStyle(
                color: ev.fecha != null ? tokens.accentColor : scheme.onSurfaceVariant,
                fontWeight: ev.fecha != null ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
            trailing: IconButton.filledTonal(
              icon: const Icon(Icons.edit_calendar_rounded, size: 20),
              onPressed: () async {
                DateTime? pickedDate = await showDatePicker(
                  context: context,
                  initialDate: ev.fecha ?? DateTime.now(),
                  firstDate: DateTime(2020),
                  lastDate: DateTime(2030),
                );
                if (pickedDate != null && context.mounted) {
                  TimeOfDay? pickedTime = await showTimePicker(
                    context: context,
                    initialTime: ev.fecha != null ? TimeOfDay.fromDateTime(ev.fecha!) : TimeOfDay.now(),
                  );
                  if (pickedTime != null) {
                    final finalDateTime = DateTime(
                      pickedDate.year,
                      pickedDate.month,
                      pickedDate.day,
                      pickedTime.hour,
                      pickedTime.minute,
                    );
                    ev.fecha = finalDateTime;
                    await ref.read(categoriaProvider(widget.ramo.id!).notifier).actualizarEvaluacion(ev);

                    // Notificación local 1 día antes
                    NotificationService.scheduleEvaluationReminder(ev, widget.ramo.nombre);
                    // Actualizar Widget
                    HomeWidgetService.updateWidget();

                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Fecha y recordatorio guardados')),
                      );
                    }
                  }
                }
              },
            ),
          ),
        );
      },
    );
  }
}
