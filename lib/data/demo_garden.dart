import '../models/plant.dart';

/// Demonstration fixture for lab 1, anchored to the first launch date.
class DemoGarden {
  DemoGarden(DateTime today) {
    plants = [
      Plant(
        id: 'monstera',
        name: 'Монстера',
        species: 'Monstera deliciosa',
        room: 'Гостиная',
        nextWatering: addDays(today, -2),
        art: 0,
      ),
      Plant(
        id: 'ficus',
        name: 'Фикус',
        species: 'Ficus elastica',
        room: 'Спальня',
        nextWatering: today,
        art: 1,
      ),
      Plant(
        id: 'sansevieria',
        name: 'Сансевиерия',
        species: 'Dracaena trifasciata',
        room: 'Кабинет',
        nextWatering: addDays(today, 3),
        art: 2,
      ),
      Plant(
        id: 'spathiphyllum',
        name: 'Спатифиллум',
        species: 'Spathiphyllum wallisii',
        room: 'Гостиная',
        nextWatering: addDays(today, 1),
        art: 3,
      ),
    ];
    procedures = [
      for (final plant in plants)
        CareProcedure(
          plantId: plant.id,
          date: plant.nextWatering!,
          type: CareType.watering,
        ),
      CareProcedure(plantId: 'monstera', date: today, type: CareType.feeding),
      CareProcedure(
        plantId: 'ficus',
        date: addDays(today, 5),
        type: CareType.repotting,
      ),
      CareProcedure(
        plantId: 'sansevieria',
        date: addDays(today, 8),
        type: CareType.feeding,
      ),
    ];
  }
  late final List<Plant> plants;
  late final List<CareProcedure> procedures;
}
