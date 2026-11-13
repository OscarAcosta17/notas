import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/evaluacion.dart';
import '../theme/app_theme.dart';
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

  @override
  void dispose() {
    _nombreController.dispose();
    _pesoController.dispose();
    super.dispose();
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
    final scheme = Theme.of(context).colorScheme;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.radiusExtraLarge)),
      backgroundColor: scheme.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Editar Evaluación',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 21, color: scheme.onSurface),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _nombreController,
              decoration: const InputDecoration(labelText: 'Nombre'),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _pesoController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Peso de la nota (%)'),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancelar'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _submit,
                  child: const Text('Guardar'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
