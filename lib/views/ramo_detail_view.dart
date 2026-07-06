import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/ramo.dart';

import '../viewmodels/categoria_provider.dart';

import 'add_categoria_dialog.dart';
import 'add_evaluacion_dialog.dart';

class RamoDetailView extends ConsumerWidget {
  final Ramo ramo;
  const RamoDetailView({super.key, required this.ramo});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categorias = ref.watch(categoriaProvider(ramo.id!));
    
    // Inject loaded categories into the Ramo instance
    ramo.categorias = categorias;

    final notaActual = ramo.calcularNotaActual();
    final notaNecesaria = ramo.calcularNotaNecesaria();
    
    bool isApproved = false;
    double totalWeight = categorias.fold(0.0, (s, c) => s + c.porcentajeTotal);
    if (totalWeight >= 100 && notaActual >= ramo.notaAprobacion) {
      isApproved = true;
    }

    Color notaColor = notaActual >= ramo.notaAprobacion ? Colors.green.shade600 : Colors.red.shade600;
    if (notaActual == 0.0) notaColor = Colors.grey;

    return Scaffold(
      appBar: AppBar(
        title: Text(ramo.nombre, style: const TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
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
                const SizedBox(width: 16),
                Expanded(
                  child: Card(
                    color: Theme.of(context).colorScheme.surface,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: Colors.grey.shade400)),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        children: [
                          const Text('Necesaria', style: TextStyle(fontSize: 14)),
                          const SizedBox(height: 8),
                          Text(isApproved ? '¡Lista!' : notaNecesaria.toStringAsFixed(2), style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
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
                                      ref.read(categoriaProvider(ramo.id!).notifier).eliminarCategoria(cat.id!);
                                    },
                                  )
                                ],
                              ),
                              if (cat.notaAprobacion != null)
                                Text('Requiere mínimo: ${cat.notaAprobacion}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                              const SizedBox(height: 12),
                              // Lista de evaluaciones
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
                                            ref.read(categoriaProvider(ramo.id!).notifier).actualizarNotaEvaluacion(ev, nuevaNota);
                                          },
                                        ),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.close, color: Colors.grey, size: 18),
                                        onPressed: () {
                                          ref.read(categoriaProvider(ramo.id!).notifier).eliminarEvaluacion(ev.id!);
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
                                      builder: (context) => AddEvaluacionDialog(categoriaId: cat.id!, ramoId: ramo.id!),
                                    );
                                  },
                                  icon: const Icon(Icons.add),
                                  label: const Text('Añadir Evaluación a este grupo'),
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
      ),
      floatingActionButton: FloatingActionButton(
        child: const Icon(Icons.create_new_folder),
        onPressed: () {
          showDialog(
            context: context,
            builder: (context) => AddCategoriaDialog(ramoId: ramo.id!),
          );
        },
      ),
    );
  }
}
