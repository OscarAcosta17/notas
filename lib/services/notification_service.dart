import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import '../models/clase_horario.dart';
import '../models/evaluacion.dart';
import '../utils/schedule_blocks.dart';
import 'database_helper.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();
  static const MethodChannel _tzChannel =
      MethodChannel('com.example.notas/timezone');
  static bool _initialized = false;

  static int _evalScheduledId(int evalId) => 100000 + (evalId * 10) + 1;
  static int _evalInstantId(int evalId) => 100000 + (evalId * 10) + 2;
  static int _classScheduledId(int claseId) => 200000 + (claseId * 10) + 1;
  static int _classInstantId(int claseId) => 200000 + (claseId * 10) + 2;
  static const int _updateNotificationId = 900001;
  static const int _testSoundNotificationId = 900002;

  static Future<void> _ensureTimeZoneInitialized() async {
    tz.initializeTimeZones();
    try {
      final tzName = await _tzChannel.invokeMethod<String>('getLocalTimezone');
      if (tzName != null && tzName.isNotEmpty) {
        tz.setLocalLocation(tz.getLocation(tzName));
        return;
      }
    } catch (e) {
      debugPrint('Failed to resolve native timezone, using fallback: $e');
    }
    try {
      tz.setLocalLocation(tz.getLocation('America/Santiago'));
    } catch (_) {
      tz.setLocalLocation(tz.UTC);
    }
  }

  static Future<void> initialize() async {
    if (!Platform.isAndroid || _initialized) return;
    await _ensureTimeZoneInitialized();
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/launcher_icon');
    const InitializationSettings initializationSettings =
        InitializationSettings(android: initializationSettingsAndroid);
    await _notificationsPlugin.initialize(settings: initializationSettings);
    _initialized = true;
  }

  static Future<bool> requestPermissions() async {
    if (!Platform.isAndroid) return true;
    final statusNotif = await Permission.notification.request();
    final statusAlarm = await Permission.scheduleExactAlarm.request();
    return statusNotif.isGranted &&
        (statusAlarm.isGranted || statusAlarm.isRestricted);
  }

  static Future<void> cancelAll() async {
    if (!Platform.isAndroid) return;
    await _notificationsPlugin.cancelAll();
  }

  static Future<void> showInstantNotification(String title, String body) async {
    if (!Platform.isAndroid) return;
    const androidDetails = AndroidNotificationDetails(
      'update_channel',
      'Actualizaciones',
      channelDescription: 'Notificaciones sobre actualizaciones de la aplicación',
      importance: Importance.max,
      priority: Priority.high,
    );
    const details = NotificationDetails(android: androidDetails);

    await _notificationsPlugin.show(
      id: _updateNotificationId,
      title: title,
      body: body,
      notificationDetails: details,
    );
  }

  static Future<void> showTestSoundNotification(
    String title,
    String body,
    String soundName,
  ) async {
    if (!Platform.isAndroid) return;
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
      id: _testSoundNotificationId,
      title: title,
      body: body,
      notificationDetails: details,
    );
  }

  static Future<void> showInstantClassNotification(ClaseHorario clase) async {
    if (!Platform.isAndroid || clase.id == null) return;
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
      id: _classInstantId(clase.id!),
      title: '¡Clase hoy!',
      body: '${clase.subjectName} en sala ${clase.sala}',
      notificationDetails: details,
    );
  }

  static Future<void> showInstantEvalNotification(
    Evaluacion ev,
    String ramoNombre,
  ) async {
    if (!Platform.isAndroid || ev.id == null) return;
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
      id: _evalInstantId(ev.id!),
      title: 'Próxima Evaluación',
      body: 'Tienes una evaluación inminente de $ramoNombre: ${ev.nombre}',
      notificationDetails: details,
    );
  }

  static Future<void> scheduleEvaluationReminder(
    Evaluacion ev,
    String ramoNombre,
  ) async {
    if (!Platform.isAndroid || ev.fecha == null || ev.id == null) return;

    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool('notificationsEnabled') ?? true;
    if (!enabled) return;

    final horasAntes = prefs.getInt('horasAntesEvaluacion') ?? 24;
    final soundName = prefs.getString('selectedEvalSound') ?? 'eval_sound';

    final scheduleTime = ev.fecha!.subtract(Duration(hours: horasAntes));
    if (scheduleTime.isAfter(DateTime.now())) {
      await _scheduleSpecific(
        id: _evalScheduledId(ev.id!),
        title: 'Próxima Evaluación ($horasAntes hrs)',
        body: 'Tienes una evaluación de $ramoNombre: ${ev.nombre}',
        scheduledDate: tz.TZDateTime.from(scheduleTime, tz.local),
        soundName: soundName,
      );
    } else if (ev.fecha!.isAfter(DateTime.now())) {
      await showInstantEvalNotification(ev, ramoNombre);
    }
  }

  static Future<void> cancelEvaluationReminder(int evalId) async {
    if (!Platform.isAndroid) return;
    await _notificationsPlugin.cancel(id: _evalScheduledId(evalId));
    await _notificationsPlugin.cancel(id: _evalInstantId(evalId));
  }

  static Future<void> _zonedScheduleWithFallback({
    required int id,
    required String title,
    required String body,
    required tz.TZDateTime scheduledDate,
    required NotificationDetails notificationDetails,
    DateTimeComponents? matchDateTimeComponents,
  }) async {
    try {
      await _notificationsPlugin.zonedSchedule(
        id: id,
        title: title,
        body: body,
        scheduledDate: scheduledDate,
        notificationDetails: notificationDetails,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        matchDateTimeComponents: matchDateTimeComponents,
      );
    } on PlatformException {
      await _notificationsPlugin.zonedSchedule(
        id: id,
        title: title,
        body: body,
        scheduledDate: scheduledDate,
        notificationDetails: notificationDetails,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: matchDateTimeComponents,
      );
    }
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
    final platformChannelSpecifics =
        NotificationDetails(android: androidPlatformChannelSpecifics);

    await _zonedScheduleWithFallback(
      id: id,
      title: title,
      body: body,
      scheduledDate: scheduledDate,
      notificationDetails: platformChannelSpecifics,
    );
  }

  static Future<void> scheduleClassReminder(ClaseHorario clase) async {
    if (!Platform.isAndroid ||
        clase.id == null ||
        !ScheduleBlocks.isValidWeekday(clase.diaSemana)) {
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool('notificationsEnabled') ?? true;
    if (!enabled) return;

    final time = ScheduleBlocks.blockStartTimes[clase.bloque] ?? (8, 0);

    final minutosAntes = prefs.getInt('minutosAntesClase') ?? 15;
    final soundName = prefs.getString('selectedClassSound') ?? 'clase_sound';

    var hour = time.$1;
    var minute = time.$2 - minutosAntes;
    while (minute < 0) {
      hour -= 1;
      minute += 60;
    }
    if (hour < 0) hour = 0;

    final nowTime = DateTime.now();
    final now = tz.TZDateTime.now(tz.local);
    var scheduledDate =
        tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);

    if (nowTime.weekday == clase.diaSemana) {
      final classStartTime = DateTime(
        nowTime.year,
        nowTime.month,
        nowTime.day,
        time.$1,
        time.$2,
      );
      final blockEnd = classStartTime.add(const Duration(minutes: 70));

      if (nowTime.isBefore(blockEnd)) {
        if (nowTime
            .isAfter(classStartTime.subtract(Duration(minutes: minutosAntes)))) {
          await showInstantClassNotification(clase);
          scheduledDate = scheduledDate.add(const Duration(days: 7));
        }
      } else {
        scheduledDate = scheduledDate.add(const Duration(days: 7));
      }
    } else {
      for (var i = 0; i < 8; i++) {
        if (scheduledDate.weekday == clase.diaSemana &&
            !scheduledDate.isBefore(now)) {
          break;
        }
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
    final platformChannelSpecifics =
        NotificationDetails(android: androidPlatformChannelSpecifics);

    await _zonedScheduleWithFallback(
      id: _classScheduledId(clase.id!),
      title: 'Clase en $minutosAntes minutos',
      body: '${clase.subjectName} en sala ${clase.sala}',
      scheduledDate: scheduledDate,
      notificationDetails: platformChannelSpecifics,
      matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
    );
  }

  static Future<void> cancelClassReminder(int claseId) async {
    if (!Platform.isAndroid) return;
    await _notificationsPlugin.cancel(id: _classScheduledId(claseId));
    await _notificationsPlugin.cancel(id: _classInstantId(claseId));
  }

  static Future<void> rescheduleAllFromDatabase() async {
    if (!Platform.isAndroid) return;
    await initialize();
    await cancelAll();

    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool('notificationsEnabled') ?? true;
    if (!enabled) return;

    final db = DatabaseHelper.instance;
    final evalRows = await db.queryAllScheduledEvaluationsWithSubject();
    final now = DateTime.now();
    for (final row in evalRows) {
      final ev = Evaluacion.fromMap(row);
      if (ev.fecha != null && ev.fecha!.isAfter(now)) {
        await scheduleEvaluationReminder(
          ev,
          row['subject_name']?.toString() ?? '',
        );
      }
    }

    final semesters = await db.queryAllSemesters();
    for (final sem in semesters) {
      final semId = sem['id'] as int?;
      if (semId == null) continue;
      final horarios = await db.queryHorariosBySemester(semId);
      for (final h in horarios) {
        await scheduleClassReminder(ClaseHorario.fromMap(h));
      }
    }
  }
}
