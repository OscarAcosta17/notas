import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/evaluacion.dart';
import '../viewmodels/categoria_provider.dart';

class EditEvaluacionDialog extends ConsumerStatefulWidget {
  final int ramoId;
  final Evaluacion evaluacion;

  const EditEvaluacionDialog({super.key, required this.ramoId, required this.evaluacion});

  @override
  ConsumerState<EditEvaluacionDialog> createState() => _EditEvaluacionDialogState();
}

class _EditEvaluacionDialogState extends ConsumerState<EditEvaluacionDialog> {
  late final TextEditingController _nombreController;
  late final TextEditingController _pesoController;

  @override
  void initState() {
    super.initState();
    _nombreController = TextEditingController(text: widget.evaluacion.nombre);
    _pesoController = TextEditingController(text: widget.evaluacion.porcentajePeso?.toString() ?? '');
  }

  void _submit() {
    final nombre = _nombreController.text.trim();
    final pesoStr = _pesoController.text.trim();

    if (nombre.isEmpty) return;

    double? peso = pesoStr.isNotEmpty ? double.tryParse(pesoStr.replaceAll(',', '.')) : null;

    widget.evaluacion.nombre = nombre;
    widget.evaluacion.porcentajePeso = peso;

    ref.read(categoriaProvider(widget.ramoId).notifier).actualizarEvaluacion(widget.evaluacion);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      backgroundColor: Theme.of(context).colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Editar Evaluación', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: Theme.of(context).colorScheme.onSurface)),
            const SizedBox(height: 16),
            TextField(
              controller: _nombreController,
              decoration: InputDecoration(
                labelText: 'Nombre',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _pesoController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Peso de la nota (%)',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancelar', style: TextStyle(color: Colors.grey)),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Theme.of(context).colorScheme.onPrimary,
                  ),
                  onPressed: _submit,
                  child: const Text('Guardar'),
                ),
              ],
            )
          ],
        ),
      ),
    );
  }
}
