import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/categoria_evaluacion.dart';
import '../theme/app_theme.dart';
import '../viewmodels/categoria_provider.dart';
import '../viewmodels/settings_provider.dart';
import 'formula_editor_dialog.dart';

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
  String _averageType = 'Aritmetico';
  String? _customFormula;
  bool _dropLowest = false;
  int _autoCreateCount = 0;
  final TextEditingController _formulaController = TextEditingController();

  final List<String> _opcionesNombre = [
    'Certámenes',
    'Controles',
    'Tareas',
    'Laboratorios',
    'Proyecto',
    'Examen',
    'Quizzes',
    'Otro',
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
  void dispose() {
    _formulaController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final categorias = ref.watch(categoriaProvider(widget.ramoId));
    final settings = ref.watch(settingsProvider);
    final scheme = Theme.of(context).colorScheme;
    final tokens = context.visualTokens;

    double pesoActual = categorias.fold(0.0, (sum, cat) => sum + cat.porcentajeTotal);
    double pesoMaximoDisponible = 100.0 - pesoActual;
    if (pesoMaximoDisponible < 0) pesoMaximoDisponible = 0;

    double maxNota = settings.escalaNotas == '0 a 100' ? 100.0 : 7.0;
    double minNota = settings.escalaNotas == '0 a 100' ? 0.0 : 1.0;

    if (_notaMinima > maxNota) _notaMinima = maxNota;
    if (_notaMinima < minNota) _notaMinima = minNota;
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
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Peso del grupo', style: TextStyle(fontWeight: FontWeight.w600)),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(
                      color: scheme.primaryContainer,
                      borderRadius: BorderRadius.circular(AppTheme.radiusFull),
                    ),
                    child: Text(
                      '${_porcentaje.toInt()}%',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: scheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                ],
              ),
              if (pesoMaximoDisponible == 0)
                Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: Text(
                    'Ya has alcanzado el 100% en este ramo.',
                    style: TextStyle(color: tokens.failingColor, fontSize: 12.5, fontWeight: FontWeight.w600),
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
              const SizedBox(height: 8),
              SwitchListTile(
                title: const Text('Requiere nota de aprobación', style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w500)),
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
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                Slider(
                  value: _notaMinima,
                  min: minNota,
                  max: maxNota,
                  divisions: settings.escalaNotas == '0 a 100' ? 100 : 60,
                  label: _notaMinima.toStringAsFixed(1),
                  onChanged: (val) {
                    setState(() {
                      _notaMinima = val;
                    });
                  },
                ),
              ],
              const SizedBox(height: 12),
              TextFormField(
                initialValue: _autoCreateCount.toString(),
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Autocrear N evaluaciones vacías',
                ),
                onChanged: (val) {
                  setState(() {
                    _autoCreateCount = int.tryParse(val) ?? 0;
                  });
                },
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
                  setState(() {
                    _averageType = val!;
                  });
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
                        autoCreateCount: _autoCreateCount,
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
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          onPressed: pesoMaximoDisponible == 0 || _porcentaje == 0
              ? null
              : () {
                  if (_formKey.currentState!.validate()) {
                    final cat = CategoriaEvaluacion(
                      idRamo: widget.ramoId,
                      nombre: _nombre,
                      porcentajeTotal: _porcentaje,
                      notaAprobacion: _tieneNotaMinima ? _notaMinima : null,
                      averageType: _averageType,
                      customFormula: _averageType == 'Personalizada' ? _customFormula : null,
                      dropLowest: _dropLowest,
                    );

                    ref.read(categoriaProvider(widget.ramoId).notifier).agregarCategoriaConEvaluaciones(cat, _autoCreateCount);
                    Navigator.pop(context);
                  }
                },
          child: const Text('Crear Grupo'),
        ),
      ],
    );
  }
}
