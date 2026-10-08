import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:home_plants_organizer/models/care_guide.dart';
import 'package:home_plants_organizer/models/plant.dart';
import 'package:home_plants_organizer/models/reference_entry.dart';
import 'package:home_plants_organizer/services/hive_reference_repository.dart';
import 'package:home_plants_organizer/services/sqlite_garden_repository.dart';
import 'package:home_plants_organizer/viewmodels/garden_view_model.dart';
import 'package:home_plants_organizer/viewmodels/reference_view_model.dart';
import 'package:home_plants_organizer/views/care_guide_screen.dart';
import 'lab3_storage_test.dart' show MemoryReferenceRepository;
import 'lab4_test.dart' show FakeEncyclopedia;

CareGuide familyGuide([String? family = 'Araceae']) => CareGuide.fromJson({
  'species': 'Monstera deliciosa',
  'family': family,
  'light': 'Рассеянный свет.',
  'humidity': 'Умеренная влажность.',
  'watering': 'Проверять влажность почвы.',
  'sourceName': 'Тестовая энциклопедия',
  'sourceUrl': 'https://example.org/encyclopedia',
  'downloadedAt': '2026-10-08T09:00:00',
  'wateringIntervalDays': 7,
});

class ControlledFamilyRepository extends MemoryReferenceRepository {
  bool fail = false;
  Completer<void>? wait;
  @override
  Future<void> save(ReferenceKind kind, ReferenceEntry entry) async {
    if (wait != null) await wait!.future;
    if (fail) throw StateError('Catalog write failed');
    await super.save(kind, entry);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  test('Older guides remain readable and family survives JSON restoration', () {
    final older = familyGuide().toJson()..remove('family');
    expect(CareGuide.fromJson(older).family, isEmpty);
    final received = familyGuide();
    expect(received.family, 'Ароидные');
    expect(CareGuide.fromJson(received.toJson()).family, 'Ароидные');
    expect(familyGuide('  Новое   семейство  ').family, 'Новое семейство');
    for (final invalid in [42, <String>[], 'a' * 81]) {
      final data = familyGuide().toJson()..['family'] = invalid;
      expect(() => CareGuide.fromJson(data), throwsFormatException);
    }
  });

  test(
    'A new family is created once and assigned to both scanned plants',
    () async {
      final store = MemoryReferenceRepository();
      final references = await ReferenceViewModel.load(store);
      final garden = GardenViewModel(references: references);
      addTearDown(garden.dispose);
      addTearDown(references.dispose);
      final first = garden.savePlant(
        name: 'Монстера',
        species: 'Monstera deliciosa',
        room: 'Гостиная',
        careConditions: 'Мои условия.',
      );
      final second = garden.savePlant(name: 'Вторая монстера');
      await garden.applyCareGuide(first, familyGuide());
      await garden.applyCareGuide(second, familyGuide('  araceae '));
      await garden.applyCareGuide(first, familyGuide('Ароидные'));
      final families = references.entries(ReferenceKind.family);
      expect(families, hasLength(1));
      expect(families.single.name, 'Ароидные');
      expect(
        garden.plants.firstWhere((p) => p.id == first).familyId,
        families.single.id,
      );
      expect(
        garden.plants.firstWhere((p) => p.id == second).familyId,
        families.single.id,
      );
      expect(garden.plants.firstWhere((p) => p.id == first).room, 'Гостиная');
      expect(
        garden.plants.firstWhere((p) => p.id == first).careConditions,
        'Мои условия.',
      );
      await expectLater(
        references.deleteEntry(ReferenceKind.family, families.single.id),
        throwsArgumentError,
      );
    },
  );

  test(
    'Existing scientific name is reused and missing family preserves manual choice',
    () async {
      final store = MemoryReferenceRepository();
      final references = await ReferenceViewModel.load(store);
      final existing = await references.saveEntry(
        kind: ReferenceKind.family,
        name: '  ARACEAE  ',
        icon: ReferenceIcon.flower,
      );
      final garden = GardenViewModel(references: references);
      addTearDown(garden.dispose);
      addTearDown(references.dispose);
      final id = garden.savePlant(name: 'Монстера');
      await garden.applyCareGuide(id, familyGuide('Ароидные'));
      await garden.applyCareGuide(id, familyGuide(null));
      expect(references.entries(ReferenceKind.family), hasLength(1));
      expect(
        references.find(ReferenceKind.family, existing)!.icon,
        ReferenceIcon.flower,
      );
      expect(garden.plants.firstWhere((p) => p.id == id).familyId, existing);
      expect(garden.careGuideFor(id)!.family, isEmpty);
    },
  );

  test('Invalid schedule is rejected before a family is inserted', () async {
    final store = MemoryReferenceRepository();
    final references = await ReferenceViewModel.load(store);
    final garden = GardenViewModel(references: references);
    addTearDown(garden.dispose);
    addTearDown(references.dispose);
    final id = garden.savePlant(name: 'Монстера');
    await expectLater(
      garden.applyCareGuide(
        id,
        familyGuide(),
        firstWatering: garden.today,
        intervalDays: 0,
      ),
      throwsArgumentError,
    );
    expect(references.entries(ReferenceKind.family), isEmpty);
    expect(garden.careGuideFor(id), isNull);
    expect(garden.plants.firstWhere((p) => p.id == id).familyId, isEmpty);
  });

  test(
    'Failed Hive write leaves card, guide and schedule unchanged and can be retried',
    () async {
      final store = ControlledFamilyRepository()..fail = true;
      final references = await ReferenceViewModel.load(store);
      final garden = GardenViewModel(references: references);
      addTearDown(garden.dispose);
      addTearDown(references.dispose);
      final id = garden.savePlant(
        name: 'Монстера',
        firstWatering: garden.today,
      );
      final previousId = garden.procedures.last.id;
      await expectLater(
        garden.applyCareGuide(
          id,
          familyGuide(),
          firstWatering: addDays(garden.today, 1),
          intervalDays: 7,
        ),
        throwsStateError,
      );
      expect(garden.procedures.last.id, previousId);
      expect(garden.careGuideFor(id), isNull);
      expect(garden.plants.firstWhere((p) => p.id == id).familyId, isEmpty);
      expect(references.entries(ReferenceKind.family), isEmpty);
      store.fail = false;
      await garden.applyCareGuide(id, familyGuide());
      expect(references.entries(ReferenceKind.family), hasLength(1));
      expect(garden.careGuideFor(id), isNotNull);
    },
  );

  test(
    'Deleting a plant during family creation does not recreate or link it',
    () async {
      final gate = Completer<void>();
      final store = ControlledFamilyRepository()..wait = gate;
      final references = await ReferenceViewModel.load(store);
      final garden = GardenViewModel(references: references);
      addTearDown(garden.dispose);
      addTearDown(references.dispose);
      final id = garden.savePlant(name: 'Монстера');
      final saving = garden.applyCareGuide(id, familyGuide());
      final check = expectLater(saving, throwsArgumentError);
      await Future<void>.delayed(Duration.zero);
      garden.deletePlant(id);
      gate.complete();
      await check;
      expect(garden.plants.any((p) => p.id == id), isFalse);
      expect(garden.careGuideFor(id), isNull);
    },
  );

  test(
    'Auto-created Hive family and SQLite plant link survive reopening both stores',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'plants_family_test_',
      );
      HiveReferenceRepository? catalog;
      SqliteGardenRepository? repository;
      ReferenceViewModel? references;
      GardenViewModel? garden;
      try {
        final hivePath = path.join(directory.path, 'catalog');
        await Directory(hivePath).create(recursive: true);
        catalog = await HiveReferenceRepository.open(hivePath);
        // Удаляем неиспользуемую начальную запись, чтобы проверить создание из ответа.
        await catalog.delete(ReferenceKind.family, 'family-aroids');
        references = await ReferenceViewModel.load(catalog);
        final dbPath = path.join(directory.path, 'garden.sqlite');
        repository = await SqliteGardenRepository.open(
          path: dbPath,
          factory: databaseFactoryFfi,
        );
        garden = GardenViewModel(
          repository: repository,
          references: references,
        );
        final id = garden.savePlant(
          name: 'Монстера',
          careConditions: 'Ручные условия.',
        );
        await garden.applyCareGuide(
          id,
          familyGuide(),
          firstWatering: garden.today,
          intervalDays: 7,
        );
        final familyId = garden.plants.firstWhere((p) => p.id == id).familyId;
        garden.dispose();
        garden = null;
        references.dispose();
        references = null;
        await repository.close();
        repository = null;
        await catalog.close();
        catalog = null;

        catalog = await HiveReferenceRepository.open(hivePath);
        references = await ReferenceViewModel.load(catalog);
        repository = await SqliteGardenRepository.open(
          path: dbPath,
          factory: databaseFactoryFfi,
        );
        garden = GardenViewModel(
          repository: repository,
          references: references,
          snapshot: await repository.load(),
        );
        final restored = garden.plants.firstWhere((p) => p.id == id);
        expect(restored.familyId, familyId);
        expect(
          references.find(ReferenceKind.family, familyId)!.name,
          'Ароидные',
        );
        expect(
          references
              .entries(ReferenceKind.family)
              .where((e) => e.name == 'Ароидные'),
          hasLength(1),
        );
        expect(restored.careConditions, 'Ручные условия.');
        expect(garden.careGuideFor(id)!.family, 'Ароидные');
        expect(
          garden.procedures.firstWhere((p) => p.plantId == id).intervalDays,
          7,
        );
      } finally {
        garden?.dispose();
        references?.dispose();
        await repository?.close();
        await catalog?.close();
        final resolved = directory.absolute;
        if (path.equals(
              resolved.parent.path,
              Directory.systemTemp.absolute.path,
            ) &&
            path.basename(resolved.path).startsWith('plants_family_test_')) {
          await resolved.delete(recursive: true);
        }
      }
    },
  );

  testWidgets(
    'Family is displayed and assigned from the guide on a compact phone',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final references = await ReferenceViewModel.load(
        MemoryReferenceRepository(),
      );
      final api = FakeEncyclopedia();
      final garden = GardenViewModel(references: references, encyclopedia: api);
      addTearDown(garden.dispose);
      addTearDown(references.dispose);
      final id = garden.savePlant(
        name: 'Монстера',
        species: 'Monstera deliciosa',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: CareGuideScreen(garden: garden, plantId: id),
        ),
      );
      api.requests.single.complete(familyGuide());
      await tester.pumpAndSettle();
      expect(find.text('Семейство: Ароидные'), findsOneWidget);
      await tester.ensureVisible(find.byKey(const ValueKey('save-care-guide')));
      await tester.tap(find.byKey(const ValueKey('save-care-guide')));
      await tester.pumpAndSettle();
      expect(garden.careGuideFor(id)!.family, 'Ароидные');
      final entry = references.entries(ReferenceKind.family).single;
      expect(garden.plants.firstWhere((p) => p.id == id).familyId, entry.id);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
