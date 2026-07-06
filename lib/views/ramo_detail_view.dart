import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/ramo.dart';
import '../models/evaluacion.dart';

import '../viewmodels/categoria_provider.dart';
import '../services/notification_service.dart';
import '../services/home_widget_service.dart';

import 'add_categoria_dialog.dart';
import 'add_evaluacion_dialog.dart';

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
    
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.ramo.nombre, style: const TextStyle(fontWeight: FontWeight.bold)),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Notas', icon: Icon(Icons.calculate)),
              Tab(text: 'Fechas', icon: Icon(Icons.calendar_month)),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildNotasTab(context, categorias),
            _buildFechasTab(context, categorias),
          ],
        ),
        floatingActionButton: FloatingActionButton(
          child: const Icon(Icons.create_new_folder),
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
    Color notaColor = notaActual >= widget.ramo.notaAprobacion ? Colors.green.shade600 : Colors.red.shade600;
    if (notaActual == 0.0) notaColor = Colors.grey;

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          width: double.infinity,
          child: Card(
            color: Theme.of(context).colorScheme.surface,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: notaColor, width: 2)),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  const Text('Nota Actual', style: TextStyle(fontSize: 14)),
                  const SizedBox(height: 8),
                  Text(notaActual.toStringAsFixed(2), style: TextStyle(color: notaColor, fontSize: 28, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ),
        ),
        const Divider(),
        Expanded(
          child: categorias.isEmpty
              ? const Center(child: Text('No hay grupos de evaluaciones creados.', style: TextStyle(color: Colors.grey)))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: categorias.length,
                  itemBuilder: (context, index) {
                    final cat = categorias[index];
                    final promedioCat = cat.calcularPromedio() ?? 0.0;
                    
                    return Card(
                      elevation: 2,
                      margin: const EdgeInsets.only(bottom: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      child: Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    "${cat.nombre} (${cat.porcentajeTotal}%)",
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                                  ),
                                ),
                                Text(
                                  promedioCat.toStringAsFixed(2),
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 18,
                                    color: (cat.notaAprobacion != null && promedioCat < cat.notaAprobacion!) ? Colors.red : Colors.green,
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete, color: Colors.grey, size: 20),
                                  onPressed: () {
                                    ref.read(categoriaProvider(widget.ramo.id!).notifier).eliminarCategoria(cat.id!);
                                  },
                                )
                              ],
                            ),
                            if (cat.notaAprobacion != null)
                              Text('Requiere mínimo: ${cat.notaAprobacion}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                            const SizedBox(height: 12),
                            ...cat.evaluaciones.map((ev) {
                              return Padding(
                                padding: const EdgeInsets.symmetric(vertical: 4.0),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(ev.nombre),
                                          if (ev.porcentajePeso != null)
                                            Text('Peso: ${ev.porcentajePeso}%', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                                        ],
                                      ),
                                    ),
                                    SizedBox(
                                      width: 80,
                                      child: TextFormField(
                                        initialValue: ev.nota?.toString() ?? '',
                                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                        style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
                                        decoration: InputDecoration(
                                          hintText: 'Nota',
                                          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                          border: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(8),
                                            borderSide: BorderSide(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5))
                                          ),
                                        ),
                                        onFieldSubmitted: (value) {
                                          double? nuevaNota = double.tryParse(value);
                                          ev.nota = nuevaNota;
                                          ref.read(categoriaProvider(widget.ramo.id!).notifier).actualizarEvaluacion(ev);
                                        },
                                      ),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.close, color: Colors.grey, size: 18),
                                      onPressed: () {
                                        ref.read(categoriaProvider(widget.ramo.id!).notifier).eliminarEvaluacion(ev.id!);
                                      },
                                    )
                                  ],
                                ),
                              );
                            }),
                            const SizedBox(height: 8),
                            Center(
                              child: TextButton.icon(
                                onPressed: () {
                                  showDialog(
                                    context: context,
                                    builder: (context) => AddEvaluacionDialog(categoriaId: cat.id!, ramoId: widget.ramo.id!),
                                  );
                                },
                                icon: const Icon(Icons.add),
                                label: const Text('Añadir Evaluación'),
                              ),
                            )
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildFechasTab(BuildContext context, List<dynamic> categorias) {
    if (categorias.isEmpty) {
      return const Center(child: Text('Agrega evaluaciones primero en la pestaña Notas.', style: TextStyle(color: Colors.grey)));
    }

    List<Evaluacion> todas = [];
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
      padding: const EdgeInsets.all(16),
      itemCount: todas.length,
      itemBuilder: (context, index) {
        final ev = todas[index];
        final fechaStr = ev.fecha != null 
          ? "${ev.fecha!.day}/${ev.fecha!.month}/${ev.fecha!.year} ${ev.fecha!.hour.toString().padLeft(2, '0')}:${ev.fecha!.minute.toString().padLeft(2, '0')}" 
          : "Sin fecha asignada";

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: ListTile(
            leading: const Icon(Icons.event),
            title: Text(ev.nombre, style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text(fechaStr),
            trailing: IconButton(
              icon: const Icon(Icons.edit_calendar),
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
                      pickedDate.year, pickedDate.month, pickedDate.day, 
                      pickedTime.hour, pickedTime.minute
                    );
                    ev.fecha = finalDateTime;
                    await ref.read(categoriaProvider(widget.ramo.id!).notifier).actualizarEvaluacion(ev);
                    
                    // Notificación local 1 día antes
                    NotificationService.scheduleEvaluationReminder(ev, widget.ramo.nombre);
                    // Actualizar Widget
                    HomeWidgetService.updateWidget();
                    
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Fecha y recordatorio guardados')));
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
