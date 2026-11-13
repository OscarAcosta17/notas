import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../services/database_helper.dart';
import '../../theme/expressive_widgets.dart';
import '../../viewmodels/settings_provider.dart';

class DataSettingsView extends ConsumerStatefulWidget {
  const DataSettingsView({super.key});

  @override
  ConsumerState<DataSettingsView> createState() => _DataSettingsViewState();
}

class _DataSettingsViewState extends ConsumerState<DataSettingsView> {
  String _cacheSizeStr = 'Calculando...';

  @override
  void initState() {
    super.initState();
    _calculateCacheSize();
  }

  Future<void> _calculateCacheSize() async {
    try {
      final dir = await getTemporaryDirectory();
      int totalSize = 0;
      if (dir.existsSync()) {
        dir.listSync(recursive: true, followLinks: false).forEach((FileSystemEntity entity) {
          if (entity is File) {
            totalSize += entity.lengthSync();
          }
        });
      }

      if (mounted) {
        setState(() {
          if (totalSize < 1024) {
            _cacheSizeStr = '$totalSize B';
          } else if (totalSize < 1024 * 1024) {
            _cacheSizeStr = '${(totalSize / 1024).toStringAsFixed(1)} KB';
          } else {
            _cacheSizeStr = '${(totalSize / (1024 * 1024)).toStringAsFixed(2)} MB';
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _cacheSizeStr = 'Desconocido');
      }
    }
  }

  Future<void> _clearCache() async {
    try {
      final dir = await getTemporaryDirectory();
      if (dir.existsSync()) {
        dir.listSync(recursive: true, followLinks: false).forEach((FileSystemEntity entity) {
          if (entity is File) {
            entity.deleteSync();
          }
        });
      }
      await _calculateCacheSize();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Caché limpiada correctamente.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al limpiar caché: $e')),
        );
      }
    }
  }

  Future<void> _exportBackup() async {
    try {
      final path = await DatabaseHelper.instance.exportDatabase();
      await Share.shareXFiles([XFile(path)], text: 'Copia de Seguridad de NotasApp');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Menú para compartir o guardar abierto.')),
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
      FilePickerResult? result = await FilePicker.pickFiles();
      if (result != null) {
        String? filePath = result.files.single.path;
        if (filePath != null) {
          await DatabaseHelper.instance.importDatabase(filePath);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Copia de seguridad restaurada. Por favor reinicia la app.')),
            );
          }
        }
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
    final scheme = Theme.of(context).colorScheme;
    final topInset = MediaQuery.paddingOf(context).top + kToolbarHeight;
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;

    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: scheme.surface,
      appBar: const FrostedAppBar(
        title: Text('Datos y Almacenamiento'),
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(0, topInset + 8, 0, 28 + bottomInset),
        children: [
          const ExpressiveSectionHeader(title: 'Sistema de Notas'),
          RadioGroup<String>(
            groupValue: settings.escalaNotas,
            onChanged: (String? value) {
              if (value != null) {
                ref.read(settingsProvider.notifier).setEscalaNotas(value);
              }
            },
            child: const ExpressiveGroupedSection(
              children: [
                RadioListTile<String>(
                  title: Text('Escala 1 al 7', style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text('Nota mínima sugerida: 4.0'),
                  value: '1 a 7',
                ),
                RadioListTile<String>(
                  title: Text('Escala 0 al 100', style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text('Nota mínima sugerida: 55.0'),
                  value: '0 a 100',
                ),
              ],
            ),
          ),
          const ExpressiveSectionHeader(title: 'Copias de Seguridad'),
          ExpressiveGroupedSection(
            children: [
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                leading: const TonalIconBadge(icon: Icons.upload_file_rounded),
                title: const Text('Exportar Datos', style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: const Text('Guardar una copia de seguridad en Descargas'),
                onTap: _exportBackup,
              ),
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                leading: const TonalIconBadge(icon: Icons.download_rounded),
                title: const Text('Importar Datos', style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: const Text('Restaurar desde una copia previa'),
                onTap: _importBackup,
              ),
            ],
          ),
          const ExpressiveSectionHeader(title: 'Almacenamiento'),
          ExpressiveGroupedSection(
            children: [
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                leading: const TonalIconBadge(icon: Icons.cleaning_services_rounded),
                title: const Text('Limpiar Caché', style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text('Archivos temporales (imágenes, actualizadores): $_cacheSizeStr'),
                onTap: _clearCache,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
