import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../services/updater_service.dart';
import '../theme/app_theme.dart';
import '../theme/expressive_widgets.dart';
import '../viewmodels/settings_provider.dart';
import 'bug_report_sheet.dart';

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
    if (mounted) {
      setState(() {
        _version = 'v${info.version}+${info.buildNumber}';
      });
    }
  }

  void _showNovedades() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Novedades (v1.2.4)'),
        content: const SingleChildScrollView(
          child: Text(
            '• 💻 App de Escritorio Nativa para Windows: Ejecuta NotasApp directamente en tu PC con base de datos SQLite local independiente, soporte táctil/mouse completo y actualizaciones automáticas multiplataforma.\n'
            '• ☁️ Sincronización con Google Drive (Obsidian Sync): Vincula tu cuenta mediante ogd.richardxiong.com y sincroniza tus ramos, notas, horario y ajustes en tu carpeta NotasApp de Drive entre Android y Windows.\n'
            '• 🔐 Nube Alternativa y Carpeta Local: Soporta también GitHub Secret Gist en 1 clic, carpetas sincronizadas (Drive Desktop / OneDrive) y paquetes portables notas_sync_bundle.json.\n'
            '• 🎨 4 Nuevos Iconos Android 17 (6 Opciones en Total): Elige entre Clásico, Minimalista, Cristal A+, Cápsulas M3, Libreta Glass y Material You Dúotono en Ajustes ➔ Apariencia.\n'
            '• 🐛 Sistema de Reporte de Fallos y Tickets en GitHub: Captura automática de errores en segundo plano y formulario integrado para levantar Issues en GitHub con ficha técnica de Android o Windows.',
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cerrar'),
          ),
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
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final topInset = MediaQuery.paddingOf(context).top + kToolbarHeight;
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;

    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: scheme.surface,
      appBar: const FrostedAppBar(
        title: Text('Acerca de Notas'),
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(0, topInset + 12, 0, 28 + bottomInset),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(AppTheme.radiusExtraLarge),
                border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.45)),
              ),
              child: Column(
                children: [
                  Consumer(
                    builder: (context, ref, _) {
                      final appIcon = ref.watch(settingsProvider).appIcon;
                      final assetPath = switch (appIcon) {
                        'icon2' => 'assets/icon2.png',
                        'icon3' => 'assets/icon_a17_cristal.png',
                        'icon4' => 'assets/icon_a17_capsulas.png',
                        'icon5' => 'assets/icon_a17_libreta.png',
                        'icon6' => 'assets/icon_a17_tonal.png',
                        _ => 'assets/icon.jpg',
                      };
                      return ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: Image.asset(
                          assetPath,
                          width: 72,
                          height: 72,
                          fit: BoxFit.cover,
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'NotasApp',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(AppTheme.radiusFull),
                    ),
                    child: Text(
                      _version,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const ExpressiveSectionHeader(title: 'Información y Actualizaciones'),
          ExpressiveGroupedSection(
            children: [
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                leading: const TonalIconBadge(icon: Icons.system_update_rounded),
                title: const Text('Buscar Actualizaciones', style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: const Text('Verifica si hay una nueva versión disponible'),
                onTap: () {
                  UpdaterService.checkForUpdates(context);
                },
              ),
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                leading: const TonalIconBadge(icon: Icons.new_releases_rounded),
                title: const Text('Novedades', style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: const Text('Descubre qué ha cambiado en esta versión'),
                onTap: _showNovedades,
              ),
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                leading: const TonalIconBadge(icon: Icons.bug_report_rounded),
                title: const Text('Reportar un Fallo o Sugerencia', style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: const Text('Levanta un ticket en GitHub con diagnóstico automático'),
                onTap: () => showBugReportSheet(context),
              ),
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                leading: const TonalIconBadge(icon: Icons.privacy_tip_rounded),
                title: const Text('Política de Privacidad', style: TextStyle(fontWeight: FontWeight.w600)),
                onTap: _showPrivacyPolicy,
              ),
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                leading: const TonalIconBadge(icon: Icons.article_rounded),
                title: const Text('Licencias', style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: const Text('Software de terceros y dependencias'),
                onTap: () {
                  showLicensePage(
                    context: context,
                    applicationName: 'NotasApp',
                    applicationVersion: _version,
                    applicationIcon: const Padding(
                      padding: EdgeInsets.all(8.0),
                      child: TonalIconBadge(icon: Icons.book_rounded, size: 56),
                    ),
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}
