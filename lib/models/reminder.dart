import 'plant.dart';
import 'garden_snapshot.dart';

/// Сохранённые настройки времени и разрешения пользователя на напоминания.
class ReminderPreferences {
  const ReminderPreferences({
    this.enabled = false,
    this.hour = 9,
    this.minute = 0,
  });
  final bool enabled;
  final int hour, minute;
  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'hour': hour,
    'minute': minute,
  };
  factory ReminderPreferences.fromJson(Map<String, dynamic> json) {
    final hour = json['hour'];
    final minute = json['minute'];
    if (json['enabled'] is! bool ||
        hour is! int ||
        hour < 0 ||
        hour > 23 ||
        minute is! int ||
        minute < 0 ||
        minute > 59) {
      throw const FormatException('Некорректные настройки напоминаний.');
    }
    return ReminderPreferences(
      enabled: json['enabled'] as bool,
      hour: hour,
      minute: minute,
    );
  }
}

/// Одно локальное уведомление о конкретной процедуре в конкретную дату.
class CareReminder {
  const CareReminder({
    required this.id,
    required this.plantId,
    required this.procedureId,
    required this.date,
    required this.title,
    required this.body,
  });
  final int id;
  final String plantId, procedureId, title, body;
  final DateTime date;
}

/// Строит ограниченную цепочку будущих уведомлений без завершённых повторений.
/// Даты прибавляются календарно, поэтому переход часового пояса не сдвигает день.
List<CareReminder> planReminders(
  GardenSnapshot state,
  DateTime now, {
  int horizonDays = 30,
  int limit = 64,
}) {
  final result = <CareReminder>[];
  final today = dateOnly(now);
  for (var offset = 0; offset <= horizonDays; offset++) {
    final day = addDays(today, offset);
    final at = DateTime(
      day.year,
      day.month,
      day.day,
      state.reminderPreferences.hour,
      state.reminderPreferences.minute,
    );
    if (!at.isAfter(now)) continue;
    for (final procedure in state.procedures) {
      if (!procedure.occursOn(day)) continue;
      final completed = procedure.repeats
          ? (state.completions[procedure.id]?[day] != null)
          : procedure.isCompleted;
      if (completed) continue;
      final plant = state.plants
          .where((p) => p.id == procedure.plantId)
          .firstOrNull;
      if (plant == null) continue;
      result.add(
        CareReminder(
          id: result.length + 1,
          plantId: plant.id,
          procedureId: procedure.id,
          date: at,
          title: '${procedure.type.label}: ${plant.name}',
          body:
              '${plant.room.isEmpty ? '' : '${plant.room}. '}Сегодня запланирована процедура ухода.',
        ),
      );
      if (result.length >= limit) return result;
    }
  }
  return result;
}
