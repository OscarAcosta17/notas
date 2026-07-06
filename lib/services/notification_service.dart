import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:permission_handler/permission_handler.dart';
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
    
    // 24 horas antes
    final scheduleTime24 = ev.fecha!.subtract(const Duration(hours: 24));
    if (scheduleTime24.isAfter(DateTime.now())) {
      await _scheduleSpecific(
        id: (ev.id! * 100) + 1, // Unique ID derived from eval ID
        title: 'Próxima Evaluación (Mañana)',
        body: 'Tienes una evaluación de $ramoNombre: ${ev.nombre}',
        scheduledDate: tz.TZDateTime.from(scheduleTime24, tz.local),
      );
    }

    // 12 horas antes
    final scheduleTime12 = ev.fecha!.subtract(const Duration(hours: 12));
    if (scheduleTime12.isAfter(DateTime.now())) {
      await _scheduleSpecific(
        id: (ev.id! * 100) + 2,
        title: 'Próxima Evaluación (12 hrs)',
        body: 'Tienes una evaluación de $ramoNombre: ${ev.nombre}',
        scheduledDate: tz.TZDateTime.from(scheduleTime12, tz.local),
      );
    }
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
    // 15 minutos antes
    int hour = time[0];
    int minute = time[1] - 15;
    if (minute < 0) {
      hour -= 1;
      minute += 60;
    }

    // Find the next occurrence of this day of the week
    tz.TZDateTime now = tz.TZDateTime.now(tz.local);
    tz.TZDateTime scheduledDate = tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    
    // clase.diaSemana: 1=Lunes, 7=Domingo (Igual que DateTime.weekday)
    while (scheduledDate.weekday != clase.diaSemana || scheduledDate.isBefore(now)) {
      scheduledDate = scheduledDate.add(const Duration(days: 1));
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
      title: 'Clase en 15 minutos',
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
