import 'plant.dart';
import 'garden_snapshot.dart';

/// Время уведомления в часовом поясе устройства без календарной даты.
class ReminderTime {
  const ReminderTime({required this.hour, required this.minute});
  final int hour, minute;
  bool get isValid => hour >= 0 && hour <= 23 && minute >= 0 && minute <= 59;
  Map<String, dynamic> toJson() => {'hour': hour, 'minute': minute};

  /// Проверяет время, восстановленное из постоянного хранилища.
  factory ReminderTime.fromJson(Map<String, dynamic> json) {
    if (json['hour'] is! int || json['minute'] is! int) {
      throw const FormatException('Некорректное время напоминания.');
    }
    final time = ReminderTime(
      hour: json['hour'] as int,
      minute: json['minute'] as int,
    );
    if (!time.isValid) {
      throw const FormatException('Некорректное время напоминания.');
    }
    return time;
  }
}

/// Общее время ухода и выбор общего либо отдельного времени полива.
class ReminderPreferences {
  const ReminderPreferences({
    this.enabled = false,
    this.hour = 9,
    this.minute = 0,
    this.individualWateringTimes = false,
  });
  final bool enabled;
  final int hour, minute;
  final bool individualWateringTimes;
  ReminderTime get commonTime => ReminderTime(hour: hour, minute: minute);
  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'hour': hour,
    'minute': minute,
    'individualWateringTimes': individualWateringTimes,
  };

  /// Старые настройки без режима полива восстанавливаются с общим временем.
  factory ReminderPreferences.fromJson(Map<String, dynamic> json) {
    final time = ReminderTime.fromJson(json);
    final individual = json['individualWateringTimes'] ?? false;
    if (json['enabled'] is! bool || individual is! bool) {
      throw const FormatException('Некорректные настройки напоминаний.');
    }
    return ReminderPreferences(
      enabled: json['enabled'] as bool,
      hour: time.hour,
      minute: time.minute,
      individualWateringTimes: individual,
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

/// Вычисляет время каждого события и выбирает ближайшие уведомления по времени.
/// Свои часы растений применяются только к поливу при включённом отдельном режиме.
List<CareReminder> planReminders(
  GardenSnapshot state,
  DateTime now, {
  int horizonDays = 30,
  int limit = 64,
}) {
  if (limit <= 0 || horizonDays < 0) return [];
  final result = <CareReminder>[];
  final today = dateOnly(now);
  for (var offset = 0; offset <= horizonDays; offset++) {
    final day = addDays(today, offset);
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
      final prefs = state.reminderPreferences;
      final time =
          prefs.individualWateringTimes && procedure.type == CareType.watering
          ? state.wateringReminderTimes[plant.id] ?? prefs.commonTime
          : prefs.commonTime;
      final at = DateTime(day.year, day.month, day.day, time.hour, time.minute);
      if (!at.isAfter(now)) continue;
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
    }
  }
  // Ограничение применяется после сортировки, чтобы позднее событие не вытеснило раннее.
  result.sort((a, b) {
    final byTime = a.date.compareTo(b.date);
    if (byTime != 0) return byTime;
    final byPlant = a.plantId.compareTo(b.plantId);
    return byPlant != 0 ? byPlant : a.procedureId.compareTo(b.procedureId);
  });
  return result.take(limit).toList();
}
