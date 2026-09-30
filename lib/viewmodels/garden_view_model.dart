import 'package:flutter/foundation.dart';
import '../data/demo_garden.dart';
import '../models/plant.dart';
import '../models/care_record.dart';

/// Управляет растениями, расписанием и историей ухода в оперативной памяти.
/// Представления подписываются на изменения через [ChangeNotifier].
class GardenViewModel extends ChangeNotifier {
  GardenViewModel({DateTime Function()? clock, DemoGarden? garden})
    : _clock = clock ?? DateTime.now {
    today = dateOnly(_clock());
    selectedDate = today;
    visibleMonth = DateTime(today.year, today.month);
    final source = garden ?? DemoGarden(today);
    _plants = List.of(source.plants);
    _procedures = [
      for (var i = 0; i < source.procedures.length; i++)
        CareProcedure(
          id: 'seed-$i',
          plantId: source.procedures[i].plantId,
          date: source.procedures[i].date,
          type: source.procedures[i].type,
          completedOn: source.procedures[i].completedOn,
        ),
    ];
    if (_plants.isNotEmpty) {
      for (final type in CareType.values) {
        _records.add(
          CareRecord(
            id: 'history-${type.name}',
            plantId: _plants.first.id,
            type: type,
            performedOn: addDays(today, -7 * (type.index + 1)),
            note: 'Демонстрационная запись',
          ),
        );
      }
    }
  }
  final DateTime Function() _clock;
  late DateTime today;
  late DateTime selectedDate;
  late DateTime visibleMonth;
  late final List<Plant> _plants;
  late final List<CareProcedure> _procedures;
  final List<CareRecord> _records = [];
  // Отметки хранятся для отдельных дат серии, а не для всей серии сразу.
  final Map<String, Map<DateTime, DateTime>> _completions = {};
  int _sequence = 0;
  String _newId(String prefix) => '$prefix-${_sequence++}';

  /// Возвращает исходные однократные процедуры и начала недельных серий.
  List<CareProcedure> get procedures => List.unmodifiable(_procedures);

  /// Возвращает неизменяемую историю выполненных действий.
  List<CareRecord> get records => List.unmodifiable(_records);

  /// Возвращает исходную запись серии для редактирования всех повторений.
  CareProcedure procedureById(String id) =>
      _procedures.firstWhere((p) => p.id == id);

  DateTime? _completion(CareProcedure p, DateTime day) => p.weekly
      ? (_completions[p.id] ?? const <DateTime, DateTime>{})[dateOnly(day)]
      : p.completedOn;

  DateTime? _nextPending(CareProcedure p) {
    if (!p.weekly) return p.isCompleted ? null : p.date;
    var day = dateOnly(p.date);
    while (_completion(p, day) != null) {
      day = addDays(day, 7);
    }
    return day;
  }

  /// Срок ближайшего незавершённого полива вычисляется из расписания.
  List<Plant> get plants => List.unmodifiable(
    _plants.map((plant) {
      final pending =
          _procedures
              .where(
                (p) => p.plantId == plant.id && p.type == CareType.watering,
              )
              .map(_nextPending)
              .whereType<DateTime>()
              .toList()
            ..sort();
      final completed =
          _records
              .where(
                (r) => r.plantId == plant.id && r.type == CareType.watering,
              )
              .map((r) => r.performedOn)
              .toList()
            ..sort();
      return Plant(
        id: plant.id,
        name: plant.name,
        species: plant.species,
        room: plant.room,
        art: plant.art,
        nextWatering: pending.isEmpty ? null : pending.first,
        lastWateredOn: completed.isEmpty ? null : completed.last,
      );
    }),
  );

  /// Количество карточек с просроченным поливом относительно текущего дня.
  int get overdueCount =>
      plants.where((p) => p.statusAt(today) == WateringStatus.overdue).length;

  /// Вычисляет повторы только для запрошенного дня без генерации бесконечного списка.
  List<CareProcedure> proceduresOn(DateTime date) => [
    for (final p in _procedures)
      if (p.occursOn(date)) p.occurrence(date, _completion(p, date)),
  ];

