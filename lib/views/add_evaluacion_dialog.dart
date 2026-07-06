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
                validator: (val) => val == null || val.isEmpty ? 'Requerido' : null,
                onSaved: (val) => _nombre = val!,
              ),
              const SizedBox(height: 12),
              TextFormField(
                decoration: const InputDecoration(labelText: 'Peso Específico % (Dejar en blanco si se divide en partes iguales)'),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                validator: (val) {
                  if (val != null && val.isNotEmpty && double.tryParse(val) == null) {
                    return 'Debe ser número válido';
                  }
                  return null;
                },
                onSaved: (val) {
                  if (val != null && val.trim().isNotEmpty) {
                    _pesoEspecifico = double.parse(val);
                  }
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
          ),
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
