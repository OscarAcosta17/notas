import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/evaluacion.dart';
import '../viewmodels/categoria_provider.dart';

class AddEvaluacionDialog extends ConsumerStatefulWidget {
  final int categoriaId;
  final int ramoId;
  const AddEvaluacionDialog({super.key, required this.categoriaId, required this.ramoId});

  @override
  ConsumerState<AddEvaluacionDialog> createState() => _AddEvaluacionDialogState();
}

class _AddEvaluacionDialogState extends ConsumerState<AddEvaluacionDialog> {
  final _formKey = GlobalKey<FormState>();
  String _nombre = '';
  double? _pesoEspecifico;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Nueva Evaluación'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                decoration: const InputDecoration(labelText: 'Nombre (ej: Certamen 1)'),
                validator: (val) =>
                    val == null || val.trim().isEmpty ? 'Requerido' : null,
                onSaved: (val) => _nombre = val!.trim(),
              ),
              const SizedBox(height: 14),
              TextFormField(
                decoration: const InputDecoration(
                  labelText: 'Peso Específico %',
                  hintText: 'Dejar vacío si es equitativo',
                ),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                validator: (val) {
                  final trimmed = val?.trim() ?? '';
                  if (trimmed.isEmpty) return null;
                  final parsed = double.tryParse(trimmed.replaceAll(',', '.'));
                  if (parsed == null || !parsed.isFinite || parsed <= 0 || parsed > 100) {
                    return 'Debe ser un número entre 0 y 100';
                  }
                  return null;
                },
                onSaved: (val) {
                  final trimmed = val?.trim() ?? '';
                  if (trimmed.isNotEmpty) {
                    _pesoEspecifico = double.parse(trimmed.replaceAll(',', '.'));
                  } else {
                    _pesoEspecifico = null;
                  }
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          onPressed: () {
            if (_formKey.currentState!.validate()) {
              _formKey.currentState!.save();
              final ev = Evaluacion(
                idCategoria: widget.categoriaId,
                nombre: _nombre,
                porcentajePeso: _pesoEspecifico,
              );
              ref.read(categoriaProvider(widget.ramoId).notifier).agregarEvaluacion(ev);
              Navigator.pop(context);
            }
          },
          child: const Text('Añadir'),
        ),
      ],
    );
  }
}
