import '../models/reminder.dart';

/// Контракт платформенных уведомлений для подмены в автоматизированных проверках.
abstract interface class ReminderService {
  Future<bool> permitted();
  Future<bool> requestPermission();
  Future<void> replace(List<CareReminder> reminders);
  Future<void> showTest();
}
