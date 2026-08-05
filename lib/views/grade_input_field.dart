import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:async';
import '../models/evaluacion.dart';
import '../viewmodels/categoria_provider.dart';

class GradeInputField extends ConsumerStatefulWidget {
  final int ramoId;
  final Evaluacion evaluacion;

  const GradeInputField({super.key, required this.ramoId, required this.evaluacion});

  @override
  ConsumerState<GradeInputField> createState() => _GradeInputFieldState();
}

class _GradeInputFieldState extends ConsumerState<GradeInputField> {
  late final TextEditingController _controller;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.evaluacion.nota?.toString() ?? '');
  }

  @override
  void didUpdateWidget(GradeInputField oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Only update if it wasn't modified by user locally (to prevent cursor jumping while typing)
    if (widget.evaluacion.nota?.toString() != oldWidget.evaluacion.nota?.toString() &&
        _controller.text != widget.evaluacion.nota?.toString()) {
      _controller.text = widget.evaluacion.nota?.toString() ?? '';
    }
  }

  void _onChanged(String value) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      if (value.isEmpty) {
        widget.evaluacion.nota = null;
      } else {
        double? nuevaNota = double.tryParse(value.replaceAll(',', '.'));
        if (nuevaNota != null) {
          widget.evaluacion.nota = nuevaNota;
        }
      }
      ref.read(categoriaProvider(widget.ramoId).notifier).actualizarEvaluacion(widget.evaluacion);
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: _controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
      decoration: InputDecoration(
        hintText: 'Nota',
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5)),
        ),
      ),
      onChanged: _onChanged,
    );
  }
}
