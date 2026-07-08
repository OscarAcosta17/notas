import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/evaluacion.dart';
import '../models/clase_horario.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _notificationsPlugin = FlutterLocalNotificationsPlugin();

  static Future<void> initialize() async {
    tz.initializeTimeZones();
    const AndroidInitializationSettings initializationSettingsAndroid = AndroidInitializationSettings('@mipmap/launcher_icon');
    const InitializationSettings initializationSettings = InitializationSettings(android: initializationSettingsAndroid);
    await _notificationsPlugin.initialize(settings: initializationSettings);
  }

  static Future<bool> requestPermissions() async {
    final statusNotif = await Permission.notification.request();
    final statusAlarm = await Permission.scheduleExactAlarm.request();
    return statusNotif.isGranted && (statusAlarm.isGranted || statusAlarm.isRestricted); // Restricted might mean it's not applicable or already allowed by default on older OS
  }

  static Future<void> showInstantNotification(String title, String body) async {
    const androidDetails = AndroidNotificationDetails(
      'update_channel',
      'Actualizaciones',
      channelDescription: 'Notificaciones sobre actualizaciones de la aplicación',
      importance: Importance.max,
      priority: Priority.high,
    );
    const details = NotificationDetails(android: androidDetails);
    
    // Usar un ID arbitrario alto para evitar colisión con los recordatorios
    await _notificationsPlugin.show(
      id: 9999,
      title: title,
      body: body,
      notificationDetails: details,
    );
  }

  static Future<void> scheduleEvaluationReminder(Evaluacion ev, String ramoNombre) async {
    if (ev.fecha == null || ev.id == null) return;
    
    final prefs = await SharedPreferences.getInstance();
    final horasAntes = prefs.getInt('horasAntesEvaluacion') ?? 24;

    // Configured reminder
    final scheduleTime = ev.fecha!.subtract(Duration(hours: horasAntes));
    if (scheduleTime.isAfter(DateTime.now())) {
      await _scheduleSpecific(
        id: (ev.id! * 100) + 1, // Unique ID derived from eval ID
        title: 'Próxima Evaluación ($horasAntes hrs)',
        body: 'Tienes una evaluación de $ramoNombre: ${ev.nombre}',
        scheduledDate: tz.TZDateTime.from(scheduleTime, tz.local),
      );
    } else {
      // Si ya pasó el tiempo de aviso, revisar si la evaluación es en el futuro cercano (e.g. hoy)
      // Si la evaluación es hoy, y no ha pasado, avisar de inmediato
      if (ev.fecha!.isAfter(DateTime.now())) {
         await showInstantNotification('Próxima Evaluación', 'Tienes una evaluación inminente de $ramoNombre: ${ev.nombre}');
      }
    }
  }

  static Future<void> cancelEvaluationReminder(int evalId) async {
    await _notificationsPlugin.cancel(id: (evalId * 100) + 1);
    await _notificationsPlugin.cancel(id: (evalId * 100) + 2);
  }

  static Future<void> _scheduleSpecific({
    required int id,
    required String title,
    required String body,
    required tz.TZDateTime scheduledDate,
  }) async {
    const androidPlatformChannelSpecifics = AndroidNotificationDetails(
      'evaluations_channel_id',
      'Recordatorios de Evaluaciones',
      channelDescription: 'Canal para recordatorios',
      importance: Importance.max,
      priority: Priority.high,
    );
    const platformChannelSpecifics = NotificationDetails(android: androidPlatformChannelSpecifics);

    await _notificationsPlugin.zonedSchedule(
      id: id,
      title: title,
      body: body,
      scheduledDate: scheduledDate,
      notificationDetails: platformChannelSpecifics,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
    );
  }

  static Future<void> scheduleClassReminder(ClaseHorario clase) async {
    if (clase.id == null) return;

    // Calcular la hora según el bloque (1-2 => 8:15, 3-4 => 9:40...)
    // tuple (hour, minute)
    final blockTimes = {
      1: [8, 15],
      3: [9, 40],
      5: [11, 5],
      7: [12, 30],
      9: [14, 40],
      11: [16, 5],
      13: [17, 30],
      15: [18, 55],
    };

    final time = blockTimes[clase.bloque] ?? [8, 0];
    
    final prefs = await SharedPreferences.getInstance();
    final minutosAntes = prefs.getInt('minutosAntesClase') ?? 15;

    // Calcular hora de notificación
    int hour = time[0];
    int minute = time[1] - minutosAntes;
    while (minute < 0) {
      hour -= 1;
      minute += 60;
    }
    if (hour < 0) hour = 0; // Prevent invalid hours

    // Find the next occurrence of this day of the week
    tz.TZDateTime now = tz.TZDateTime.now(tz.local);
    tz.TZDateTime scheduledDate = tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    
    if (scheduledDate.weekday == clase.diaSemana && scheduledDate.isBefore(now)) {
       // Revisa si la clase en sí (hora original) todavía no termina
       final originalStart = scheduledDate.add(Duration(minutes: minutosAntes));
       final blockEnd = originalStart.add(const Duration(minutes: 70)); // Bloque dura 1h 10m
       
       if (now.isBefore(blockEnd)) {
         // La clase está por empezar o en curso hoy mismo! Lanzar alerta inmediata.
         await showInstantNotification('¡Clase hoy!', '${clase.subjectName} en sala ${clase.sala}');
       }
       // Y dejar que scheduledDate avance a la próxima semana
       scheduledDate = scheduledDate.add(const Duration(days: 7));
    } else {
      while (scheduledDate.weekday != clase.diaSemana || scheduledDate.isBefore(now)) {
        scheduledDate = scheduledDate.add(const Duration(days: 1));
      }
    }

    const androidPlatformChannelSpecifics = AndroidNotificationDetails(
      'clases_channel_id',
      'Recordatorios de Clases',
      channelDescription: 'Canal para recordatorios de horario',
      importance: Importance.max,
      priority: Priority.high,
    );
    const platformChannelSpecifics = NotificationDetails(android: androidPlatformChannelSpecifics);

    await _notificationsPlugin.zonedSchedule(
      id: (clase.id! * 1000) + 3, // Unique ID for class
      title: 'Clase en $minutosAntes minutos',
      body: '${clase.subjectName} en sala ${clase.sala}',
      scheduledDate: scheduledDate,
      notificationDetails: platformChannelSpecifics,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime, // Repeats weekly
    );
  }
  
  static Future<void> cancelClassReminder(int claseId) async {
    await _notificationsPlugin.cancel(id: (claseId * 1000) + 3);
  }
}
