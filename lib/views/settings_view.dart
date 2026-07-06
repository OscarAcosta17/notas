import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_dynamic_icon_plus/flutter_dynamic_icon_plus.dart';
import '../viewmodels/settings_provider.dart';
import '../services/notification_service.dart';
import '../services/database_helper.dart';
import 'package:share_plus/share_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import 'app_info_view.dart';

class SettingsView extends ConsumerStatefulWidget {
  const SettingsView({super.key});

  @override
  ConsumerState<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends ConsumerState<SettingsView> {
  Future<void> _exportDatabase() async {
    try {
      final dbPath = await DatabaseHelper.instance.getDatabasePath();
      // ignore: deprecated_member_use
      await Share.shareXFiles([XFile(dbPath)], text: 'Copia de seguridad de NotasApp (NotasDB.db)');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error al exportar: $e')));
      }
    }
  }

  Future<void> _importDatabase() async {
    try {
      FilePickerResult? result = await FilePicker.pickFiles(
        type: FileType.any,
      );

      if (result != null && result.files.single.path != null) {
        File sourceFile = File(result.files.single.path!);
        if (!sourceFile.path.endsWith('.db')) {
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Por favor, selecciona un archivo .db válido.')));
          return;
        }
        
        final dbPath = await DatabaseHelper.instance.getDatabasePath();
        await sourceFile.copy(dbPath);
        
        if (mounted) {
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (context) => AlertDialog(
              title: const Text('Copia Restaurada'),
              content: const Text('La copia de seguridad se ha restaurado con éxito. Por favor, reinicia la aplicación para cargar los nuevos datos.'),
              actions: [
                TextButton(
                  onPressed: () => exit(0),
                  child: const Text('Cerrar App'),
                )
              ],
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error al importar: $e')));
      }
    }
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
                const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Text('Datos', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
                ListTile(
                  leading: const Icon(Icons.upload_file),
                  title: const Text('Exportar Copia de Seguridad'),
                  subtitle: const Text('Guarda tus notas y ramos en un archivo'),
                  onTap: _exportDatabase,
                ),
                ListTile(
                  leading: const Icon(Icons.download),
                  title: const Text('Importar Copia de Seguridad'),
                  subtitle: const Text('Restaura un archivo de copia de seguridad anterior'),
                  onTap: _importDatabase,
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.info),
                  title: const Text('Acerca de Notas'),
                  subtitle: const Text('Versión, Actualizaciones, Novedades y Privacidad'),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const AppInfoView()),
                    );
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
                ListTile(
                  leading: const Icon(Icons.bug_report),
                  title: const Text('Probar Notificaciones'),
                  subtitle: const Text('Lanzar una notificación de prueba ahora'),
                  onTap: () {
                    NotificationService.showInstantNotification('Prueba', '¡Las notificaciones funcionan correctamente!');
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
