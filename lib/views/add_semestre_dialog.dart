import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../viewmodels/semestre_provider.dart';
import '../models/semestre.dart';

class AddSemestreDialog extends ConsumerStatefulWidget {
  const AddSemestreDialog({super.key});

  @override
  ConsumerState<AddSemestreDialog> createState() => _AddSemestreDialogState();
}

class _AddSemestreDialogState extends ConsumerState<AddSemestreDialog> {
  final _controller = TextEditingController();

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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      backgroundColor: Colors.white,
      title: const Text('Nuevo Semestre', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black)),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: InputDecoration(
          hintText: 'Ej. Primer Semestre 2026',
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Colors.black, width: 2),
          ),
        ),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar', style: TextStyle(color: Colors.grey)),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          onPressed: _submit,
          child: const Text('Crear'),
        ),
      ],
    );
  }
}
