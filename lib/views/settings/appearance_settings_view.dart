import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_dynamic_icon_plus/flutter_dynamic_icon_plus.dart';
import 'package:flex_color_picker/flex_color_picker.dart';
import '../../viewmodels/settings_provider.dart';

class AppearanceSettingsView extends ConsumerStatefulWidget {
  const AppearanceSettingsView({super.key});

  @override
  ConsumerState<AppearanceSettingsView> createState() => _AppearanceSettingsViewState();
}

class _AppearanceSettingsViewState extends ConsumerState<AppearanceSettingsView> {
  Future<void> _changeIcon(String? iconName) async {
    try {
      if (await FlutterDynamicIconPlus.supportsAlternateIcons) {
        await FlutterDynamicIconPlus.setAlternateIconName(iconName: iconName);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Icono cambiado (la app podría cerrarse momentáneamente)')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al cambiar el icono: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Apariencia'),
      ),
      body: ListView(
        children: [
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: Text('Tema', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ),
          SwitchListTile(
            title: const Text('Modo Oscuro'),
            subtitle: const Text('Activar paleta de colores oscuros'),
            value: settings.isDarkMode,
            activeTrackColor: Colors.black,
            onChanged: (bool value) {
              ref.read(settingsProvider.notifier).toggleDarkMode();
            },
          ),
          const Divider(),
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: Text('Apariencia de Asignaturas', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ),
          ListTile(
            title: const Text('Modo de Vista'),
            subtitle: const Text('Lista o Cuadrícula'),
            trailing: DropdownButton<String>(
              value: settings.subjectViewMode,
              onChanged: (String? newValue) {
                if (newValue != null) {
                  ref.read(settingsProvider.notifier).setSubjectViewMode(newValue);
                }
              },
              items: <String>['lista', 'cuadricula'].map<DropdownMenuItem<String>>((String value) {
                return DropdownMenuItem<String>(
                  value: value,
                  child: Text(value == 'lista' ? 'Lista' : 'Cuadrícula'),
                );
              }).toList(),
            ),
          ),
          SwitchListTile(
            title: const Text('Modo Compacto'),
            subtitle: const Text('Muestra las asignaturas ocupando menos espacio'),
            value: settings.isCompactList,
            onChanged: (bool value) {
              ref.read(settingsProvider.notifier).setIsCompactList(value);
            },
          ),
          if (settings.subjectViewMode == 'cuadricula') ...[
            ListTile(
              title: const Text('Columnas en Cuadrícula'),
              subtitle: const Text('Cantidad de cursos por fila'),
              trailing: DropdownButton<int>(
                value: settings.gridCrossAxisCount,
                onChanged: (int? newValue) {
                  if (newValue != null) {
                    ref.read(settingsProvider.notifier).setGridCrossAxisCount(newValue);
                  }
                },
                items: <int>[2, 3].map<DropdownMenuItem<int>>((int value) {
                  return DropdownMenuItem<int>(
                    value: value,
                    child: Text(value.toString()),
                  );
                }).toList(),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Previsualización:', style: TextStyle(fontSize: 12, color: Colors.grey)),
                  const SizedBox(height: 8),
                  Row(
                    children: List.generate(settings.gridCrossAxisCount, (index) {
                      return Expanded(
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          height: settings.isCompactList ? 40 : 80,
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primary.withOpacity(0.1 + (index * 0.1)),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Theme.of(context).colorScheme.primary.withOpacity(0.5)),
                          ),
                          alignment: Alignment.center,
                          child: Text('Ramo \${index + 1}', style: const TextStyle(fontSize: 10)),
                        ),
                      );
                    }),
                  ),
                ],
              ),
            ),
          ],
          const Divider(),
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: Text('Color de la App', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ),
          ListTile(
            leading: Icon(Icons.color_lens, color: settings.tertiaryColor != null ? Color(settings.tertiaryColor!) : null),
            title: const Text('Color Destacado (Terciario)'),
            subtitle: const Text('Personaliza el color de acento principal'),
            trailing: settings.tertiaryColor != null
                ? IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () => ref.read(settingsProvider.notifier).setTertiaryColor(null),
                  )
                : null,
            onTap: () async {
              Color newColor = await showColorPickerDialog(
                context,
                settings.tertiaryColor != null ? Color(settings.tertiaryColor!) : Colors.blue,
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
              ref.read(settingsProvider.notifier).setTertiaryColor(newColor.value);
            },
          ),
          const Divider(),
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: Text('Icono de la App', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ),
          ListTile(
            leading: const Icon(Icons.apps),
            title: const Text('Clásico'),
            onTap: () => _changeIcon(null),
          ),
          ListTile(
            leading: const Icon(Icons.apps_outage),
            title: const Text('Minimalista (Nuevo)'),
            onTap: () => _changeIcon('com.example.notas.Icon2'),
          ),
        ],
      ),
    );
  }
}
