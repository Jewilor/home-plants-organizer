import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as zones;
import 'package:timezone/timezone.dart' as tz;
import '../models/reminder.dart';
import 'reminder_service.dart';

/// Планирует уведомления Android в местном часовом поясе без точных будильников.
class AndroidReminderService implements ReminderService {
  AndroidReminderService._(this.plugin);
  final FlutterLocalNotificationsPlugin plugin;
  static const details = NotificationDetails(
    android: AndroidNotificationDetails(
      'plant_care',
      'Уход за растениями',
      channelDescription: 'Напоминания о поливе, подкормке и пересадке',
      importance: Importance.high,
      priority: Priority.high,
      icon: 'ic_notification',
    ),
  );

  /// Инициализирует часовой пояс и канал, не запрашивая разрешение при старте.
  static Future<AndroidReminderService> open() async {
    final zone = await FlutterTimezone.getLocalTimezone();
    initializeTimeZone(zone.identifier);
    final plugin = FlutterLocalNotificationsPlugin();
    await plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('ic_notification'),
      ),
    );
    return AndroidReminderService._(plugin);
  }

  /// Поддерживает идентификаторы GMT и UTC, возвращаемые устройствами Android.
  static void initializeTimeZone(String identifier) {
    zones.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation(identifier));
  }

  @override
  Future<bool> permitted() async =>
      await plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.areNotificationsEnabled() ??
      false;
  @override
  Future<bool> requestPermission() async =>
      await plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.requestNotificationsPermission() ??
      false;

  /// Удаляет старые будущие уведомления и регистрирует актуальные даты и названия.
  @override
  Future<void> replace(List<CareReminder> reminders) async {
    await plugin.cancelAllPendingNotifications();
    try {
      for (final reminder in reminders) {
        final d = reminder.date;
        await plugin.zonedSchedule(
          id: reminder.id,
          title: reminder.title,
          body: reminder.body,
          scheduledDate: tz.TZDateTime(
            tz.local,
            d.year,
            d.month,
            d.day,
            d.hour,
            d.minute,
          ),
          notificationDetails: details,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          payload: reminder.plantId,
        );
      }
    } catch (_) {
      await plugin.cancelAllPendingNotifications();
      rethrow;
    }
  }

  @override
  Future<void> showTest() => plugin.show(
    id: 1000000,
    title: 'Листва – проверка напоминаний',
    body:
        'Уведомления разрешены. Напоминания об уходе будут приходить по расписанию.',
    notificationDetails: details,
  );
}
