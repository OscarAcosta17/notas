import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../viewmodels/settings_provider.dart';
import '../../services/notification_service.dart';

import '../../services/sound_service.dart';

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
        _availableSounds = sounds.isNotEmpty ? sounds : ['clase_sound', 'eval_sound']; // Fallback in case list is completely empty
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notificaciones y Alertas'),
      ),
      body: ListView(
        children: [
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: Text('Tiempos de Aviso', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ),
          ListTile(
            title: const Text('Recordatorio de Clases'),
            subtitle: const Text('Minutos antes de cada bloque del horario'),
            trailing: DropdownButton<int>(
              value: settings.minutosAntesClase,
              items: <int>[5, 10, 15, 30, 60].map((int value) {
                return DropdownMenuItem<int>(
                  value: value,
                  child: Text('$value min'),
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
            title: const Text('Recordatorio de Evaluaciones'),
            subtitle: const Text('Horas antes de una prueba o certamen'),
            trailing: DropdownButton<int>(
              value: settings.horasAntesEvaluacion,
              items: <int>[1, 2, 12, 24, 48].map((int value) {
                return DropdownMenuItem<int>(
                  value: value,
                  child: Text('$value hrs'),
                );
              }).toList(),
              onChanged: (int? newValue) {
                if (newValue != null) {
                  ref.read(settingsProvider.notifier).setHorasAntesEvaluacion(newValue);
                }
              },
            ),
          ),
          const Divider(),
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: Text('Sonidos (Requiere reiniciar)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ),
          if (_isLoading)
            const Center(child: CircularProgressIndicator())
          else ...[
            ListTile(
              title: const Text('Sonido para Clases'),
              subtitle: Text(settings.selectedClassSound),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.play_arrow),
                    onPressed: () {
                      NotificationService.showTestSoundNotification('Prueba de Clase', 'Sonido: ${settings.selectedClassSound}', settings.selectedClassSound);
                    },
                  ),
                  DropdownButton<String>(
                    value: _availableSounds.contains(settings.selectedClassSound) ? settings.selectedClassSound : _availableSounds.first,
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
              title: const Text('Sonido para Evaluaciones'),
              subtitle: Text(settings.selectedEvalSound),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.play_arrow),
                    onPressed: () {
                      NotificationService.showTestSoundNotification('Prueba de Eval', 'Sonido: ${settings.selectedEvalSound}', settings.selectedEvalSound);
                    },
                  ),
                  DropdownButton<String>(
                    value: _availableSounds.contains(settings.selectedEvalSound) ? settings.selectedEvalSound : _availableSounds.first,
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
          const Divider(),
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: Text('Permisos y Pruebas', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ),
          ListTile(
            leading: const Icon(Icons.notifications_active),
            title: const Text('Permisos de Notificación'),
            subtitle: const Text('Otorgar permisos para recibir alertas'),
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
    );
  }
}
