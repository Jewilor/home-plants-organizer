import 'package:flutter/foundation.dart';
import '../data/demo_garden.dart';
import '../models/plant.dart';
import '../models/care_record.dart';
import '../models/garden_snapshot.dart';
import '../models/reference_entry.dart';
import '../services/garden_repository.dart';
import 'reference_view_model.dart';
import '../models/care_guide.dart';
import '../models/reminder.dart';
import '../services/plant_encyclopedia.dart';
import '../services/reminder_service.dart';

/// Управляет садом и последовательно сохраняет его состояние в основной базе.
/// Представления подписываются на изменения через [ChangeNotifier].
class GardenViewModel extends ChangeNotifier {
  GardenViewModel({
    DateTime Function()? clock,
    DemoGarden? garden,
    this.repository,
    this.references,
    this.encyclopedia,
    this.reminderService,
    GardenSnapshot? snapshot,
  }) : _clock = clock ?? DateTime.now {
    today = dateOnly(_clock());
    selectedDate = today;
    visibleMonth = DateTime(today.year, today.month);
    if (snapshot != null) {
      _plants = List.of(snapshot.plants);
      _procedures = List.of(snapshot.procedures);
      _records.addAll(snapshot.records);
      for (final entry in snapshot.completions.entries) {
        _completions[entry.key] = Map.of(entry.value);
      }
      _sequence = snapshot.sequence;
      _careGuides.addAll(snapshot.careGuides);
      _reminderPreferences = snapshot.reminderPreferences;
      _wateringReminderTimes.addAll(snapshot.wateringReminderTimes);
      _watchReferences();
      return;
    }
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
    _watchReferences();
  }
  final GardenRepository? repository;
  final ReferenceViewModel? references;
  final PlantEncyclopedia? encyclopedia;
  final ReminderService? reminderService;
  final Map<String, CareGuide> _careGuides = {};
  final Map<String, ReminderTime> _wateringReminderTimes = {};
  ReminderPreferences _reminderPreferences = const ReminderPreferences();
  List<CareReminder> _scheduledReminders = [];
  String? notificationIssue;
  ReminderPreferences get reminderPreferences => _reminderPreferences;
  List<CareReminder> get scheduledReminders =>
      List.unmodifiable(_scheduledReminders);
  CareGuide? careGuideFor(String plantId) => _careGuides[plantId];

  /// Собственное время растения; отсутствие записи означает использование общего.
  ReminderTime? customWateringTimeFor(String plantId) =>
      _wateringReminderTimes[plantId];

  /// Время полива с учётом выбранного общего или отдельного режима.
  ReminderTime wateringTimeFor(String plantId) =>
      _reminderPreferences.individualWateringTimes
      ? _wateringReminderTimes[plantId] ?? _reminderPreferences.commonTime
      : _reminderPreferences.commonTime;
  Future<void> _writes = Future.value();
  int _pendingWrites = 0;
  bool _disposed = false;
  String? storageError;
  bool get saving => _pendingWrites > 0;
  bool get persistent => repository != null;

  /// Отделяет исходные записи от вычисляемых сроков полива.
  GardenSnapshot get snapshot => GardenSnapshot(
    plants: _plants,
    procedures: _procedures,
    records: _records,
    completions: _completions,
    sequence: _sequence,
    careGuides: _careGuides,
    reminderPreferences: _reminderPreferences,
    wateringReminderTimes: _wateringReminderTimes,
  );

  void _watchReferences() {
    references?.addListener(_referencesChanged);
    references?.bindUsageCheck(isReferenceInUse);
  }

  void _referencesChanged() {
    if (!_disposed) notifyListeners();
  }

  /// Проверяет ссылки и запрещает удаление справочника до подтверждения записи сада.
  bool isReferenceInUse(ReferenceKind kind, String id) {
    if (saving) throw ArgumentError('Дождитесь сохранения изменений сада.');
    if (storageError != null) {
      throw ArgumentError('Сначала повторите сохранение изменений сада.');
    }
    return kind == ReferenceKind.family
        ? _plants.any((plant) => plant.familyId == id)
        : _procedures.any((procedure) => procedure.fertilizerId == id);
  }

  /// Ставит неизменяемый снимок в очередь: поздняя запись не обгоняет раннюю.
  void _saveChanged() {
    if (repository == null && reminderService == null) {
      notifyListeners();
      return;
    }
    final state = snapshot;
    _pendingWrites++;
    storageError = null;
    notifyListeners();
    _writes = _writes
        .then((_) async {
          await repository?.save(state);
          await _syncNotifications(state);
        })
        .then(
          (_) {
            storageError = null;
          },
          onError: (Object error, StackTrace stack) {
            storageError =
                'Не удалось сохранить изменения. Повторите сохранение.';
          },
        )
        .whenComplete(() {
          _pendingWrites--;
          if (!_disposed) notifyListeners();
        });
  }

