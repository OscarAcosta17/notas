import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/evaluacion.dart';
import '../viewmodels/categoria_provider.dart';
import '../viewmodels/settings_provider.dart';

class GradeInputField extends ConsumerStatefulWidget {
  final int ramoId;
  final Evaluacion evaluacion;

  const GradeInputField({
    super.key,
    required this.ramoId,
    required this.evaluacion,
  });

  @override
  ConsumerState<GradeInputField> createState() => _GradeInputFieldState();
}

class _GradeInputFieldState extends ConsumerState<GradeInputField> {
  late final TextEditingController _controller;
  Timer? _debounce;
  String? _errorText;
  String _lastEscala = '0 a 100';

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: widget.evaluacion.nota?.toString() ?? '',
    );
  }

  static bool _isWithinScale(double value, String escala) {
    if (!value.isFinite) return false;
    if (escala == '1 a 7') {
      return value >= 1.0 && value <= 7.0;
    }
    return value >= 0.0 && value <= 100.0;
  }

  @override
  void didUpdateWidget(GradeInputField oldWidget) {
    super.didUpdateWidget(oldWidget);
    final newNota = widget.evaluacion.nota;
    if (newNota != oldWidget.evaluacion.nota) {
      final currentText = _controller.text.trim();
      final currentParsed =
          double.tryParse(currentText.replaceAll(',', '.'));
      final matchesSameValue =
          (currentText.isEmpty && newNota == null) ||
              (currentParsed != null &&
                  newNota != null &&
                  (currentParsed - newNota).abs() < 1e-9);
      if (!matchesSameValue) {
        _controller.text = newNota?.toString() ?? '';
        _errorText = null;
      }
    }
  }

  void _persistIfValid(String value, String escala) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      if (widget.evaluacion.nota != null) {
        ref.read(categoriaProvider(widget.ramoId).notifier).actualizarEvaluacion(
              widget.evaluacion.copyWith(nota: null, clearNota: true),
            );
      }
      return;
    }
    final parsed = double.tryParse(trimmed.replaceAll(',', '.'));
    if (parsed == null || !_isWithinScale(parsed, escala)) {
      return;
    }
    if (widget.evaluacion.nota != parsed) {
      ref.read(categoriaProvider(widget.ramoId).notifier).actualizarEvaluacion(
            widget.evaluacion.copyWith(nota: parsed),
          );
    }
  }

  void _onChanged(String value, String escala) {
    _lastEscala = escala;
    final trimmed = value.trim();
    String? nextError;
    if (trimmed.isNotEmpty) {
      final parsed = double.tryParse(trimmed.replaceAll(',', '.'));
      if (parsed == null || !_isWithinScale(parsed, escala)) {
        nextError = escala == '1 a 7' ? '1-7' : '0-100';
      }
    }
    if (nextError != _errorText) {
      setState(() => _errorText = nextError);
    }

    if (_debounce?.isActive ?? false) _debounce!.cancel();
    if (nextError != null) return;

    _debounce = Timer(const Duration(milliseconds: 500), () {
      if (!mounted) return;
      _persistIfValid(value, escala);
    });
  }

  @override
  void dispose() {
    if (_debounce?.isActive ?? false) {
      _debounce!.cancel();
      try {
        _persistIfValid(_controller.text, _lastEscala);
      } catch (_) {}
    } else {
      _debounce?.cancel();
    }
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final escala = ref.watch(settingsProvider.select((s) => s.escalaNotas));
    _lastEscala = escala;

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
        errorText: _errorText,
        errorStyle: const TextStyle(fontSize: 10, height: 0.9),
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
      onChanged: (value) => _onChanged(value, escala),
    );
  }
}
