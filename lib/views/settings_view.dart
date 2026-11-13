import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/app_theme.dart';
import '../theme/expressive_widgets.dart';
import 'app_info_view.dart';
import 'settings/appearance_settings_view.dart';
import 'settings/data_settings_view.dart';
import 'settings/notifications_settings_view.dart';

class SettingsView extends ConsumerWidget {
  const SettingsView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final topInset = MediaQuery.paddingOf(context).top + kToolbarHeight;
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;

    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: scheme.surface,
      appBar: const FrostedAppBar(
        title: Text('Configuración'),
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(0, topInset + 8, 0, 28 + bottomInset),
        children: [
          const ExpressiveSectionHeader(title: 'Personalización'),
          ExpressiveGroupedSection(
            children: [
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                leading: const TonalIconBadge(icon: Icons.palette_rounded),
                title: const Text('Apariencia', style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: const Text('Tema, Material You, cristal e icono'),
                trailing: Icon(Icons.chevron_right_rounded, color: scheme.onSurfaceVariant),
                onTap: () {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const AppearanceSettingsView()));
                },
              ),
            ],
          ),
          const ExpressiveSectionHeader(title: 'Alertas y Datos'),
          ExpressiveGroupedSection(
            children: [
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                leading: const TonalIconBadge(icon: Icons.notifications_rounded),
                title: const Text('Notificaciones y Alertas', style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: const Text('Permisos, sonidos y tiempos de recordatorio'),
                trailing: Icon(Icons.chevron_right_rounded, color: scheme.onSurfaceVariant),
                onTap: () {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const NotificationsSettingsView()));
                },
              ),
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                leading: const TonalIconBadge(icon: Icons.storage_rounded),
                title: const Text('Datos y Almacenamiento', style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: const Text('Copias de seguridad, caché y escala de notas'),
                trailing: Icon(Icons.chevron_right_rounded, color: scheme.onSurfaceVariant),
                onTap: () {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const DataSettingsView()));
                },
              ),
            ],
          ),
          const ExpressiveSectionHeader(title: 'Aplicación'),
          ExpressiveGroupedSection(
            children: [
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                leading: const TonalIconBadge(icon: Icons.info_rounded),
                title: const Text('Acerca de Notas', style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: const Text('Versión, novedades y política de privacidad'),
                trailing: Icon(Icons.chevron_right_rounded, color: scheme.onSurfaceVariant),
                onTap: () {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const AppInfoView()));
                },
              ),
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                leading: const TonalIconBadge(icon: Icons.favorite_rounded, color: Colors.red),
                title: const Text('Apoyar el Proyecto', style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: const Text('Invítame un café ☕ (Toca para donar)'),
                trailing: Icon(Icons.chevron_right_rounded, color: scheme.onSurfaceVariant),
                onTap: () => _showDonationDialog(context),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showDonationDialog(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    showDialog(
      context: context,
      builder: (dialogContext) {
        return Dialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          child: FrostedGlassSurface(
            borderRadius: BorderRadius.circular(AppTheme.radiusExtraLarge),
            baseColor: scheme.surfaceContainerHigh,
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.blue.withValues(alpha: 0.14),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.favorite_rounded, color: Colors.blue, size: 44),
                ),
                const SizedBox(height: 18),
                const Text(
                  '¡Apoya el Desarrollo!',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  'NotasApp es un proyecto gratuito y sin publicidad hecho por un estudiante para estudiantes.\n\n'
                  'Si la app te ha sido útil para organizar tus estudios y quieres apoyar el tiempo invertido en desarrollarla, te agradecería muchísimo una pequeña donación voluntaria.\n\n'
                  '¡Cualquier aporte me ayuda un montón! ❤️',
                  style: TextStyle(
                    fontSize: 14.5,
                    color: scheme.onSurfaceVariant,
                    height: 1.45,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onPressed: () async {
                      final uri = Uri.parse('https://link.mercadopago.cl/donacionappnotas');
                      try {
                        await launchUrl(uri, mode: LaunchMode.externalApplication);
                      } catch (e) {
                        debugPrint('No se pudo abrir el enlace: $e');
                      }
                      if (dialogContext.mounted) Navigator.pop(dialogContext);
                    },
                    child: const Text('Donar con MercadoPago', style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700)),
                  ),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: Text('Quizás más tarde', style: TextStyle(color: scheme.onSurfaceVariant)),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
