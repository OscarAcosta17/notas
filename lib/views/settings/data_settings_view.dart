import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../viewmodels/settings_provider.dart';
import '../../services/database_helper.dart';

class DataSettingsView extends ConsumerStatefulWidget {
  const DataSettingsView({super.key});

  @override
  ConsumerState<DataSettingsView> createState() => _DataSettingsViewState();
}

class _DataSettingsViewState extends ConsumerState<DataSettingsView> {
  Future<void> _exportBackup() async {
    try {
      final path = await DatabaseHelper.instance.exportDatabase();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Copia de seguridad guardada en Descargas:\n$path')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al exportar: $e')),
        );
      }
    }
  }

  Future<void> _importBackup() async {
    try {
      await DatabaseHelper.instance.importDatabase();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Copia de seguridad restaurada. Por favor reinicia la app.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al importar: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Datos y Almacenamiento'),
      ),
      body: ListView(
        children: [
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: Text('Sistema de Notas', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ),
          RadioListTile<String>(
            title: const Text('Escala 1 al 7'),
            value: '1 a 7',
            groupValue: settings.escalaNotas,
            activeColor: Theme.of(context).colorScheme.primary,
            onChanged: (String? value) {
              if (value != null) ref.read(settingsProvider.notifier).setEscalaNotas(value);
            },
          ),
          RadioListTile<String>(
            title: const Text('Escala 0 al 100'),
            value: '0 a 100',
            groupValue: settings.escalaNotas,
            activeColor: Theme.of(context).colorScheme.primary,
            onChanged: (String? value) {
              if (value != null) ref.read(settingsProvider.notifier).setEscalaNotas(value);
            },
          ),
          const Divider(),
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: Text('Copias de Seguridad', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ),
          ListTile(
            leading: const Icon(Icons.upload_file),
            title: const Text('Exportar Datos'),
            subtitle: const Text('Guardar una copia de seguridad en Descargas'),
            onTap: _exportBackup,
          ),
          ListTile(
            leading: const Icon(Icons.download),
            title: const Text('Importar Datos'),
            subtitle: const Text('Restaurar desde una copia previa'),
            onTap: _importBackup,
          ),
        ],
      ),
    );
  }
}
