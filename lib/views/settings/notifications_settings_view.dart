import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/notification_service.dart';
import '../../services/sound_service.dart';
import '../../theme/expressive_widgets.dart';
import '../../viewmodels/settings_provider.dart';

class NotificationsSettingsView extends ConsumerStatefulWidget {
  const NotificationsSettingsView({super.key});

  @override
  ConsumerState<NotificationsSettingsView> createState() => _NotificationsSettingsViewState();
}

class _NotificationsSettingsViewState extends ConsumerState<NotificationsSettingsView> {
  List<String> _availableSounds = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSounds();
  }

  Future<void> _loadSounds() async {
    final sounds = await SoundService.getAvailableSounds();
    if (mounted) {
      setState(() {
        _availableSounds = sounds.isNotEmpty ? sounds : ['clase_sound', 'eval_sound'];
        _isLoading = false;
      });
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
        title: Text('Notificaciones y Alertas'),
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(0, topInset + 8, 0, 28 + bottomInset),
        children: [
          const ExpressiveSectionHeader(title: 'General'),
          ExpressiveGroupedSection(
            children: [
              SwitchListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                secondary: const TonalIconBadge(icon: Icons.notifications_active_rounded),
                title: const Text('Habilitar notificaciones globales', style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: const Text('Activa o desactiva todas las alertas de la aplicación'),
                value: settings.notificationsEnabled,
                onChanged: (bool value) async {
                  final messenger = ScaffoldMessenger.of(context);
                  await ref.read(settingsProvider.notifier).setNotificationsEnabled(value);
                  if (!value) {
                    await NotificationService.cancelAll();
                    if (mounted) {
                      messenger.showSnackBar(
                        const SnackBar(content: Text('Todas las notificaciones han sido desactivadas.')),
                      );
                    }
                  } else {
                    if (mounted) {
                      messenger.showSnackBar(
                        const SnackBar(content: Text('Notificaciones activadas.')),
                      );
                    }
                  }
                },
              ),
            ],
          ),
          const ExpressiveSectionHeader(title: 'Tiempos de Aviso'),
          ExpressiveGroupedSection(
            children: [
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                leading: const TonalIconBadge(icon: Icons.schedule_rounded),
                title: const Text('Recordatorio de Clases', style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: const Text('Minutos antes de cada bloque del horario'),
                trailing: DropdownButton<int>(
                  value: settings.minutosAntesClase,
                  underline: const SizedBox.shrink(),
                  borderRadius: BorderRadius.circular(16),
                  items: <int>[5, 10, 15, 30, 60].map((int value) {
                    return DropdownMenuItem<int>(
                      value: value,
                      child: Text('$value min', style: const TextStyle(fontWeight: FontWeight.w600)),
                    );
                  }).toList(),
                  onChanged: (int? newValue) {
                    if (newValue != null) {
                      ref.read(settingsProvider.notifier).setMinutosAntesClase(newValue);
                    }
                  },
                ),
              ),
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                leading: const TonalIconBadge(icon: Icons.event_available_rounded),
                title: const Text('Recordatorio de Evaluaciones', style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: const Text('Horas antes de una prueba o certamen'),
                trailing: DropdownButton<int>(
                  value: settings.horasAntesEvaluacion,
                  underline: const SizedBox.shrink(),
                  borderRadius: BorderRadius.circular(16),
                  items: <int>[1, 2, 12, 24, 48].map((int value) {
                    return DropdownMenuItem<int>(
                      value: value,
                      child: Text('$value hrs', style: const TextStyle(fontWeight: FontWeight.w600)),
                    );
                  }).toList(),
                  onChanged: (int? newValue) {
                    if (newValue != null) {
                      ref.read(settingsProvider.notifier).setHorasAntesEvaluacion(newValue);
                    }
                  },
                ),
              ),
            ],
          ),
          const ExpressiveSectionHeader(title: 'Sonidos (Requiere reiniciar)'),
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            )
          else
            ExpressiveGroupedSection(
              children: [
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  leading: const TonalIconBadge(icon: Icons.music_note_rounded),
                  title: const Text('Sonido para Clases', style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(settings.selectedClassSound),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton.filledTonal(
                        icon: const Icon(Icons.play_arrow_rounded, size: 20),
                        onPressed: () {
                          NotificationService.showTestSoundNotification(
                            'Prueba de Clase',
                            'Sonido: ${settings.selectedClassSound}',
                            settings.selectedClassSound,
                          );
                        },
                      ),
                      const SizedBox(width: 8),
                      DropdownButton<String>(
                        value: _availableSounds.contains(settings.selectedClassSound)
                            ? settings.selectedClassSound
                            : _availableSounds.first,
                        underline: const SizedBox.shrink(),
                        borderRadius: BorderRadius.circular(16),
                        items: _availableSounds.map((String value) {
                          return DropdownMenuItem<String>(
                            value: value,
                            child: Text(value),
                          );
                        }).toList(),
                        onChanged: (String? newValue) {
                          if (newValue != null) {
                            ref.read(settingsProvider.notifier).setClassSound(newValue);
                          }
                        },
                      ),
                    ],
                  ),
                ),
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  leading: const TonalIconBadge(icon: Icons.notifications_rounded),
                  title: const Text('Sonido para Evaluaciones', style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(settings.selectedEvalSound),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton.filledTonal(
                        icon: const Icon(Icons.play_arrow_rounded, size: 20),
                        onPressed: () {
                          NotificationService.showTestSoundNotification(
                            'Prueba de Eval',
                            'Sonido: ${settings.selectedEvalSound}',
                            settings.selectedEvalSound,
                          );
                        },
                      ),
                      const SizedBox(width: 8),
                      DropdownButton<String>(
                        value: _availableSounds.contains(settings.selectedEvalSound)
                            ? settings.selectedEvalSound
                            : _availableSounds.first,
                        underline: const SizedBox.shrink(),
                        borderRadius: BorderRadius.circular(16),
                        items: _availableSounds.map((String value) {
                          return DropdownMenuItem<String>(
                            value: value,
                            child: Text(value),
                          );
                        }).toList(),
                        onChanged: (String? newValue) {
                          if (newValue != null) {
                            ref.read(settingsProvider.notifier).setEvalSound(newValue);
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          const ExpressiveSectionHeader(title: 'Permisos y Pruebas'),
          ExpressiveGroupedSection(
            children: [
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                leading: const TonalIconBadge(icon: Icons.verified_user_rounded),
                title: const Text('Permisos de Notificación', style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: const Text('Otorgar permisos para recibir alertas'),
                onTap: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  final bool granted = await NotificationService.requestPermissions();
                  if (mounted) {
                    messenger.showSnackBar(
                      SnackBar(content: Text(granted ? 'Permisos otorgados' : 'Permisos denegados')),
                    );
                  }
                },
              ),
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                leading: const TonalIconBadge(icon: Icons.bug_report_rounded),
                title: const Text('Probar Notificaciones', style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: const Text('Lanzar una notificación de prueba ahora'),
                onTap: () {
                  NotificationService.showInstantNotification(
                    'Prueba',
                    '¡Las notificaciones funcionan correctamente!',
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
