import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
    final scheme = Theme.of(context).colorScheme;

    return TextFormField(
      controller: _controller,
      textAlign: TextAlign.center,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      style: TextStyle(
        color: scheme.onSurface,
        fontWeight: FontWeight.w700,
        fontSize: 15,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
      decoration: InputDecoration(
        hintText: 'Nota',
        isDense: true,
        filled: true,
        fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.55),
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.45)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: scheme.primary, width: 2),
        ),
      ),
      onChanged: _onChanged,
    );
  }
}