  /// Ожидает подтверждения всех поставленных в очередь операций.
  Future<void> flush() async {
    await _writes;
    if (storageError != null) throw StateError(storageError!);
  }

  /// Сохраняет текущее состояние, в том числе после устранимой ошибки хранилища.
  Future<void> persist() {
    _saveChanged();
    return flush();
  }

  @override
  void dispose() {
    _disposed = true;
    references?.removeListener(_referencesChanged);
    references?.bindUsageCheck(null);
    super.dispose();
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

  DateTime? _completion(CareProcedure p, DateTime day) => p.repeats
      ? (_completions[p.id] ?? const <DateTime, DateTime>{})[dateOnly(day)]
      : p.completedOn;

  DateTime? _nextPending(CareProcedure p) {
    if (!p.repeats) return p.isCompleted ? null : p.date;
    var day = dateOnly(p.date);
    while (_completion(p, day) != null) {
      day = addDays(day, p.intervalDays);
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
        careConditions: plant.careConditions,
        familyId: plant.familyId,
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
    String? careConditions,
    String? familyId,
    DateTime? firstWatering,
    bool weekly = false,
  }) {
    if (familyId != null &&
        familyId.isNotEmpty &&
        (references?.saving == true ||
            references?.find(ReferenceKind.family, familyId) == null)) {
      throw ArgumentError(
        'Выберите существующее семейство и дождитесь сохранения справочника.',
      );
    }
    final clean = name.trim();
    if (clean.isEmpty) throw ArgumentError('Введите название растения.');
    if (clean.length > 80 ||
        species.trim().length > 100 ||
        room.trim().length > 60 ||
        (careConditions?.trim().length ?? 0) > 2000) {
      throw ArgumentError('Сократите слишком длинное поле.');
    }
    final index = id == null ? -1 : _plants.indexWhere((p) => p.id == id);
    if (id != null && index < 0) throw ArgumentError('Растение уже удалено.');
    final plant = Plant(
      id: id ?? _newId('plant'),
      name: clean,
      species: species.trim(),
      room: room.trim(),
      careConditions:
          (careConditions ?? (index < 0 ? '' : _plants[index].careConditions))
              .trim(),
      familyId: familyId ?? (index < 0 ? '' : _plants[index].familyId),
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
    _saveChanged();
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
    _careGuides.remove(id);
    _wateringReminderTimes.remove(id);
    _saveChanged();
  }

  bool _overlaps(CareProcedure a, CareProcedure b) {
    if (a.repeats && b.repeats) {
      final difference = DateTime.utc(
        a.date.year,
        a.date.month,
        a.date.day,
      ).difference(DateTime.utc(b.date.year, b.date.month, b.date.day)).inDays;
      return difference % a.intervalDays.gcd(b.intervalDays) == 0;
    }
    if (a.repeats) return a.occursOn(b.date);
    if (b.repeats) return b.occursOn(a.date);
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
    String fertilizerId = '',
    int repeatEveryDays = 0,
  }) {
    if (!_plants.any((p) => p.id == plantId)) {
      throw ArgumentError('Выберите существующее растение.');
    }
    if (repeatEveryDays < 0 || repeatEveryDays > 365) {
      throw ArgumentError(
        'Интервал должен быть от 1 до 365 дней либо 0 для одной даты.',
      );
    }
    final fertilizer = type == CareType.feeding ? fertilizerId : '';
    if (fertilizer.isNotEmpty &&
        (references?.saving == true ||
            references?.find(ReferenceKind.fertilizer, fertilizer) == null)) {
      throw ArgumentError(
        'Выберите существующий тип удобрения и дождитесь сохранения справочника.',
      );
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
        old.weekly == weekly &&
        old.repeatEveryDays == repeatEveryDays;
    final p = CareProcedure(
      id: id ?? _newId('procedure'),
      plantId: plantId,
      date: day,
      type: type,
      weekly: weekly,
      fertilizerId: fertilizer,
      repeatEveryDays: repeatEveryDays,
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
    _saveChanged();
    return p.id;
  }

  /// Удаляет процедуру или всю серию. Выполненные действия остаются в журнале.
  void deleteProcedure(String id) {
    _procedures.removeWhere((p) => p.id == id);
    _completions.remove(id);
    _saveChanged();
  }

  void _markDue(String plantId, CareType type, DateTime performedOn) {
    for (var i = 0; i < _procedures.length; i++) {
      final p = _procedures[i];
      if (p.plantId != plantId || p.type != type) continue;
      if (p.repeats) {
        final entries = _completions.putIfAbsent(p.id, () => {});
        for (
          var day = dateOnly(p.date);
          !day.isAfter(performedOn);
          day = addDays(day, p.intervalDays)
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
    _saveChanged();
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
      if (p.repeats) {
        _completions[p.id]?.removeWhere(
          (_, completed) => sameDay(completed, today),
        );
      } else if (p.completedOn != null && sameDay(p.completedOn!, today)) {
        _procedures[i] = p.withCompletion(null);
      }
    }
    _saveChanged();
  }

  /// Сохраняет полученную справку и атомарно заменяет расписание полива при выборе.
  /// Другие виды ухода, ручные условия содержания и фактический журнал сохраняются.
  Future<void> applyCareGuide(
    String plantId,
    CareGuide guide, {
    DateTime? firstWatering,
    int? intervalDays,
  }) async {
    if (!_plants.any((p) => p.id == plantId)) {
      throw ArgumentError('Растение уже удалено.');
    }
    if (firstWatering != null &&
        (intervalDays == null || intervalDays < 1 || intervalDays > 365)) {
      throw ArgumentError('Укажите интервал полива от 1 до 365 дней.');
    }
    _careGuides[plantId] = guide;
    if (firstWatering != null) {
      final removed = _procedures
          .where((p) => p.plantId == plantId && p.type == CareType.watering)
          .map((p) => p.id)
          .toSet();
      _procedures.removeWhere((p) => removed.contains(p.id));
      _completions.removeWhere((key, _) => removed.contains(key));
      _procedures.add(
        CareProcedure(
          id: _newId('procedure'),
          plantId: plantId,
          date: dateOnly(firstWatering),
          type: CareType.watering,
          weekly: intervalDays == 7,
          repeatEveryDays: intervalDays == 7 ? 0 : intervalDays!,
        ),
      );
    }
    _saveChanged();
    await flush();
  }

  /// Синхронизирует системную очередь только после успешного сохранения состояния.
  /// Ошибка уведомлений не скрывает результат записи базы данных.
  Future<void> _syncNotifications(GardenSnapshot state) async {
    final service = reminderService;
    if (service == null) return;
    try {
      final allowed = await service.permitted();
      final planned = state.reminderPreferences.enabled && allowed
          ? planReminders(state, _clock())
          : <CareReminder>[];
      await service.replace(planned);
      _scheduledReminders = planned;
      notificationIssue = state.reminderPreferences.enabled && !allowed
          ? 'Разрешите уведомления для «Листва» в настройках Android.'
          : null;
    } catch (_) {
      _scheduledReminders = [];
      notificationIssue =
          'Не удалось обновить напоминания. Нажмите «Обновить напоминания».';
    }
    if (!_disposed) notifyListeners();
  }

  /// Восстанавливает очередь при запуске или возвращении приложения на экран.
  Future<void> refreshReminders() {
    final state = snapshot;
    _writes = _writes.then((_) => _syncNotifications(state));
    return _writes;
  }

  /// Запрашивает системное разрешение после нажатия пользователем переключателя.
  Future<bool> configureReminders({
    required bool enabled,
    int? hour,
    int? minute,
  }) async {
    final service = reminderService;
    if (service == null) return false;
    final h = hour ?? _reminderPreferences.hour;
    final m = minute ?? _reminderPreferences.minute;
    if (h < 0 || h > 23 || m < 0 || m > 59) {
      throw ArgumentError('Некорректное время.');
    }
    if (enabled && !await service.requestPermission()) {
      notificationIssue =
          'Разрешение не предоставлено. Включите уведомления для «Листва» в настройках Android.';
      if (!_disposed) notifyListeners();
      return false;
    }
    _reminderPreferences = ReminderPreferences(
      enabled: enabled,
      hour: h,
      minute: m,
      individualWateringTimes: _reminderPreferences.individualWateringTimes,
    );
    _saveChanged();
    await flush();
    return true;
  }

  /// Выбирает общее время полива либо сохранённые отдельные часы растений.
  /// При переходе к общему режиму отдельные часы сохраняются для возврата к ним.
  Future<void> configureWateringReminders({required bool individual}) async {
    _reminderPreferences = ReminderPreferences(
      enabled: _reminderPreferences.enabled,
      hour: _reminderPreferences.hour,
      minute: _reminderPreferences.minute,
      individualWateringTimes: individual,
    );
    _saveChanged();
    await flush();
  }

  /// Сохраняет время полива одного растения; null возвращает его к общему времени.
  Future<void> setWateringReminderTime(
    String plantId,
    ReminderTime? time,
  ) async {
    if (!_plants.any((plant) => plant.id == plantId)) {
      throw ArgumentError('Растение уже удалено.');
    }
    if (time != null && !time.isValid) {
      throw ArgumentError('Некорректное время.');
    }
    if (time == null) {
      _wateringReminderTimes.remove(plantId);
    } else {
      _wateringReminderTimes[plantId] = time;
    }
    _saveChanged();
    await flush();
  }

  /// Отправляет настоящее системное уведомление для самостоятельной проверки.
  Future<void> testNotification() async {
    final service = reminderService;
    if (service == null || !await service.requestPermission()) {
      throw ArgumentError(
        'Для проверки разрешите уведомления в настройках Android.',
      );
    }
    await service.showTest();
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
