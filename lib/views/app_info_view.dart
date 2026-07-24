import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../services/updater_service.dart';

class AppInfoView extends StatefulWidget {
  const AppInfoView({super.key});

  @override
  State<AppInfoView> createState() => _AppInfoViewState();
}

class _AppInfoViewState extends State<AppInfoView> {
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

  void _showNovedades() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Novedades (v1.1.4)'),
        content: const SingleChildScrollView(
          child: Text(
            '• Imagen de Horario: Ahora puedes exportar tu horario como una imagen para compartir.\n'
            '• Interruptor de Notificaciones: Nuevo botón para apagar/encender todas las notificaciones de golpe.\n'
            '• Limpiar Caché: Desde Datos puedes borrar archivos temporales y optimizar memoria.\n'
            '• Exportar a App: Al exportar archivos (.ics) puedes elegir abrirlos directo en tu calendario.\n'
            '• Modificar Semestres: Mantén presionado un semestre para renombrarlo o borrarlo por completo.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cerrar'),
          )
        ],
      ),
    );
  }

  void _showPrivacyPolicy() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Política de Privacidad'),
        content: const SingleChildScrollView(
          child: Text(
            'Todos tus datos (notas, ramos y configuraciones) se guardan de manera estrictamente local en tu dispositivo.\n\n'
            'La aplicación se conecta a internet únicamente para buscar y descargar nuevas versiones desde GitHub.\n\n'
            'Ninguna de tu información académica o personal es recopilada ni transmitida a servidores externos.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cerrar'),
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Acerca de Notas'),
      ),
      body: ListView(
        children: [
          const SizedBox(height: 20),
          Center(
            child: Icon(
              Icons.book,
              size: 80,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(height: 10),
          Center(
            child: Text(
              'NotasApp',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
          ),
          Center(
            child: Text(
              _version,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
            ),
          ),
          const SizedBox(height: 30),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.system_update),
            title: const Text('Buscar Actualizaciones'),
            subtitle: const Text('Verifica si hay una nueva versión disponible'),
            onTap: () {
              UpdaterService.checkForUpdates(context);
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.new_releases),
            title: const Text('Novedades'),
            subtitle: const Text('Descubre qué ha cambiado en esta versión'),
            onTap: _showNovedades,
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.privacy_tip),
            title: const Text('Política de Privacidad'),
            onTap: _showPrivacyPolicy,
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.article),
            title: const Text('Licencias'),
            subtitle: const Text('Software de terceros y dependencias'),
            onTap: () {
              showLicensePage(
                context: context,
                applicationName: 'NotasApp',
                applicationVersion: _version,
                applicationIcon: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Icon(Icons.book, size: 64, color: Theme.of(context).colorScheme.primary),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