  /// Находит актуальное растение, поэтому переименование видно и в календаре.
  Plant plantFor(CareProcedure procedure) =>
      plants.firstWhere((p) => p.id == procedure.plantId);

  /// Добавляет или изменяет растение и при необходимости планирует первый полив.
  String savePlant({
    String? id,
    required String name,
    String species = '',
    String room = '',
    DateTime? firstWatering,
    bool weekly = false,
  }) {
    final clean = name.trim();
    if (clean.isEmpty) throw ArgumentError('Введите название растения.');
    if (clean.length > 80 ||
        species.trim().length > 100 ||
        room.trim().length > 60) {
      throw ArgumentError('Сократите слишком длинное поле.');
    }
    final index = id == null ? -1 : _plants.indexWhere((p) => p.id == id);
    if (id != null && index < 0) throw ArgumentError('Растение уже удалено.');
    final plant = Plant(
      id: id ?? _newId('plant'),
      name: clean,
      species: species.trim(),
      room: room.trim(),
      art: index < 0 ? _sequence % 4 : _plants[index].art,
    );
    if (index < 0) {
      _plants.add(plant);
      if (firstWatering != null) {
        _procedures.add(
          CareProcedure(
            id: _newId('procedure'),
            plantId: plant.id,
            date: dateOnly(firstWatering),
            type: CareType.watering,
            weekly: weekly,
          ),
        );
      }
    } else {
      _plants[index] = plant;
    }
    notifyListeners();
    return plant.id;
  }

  /// Удаляет растение вместе с расписанием, отметками и историей ухода.
  void deletePlant(String id) {
    final ids = _procedures
        .where((p) => p.plantId == id)
        .map((p) => p.id)
        .toSet();
    _plants.removeWhere((p) => p.id == id);
    _procedures.removeWhere((p) => p.plantId == id);
    _completions.removeWhere((key, _) => ids.contains(key));
    _records.removeWhere((r) => r.plantId == id);
    notifyListeners();
  }

  bool _overlaps(CareProcedure a, CareProcedure b) {
    if (a.weekly && b.weekly) return a.date.weekday == b.date.weekday;
    if (a.weekly) return a.occursOn(b.date);
    if (b.weekly) return b.occursOn(a.date);
    return sameDay(a.date, b.date);
  }

  /// Сохраняет однократную процедуру или недельную серию.
  /// При редактировании серии меняются все её будущие даты; история сохраняется.
  String saveProcedure({
    String? id,
    required String plantId,
    required DateTime date,
    required CareType type,
    bool weekly = false,
  }) {
    if (!_plants.any((p) => p.id == plantId)) {
      throw ArgumentError('Выберите существующее растение.');
    }
    final index = id == null ? -1 : _procedures.indexWhere((p) => p.id == id);
    if (id != null && index < 0) throw ArgumentError('Процедура уже удалена.');
    final day = dateOnly(date);
    final old = index < 0 ? null : _procedures[index];
    final unchanged =
        old != null &&
        old.plantId == plantId &&
        old.type == type &&
        sameDay(old.date, day) &&
        old.weekly == weekly;
    final p = CareProcedure(
      id: id ?? _newId('procedure'),
      plantId: plantId,
      date: day,
      type: type,
      weekly: weekly,
      completedOn: unchanged ? old.completedOn : null,
    );
    if (_procedures.any(
      (other) =>
          other.id != id &&
          other.plantId == plantId &&
          other.type == type &&
          _overlaps(other, p),
    )) {
      throw ArgumentError(
        'Расписание пересекается с такой же процедурой этого растения.',
      );
    }
    if (!unchanged) _completions.remove(p.id);
    if (index < 0) {
      _procedures.add(p);
    } else {
      _procedures[index] = p;
    }
    selectedDate = day;
    visibleMonth = DateTime(day.year, day.month);
    notifyListeners();
    return p.id;
  }

