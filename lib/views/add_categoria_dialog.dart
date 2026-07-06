import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/categoria_evaluacion.dart';
import '../viewmodels/categoria_provider.dart';
import '../viewmodels/settings_provider.dart';

class AddCategoriaDialog extends ConsumerStatefulWidget {
  final int ramoId;
  const AddCategoriaDialog({super.key, required this.ramoId});

  @override
  ConsumerState<AddCategoriaDialog> createState() => _AddCategoriaDialogState();
}

class _AddCategoriaDialogState extends ConsumerState<AddCategoriaDialog> {
  final _formKey = GlobalKey<FormState>();
  String _nombre = 'Certámenes';
  double _porcentaje = 0;
  bool _tieneNotaMinima = false;
  double _notaMinima = 4.0;

  final List<String> _opcionesNombre = [
    'Certámenes',
    'Controles',
    'Tareas',
    'Laboratorios',
    'Proyecto',
    'Examen',
    'Quizzes',
    'Otro'
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final settings = ref.read(settingsProvider);
      if (settings.escalaNotas == '0 a 100') {
        setState(() {
          _notaMinima = 55.0; // Typical passing grade in 1-100
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final categorias = ref.watch(categoriaProvider(widget.ramoId));
    final settings = ref.watch(settingsProvider);
    
    double pesoActual = categorias.fold(0.0, (sum, cat) => sum + cat.porcentajeTotal);
    double pesoMaximoDisponible = 100.0 - pesoActual;
    
    // If we have less than 0 available, something went wrong, but let's clamp it.
    if (pesoMaximoDisponible < 0) pesoMaximoDisponible = 0;

    double maxNota = settings.escalaNotas == '0 a 100' ? 100.0 : 7.0;
    double minNota = settings.escalaNotas == '0 a 100' ? 0.0 : 1.0;
    
    // Safety clamp for _notaMinima if it goes out of bounds after changing settings
    if (_notaMinima > maxNota) _notaMinima = maxNota;
    if (_notaMinima < minNota) _notaMinima = minNota;

    // Safety clamp for _porcentaje
    if (_porcentaje > pesoMaximoDisponible) _porcentaje = pesoMaximoDisponible;

    return AlertDialog(
      title: const Text('Nuevo Grupo de Evaluación'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DropdownButtonFormField<String>(
                initialValue: _nombre,
                decoration: const InputDecoration(labelText: 'Tipo de Evaluación'),
                items: _opcionesNombre.map((String val) {
                  return DropdownMenuItem(
                    value: val,
                    child: Text(val),
                  );
                }).toList(),
                onChanged: (val) {
                  setState(() {
                    _nombre = val!;
                  });
                },
              ),
              const SizedBox(height: 24),
              Text(
                'Peso del grupo: ${_porcentaje.toInt()}%',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              if (pesoMaximoDisponible == 0)
                const Padding(
                  padding: EdgeInsets.only(top: 8.0),
                  child: Text(
                    'Ya has alcanzado el 100% en este ramo.',
                    style: TextStyle(color: Colors.red, fontSize: 12),
                  ),
                )
              else
                Slider(
                  value: _porcentaje,
                  min: 0,
                  max: pesoMaximoDisponible,
                  divisions: pesoMaximoDisponible > 0 ? pesoMaximoDisponible.toInt() : 1,
                  label: '${_porcentaje.toInt()}%',
                  onChanged: (val) {
                    setState(() {
                      _porcentaje = val;
                    });
                  },
                ),
              const SizedBox(height: 16),
              SwitchListTile(
                title: const Text('Requiere nota de aprobación', style: TextStyle(fontSize: 14)),
                value: _tieneNotaMinima,
                contentPadding: EdgeInsets.zero,
                onChanged: (val) {
                  setState(() {
                    _tieneNotaMinima = val;
                  });
                },
              ),
              if (_tieneNotaMinima) ...[
                Text(
                  'Nota Mínima Requerida: ${_notaMinima.toStringAsFixed(1)}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                Slider(
                  value: _notaMinima,
                  min: minNota,
                  max: maxNota,
                  divisions: settings.escalaNotas == '0 a 100' ? 100 : 60, // 6.0 divisions for 1-7 (e.g. 1.0 to 7.0 by 0.1)
                  label: _notaMinima.toStringAsFixed(1),
                  onChanged: (val) {
                    setState(() {
                      _notaMinima = val;
                    });
                  },
                ),
              ]
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.primary,
            foregroundColor: Theme.of(context).colorScheme.onPrimary,
          ),
          onPressed: pesoMaximoDisponible == 0 || _porcentaje == 0 ? null : () {
            if (_formKey.currentState!.validate()) {
              final cat = CategoriaEvaluacion(
                idRamo: widget.ramoId,
                nombre: _nombre,
                porcentajeTotal: _porcentaje,
                notaAprobacion: _tieneNotaMinima ? _notaMinima : null,
              );
              ref.read(categoriaProvider(widget.ramoId).notifier).agregarCategoria(cat);
              Navigator.pop(context);
            }
          },
          child: const Text('Crear Grupo'),
        ),
      ],
    );
  }
}
