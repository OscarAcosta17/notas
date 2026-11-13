import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/semestre.dart';
import '../viewmodels/semestre_provider.dart';

class EditSemestreDialog extends ConsumerStatefulWidget {
  final Semestre semestre;
  const EditSemestreDialog({super.key, required this.semestre});

  @override
  ConsumerState<EditSemestreDialog> createState() => _EditSemestreDialogState();
}

class _EditSemestreDialogState extends ConsumerState<EditSemestreDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.semestre.nombre);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _controller.text.trim();
    if (text.isNotEmpty) {
      final updatedSemestre = Semestre(
        id: widget.semestre.id,
        nombre: text,
      );
      ref.read(semestreProvider.notifier).actualizarSemestre(updatedSemestre);
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Editar Semestre'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: const InputDecoration(
          hintText: 'Ej. Primer Semestre 2026',
        ),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}
