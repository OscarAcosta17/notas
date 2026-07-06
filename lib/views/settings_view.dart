import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../viewmodels/settings_provider.dart';

class SettingsView extends ConsumerWidget {
  const SettingsView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Configuración'),
      ),
      body: ListView(
        children: [
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
          ListTile(
            title: const Text('Escala de Notas'),
            subtitle: const Text('Define los límites y validaciones de notas'),
            trailing: DropdownButton<String>(
              value: settings.escalaNotas,
              items: <String>['1 a 7', '0 a 100'].map((String value) {
                return DropdownMenuItem<String>(
                  value: value,
                  child: Text(value),
                );
              }).toList(),
              onChanged: (String? newValue) {
                if (newValue != null) {
                  ref.read(settingsProvider.notifier).setEscalaNotas(newValue);
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}
