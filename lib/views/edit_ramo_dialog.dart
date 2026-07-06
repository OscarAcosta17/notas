import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../viewmodels/ramo_provider.dart';
import '../models/ramo.dart';

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

  @override
  void initState() {
    super.initState();
    _nombreController = TextEditingController(text: widget.ramo.nombre);
    _notaController = TextEditingController(text: widget.ramo.notaAprobacion.toString());
    _tipoPromedio = widget.ramo.tipoPromedio;
    _tieneGlobal = widget.ramo.tieneGlobal;
    _reemplazaPeorNota = widget.ramo.reemplazaPeorNota;
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
    );

    ref.read(ramoProvider(widget.ramo.idSemestre).notifier).actualizarRamo(updatedRamo);
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
            Text('Editar Ramo', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: Theme.of(context).colorScheme.onSurface)),
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
              value: _tipoPromedio,
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
