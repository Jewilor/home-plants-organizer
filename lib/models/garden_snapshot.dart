import 'plant.dart';
import 'care_record.dart';
import 'care_guide.dart';
import 'reminder.dart';

/// Согласованное состояние сада для сохранения и восстановления.
/// Копии коллекций защищают ожидающую записи операцию от последующих изменений.
class GardenSnapshot {
  GardenSnapshot({
    required Iterable<Plant> plants,
    required Iterable<CareProcedure> procedures,
    required Iterable<CareRecord> records,
    required Map<String, Map<DateTime, DateTime>> completions,
    required this.sequence,
    Map<String, CareGuide> careGuides = const {},
    Map<String, ReminderTime> wateringReminderTimes = const {},
    this.reminderPreferences = const ReminderPreferences(),
  }) : plants = List.unmodifiable(plants),
       procedures = List.unmodifiable(procedures),
       records = List.unmodifiable(records),
       careGuides = Map.unmodifiable(careGuides),
       wateringReminderTimes = Map.unmodifiable(wateringReminderTimes),
       completions = Map.unmodifiable({
         for (final entry in completions.entries)
           entry.key: Map<DateTime, DateTime>.unmodifiable(entry.value),
       });
  final List<Plant> plants;
  final List<CareProcedure> procedures;
  final List<CareRecord> records;
  final Map<String, Map<DateTime, DateTime>> completions;
  final int sequence;
  final Map<String, CareGuide> careGuides;
  final ReminderPreferences reminderPreferences;
  final Map<String, ReminderTime> wateringReminderTimes;
}

/// Сохраняет календарную дату без часового пояса и времени суток.
String encodeDay(DateTime date) =>
    dateOnly(date).toIso8601String().split('T').first;

/// Восстанавливает календарную дату из сохранённого текста.
DateTime decodeDay(String value) => dateOnly(DateTime.parse(value));
