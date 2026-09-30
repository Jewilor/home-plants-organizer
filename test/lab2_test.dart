import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:home_plants_organizer/models/plant.dart';
import 'package:home_plants_organizer/models/botanical_profile.dart';
import 'package:home_plants_organizer/services/botanical_repository.dart';
import 'package:home_plants_organizer/services/label_recognition_service.dart';
import 'package:home_plants_organizer/viewmodels/garden_view_model.dart';
import 'package:home_plants_organizer/viewmodels/plant_detail_view_model.dart';
import 'package:home_plants_organizer/viewmodels/label_scan_view_model.dart';

class FakeRepository implements BotanicalRepository {
  @override
  Future<List<BotanicalProfile>> load() async => [
    const BotanicalProfile(
      name: 'Монстера',
      species: 'Monstera deliciosa',
      aliases: ['Монстера', 'Monstera deliciosa'],
      light: 'Рассеянный',
      humidity: 'Умеренная',
      source: 'fixture',
    ),
  ];
}

class FakeRecognition implements LabelRecognitionService {
  String? text = 'HOME GARDEN\nMonstera deliciosa\nPrice 12.90';
  @override
  Future<String?> pickAndRecognize(ImageSource source) async => text;
  @override
  Future<String> recognizeSample(String asset) async => text!;
  @override
  Future<String?> recoverLostImage() async => null;
  @override
  Future<void> close() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'Weekly recurrence crosses months, years, and leap days without a horizon',
    () {
      final model = GardenViewModel(clock: () => DateTime(2024, 2, 29));
      final id = model.savePlant(name: 'Тест');
      final series = model.saveProcedure(
        plantId: id,
        date: DateTime(2024, 2, 29),
        type: CareType.watering,
        weekly: true,
      );
      expect(model.proceduresOn(DateTime(2024, 3, 7)).single.id, series);
      expect(
        model.proceduresOn(DateTime(2024, 3, 6)).where((p) => p.id == series),
        isEmpty,
      );
      expect(
        model.proceduresOn(DateTime(2024, 2, 22)).where((p) => p.id == series),
        isEmpty,
      );
      expect(model.proceduresOn(DateTime(2030, 1, 3)).single.id, series);
      model.dispose();
    },
  );
  test(
    'Marking weekly watering advances next due date and undo restores it',
    () {
      final model = GardenViewModel(clock: () => DateTime(2026, 12, 31));
      final id = model.savePlant(
        name: 'Тест',
        firstWatering: model.today,
        weekly: true,
      );
      model.toggleWateredToday(id);
      final plant = model.plants.firstWhere((p) => p.id == id);
      expect(plant.nextWatering, DateTime(2027, 1, 7));
      expect(plant.statusAt(model.today), WateringStatus.watered);
      expect(
        model.proceduresOn(DateTime(2027, 1, 7)).single.isCompleted,
        isFalse,
      );
      expect(model.records.where((r) => r.plantId == id).length, 1);
      model.toggleWateredToday(id);
      expect(
        model.plants.firstWhere((p) => p.id == id).nextWatering,
        model.today,
      );
      expect(model.records.where((r) => r.plantId == id), isEmpty);
      model.dispose();
    },
  );
  test(
    'Overdue weekly occurrences are completed without closing future dates',
    () {
      final model = GardenViewModel(clock: () => DateTime(2026, 10, 14));
      final id = model.savePlant(
        name: 'Тест',
        firstWatering: DateTime(2026, 9, 30),
        weekly: true,
      );
      model.toggleWateredToday(id);
      expect(
        model.plants.firstWhere((p) => p.id == id).nextWatering,
        DateTime(2026, 10, 21),
      );
      expect(
        model.proceduresOn(DateTime(2026, 10, 7)).single.isCompleted,
        isTrue,
      );
      model.dispose();
    },
  );
  test(
    'Editing and deleting a series changes all repeats but preserves actual history',
    () {
      final model = GardenViewModel(clock: () => DateTime(2026, 9, 30));
      final id = model.savePlant(name: 'Тест');
      final series = model.saveProcedure(
        plantId: id,
        date: model.today,
        type: CareType.feeding,
        weekly: true,
      );
      model.recordCare(
        plantId: id,
        type: CareType.feeding,
        performedOn: model.today,
        note: 'Выполнено',
      );
      model.saveProcedure(
        id: series,
        plantId: id,
        date: DateTime(2026, 10, 1),
        type: CareType.feeding,
        weekly: true,
      );
      expect(model.proceduresOn(DateTime(2026, 10, 7)), isEmpty);
      expect(
        model
            .proceduresOn(DateTime(2026, 10, 8))
            .firstWhere((p) => p.id == series)
            .id,
        series,
      );
      model.deleteProcedure(series);
      expect(
        model.proceduresOn(DateTime(2026, 10, 8)).where((p) => p.id == series),
        isEmpty,
      );
      expect(
        model.records.where((r) => r.plantId == id).single.note,
        'Выполнено',
      );
      model.deletePlant(id);
      expect(model.records.where((r) => r.plantId == id), isEmpty);
      model.dispose();
    },
  );
  test('Duplicate occurrence and overlapping series are rejected', () {
    final model = GardenViewModel(clock: () => DateTime(2026, 9, 30));
    final id = model.savePlant(name: 'Тест');
    model.saveProcedure(
      plantId: id,
      date: model.today,
      type: CareType.watering,
      weekly: true,
    );
    expect(
      () => model.saveProcedure(
        plantId: id,
        date: DateTime(2026, 10, 7),
        type: CareType.watering,
      ),
      throwsArgumentError,
    );
    expect(
      () => model.saveProcedure(
        plantId: id,
        date: DateTime(2026, 10, 14),
        type: CareType.watering,
        weekly: true,
      ),
      throwsArgumentError,
    );
    model.dispose();
  });
  test('Future journal records and duplicate records are rejected', () {
    final model = GardenViewModel(clock: () => DateTime(2026, 9, 30));
    final id = model.savePlant(name: 'Тест');
    expect(
      () => model.recordCare(
        plantId: id,
        type: CareType.repotting,
        performedOn: DateTime(2026, 10, 1),
      ),
      throwsArgumentError,
    );
    model.recordCare(
      plantId: id,
      type: CareType.repotting,
      performedOn: model.today,
    );
    expect(
      () => model.recordCare(
        plantId: id,
        type: CareType.repotting,
        performedOn: model.today,
      ),
      throwsArgumentError,
    );
    model.dispose();
  });
  test(
    'Details resolve species independently of nickname and filter journal',
    () async {
      final garden = GardenViewModel(clock: () => DateTime(2026, 9, 30));
      garden.savePlant(
        id: 'monstera',
        name: 'Любимая',
        species: 'Monstera deliciosa',
      );
      final detail = PlantDetailViewModel(
        garden: garden,
        plantId: 'monstera',
        repository: FakeRepository(),
      );
      await detail.load();
      expect(detail.profile?.species, 'Monstera deliciosa');
      expect(detail.history.length, 3);
      detail.selectFilter(CareType.repotting);
      expect(detail.history.single.type, CareType.repotting);
      garden.deletePlant('monstera');
      expect(detail.plant, isNull);
      detail.dispose();
      garden.dispose();
    },
  );
  test(
    'The asset repository contains profiles and unknown species has no guessed advice',
    () async {
      final profiles = await AssetBotanicalRepository().load();
      expect(profiles.length, 4);
      expect(profileFor(profiles, 'Unknown plant', 'Новая'), isNull);
      expect(
        profileFor(profiles, 'Dracaena trifasciata', 'Переименована')?.name,
        'Сансевиерия',
      );
    },
  );
  test(
    'Recognition selects botanical name instead of shop name or price',
    () async {
      final service = FakeRecognition();
      final model = LabelScanViewModel(
        service: service,
        repository: FakeRepository(),
      );
      await model.scanSample('fixture');
      expect(model.suggestion, 'Monstera deliciosa');
      expect(model.profile?.name, 'Монстера');
      service.text = null;
      await model.scanCamera();
      expect(model.suggestion, 'Monstera deliciosa');
      expect(model.busy, isFalse);
      expect(model.error, isNull);
      model.dispose();
    },
  );
  test('Recognition refuses to turn a price-only label into a plant name', () {
    expect(LabelScanViewModel.suggestName('Price 12.90\nEUR 5', []), '');
  });
}
