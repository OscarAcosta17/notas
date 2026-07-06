import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/semestre.dart';
import '../viewmodels/ramo_provider.dart';
import 'add_ramo_dialog.dart';
import 'ramo_detail_view.dart';

class SemestreDetailView extends ConsumerWidget {
  final Semestre semestre;
  const SemestreDetailView({super.key, required this.semestre});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ramos = ref.watch(ramoProvider(semestre.id!));

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        title: Text(semestre.nombre, style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.bold)),
        backgroundColor: Theme.of(context).colorScheme.surface,
        elevation: 0,
        iconTheme: IconThemeData(color: Theme.of(context).colorScheme.onSurface),
      ),
      body: ramos.isEmpty
          ? const Center(child: Text('No hay ramos configurados.', style: TextStyle(color: Colors.grey)))
          : ListView.builder(
              padding: const EdgeInsets.all(16.0),
              itemCount: ramos.length,
              itemBuilder: (context, index) {
                final ramo = ramos[index];
                return Card(
                  color: Theme.of(context).colorScheme.surface,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.1))),
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    title: Text(ramo.nombre, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 18, color: Theme.of(context).colorScheme.onSurface)),
                    subtitle: Text('Promedio: ${ramo.tipoPromedio} - Apruébase con: ${ramo.notaAprobacion}', style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7))),
                    trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => RamoDetailView(ramo: ramo)),
                      );
                    },
                    onLongPress: () {
                      ref.read(ramoProvider(semestre.id!).notifier).eliminarRamo(ramo.id!);
                    },
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Theme.of(context).colorScheme.onPrimary,
        elevation: 2,
        child: const Icon(Icons.add),
        onPressed: () {
          showDialog(
            context: context,
            builder: (context) => AddRamoDialog(semestreId: semestre.id!),
          );
        },
      ),
    );
  }
}