  /// Удаляет процедуру или всю серию. Выполненные действия остаются в журнале.
  void deleteProcedure(String id) {
    _procedures.removeWhere((p) => p.id == id);
    _completions.remove(id);
    notifyListeners();
  }

  void _markDue(String plantId, CareType type, DateTime performedOn) {
    for (var i = 0; i < _procedures.length; i++) {
      final p = _procedures[i];
      if (p.plantId != plantId || p.type != type) continue;
      if (p.weekly) {
        final entries = _completions.putIfAbsent(p.id, () => {});
        for (
          var day = dateOnly(p.date);
          !day.isAfter(performedOn);
          day = addDays(day, 7)
        ) {
          entries.putIfAbsent(day, () => performedOn);
        }
      } else if (!p.isCompleted && !p.date.isAfter(performedOn)) {
        _procedures[i] = p.withCompletion(performedOn);
      }
    }
  }

  /// Записывает факт ухода. Будущую дату и повтор того же вида за день запрещает.
  void recordCare({
    required String plantId,
    required CareType type,
    required DateTime performedOn,
    String note = '',
  }) {
    refreshToday();
    final day = dateOnly(performedOn);
    if (!_plants.any((p) => p.id == plantId)) {
      throw ArgumentError('Растение уже удалено.');
    }
    if (day.isAfter(today)) {
      throw ArgumentError('Нельзя записать уход будущей датой.');
    }
    if (note.trim().length > 300) {
      throw ArgumentError('Сократите примечание до 300 символов.');
    }
    if (_records.any(
      (r) =>
          r.plantId == plantId && r.type == type && sameDay(r.performedOn, day),
    )) {
      throw ArgumentError('Такая запись ухода уже есть на выбранный день.');
    }
    _markDue(plantId, type, day);
    _records.add(
      CareRecord(
        id: _newId('record'),
        plantId: plantId,
        type: type,
        performedOn: day,
        note: note.trim(),
      ),
    );
    notifyListeners();
  }

  /// Отмечает полив за текущий день либо отменяет отметки этого дня.
  /// Недельная серия после выполнения сохраняет будущие повторения.
  void toggleWateredToday(String plantId) {
    refreshToday();
    final logged = _records.any(
      (r) =>
          r.plantId == plantId &&
          r.type == CareType.watering &&
          sameDay(r.performedOn, today),
    );
    if (!logged) {
      if (!_plants.any((p) => p.id == plantId)) return;
      recordCare(plantId: plantId, type: CareType.watering, performedOn: today);
      return;
    }
    _records.removeWhere(
      (r) =>
          r.plantId == plantId &&
          r.type == CareType.watering &&
          sameDay(r.performedOn, today),
    );
    for (var i = 0; i < _procedures.length; i++) {
      final p = _procedures[i];
      if (p.plantId != plantId || p.type != CareType.watering) continue;
      if (p.weekly) {
        _completions[p.id]?.removeWhere(
          (_, completed) => sameDay(completed, today),
        );
      } else if (p.completedOn != null && sameDay(p.completedOn!, today)) {
        _procedures[i] = p.withCompletion(null);
      }
    }
    notifyListeners();
  }

  /// Выбирает календарный день и соответствующий месяц.
  void selectDay(DateTime date) {
    selectedDate = dateOnly(date);
    visibleMonth = DateTime(date.year, date.month);
    notifyListeners();
  }

  /// Переключает календарь между месяцами, включая границу года.
  void changeMonth(int offset) {
    visibleMonth = DateTime(visibleMonth.year, visibleMonth.month + offset);
    selectedDate = visibleMonth;
    notifyListeners();
  }

  /// Возвращает календарь к текущему дню.
  void goToToday() {
    refreshToday();
    selectDay(today);
  }

  /// Обновляет дату при смене суток, сохраняя выбранный день календаря.
  void refreshToday() {
    final current = dateOnly(_clock());
    if (current != today) {
      today = current;
      notifyListeners();
    }
  }
}
