DateTime dateOnly(DateTime date) => DateTime(date.year, date.month, date.day);

/// Calendar arithmetic deliberately avoids Duration(days:) across DST changes.
DateTime addDays(DateTime date, int days) =>
    DateTime(date.year, date.month, date.day + days);

bool sameDay(DateTime a, DateTime b) => dateOnly(a) == dateOnly(b);

enum WateringStatus { overdue, today, upcoming }
enum CareType { watering, feeding, repotting }

extension CareTypeLabel on CareType {
  String get label => switch (this) {
    CareType.watering => 'Полив',
    CareType.feeding => 'Подкормка',
    CareType.repotting => 'Пересадка',
  };
}

class Plant {
  const Plant({required this.id, required this.name, required this.species,
    required this.room, required this.nextWatering, required this.art});
  final String id;
  final String name;
  final String species;
  final String room;
  final DateTime nextWatering;
  final int art;

  WateringStatus statusAt(DateTime now) {
    final due = dateOnly(nextWatering);
    final today = dateOnly(now);
    if (due.isBefore(today)) return WateringStatus.overdue;
    if (due == today) return WateringStatus.today;
    return WateringStatus.upcoming;
  }
}

class CareProcedure {
  const CareProcedure({required this.plantId, required this.date, required this.type});
  final String plantId;
  final DateTime date;
  final CareType type;
}
