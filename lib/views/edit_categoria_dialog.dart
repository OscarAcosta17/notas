import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/categoria_evaluacion.dart';
import '../theme/app_theme.dart';
import '../viewmodels/categoria_provider.dart';
import 'formula_editor_dialog.dart';

class EditCategoriaDialog extends ConsumerStatefulWidget {
  final int ramoId;
  final CategoriaEvaluacion categoria;

  const EditCategoriaDialog({super.key, required this.ramoId, required this.categoria});

  @override
  ConsumerState<EditCategoriaDialog> createState() => _EditCategoriaDialogState();
}

class _EditCategoriaDialogState extends ConsumerState<EditCategoriaDialog> {
  late final TextEditingController _nombreController;
  late final TextEditingController _porcentajeController;
  late final TextEditingController _notaController;

  late String _averageType;
  String? _customFormula;
  late bool _dropLowest;
  late final TextEditingController _formulaController;

  @override
  void initState() {
    super.initState();
    _nombreController = TextEditingController(text: widget.categoria.nombre);
    _porcentajeController = TextEditingController(text: widget.categoria.porcentajeTotal.toString());
    _notaController = TextEditingController(text: widget.categoria.notaAprobacion?.toString() ?? '');
    _averageType = widget.categoria.averageType;
    _customFormula = widget.categoria.customFormula;
    _dropLowest = widget.categoria.dropLowest;
    _formulaController = TextEditingController(text: _customFormula ?? '');
  }

  @override
  void dispose() {
    _nombreController.dispose();
    _porcentajeController.dispose();
    _notaController.dispose();
    _formulaController.dispose();
    super.dispose();
  }

  void _submit() {
    final nombre = _nombreController.text.trim();
    final porcentajeStr = _porcentajeController.text.trim();
    final notaStr = _notaController.text.trim();

    if (nombre.isEmpty || porcentajeStr.isEmpty) return;

    double? porcentaje = double.tryParse(porcentajeStr.replaceAll(',', '.'));
    double? nota = notaStr.isNotEmpty ? double.tryParse(notaStr.replaceAll(',', '.')) : null;

    if (porcentaje == null || porcentaje <= 0) return;

    widget.categoria.nombre = nombre;
    widget.categoria.porcentajeTotal = porcentaje;
    widget.categoria.notaAprobacion = nota;
    widget.categoria.averageType = _averageType;
    widget.categoria.customFormula = _averageType == 'Personalizada' ? _customFormula : null;
    widget.categoria.dropLowest = _dropLowest;

    ref.read(categoriaProvider(widget.ramoId).notifier).actualizarCategoria(widget.categoria);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.radiusExtraLarge)),
      backgroundColor: scheme.surfaceContainerHigh,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Editar Categoría',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 21, color: scheme.onSurface),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _nombreController,
              decoration: const InputDecoration(labelText: 'Nombre de la Categoría'),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _porcentajeController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Porcentaje Total (%)'),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _notaController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Nota Mínima (Opcional)'),
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              initialValue: _averageType,
              decoration: const InputDecoration(labelText: 'Tipo de Promedio'),
              items: ['Aritmetico', 'Geometrico', 'Personalizada'].map((String val) {
                return DropdownMenuItem(
                  value: val,
                  child: Text(val),
                );
              }).toList(),
              onChanged: (val) {
                if (val != null) setState(() => _averageType = val);
              },
            ),
            if (_averageType == 'Personalizada') ...[
              const SizedBox(height: 10),
              Text('Fórmula:', style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant)),
              const SizedBox(height: 6),
              InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () async {
                  final result = await showDialog<String>(
                    context: context,
                    builder: (context) => FormulaEditorDialog(
                      initialFormula: _customFormula ?? '',
                      existingVariables: List.generate(widget.categoria.evaluaciones.length, (i) => 'e${i + 1}'),
                    ),
                  );
                  if (result != null) {
                    setState(() {
                      _customFormula = result;
                    });
                  }
                },
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerLow,
                    border: Border.all(color: scheme.outlineVariant),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    _customFormula?.isNotEmpty == true ? _customFormula! : 'Toca para editar fórmula...',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      color: _customFormula?.isNotEmpty == true ? scheme.onSurface : scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 10),
            SwitchListTile(
              title: const Text('Eliminar peor nota', style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w500)),
              value: _dropLowest,
              contentPadding: EdgeInsets.zero,
              onChanged: (val) {
                setState(() {
                  _dropLowest = val;
                });
              },
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
