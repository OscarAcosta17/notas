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
  late bool _tieneGlobal;
  late bool _reemplazaPeorNota;
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
    _tieneGlobal = widget.ramo.tieneGlobal;
    _reemplazaPeorNota = widget.ramo.reemplazaPeorNota;
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
    if (nota == null || nota < 0) return; // Validación estricta

    final updatedRamo = Ramo(
      id: widget.ramo.id,
      idSemestre: widget.ramo.idSemestre,
      nombre: nombre,
      tipoPromedio: _tipoPromedio,
      tieneGlobal: _tieneGlobal,
      reemplazaPeorNota: _reemplazaPeorNota,
      notaAprobacion: nota,
      orderIndex: widget.ramo.orderIndex,
      color: _selectedColor,
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
            const SizedBox(height: 12),
            SwitchListTile(
              title: const Text('¿Tiene Examen Global?', style: TextStyle(fontWeight: FontWeight.w600)),
              value: _tieneGlobal,
              contentPadding: EdgeInsets.zero,
              onChanged: (val) => setState(() => _tieneGlobal = val),
            ),
            if (_tieneGlobal)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Regla del Examen Global:', style: TextStyle(fontWeight: FontWeight.w600, color: scheme.onSurfaceVariant)),
                  SwitchListTile(
                    title: const Text('Reemplaza peor nota (Certamen)'),
                    subtitle: const Text('Si está apagado, promediará con la nota final.'),
                    value: _reemplazaPeorNota,
                    contentPadding: EdgeInsets.zero,
                    onChanged: (val) => setState(() => _reemplazaPeorNota = val),
                  ),
                ],
              ),
            const SizedBox(height: 6),
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
                        icon: const Icon(Icons.clear_rounded),
                        onPressed: () => setState(() => _selectedColor = null),
                      )
                    : null,
                onTap: () async {
                  Color newColor = await showColorPickerDialog(
                    context,
                    _selectedColor != null ? Color(_selectedColor!) : Colors.blue,
                    title: Text('Selecciona el Color', style: Theme.of(context).textTheme.titleLarge),
                    width: 40,
                    height: 40,
                    spacing: 0,
                    runSpacing: 0,
                    borderRadius: 0,
                    wheelDiameter: 165,
                    enableOpacity: false,
                    showColorCode: true,
                    colorCodeHasColor: true,
                    pickersEnabled: <ColorPickerType, bool>{
                      ColorPickerType.both: false,
                      ColorPickerType.primary: false,
                      ColorPickerType.accent: false,
                      ColorPickerType.bw: false,
                      ColorPickerType.custom: false,
                      ColorPickerType.wheel: true,
                    },
                  );
                  setState(() => _selectedColor = newColor.toARGB32());
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
