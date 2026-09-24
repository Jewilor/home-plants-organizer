/// Возвращает дату без времени для календарного сравнения.
DateTime dateOnly(DateTime date) => DateTime(date.year, date.month, date.day);
/// Прибавляет указанное количество календарных дней.
DateTime addDays(DateTime date, int days) =>
    DateTime(date.year, date.month, date.day + days);
/// Проверяет совпадение двух дат без учёта времени.
bool sameDay(DateTime a, DateTime b) => dateOnly(a) == dateOnly(b);

/// Состояние полива растения, используемое для оформления карточки.
enum WateringStatus { overdue, today, upcoming, watered, unscheduled }

/// Вид процедуры ухода за комнатным растением.
enum CareType { watering, feeding, repotting }

/// Предоставляет русское название для вида процедуры.
extension CareTypeLabel on CareType {
  String get label => switch (this) {
    CareType.watering => 'Полив',
    CareType.feeding => 'Подкормка',
    CareType.repotting => 'Пересадка',
  };
}

/// Модель комнатного растения и вычисляемых сведений о поливе.
class Plant {
  const Plant({
    required this.id,
    required this.name,
    required this.species,
    required this.room,
    this.nextWatering,
    this.lastWateredOn,
    required this.art,
  });
  final String id;
  final String name;
  final String species;
  final String room;
  // These dates are derived by the ViewModel from the procedures.
  final DateTime? nextWatering;
  final DateTime? lastWateredOn;
  final int art;

  /// Возвращает состояние полива относительно указанной даты.
  WateringStatus statusAt(DateTime now) {
    if (lastWateredOn != null && sameDay(lastWateredOn!, now)) {
      return WateringStatus.watered;
    }
    if (nextWatering == null) return WateringStatus.unscheduled;
    final due = dateOnly(nextWatering!);
    final today = dateOnly(now);
    if (due.isBefore(today)) return WateringStatus.overdue;
    if (due == today) return WateringStatus.today;
    return WateringStatus.upcoming;
  }
}

/// Модель одной процедуры ухода, связанной с растением по идентификатору.
class CareProcedure {
  const CareProcedure({
    this.id = '',
    required this.plantId,
    required this.date,
    required this.type,
    this.completedOn,
    this.quickLog = false,
  });
  final String id;
  final String plantId;
  final DateTime date;
  final CareType type;
  final DateTime? completedOn;
  // Only an automatically created same-day watering log is removed on undo.
  final bool quickLog;
  /// Показывает, была ли процедура отмечена выполненной.
  bool get isCompleted => completedOn != null;

  /// Создаёт копию процедуры с новой отметкой выполнения.
  CareProcedure withCompletion(DateTime? value) => CareProcedure(
    id: id,
    plantId: plantId,
    date: date,
    type: type,
    completedOn: value,
    quickLog: quickLog,
  );
}
