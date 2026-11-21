import 'package:flex_color_picker/flex_color_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/ramo.dart';
import '../theme/app_theme.dart';
import '../theme/expressive_widgets.dart';
import '../viewmodels/ramo_provider.dart';

class EditRamoDialog extends ConsumerStatefulWidget {
  final Ramo ramo;
  const EditRamoDialog({super.key, required this.ramo});

  @override
  ConsumerState<EditRamoDialog> createState() => _EditRamoDialogState();
}

class _EditRamoDialogState extends ConsumerState<EditRamoDialog> {
  late final TextEditingController _nombreController;
  late final TextEditingController _notaController;

  late String _tipoPromedio;
  int? _selectedColor;

  @override
  void initState() {
    super.initState();
    _nombreController = TextEditingController(text: widget.ramo.nombre);
    _notaController = TextEditingController(text: widget.ramo.notaAprobacion.toString());
    // Normalize legacy accentless value if stored in DB
    _tipoPromedio = widget.ramo.tipoPromedio == 'Aritmetico'
        ? 'Aritmético'
        : (widget.ramo.tipoPromedio == 'Geometrico' ? 'Geométrico' : widget.ramo.tipoPromedio);
    _selectedColor = widget.ramo.color;
  }

  @override
  void dispose() {
    _nombreController.dispose();
    _notaController.dispose();
    super.dispose();
  }

  void _submit() {
    final nombre = _nombreController.text.trim();
    final notaStr = _notaController.text.trim();

    if (nombre.isEmpty) return;
    double? nota = double.tryParse(notaStr.replaceAll(',', '.'));
    if (nota == null || !nota.isFinite || nota < 0) return;

    final updatedRamo = widget.ramo.copyWith(
      nombre: nombre,
      tipoPromedio: _tipoPromedio,
      notaAprobacion: nota,
      color: _selectedColor,
      clearColor: _selectedColor == null,
    );

    ref.read(ramoProvider(widget.ramo.idSemestre).notifier).actualizarRamo(updatedRamo);
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
              'Editar Ramo',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 21, color: scheme.onSurface),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _nombreController,
              decoration: const InputDecoration(labelText: 'Nombre del Ramo'),
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              initialValue: ['Aritmético', 'Geométrico'].contains(_tipoPromedio) ? _tipoPromedio : 'Aritmético',
              decoration: const InputDecoration(labelText: 'Tipo de Promedio'),
              items: ['Aritmético', 'Geométrico'].map((String value) {
                return DropdownMenuItem<String>(
                  value: value,
                  child: Text(value),
                );
              }).toList(),
              onChanged: (val) {
                if (val != null) setState(() => _tipoPromedio = val);
              },
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _notaController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Nota Mínima de Aprobación'),
            ),
            const SizedBox(height: 16),
            Container(
              decoration: BoxDecoration(
                color: scheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
              ),
              child: ListTile(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.radiusMedium)),
                leading: TonalIconBadge(
                  icon: Icons.color_lens_rounded,
                  color: _selectedColor != null ? Color(_selectedColor!) : null,
                ),
                title: const Text('Color del Ramo', style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: const Text('Color para destacar en la lista'),
                trailing: _selectedColor != null
                    ? IconButton(
                        tooltip: 'Quitar color',
                        icon: const Icon(Icons.clear_rounded),
                        onPressed: () => setState(() => _selectedColor = null),
                      )
                    : null,
                onTap: () async {
                  final picker = ColorPicker(
                    color: _selectedColor != null ? Color(_selectedColor!) : Colors.blue,
                    onColorChanged: (c) => _selectedColor = c.toARGB32(),
                    width: 40,
                    height: 40,
                    spacing: 4,
                    runSpacing: 4,
                    borderRadius: 8,
                    wheelDiameter: 165,
                    enableOpacity: false,
                    showColorCode: true,
                    colorCodeHasColor: true,
                    pickersEnabled: const <ColorPickerType, bool>{
                      ColorPickerType.both: false,
                      ColorPickerType.primary: true,
                      ColorPickerType.accent: false,
                      ColorPickerType.bw: false,
                      ColorPickerType.custom: false,
                      ColorPickerType.wheel: true,
                    },
                  );
                  final confirmed = await picker.showPickerDialog(
                    context,
                    constraints: const BoxConstraints(minHeight: 400, minWidth: 280, maxWidth: 360),
                  );
                  if (confirmed && mounted) setState(() {});
                },
              ),
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
