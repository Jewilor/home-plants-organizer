import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:home_plants_organizer/models/plant.dart';
import 'package:home_plants_organizer/models/garden_snapshot.dart';
import 'package:home_plants_organizer/models/reference_entry.dart';
import 'package:home_plants_organizer/services/garden_repository.dart';
import 'package:home_plants_organizer/services/reference_repository.dart';
import 'package:home_plants_organizer/services/sqlite_garden_repository.dart';
import 'package:home_plants_organizer/services/hive_reference_repository.dart';
import 'package:home_plants_organizer/viewmodels/garden_view_model.dart';
import 'package:home_plants_organizer/viewmodels/reference_view_model.dart';
import 'package:home_plants_organizer/views/reference_screen.dart';

class ControlledRepository implements GardenRepository {
  final List<GardenSnapshot> saved = [];
  bool fail = false;
  @override
  Future<GardenSnapshot?> load() async => saved.isEmpty ? null : saved.last;
  @override
  Future<void> save(GardenSnapshot snapshot) async {
    await Future<void>.delayed(const Duration(milliseconds: 5));
    if (fail) throw StateError('Simulated disk error');
    saved.add(snapshot);
  }

  @override
  Future<void> close() async {}
}

class MemoryReferenceRepository implements ReferenceRepository {
  final data = <ReferenceKind, Map<String, ReferenceEntry>>{
    ReferenceKind.family: {},
    ReferenceKind.fertilizer: {},
  };
  int sequence = 0;
  @override
  Future<List<ReferenceEntry>> load(ReferenceKind kind) async =>
      data[kind]!.values.toList();
  @override
  Future<String> nextId(ReferenceKind kind) async =>
      '${kind.name}-${sequence++}';
  @override
  Future<void> save(ReferenceKind kind, ReferenceEntry entry) async {
    data[kind]![entry.id] = entry;
  }

  @override
  Future<void> delete(ReferenceKind kind, String id) async {
    data[kind]!.remove(id);
  }

