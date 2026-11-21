import 'package:flutter/material.dart';
import '../models/categoria_evaluacion.dart';
import '../theme/app_theme.dart';

class FormulaEditorDialog extends StatefulWidget {
  final String initialFormula;
  final int autoCreateCount;
  final List<String> existingVariables;

  const FormulaEditorDialog({
    super.key,
    required this.initialFormula,
    this.autoCreateCount = 0,
    this.existingVariables = const [],
  });

  @override
  State<FormulaEditorDialog> createState() => _FormulaEditorDialogState();
}

class _FormulaEditorDialogState extends State<FormulaEditorDialog> {
  late String _formula;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _formula = widget.initialFormula;
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onKeyPress(String key) {
    setState(() {
      _formula += key;
    });
    _scrollToEnd();
  }

  void _onBackspace() {
    if (_formula.isNotEmpty) {
      setState(() {
        _formula = _formula.substring(0, _formula.length - 1);
      });
      _scrollToEnd();
    }
  }

  void _onClear() {
    setState(() {
      _formula = '';
    });
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Widget _buildKey(
    String label, {
    Color? color,
    Color? foregroundColor,
    VoidCallback? onPressed,
    int flex = 1,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final bg = color ?? scheme.surfaceContainerLowest;
    final fg = foregroundColor ?? (color != null ? Colors.white : scheme.onSurface);

    return Expanded(
      flex: flex,
      child: Padding(
        padding: const EdgeInsets.all(2.5),
        child: SizedBox(
          height: 42,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: bg,
              foregroundColor: fg,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              padding: EdgeInsets.zero,
            ),
            onPressed: onPressed ?? () => _onKeyPress(label),
            child: Text(
              label,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tokens = context.visualTokens;
    final validationError = _formula.trim().isEmpty
        ? null
        : CategoriaEvaluacion.validateCustomFormula(_formula);

    final List<String> variables;
    if (widget.existingVariables.isNotEmpty) {
      variables = widget.existingVariables;
    } else if (widget.autoCreateCount > 0) {
      variables = List.generate(widget.autoCreateCount, (i) => 'e${i + 1}');
    } else {
      variables = ['e1', 'e2', 'e3', 'e4'];
    }

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.radiusExtraLarge)),
      backgroundColor: scheme.surfaceContainerHigh,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(14.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Editor de Fórmula',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 19, color: scheme.onSurface),
                ),
                IconButton(
                  tooltip: 'Cerrar',
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                border: Border.all(
                  color: validationError != null
                      ? scheme.error
                      : scheme.primary.withValues(alpha: 0.45),
                  width: 1.5,
                ),
              ),
              child: SingleChildScrollView(
                controller: _scrollController,
                scrollDirection: Axis.horizontal,
                child: Text(
                  _formula.isEmpty ? 'Escribe aquí...' : _formula,
                  style: TextStyle(
                    fontSize: 22,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w700,
                    color: _formula.isEmpty ? scheme.onSurfaceVariant : scheme.onSurface,
                  ),
                ),
              ),
            ),
            if (validationError != null) ...[
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  validationError,
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.error,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 10),
            if (variables.isNotEmpty) ...[
              SizedBox(
                height: 44,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: variables.length,
                  itemBuilder: (context, index) {
                    return Padding(
                      padding: const EdgeInsets.only(right: 8.0),
                      child: ActionChip(
                        backgroundColor: scheme.secondaryContainer,
                        side: BorderSide.none,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.radiusFull)),
                        label: Text(
                          variables[index],
                          style: TextStyle(fontWeight: FontWeight.w700, color: scheme.onSecondaryContainer),
                        ),
                        onPressed: () => _onKeyPress(variables[index]),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 10),
            ],
            Column(
              children: [
                Row(
                  children: [
                    _buildKey('sqrt(', color: const Color(0xFF5B21B6)),
                    _buildKey('^', color: const Color(0xFF5B21B6)),
                    _buildKey('abs(', color: const Color(0xFF5B21B6)),
                    _buildKey('C', color: tokens.failingColor, onPressed: _onClear),
                  ],
                ),
                Row(
                  children: [
                    _buildKey('min(', color: const Color(0xFF1D4ED8)),
                    _buildKey('max(', color: const Color(0xFF1D4ED8)),
                    _buildKey(','),
                    _buildKey('⌫', onPressed: _onBackspace),
                  ],
                ),
                Row(
                  children: [
                    _buildKey('7'),
                    _buildKey('8'),
                    _buildKey('9'),
                    _buildKey('/', color: scheme.secondaryContainer, foregroundColor: scheme.onSecondaryContainer),
                  ],
                ),
                Row(
                  children: [
                    _buildKey('4'),
                    _buildKey('5'),
                    _buildKey('6'),
                    _buildKey('*', color: scheme.secondaryContainer, foregroundColor: scheme.onSecondaryContainer),
                  ],
                ),
                Row(
                  children: [
                    _buildKey('1'),
                    _buildKey('2'),
                    _buildKey('3'),
                    _buildKey('-', color: scheme.secondaryContainer, foregroundColor: scheme.onSecondaryContainer),
                  ],
                ),
                Row(
                  children: [
                    _buildKey('.'),
                    _buildKey('0', flex: 2),
                    _buildKey('+', color: scheme.secondaryContainer, foregroundColor: scheme.onSecondaryContainer),
                  ],
                ),
                Row(
                  children: [
                    _buildKey('('),
                    _buildKey(')'),
                    _buildKey(
                      'Guardar',
                      color: scheme.primary,
                      foregroundColor: scheme.onPrimary,
                      flex: 2,
                      onPressed: () {
                        if (_formula.trim().isNotEmpty &&
                            CategoriaEvaluacion.validateCustomFormula(_formula) != null) {
                          return;
                        }
                        Navigator.pop(context, _formula.trim());
                      },
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
