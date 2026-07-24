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

  static Future<void> cancelAll() async {
    await _notificationsPlugin.cancelAll();
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

  static Future<void> showTestSoundNotification(String title, String body, String soundName) async {
    final channelId = 'test_channel_$soundName';
    final androidDetails = AndroidNotificationDetails(
      channelId,
      'Pruebas de Sonido',
      channelDescription: 'Canal para probar sonidos',
      importance: Importance.max,
      priority: Priority.high,
      sound: RawResourceAndroidNotificationSound(soundName),
    );
    final details = NotificationDetails(android: androidDetails);
    
    await _notificationsPlugin.show(
      id: DateTime.now().millisecondsSinceEpoch.remainder(100000),
      title: title,
      body: body,
      notificationDetails: details,
    );
  }

  static Future<void> showInstantClassNotification(ClaseHorario clase) async {
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool('notificationsEnabled') ?? true;
    if (!enabled) return;
    
    final soundName = prefs.getString('selectedClassSound') ?? 'clase_sound';
    
    final androidDetails = AndroidNotificationDetails(
      'clases_channel_$soundName',
      'Recordatorios de Clases',
      channelDescription: 'Canal para recordatorios de horario',
      importance: Importance.max,
      priority: Priority.high,
      sound: RawResourceAndroidNotificationSound(soundName),
    );
    final details = NotificationDetails(android: androidDetails);
    
    await _notificationsPlugin.show(
      id: (clase.id! * 1000) + 4,
      title: '¡Clase hoy!',
      body: '${clase.subjectName} en sala ${clase.sala}',
      notificationDetails: details,
    );
  }

  static Future<void> showInstantEvalNotification(Evaluacion ev, String ramoNombre) async {
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool('notificationsEnabled') ?? true;
    if (!enabled) return;

    final soundName = prefs.getString('selectedEvalSound') ?? 'eval_sound';
    
    final androidDetails = AndroidNotificationDetails(
      'eval_channel_$soundName',
      'Recordatorios de Evaluaciones',
      channelDescription: 'Canal para recordatorios de pruebas',
      importance: Importance.max,
      priority: Priority.high,
      sound: RawResourceAndroidNotificationSound(soundName),
    );
    final details = NotificationDetails(android: androidDetails);
    
    await _notificationsPlugin.show(
      id: (ev.id! * 100) + 5,
      title: 'Próxima Evaluación',
      body: 'Tienes una evaluación inminente de $ramoNombre: ${ev.nombre}',
      notificationDetails: details,
    );
  }

  static Future<void> scheduleEvaluationReminder(Evaluacion ev, String ramoNombre) async {
    if (ev.fecha == null || ev.id == null) return;
    
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool('notificationsEnabled') ?? true;
    if (!enabled) return;

    final horasAntes = prefs.getInt('horasAntesEvaluacion') ?? 24;
    final soundName = prefs.getString('selectedEvalSound') ?? 'eval_sound';

    final scheduleTime = ev.fecha!.subtract(Duration(hours: horasAntes));
    if (scheduleTime.isAfter(DateTime.now())) {
      await _scheduleSpecific(
        id: (ev.id! * 100) + 1,
        title: 'Próxima Evaluación ($horasAntes hrs)',
        body: 'Tienes una evaluación de $ramoNombre: ${ev.nombre}',
        scheduledDate: tz.TZDateTime.from(scheduleTime, tz.local),
        soundName: soundName,
      );
    } else {
      if (ev.fecha!.isAfter(DateTime.now())) {
         await showInstantEvalNotification(ev, ramoNombre);
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
    required String soundName,
  }) async {
    final androidPlatformChannelSpecifics = AndroidNotificationDetails(
      'eval_channel_$soundName',
      'Recordatorios de Evaluaciones',
      channelDescription: 'Canal para recordatorios',
      importance: Importance.max,
      priority: Priority.high,
      sound: RawResourceAndroidNotificationSound(soundName),
    );
    final platformChannelSpecifics = NotificationDetails(android: androidPlatformChannelSpecifics);

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

    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool('notificationsEnabled') ?? true;
    if (!enabled) return;

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
    
    final minutosAntes = prefs.getInt('minutosAntesClase') ?? 15;
    final soundName = prefs.getString('selectedClassSound') ?? 'clase_sound';

    int hour = time[0];
    int minute = time[1] - minutosAntes;
    while (minute < 0) {
      hour -= 1;
      minute += 60;
    }
    if (hour < 0) hour = 0;

    final nowTime = DateTime.now();
    tz.TZDateTime now = tz.TZDateTime.now(tz.local);
    tz.TZDateTime scheduledDate = tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    
    if (nowTime.weekday == clase.diaSemana) {
       final classStartTime = DateTime(nowTime.year, nowTime.month, nowTime.day, time[0], time[1]);
       final blockEnd = classStartTime.add(const Duration(minutes: 70));
       
       if (nowTime.isBefore(blockEnd)) {
         if (nowTime.isAfter(classStartTime.subtract(Duration(minutes: minutosAntes)))) {
           await showInstantClassNotification(clase);
           scheduledDate = scheduledDate.add(const Duration(days: 7));
         } else {
           scheduledDate = scheduledDate; 
         }
       } else {
           scheduledDate = scheduledDate.add(const Duration(days: 7));
       }
    } else {
      while (scheduledDate.weekday != clase.diaSemana || scheduledDate.isBefore(now)) {
        scheduledDate = scheduledDate.add(const Duration(days: 1));
      }
    }

    final androidPlatformChannelSpecifics = AndroidNotificationDetails(
      'clases_channel_$soundName',
      'Recordatorios de Clases',
      channelDescription: 'Canal para recordatorios de horario',
      importance: Importance.max,
      priority: Priority.high,
      sound: RawResourceAndroidNotificationSound(soundName),
    );
    final platformChannelSpecifics = NotificationDetails(android: androidPlatformChannelSpecifics);

    await _notificationsPlugin.zonedSchedule(
      id: (clase.id! * 1000) + 3,
      title: 'Clase en $minutosAntes minutos',
      body: '${clase.subjectName} en sala ${clase.sala}',
      scheduledDate: scheduledDate,
      notificationDetails: platformChannelSpecifics,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
    );
  }
  
  static Future<void> cancelClassReminder(int claseId) async {
    await _notificationsPlugin.cancel(id: (claseId * 1000) + 3);
  }
}