  @override
  Future<void> close() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late Directory directory;
  final repositories = <SqliteGardenRepository>[];
  final catalogs = <HiveReferenceRepository>[];
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('plants_lab3_test_');
  });
  tearDown(() async {
    for (final repository in repositories) {
      if (repository.database.isOpen) await repository.close();
    }
    repositories.clear();
    for (final catalog in catalogs) {
      await catalog.close();
    }
    catalogs.clear();
    final resolved = directory.absolute;
    if (path.equals(resolved.parent.path, Directory.systemTemp.absolute.path) &&
        path.basename(resolved.path).startsWith('plants_lab3_test_')) {
      await resolved.delete(recursive: true);
    }
  });
  Future<SqliteGardenRepository> openSqlite([
    String file = 'garden.sqlite',
  ]) async {
    final repository = await SqliteGardenRepository.open(
      path: path.join(directory.path, file),
      factory: databaseFactoryFfi,
    );
    repositories.add(repository);
    return repository;
  }

  Future<HiveReferenceRepository> openHive() async {
    final catalog = await HiveReferenceRepository.open(directory.path);
    catalogs.add(catalog);
    return catalog;
  }

  test(
    'SQLite restores plants, manual conditions, weekly marks, history and unique IDs',
    () async {
      var catalog = await openHive();
      var references = await ReferenceViewModel.load(catalog);
      var repository = await openSqlite();
      var garden = GardenViewModel(
        repository: repository,
        references: references,
        clock: () => DateTime(2026, 10, 4),
      );
      final id = garden.savePlant(
        name: 'Учебная аглаонема',
        species: 'Aglaonema commutatum',
        room: 'Кабинет',
        careConditions: 'Рассеянный свет.',
        familyId: 'family-aroids',
        firstWatering: garden.today,
        weekly: true,
      );
      final feeding = garden.saveProcedure(
        plantId: id,
        date: garden.today,
        type: CareType.feeding,
        weekly: true,
        fertilizerId: 'fertilizer-universal',
      );
      garden.toggleWateredToday(id);
      garden.recordCare(
        plantId: id,
        type: CareType.feeding,
        performedOn: garden.today,
        note: 'Подкормка выполнена',
      );
      await garden.flush();
      final nextSequence = garden.snapshot.sequence;
      garden.dispose();
      references.dispose();
      await repository.close();
      await catalog.close();
      catalog = await openHive();
      references = await ReferenceViewModel.load(catalog);
      repository = await openSqlite();
      garden = GardenViewModel(
        repository: repository,
        references: references,
        snapshot: await repository.load(),
        clock: () => DateTime(2026, 10, 4),
      );
      final plant = garden.plants.firstWhere((plant) => plant.id == id);
      expect(plant.name, 'Учебная аглаонема');
      expect(plant.species, 'Aglaonema commutatum');
      expect(plant.room, 'Кабинет');
      expect(plant.careConditions, 'Рассеянный свет.');
      expect(plant.familyId, 'family-aroids');
      expect(plant.nextWatering, DateTime(2026, 10, 11));
      expect(plant.statusAt(garden.today), WateringStatus.watered);
      expect(
        garden.procedureById(feeding).fertilizerId,
        'fertilizer-universal',
      );
      expect(
        garden
            .proceduresOn(DateTime(2026, 10, 4))
            .where((p) => p.plantId == id)
            .every((p) => p.isCompleted),
        isTrue,
      );
      expect(garden.records.where((record) => record.plantId == id).length, 2);
      final fresh = garden.savePlant(name: 'Новое растение');
      expect(fresh, 'plant-$nextSequence');
      garden.toggleWateredToday(id);
      await garden.flush();
      expect(
        garden.plants.firstWhere((p) => p.id == id).nextWatering,
        DateTime(2026, 10, 4),
      );
      expect(
        (await repository.load())!.records.where(
          (r) => r.plantId == id && r.type == CareType.watering,
        ),
        isEmpty,
      );
      garden.dispose();
      references.dispose();
    },
  );

  test(
    'Deleting every plant stays empty after reopening and does not reseed',
    () async {
      var repository = await openSqlite();
      var garden = GardenViewModel(repository: repository);
      for (final plant in List.of(garden.plants)) {
        garden.deletePlant(plant.id);
      }
      await garden.flush();
      garden.dispose();
      await repository.close();
      repository = await openSqlite();
      garden = GardenViewModel(
        repository: repository,
        snapshot: await repository.load(),
      );
      expect(garden.plants, isEmpty);
      expect(garden.procedures, isEmpty);
      expect(garden.records, isEmpty);
      garden.dispose();
    },
  );

  test(
    'SQLite foreign keys cascade and an invalid transaction preserves the previous state',
    () async {
      final repository = await openSqlite();
      final garden = GardenViewModel(
        repository: repository,
        clock: () => DateTime(2026, 10, 4),
      );
      final id = garden.savePlant(
        name: 'Связи',
        firstWatering: garden.today,
        weekly: true,
      );
      garden.toggleWateredToday(id);
      await garden.flush();
      final before = (await repository.load())!;
      await expectLater(
        repository.save(
          GardenSnapshot(
            plants: const [],
            procedures: [
              CareProcedure(
                id: 'orphan',
                plantId: 'missing',
                date: garden.today,
                type: CareType.watering,
              ),
            ],
            records: const [],
            completions: const {},
            sequence: 99,
          ),
        ),
        throwsA(isA<DatabaseException>()),
      );
      expect(
        (await repository.load())!.plants.map((p) => p.id),
        before.plants.map((p) => p.id),
      );
      await repository.database.delete(
        'plants',
        where: 'id = ?',
        whereArgs: [id],
      );
      expect(
        await repository.database.query(
          'care_procedures',
          where: 'plant_id = ?',
          whereArgs: [id],
        ),
        isEmpty,
      );
      expect(
        await repository.database.query(
          'care_records',
          where: 'plant_id = ?',
          whereArgs: [id],
        ),
        isEmpty,
      );
      expect(await repository.database.query('procedure_completions'), isEmpty);
      garden.dispose();
    },
  );

  test(
    'Version one migration preserves plant fields and adds catalog links',
    () async {
      final file = path.join(directory.path, 'garden.sqlite');
      final old = await databaseFactoryFfi.openDatabase(
        file,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (db, _) => SqliteGardenRepository.createVersionOne(db),
        ),
      );
      await old.insert('plants', {
        'id': 'legacy',
        'name': 'Сохранённое растение',
        'species': 'Monstera deliciosa',
        'room': 'Гостиная',
        'care_conditions': 'Рассеянный свет.',
        'art': 1,
      });
      await old.insert('settings', {'key': 'initialized', 'value': '1'});
      await old.insert('settings', {'key': 'sequence', 'value': '17'});
      await old.close();
      final repository = await openSqlite();
      final state = (await repository.load())!;
      expect(state.plants.single.name, 'Сохранённое растение');
      expect(state.plants.single.careConditions, 'Рассеянный свет.');
      expect(state.plants.single.familyId, isEmpty);
      expect(state.sequence, 17);
      expect(
        await repository.database.getVersion(),
        SqliteGardenRepository.schemaVersion,
      );
      expect(
        (await repository.database.rawQuery(
          'PRAGMA table_info(care_procedures)',
        )).any((row) => row['name'] == 'fertilizer_id'),
        isTrue,
      );
    },
  );

  test(
    'Rapid mutations save in order and earlier snapshots remain immutable',
    () async {
      final repository = ControlledRepository();
      final garden = GardenViewModel(
        repository: repository,
        clock: () => DateTime(2026, 10, 4),
      );
      final id = garden.savePlant(
        name: 'Первое название',
        firstWatering: garden.today,
        weekly: true,
      );
      garden.savePlant(id: id, name: 'Второе название');
      garden.toggleWateredToday(id);
      expect(garden.saving, isTrue);
      await garden.flush();
      expect(garden.saving, isFalse);
      expect(repository.saved.length, 3);
      expect(
        repository.saved.first.plants.firstWhere((p) => p.id == id).name,
        'Первое название',
      );
      expect(repository.saved.first.completions, isEmpty);
      expect(
        repository.saved.last.plants.firstWhere((p) => p.id == id).name,
        'Второе название',
      );
      expect(repository.saved.last.completions.values.single.length, 1);
      garden.dispose();
    },
  );

  test(
    'A write error is visible and retry persists the current state',
    () async {
      final repository = ControlledRepository()..fail = true;
      final garden = GardenViewModel(repository: repository);
      final id = garden.savePlant(name: 'Не потерять');
      await expectLater(garden.flush(), throwsStateError);
      expect(garden.storageError, isNotNull);
      expect(garden.plants.any((p) => p.id == id), isTrue);
      repository.fail = false;
      await garden.persist();
      expect(garden.storageError, isNull);
      expect(repository.saved.single.plants.any((p) => p.id == id), isTrue);
      garden.dispose();
    },
  );

  test(
    'Hive restores edited icons, reserves IDs and keeps an intentionally empty catalog',
    () async {
      var catalog = await openHive();
      var model = await ReferenceViewModel.load(catalog);
      final id = await model.saveEntry(
        kind: ReferenceKind.family,
        name: 'Марантовые',
        icon: ReferenceIcon.flower,
      );
      await model.saveEntry(
        kind: ReferenceKind.family,
        id: id,
        name: 'Марантовые растения',
        icon: ReferenceIcon.leaf,
      );
      final fertilizer = await model.saveEntry(
        kind: ReferenceKind.fertilizer,
        name: 'Учебное удобрение',
        icon: ReferenceIcon.nutrients,
      );
      await model.deleteEntry(ReferenceKind.fertilizer, fertilizer);
      model.dispose();
      await catalog.close();
      catalog = await openHive();
      model = await ReferenceViewModel.load(catalog);
      expect(model.find(ReferenceKind.family, id)!.name, 'Марантовые растения');
      expect(model.find(ReferenceKind.family, id)!.icon, ReferenceIcon.leaf);
      expect(model.find(ReferenceKind.fertilizer, fertilizer), isNull);
      final next = await model.saveEntry(
        kind: ReferenceKind.fertilizer,
        name: 'Следующая запись',
        icon: ReferenceIcon.water,
      );
      expect(next, isNot(fertilizer));
      for (final entry in model.entries(ReferenceKind.family)) {
        await model.deleteEntry(ReferenceKind.family, entry.id);
      }
      model.dispose();
      await catalog.close();
      catalog = await openHive();
      model = await ReferenceViewModel.load(catalog);
      expect(model.entries(ReferenceKind.family), isEmpty);
      model.dispose();
    },
  );

  test(
    'References are validated, renaming keeps links and deletion is blocked while used',
    () async {
      final catalog = await openHive();
      final references = await ReferenceViewModel.load(catalog);
      final garden = GardenViewModel(
        references: references,
        clock: () => DateTime(2026, 10, 4),
      );
      final id = garden.savePlant(name: 'Аглаонема', familyId: 'family-aroids');
      final procedure = garden.saveProcedure(
        plantId: id,
        date: garden.today,
        type: CareType.feeding,
        fertilizerId: 'fertilizer-universal',
      );
      await expectLater(
        references.deleteEntry(ReferenceKind.family, 'family-aroids'),
        throwsArgumentError,
      );
      await expectLater(
        references.deleteEntry(
          ReferenceKind.fertilizer,
          'fertilizer-universal',
        ),
        throwsArgumentError,
      );
      await references.saveEntry(
        kind: ReferenceKind.family,
        id: 'family-aroids',
        name: 'Ароидные растения',
        icon: ReferenceIcon.leaf,
      );
      expect(
        garden.plants.firstWhere((p) => p.id == id).familyId,
        'family-aroids',
      );
      expect(
        references
            .find(
              ReferenceKind.family,
              garden.plants.firstWhere((p) => p.id == id).familyId,
            )!
            .name,
        'Ароидные растения',
      );
      expect(
        () => garden.savePlant(name: 'Ошибка', familyId: 'unknown'),
        throwsArgumentError,
      );
      expect(
        () => garden.saveProcedure(
          plantId: id,
          date: garden.today,
          type: CareType.feeding,
          fertilizerId: 'unknown',
        ),
        throwsArgumentError,
      );
      garden.deleteProcedure(procedure);
      await references.deleteEntry(
        ReferenceKind.fertilizer,
        'fertilizer-universal',
      );
      garden.deletePlant(id);
      await references.deleteEntry(ReferenceKind.family, 'family-aroids');
      garden.dispose();
      references.dispose();
    },
  );

  testWidgets('Catalog editor works on a compact phone and shows validation', (
    tester,
  ) async {
    final model = await ReferenceViewModel.load(MemoryReferenceRepository());
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(home: ReferenceScreen(model: model)));
    await tester.tap(find.byKey(const ValueKey('add-reference')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Сохранить'));
    await tester.pumpAndSettle();
    expect(find.text('Введите название от 1 до 80 символов.'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('reference-name')),
      'Тестовое семейство',
    );
    await tester.tap(find.byKey(const ValueKey('reference-icon')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Солнце').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Сохранить'));
    await tester.pumpAndSettle();
    expect(find.text('Тестовое семейство'), findsOneWidget);
    expect(model.entries(ReferenceKind.family).single.icon, ReferenceIcon.sun);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    model.dispose();
  });
}
