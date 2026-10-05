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
    this.careConditions = '',
    this.familyId = '',
    this.nextWatering,
    this.lastWateredOn,
    this.nextWateringHasTime = false,
    required this.art,
  });
  final String id;
  final String name;
  final String species;
  final String room;

  /// Условия содержания, введённые пользователем для конкретного растения.
  final String careConditions;

  /// Идентификатор семейства из вспомогательного справочника.
  final String familyId;
  // These dates are derived by the ViewModel from the procedures.
  final DateTime? nextWatering;
  final DateTime? lastWateredOn;
  final bool nextWateringHasTime;
  final int art;

  /// Возвращает состояние полива относительно указанной даты.
  WateringStatus statusAt(DateTime now) {
    final due = nextWatering;
    final today = dateOnly(now);
    if (due != null &&
        (dateOnly(due).isBefore(today) ||
            (nextWateringHasTime && due.isBefore(now)))) {
      return WateringStatus.overdue;
    }
    if (due != null && sameDay(due, today)) return WateringStatus.today;
    if (lastWateredOn != null && sameDay(lastWateredOn!, now)) {
      return WateringStatus.watered;
    }
    return due == null ? WateringStatus.unscheduled : WateringStatus.upcoming;
  }
}

/// Расписание ухода: одна дата, интервал дней либо выбранные дни недели.
/// Времена хранятся в минутах от полуночи; пустой список использует настройки напоминаний.
class CareProcedure {
  const CareProcedure({
    this.id = '',
    required this.plantId,
    required this.date,
    required this.type,
    this.completedOn,
    this.weekly = false,
    this.fertilizerId = '',
    this.repeatEveryDays = 0,
    this.weekdays = const [],
    this.times = const [],
  });
  final String id;
  final String plantId;
  final DateTime date;
  final CareType type;
  final DateTime? completedOn;

  /// Прежний недельный режим сохраняется для чтения существующих расписаний.
  final bool weekly;
  final int repeatEveryDays;

  /// Дни недели от понедельника (1) до воскресенья (7).
  final List<int> weekdays;

  /// Отдельные времена процедур от 0 до 1439 минут; без повторяющихся значений.
  final List<int> times;
  bool get hasTimes => times.isNotEmpty;
  bool get tracksOccurrences => repeats || hasTimes;
  int get intervalDays => weekly ? 7 : repeatEveryDays;
  bool get repeats => weekdays.isNotEmpty || intervalDays > 0;
  String get repeatLabel => weekdays.isNotEmpty
      ? 'По дням недели: ${weekdays.map((d) => weekdayLabels[d - 1]).join(', ')}'
      : intervalDays == 1
      ? 'Ежедневно'
      : intervalDays == 7
      ? 'Раз в неделю'
      : intervalDays > 0
      ? 'Каждые $intervalDays дней'
      : 'Одна дата';
  final String fertilizerId;

  /// Проверяет день относительно начала расписания, не создавая список повторений.
  bool occursOn(DateTime day) {
    final start = dateOnly(date);
    final target = dateOnly(day);
    if (target.isBefore(start)) return false;
    if (weekdays.isNotEmpty) return weekdays.contains(target.weekday);
    final difference = calendarDaysBetween(start, target);
    return difference == 0 ||
        (intervalDays > 0 && difference % intervalDays == 0);
  }

  /// Находит ближайший день серии за постоянное число шагов.
  DateTime? nextDayOnOrAfter(DateTime from) {
    var day = dateOnly(from).isBefore(dateOnly(date))
        ? dateOnly(date)
        : dateOnly(from);
    if (weekdays.isNotEmpty) {
      for (var i = 0; i < 7; i++) {
        if (weekdays.contains(day.weekday)) return day;
        day = addDays(day, 1);
      }
      return null;
    }
    if (intervalDays <= 0) return sameDay(day, date) ? dateOnly(date) : null;
    final remainder = calendarDaysBetween(dateOnly(date), day) % intervalDays;
    return remainder == 0 ? day : addDays(day, intervalDays - remainder);
  }

  /// Возвращает отдельные события дня, в том числе несколько процедур одного вида.
  Iterable<DateTime> occurrencesOn(DateTime day) sync* {
    if (!occursOn(day)) return;
    if (!hasTimes) {
      yield dateOnly(day);
    } else {
      for (final minutes in times) {
        yield DateTime(
          day.year,
          day.month,
          day.day,
          minutes ~/ 60,
          minutes % 60,
        );
      }
    }
  }

  /// Ключ выполнения включает время только у расписаний с отдельными часами.
  DateTime occurrenceKey(DateTime at) => hasTimes ? at : dateOnly(at);

  /// Создаёт отображаемое событие, сохраняя идентификатор исходного расписания.
  CareProcedure occurrence(DateTime at, DateTime? completion) => CareProcedure(
    id: id,
    plantId: plantId,
    date: at,
    type: type,
    weekly: weekly,
    repeatEveryDays: repeatEveryDays,
    weekdays: weekdays,
    times: times,
    fertilizerId: fertilizerId,
    completedOn: completion,
  );
  bool get isCompleted => completedOn != null;

  /// Создаёт копию однократной процедуры с изменённой отметкой выполнения.
  CareProcedure withCompletion(DateTime? value) => occurrence(date, value);
}

const weekdayLabels = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];

/// Считает календарные дни без влияния переходов часового пояса.
int calendarDaysBetween(DateTime start, DateTime end) => DateTime.utc(
  end.year,
  end.month,
  end.day,
).difference(DateTime.utc(start.year, start.month, start.day)).inDays;

/// Форматирует выбранное время процедуры для русского интерфейса.
String clockLabel(int minutes) =>
    '${(minutes ~/ 60).toString().padLeft(2, '0')}:${(minutes % 60).toString().padLeft(2, '0')}';
