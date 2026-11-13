import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/semestre.dart';
import '../viewmodels/semestre_provider.dart';

class AddSemestreDialog extends ConsumerStatefulWidget {
  const AddSemestreDialog({super.key});

  @override
  ConsumerState<AddSemestreDialog> createState() => _AddSemestreDialogState();
}

class _AddSemestreDialogState extends ConsumerState<AddSemestreDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _controller.text.trim();
    if (text.isNotEmpty) {
      ref.read(semestreProvider.notifier).agregarSemestre(Semestre(nombre: text));
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Nuevo Semestre'),
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
          child: const Text('Crear'),
        ),
      ],
    );
  }
}
