import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app_info_view.dart';
import 'settings/appearance_settings_view.dart';
import 'settings/notifications_settings_view.dart';
import 'settings/data_settings_view.dart';
import 'package:url_launcher/url_launcher.dart';

class SettingsView extends ConsumerWidget {
  const SettingsView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Configuración', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: ListView(
        children: [
          const SizedBox(height: 10),
          ListTile(
            leading: const Icon(Icons.palette),
            title: const Text('Apariencia'),
            subtitle: const Text('Tema, colores y el icono de la app'),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const AppearanceSettingsView()));
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.notifications),
            title: const Text('Notificaciones y Alertas'),
            subtitle: const Text('Permisos y tiempos de recordatorio'),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const NotificationsSettingsView()));
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.storage),
            title: const Text('Datos y Almacenamiento'),
            subtitle: const Text('Copias de seguridad y sistema de notas'),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const DataSettingsView()));
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.info),
            title: const Text('Acerca de Notas'),
            subtitle: const Text('Versión, novedades y política de privacidad'),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const AppInfoView()));
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.favorite, color: Colors.red),
            title: const Text('Apoyar el Proyecto'),
            subtitle: const Text('Invítame un café ☕'),
            onTap: () {
              showDialog(
                context: context,
                builder: (context) {
                  return Dialog(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    elevation: 0,
                    backgroundColor: Colors.transparent,
                    child: Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface,
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [
                          BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 20, offset: const Offset(0, 10)),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.blue.withValues(alpha: 0.1),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.favorite, color: Colors.blue, size: 48),
                          ),
                          const SizedBox(height: 20),
                          const Text(
                            '¡Apoya el Desarrollo!',
                            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'NotasApp es un proyecto gratuito y sin publicidad hecho por un estudiante para estudiantes.\n\n'
                            'Si la app te ha sido útil para organizar tus estudios y quieres apoyar el tiempo invertido en desarrollarla, te agradecería muchísimo una pequeña donación voluntaria.\n\n'
                            '¡Cualquier aporte me ayuda un montón! ❤️',
                            style: TextStyle(fontSize: 15, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.8), height: 1.4),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 28),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.blue,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                elevation: 0,
                              ),
                              onPressed: () async {
                                final uri = Uri.parse('https://link.mercadopago.cl/donacionappnotas');
                                if (await canLaunchUrl(uri)) {
                                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                                }
                                if (context.mounted) Navigator.pop(context);
                              },
                              child: const Text('Donar con MercadoPago', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: Text('Quizás más tarde', style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6))),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }
}
