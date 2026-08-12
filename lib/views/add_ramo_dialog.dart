import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../viewmodels/ramo_provider.dart';
import '../viewmodels/settings_provider.dart';
import 'package:flex_color_picker/flex_color_picker.dart';
import '../models/ramo.dart';

class AddRamoDialog extends ConsumerStatefulWidget {
  final int semestreId;
  const AddRamoDialog({super.key, required this.semestreId});

  @override
  ConsumerState<AddRamoDialog> createState() => _AddRamoDialogState();
}

class _AddRamoDialogState extends ConsumerState<AddRamoDialog> {
  final _nombreController = TextEditingController();
  late final TextEditingController _notaController;
  
  String _tipoPromedio = 'Aritmético';
  bool _tieneGlobal = false;
  bool _reemplazaPeorNota = true;
  int? _selectedColor;

  @override
  void initState() {
    super.initState();
    final settings = ref.read(settingsProvider);
    _notaController = TextEditingController(text: settings.escalaNotas == '0 a 100' ? '55' : '4.0');
  }

  void _submit() {
    final nombre = _nombreController.text.trim();
    final notaStr = _notaController.text.trim();
    
    if (nombre.isEmpty) return;
    double? nota = double.tryParse(notaStr.replaceAll(',', '.'));
    if (nota == null || nota < 0) return; // Validación estricta

    final ramo = Ramo(
      idSemestre: widget.semestreId,
      nombre: nombre,
      tipoPromedio: _tipoPromedio,
      tieneGlobal: _tieneGlobal,
      reemplazaPeorNota: _reemplazaPeorNota,
      notaAprobacion: nota,
      color: _selectedColor,
    );

    ref.read(ramoProvider(widget.semestreId).notifier).agregarRamo(ramo);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      backgroundColor: Theme.of(context).colorScheme.surface,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Configurar Ramo', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: Theme.of(context).colorScheme.onSurface)),
            const SizedBox(height: 16),
            TextField(
              controller: _nombreController,
              decoration: InputDecoration(
                labelText: 'Nombre del Ramo',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Theme.of(context).colorScheme.onSurface, width: 2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _tipoPromedio,
              decoration: InputDecoration(
                labelText: 'Tipo de Promedio',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Theme.of(context).colorScheme.onSurface, width: 2),
                ),
              ),
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
            const SizedBox(height: 16),
            TextField(
              controller: _notaController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Nota Mínima de Aprobación',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Theme.of(context).colorScheme.onSurface, width: 2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            SwitchListTile(
              title: const Text('¿Tiene Examen Global?', style: TextStyle(fontWeight: FontWeight.w600)),
              value: _tieneGlobal,
              activeThumbColor: Theme.of(context).colorScheme.primary,
              contentPadding: EdgeInsets.zero,
              onChanged: (val) => setState(() => _tieneGlobal = val),
            ),
            if (_tieneGlobal)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Regla del Examen Global:', style: TextStyle(fontWeight: FontWeight.w500)),
                  SwitchListTile(
                    title: const Text('Reemplaza peor nota (Certamen)'),
                    subtitle: const Text('Si está apagado, promediará con la nota final.'),
                    value: _reemplazaPeorNota,
                    activeThumbColor: Theme.of(context).colorScheme.primary,
                    contentPadding: EdgeInsets.zero,
                    onChanged: (val) => setState(() => _reemplazaPeorNota = val),
                  ),
                ],
              ),
            const SizedBox(height: 16),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.color_lens, color: _selectedColor != null ? Color(_selectedColor!) : Theme.of(context).colorScheme.onSurface),
              title: const Text('Color del Ramo', style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: const Text('Color para destacar en la lista'),
              trailing: _selectedColor != null
                  ? IconButton(
                      icon: const Icon(Icons.clear),
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
                setState(() => _selectedColor = newColor.value);
              },
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancelar', style: TextStyle(color: Colors.grey)),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Theme.of(context).colorScheme.onPrimary,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: _submit,
                  child: const Text('Guardar'),
                ),
              ],
            )
          ],
        ),
      ),
    );
  }
}
