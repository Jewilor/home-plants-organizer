import 'package:flutter/foundation.dart';
import '../data/demo_garden.dart';
import '../models/plant.dart';

class GardenViewModel extends ChangeNotifier {
  GardenViewModel({DateTime Function()? clock, DemoGarden? garden})
    : _clock = clock ?? DateTime.now {
    today = dateOnly(_clock());
    selectedDate = today;
    visibleMonth = DateTime(today.year, today.month);
    final source = garden ?? DemoGarden(today);
    plants = List.unmodifiable(source.plants);
    procedures = List.unmodifiable(source.procedures);
  }
  final DateTime Function() _clock;
  late DateTime today;
  late DateTime selectedDate;
  late DateTime visibleMonth;
  late final List<Plant> plants;
  late final List<CareProcedure> procedures;

  int get overdueCount =>
      plants.where((p) => p.statusAt(today) == WateringStatus.overdue).length;
  List<CareProcedure> proceduresOn(DateTime date) =>
      procedures.where((p) => sameDay(p.date, date)).toList();
  Plant plantFor(CareProcedure procedure) =>
      plants.firstWhere((p) => p.id == procedure.plantId);

  void selectDay(DateTime date) {
    selectedDate = dateOnly(date);
    visibleMonth = DateTime(date.year, date.month);
    notifyListeners();
  }

  void changeMonth(int offset) {
    visibleMonth = DateTime(visibleMonth.year, visibleMonth.month + offset);
    selectedDate = visibleMonth;
    notifyListeners();
  }

  void goToToday() {
    refreshToday();
    selectDay(today);
  }

  void refreshToday() {
    final current = dateOnly(_clock());
    if (current != today) {
      today = current;
      notifyListeners();
    }
  }
}
