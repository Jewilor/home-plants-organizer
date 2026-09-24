import 'package:flutter/foundation.dart';
import '../data/demo_garden.dart';
import '../models/plant.dart';

/// Состояние каталога растений и календаря процедур.
///
/// Изменения публикуются через [ChangeNotifier] для обновления интерфейса.
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
  }
  final DateTime Function() _clock;
  late DateTime today;
  late DateTime selectedDate;
  late DateTime visibleMonth;
  late final List<Plant> _plants;
  late final List<CareProcedure> _procedures;
  int _sequence = 0;
  String _newId(String prefix) => '$prefix-${_sequence++}';

  /// Возвращает процедуры только для чтения.
  List<CareProcedure> get procedures => List.unmodifiable(_procedures);
  /// Возвращает растения с актуальными сроками полива.
  List<Plant> get plants => List.unmodifiable(
    _plants.map((plant) {
      final watering = _procedures.where(
        (p) => p.plantId == plant.id && p.type == CareType.watering,
      );
      final pending =
          watering.where((p) => !p.isCompleted).map((p) => p.date).toList()
            ..sort();
      final completed =
          watering
              .where((p) => p.isCompleted)
              .map((p) => p.completedOn!)
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
  /// Возвращает количество растений с просроченным поливом.
  int get overdueCount =>
      plants.where((p) => p.statusAt(today) == WateringStatus.overdue).length;
  /// Возвращает процедуры, назначенные на выбранную календарную дату.
  List<CareProcedure> proceduresOn(DateTime date) =>
      _procedures.where((p) => sameDay(p.date, date)).toList();
  /// Находит растение, связанное с процедурой.
  Plant plantFor(CareProcedure procedure) =>
      plants.firstWhere((p) => p.id == procedure.plantId);

  /// Добавляет растение или сохраняет изменения существующей записи.
  String savePlant({
    String? id,
    required String name,
    String species = '',
    String room = '',
    DateTime? firstWatering,
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
          ),
        );
      }
    } else {
      _plants[index] = plant;
    }
    notifyListeners();
    return plant.id;
  }

  /// Удаляет растение и все связанные с ним процедуры.
  void deletePlant(String id) {
    _plants.removeWhere((p) => p.id == id);
    _procedures.removeWhere((p) => p.plantId == id);
    notifyListeners();
  }

  /// Добавляет или изменяет процедуру календаря.
  String saveProcedure({
    String? id,
    required String plantId,
    required DateTime date,
    required CareType type,
  }) {
    if (!_plants.any((p) => p.id == plantId)) {
      throw ArgumentError('Выберите существующее растение.');
    }
    final index = id == null ? -1 : _procedures.indexWhere((p) => p.id == id);
    if (id != null && index < 0) throw ArgumentError('Процедура уже удалена.');
    final day = dateOnly(date);
    if (_procedures.any(
      (p) =>
          p.id != id &&
          p.plantId == plantId &&
          p.type == type &&
          sameDay(p.date, day),
    )) {
      throw ArgumentError(
        'Такая процедура для этого растения уже есть на выбранную дату.',
      );
    }
    final old = index < 0 ? null : _procedures[index];
    final unchanged =
        old != null &&
        old.plantId == plantId &&
        old.type == type &&
        sameDay(old.date, day);
    final procedure = CareProcedure(
      id: id ?? _newId('procedure'),
      plantId: plantId,
      date: day,
      type: type,
      completedOn: unchanged ? old.completedOn : null,
    );
    if (index < 0) {
      _procedures.add(procedure);
    } else {
      _procedures[index] = procedure;
    }
    selectedDate = day;
    visibleMonth = DateTime(day.year, day.month);
    notifyListeners();
    return procedure.id;
  }

  /// Удаляет процедуру по её идентификатору.
  void deleteProcedure(String id) {
    _procedures.removeWhere((p) => p.id == id);
    notifyListeners();
  }

  /// A watering today satisfies all overdue/today watering entries, never future ones.
  /// Clicking again restores the original schedule and removes only generated logs.
  /// Отмечает сегодняшнее выполнение полива или отменяет эту отметку.
  void toggleWateredToday(String plantId) {
    refreshToday();
    if (!_plants.any((p) => p.id == plantId)) return;
    bool wateredToday(CareProcedure p) =>
        p.plantId == plantId &&
        p.type == CareType.watering &&
        p.completedOn != null &&
        sameDay(p.completedOn!, today);
    if (_procedures.any(wateredToday)) {
      _procedures.removeWhere((p) => wateredToday(p) && p.quickLog);
      for (var i = 0; i < _procedures.length; i++) {
        if (wateredToday(_procedures[i])) {
          _procedures[i] = _procedures[i].withCompletion(null);
        }
      }
    } else {
      for (var i = 0; i < _procedures.length; i++) {
        final p = _procedures[i];
        if (p.plantId == plantId &&
            p.type == CareType.watering &&
            !p.isCompleted &&
            !dateOnly(p.date).isAfter(today)) {
          _procedures[i] = p.withCompletion(today);
        }
      }
      // Keep a visible record on today's calendar even when watering was overdue.
      if (!_procedures.any(
        (p) =>
            p.plantId == plantId &&
            p.type == CareType.watering &&
            sameDay(p.date, today),
      )) {
        _procedures.add(
          CareProcedure(
            id: _newId('procedure'),
            plantId: plantId,
            date: today,
            type: CareType.watering,
            completedOn: today,
            quickLog: true,
          ),
        );
      }
    }
    notifyListeners();
  }

  /// Выбирает день и синхронизирует отображаемый месяц.
  void selectDay(DateTime date) {
    selectedDate = dateOnly(date);
    visibleMonth = DateTime(date.year, date.month);
    notifyListeners();
  }

  /// Переключает календарь на соседний месяц.
  void changeMonth(int offset) {
    visibleMonth = DateTime(visibleMonth.year, visibleMonth.month + offset);
    selectedDate = visibleMonth;
    notifyListeners();
  }

  /// Возвращает календарь к текущей дате.
  void goToToday() {
    refreshToday();
    selectDay(today);
  }

  /// Обновляет текущую дату после смены суток или возврата в приложение.
  void refreshToday() {
    final current = dateOnly(_clock());
    if (current != today) {
      today = current;
      notifyListeners();
    }
  }
}
