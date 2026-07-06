import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:flutter_dynamic_icon_plus/flutter_dynamic_icon_plus.dart';
import '../viewmodels/settings_provider.dart';
import '../services/updater_service.dart';
import '../services/notification_service.dart';

class SettingsView extends ConsumerStatefulWidget {
  const SettingsView({super.key});

  @override
  ConsumerState<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends ConsumerState<SettingsView> {
  String _version = 'Cargando...';

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    final info = await PackageInfo.fromPlatform();
    setState(() {
      _version = 'v${info.version}+${info.buildNumber}';
    });
  }

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
        title: const Text('Configuración'),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
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
                const Divider(),
                const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Text('Icono de la App', style: TextStyle(fontWeight: FontWeight.bold)),
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
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.system_update),
                  title: const Text('Buscar Actualizaciones'),
                  subtitle: const Text('Verifica si hay una nueva versión de la app'),
                  onTap: () {
                    UpdaterService.checkForUpdates(context);
                  },
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.notifications_active),
                  title: const Text('Permisos de Notificación'),
                  subtitle: const Text('Otorgar permisos para recibir alertas (Horario y Agenda)'),
                  onTap: () async {
                    bool granted = await NotificationService.requestPermissions();
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(granted ? 'Permisos otorgados' : 'Permisos denegados')),
                      );
                    }
                  },
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              'Versión actual: $_version',
              style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5)),
            ),
          ),
        ],
      ),
    );
  }
}
