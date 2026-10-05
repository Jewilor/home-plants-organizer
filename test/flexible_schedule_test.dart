import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:home_plants_organizer/models/garden_snapshot.dart';
import 'package:home_plants_organizer/models/plant.dart';
import 'package:home_plants_organizer/models/reminder.dart';
import 'package:home_plants_organizer/services/reminder_service.dart';
import 'package:home_plants_organizer/services/sqlite_garden_repository.dart';
import 'package:home_plants_organizer/viewmodels/garden_view_model.dart';
import 'package:home_plants_organizer/views/editors.dart';
import 'package:home_plants_organizer/views/garden_screen.dart';

class ReminderProbe implements ReminderService {
  List<CareReminder> pending = [];
  @override
  Future<bool> permitted() async => true;
  @override
  Future<bool> requestPermission() async => true;
  @override
  Future<void> replace(List<CareReminder> reminders) async =>
      pending = List.of(reminders);
  @override
  Future<void> showTest() async {}
}

GardenSnapshot empty() => GardenSnapshot(
  plants: [],
  procedures: [],
  records: [],
  completions: {},
  sequence: 0,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  test('Weekdays respect the start date, year boundary and distant months', () {
    final p = CareProcedure(
      plantId: 'p',
      date: DateTime(2026, 12, 31),
      type: CareType.watering,
      weekdays: [1, 3, 5],
      times: [480, 1200],
    );
    expect(p.occursOn(DateTime(2026, 12, 30)), isFalse);
    expect(p.occursOn(DateTime(2026, 12, 31)), isFalse);
    expect(p.nextDayOnOrAfter(p.date), DateTime(2027, 1, 1));
    expect(p.occurrencesOn(DateTime(2027, 1, 1)), [
      DateTime(2027, 1, 1, 8),
      DateTime(2027, 1, 1, 20),
    ]);
    expect(p.occursOn(DateTime(2027, 1, 2)), isFalse);
    expect(p.nextDayOnOrAfter(DateTime(2027, 1, 2)), DateTime(2027, 1, 4));
    expect(p.occursOn(DateTime(2030, 1, 7)), isTrue);
  });

  test(
    'Daily and alternate-day recurrence retain multiple times across leap day',
    () {
      final p = CareProcedure(
        plantId: 'p',
        date: DateTime(2024, 2, 28),
        type: CareType.watering,
        repeatEveryDays: 2,
        times: [0, 480, 1439],
      );
      expect(p.occurrencesOn(DateTime(2024, 2, 29)), isEmpty);
      expect(p.nextDayOnOrAfter(DateTime(2024, 2, 29)), DateTime(2024, 3, 1));
      expect(p.occurrencesOn(DateTime(2024, 3, 1)).length, 3);
      final daily = CareProcedure(
        plantId: 'p',
        date: p.date,
        type: p.type,
        repeatEveryDays: 1,
        times: [480, 1200],
      );
      expect(daily.occurrencesOn(DateTime(2024, 2, 29)).length, 2);
    },
  );

  test(
    'Morning completion keeps evening pending, reminders and overdue state',
    () async {
      var now = DateTime(2026, 10, 5, 7);
      final reminders = ReminderProbe();
      final garden = GardenViewModel(
        snapshot: empty(),
        clock: () => now,
        reminderService: reminders,
      );
      addTearDown(garden.dispose);
      final plant = garden.savePlant(name: 'Фикус');
      final series = garden.saveProcedure(
        plantId: plant,
        date: garden.today,
        type: CareType.watering,
        repeatEveryDays: 1,
        times: [1200, 480],
      );
      await garden.configureReminders(enabled: true, hour: 10);
      await garden.configureWateringReminders(individual: true);
      await garden.setWateringReminderTime(
        plant,
        const ReminderTime(hour: 18, minute: 0),
      );
      expect(reminders.pending.take(2).map((r) => r.date.hour), [8, 20]);
      now = DateTime(2026, 10, 5, 9);
      garden.toggleProcedureCompleted(series, DateTime(2026, 10, 5, 8));
      await garden.flush();
      final events = garden.proceduresOn(garden.today);
      expect(events.map((p) => p.isCompleted), [true, false]);
      expect(garden.plants.single.nextWatering, DateTime(2026, 10, 5, 20));
      expect(garden.plants.single.statusAt(now), WateringStatus.today);
      expect(reminders.pending.first.date, DateTime(2026, 10, 5, 20));
      now = DateTime(2026, 10, 5, 21);
      expect(garden.plants.single.statusAt(now), WateringStatus.overdue);
      garden.toggleProcedureCompleted(series, DateTime(2026, 10, 5, 20));
      await garden.flush();
      expect(garden.records.length, 2);
      expect(garden.plants.single.nextWatering, DateTime(2026, 10, 6, 8));
      garden.toggleProcedureCompleted(series, DateTime(2026, 10, 5, 20));
      expect(garden.records.length, 1);
      expect(garden.proceduresOn(garden.today).map((p) => p.isCompleted), [
        true,
        false,
      ]);
    },
  );

  test(
    'One-date slots including midnight are independent and do not repeat',
    () {
      final garden = GardenViewModel(
        snapshot: empty(),
        clock: () => DateTime(2026, 10, 5, 13),
      );
      addTearDown(garden.dispose);
      final plant = garden.savePlant(name: 'Тест');
      final id = garden.saveProcedure(
        plantId: plant,
        date: garden.today,
        type: CareType.watering,
        times: [0, 720],
      );
      garden.toggleProcedureCompleted(id, garden.today);
      expect(garden.proceduresOn(garden.today).map((p) => p.isCompleted), [
        true,
        false,
      ]);
      garden.toggleProcedureCompleted(id, DateTime(2026, 10, 5, 12));
      expect(garden.plants.single.nextWatering, isNull);
      expect(garden.records.length, 2);
      expect(garden.proceduresOn(addDays(garden.today, 1)), isEmpty);
      expect(
        () => garden.toggleProcedureCompleted(id, DateTime(2026, 10, 5, 11)),
        throwsArgumentError,
      );
    },
  );

  test('Card and journal mark one timed slot at a time and undo only one', () {
    final garden = GardenViewModel(
      snapshot: empty(),
      clock: () => DateTime(2026, 10, 5, 9),
    );
    addTearDown(garden.dispose);
    final plant = garden.savePlant(
      name: 'Тест',
      firstWatering: garden.today,
      repeatEveryDays: 1,
      times: [480, 1200],
    );
    garden.toggleWateredToday(plant);
    expect(garden.proceduresOn(garden.today).map((p) => p.isCompleted), [
      true,
      false,
    ]);
    garden.recordCare(
      plantId: plant,
      type: CareType.watering,
      performedOn: DateTime(2026, 10, 5, 20),
    );
    expect(garden.records.length, 2);
    garden.toggleWateredToday(plant);
    expect(garden.records.length, 1);
    expect(garden.proceduresOn(garden.today).map((p) => p.isCompleted), [
      true,
      false,
    ]);
    expect(
      () => garden.toggleProcedureCompleted(
        garden.procedures.single.id,
        DateTime(2026, 10, 6, 8),
      ),
      throwsArgumentError,
    );
  });

  test(
    'Conflict detection considers weekday, clock and distant interval intersections',
    () {
      final garden = GardenViewModel(
        snapshot: empty(),
        clock: () => DateTime(2026, 10, 5),
      );
      addTearDown(garden.dispose);
      final plant = garden.savePlant(name: 'Тест');
      garden.saveProcedure(
        plantId: plant,
        date: garden.today,
        type: CareType.watering,
        weekdays: [1, 3, 5],
        times: [480],
      );
      garden.saveProcedure(
        plantId: plant,
        date: garden.today,
        type: CareType.watering,
        weekdays: [1, 3, 5],
        times: [1200],
      );
      garden.saveProcedure(
        plantId: plant,
        date: addDays(garden.today, 1),
        type: CareType.watering,
        repeatEveryDays: 14,
        times: [480],
      );
      expect(
        () => garden.saveProcedure(
          plantId: plant,
          date: garden.today,
          type: CareType.watering,
          weekdays: [3],
          times: [480],
        ),
        throwsArgumentError,
      );
      expect(
        () => garden.saveProcedure(
          plantId: plant,
          date: addDays(garden.today, 1),
          type: CareType.watering,
          repeatEveryDays: 365,
          times: [480],
        ),
        throwsArgumentError,
      );
    },
  );

  test('Invalid times and mixed repeat modes do not change existing data', () {
    final garden = GardenViewModel(snapshot: empty());
    addTearDown(garden.dispose);
    final plant = garden.savePlant(name: 'Тест');
    for (final times in [
      [480, 480],
      [-1],
      [1440],
    ]) {
      expect(
        () => garden.saveProcedure(
          plantId: plant,
          date: garden.today,
          type: CareType.watering,
          times: times,
        ),
        throwsArgumentError,
      );
    }
    expect(
      () => garden.saveProcedure(
        plantId: plant,
        date: garden.today,
        type: CareType.watering,
        weekdays: [1],
        repeatEveryDays: 1,
      ),
      throwsArgumentError,
    );
    expect(
      () => garden.savePlant(
        name: 'Неверное',
        firstWatering: garden.today,
        times: [1440],
      ),
      throwsArgumentError,
    );
    expect(garden.plants.length, 1);
    expect(garden.procedures, isEmpty);
  });

  test(
    'SQLite v3 migration preserves old marks and restores several daily records',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'plants_schedule_',
      );
      addTearDown(() => directory.delete(recursive: true));
      final path = '${directory.path}/garden.sqlite';
      final old = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 3,
          onCreate: (db, _) async {
            await SqliteGardenRepository.createVersionOne(db);
            await SqliteGardenRepository.upgradeToVersionTwo(db);
            await SqliteGardenRepository.upgradeToVersionThree(db);
          },
        ),
      );
      await old.insert('plants', {
        'id': 'old',
        'name': 'Прежнее растение',
        'species': '',
        'room': '',
        'art': 0,
      });
      await old.insert('care_procedures', {
        'id': 'old-series',
        'plant_id': 'old',
        'date': '2026-10-05',
        'type': 'watering',
        'weekly': 1,
      });
      await old.insert('procedure_completions', {
        'procedure_id': 'old-series',
        'occurrence_date': '2026-10-05',
        'performed_on': '2026-10-05',
      });
      await old.insert('care_records', {
        'id': 'old-record',
        'plant_id': 'old',
        'type': 'watering',
        'performed_on': '2026-10-05',
        'note': 'Прежняя запись',
      });
      await old.insert('settings', {'key': 'initialized', 'value': '1'});
      await old.close();
      var repo = await SqliteGardenRepository.open(
        path: path,
        factory: databaseFactoryFfi,
      );
      final garden = GardenViewModel(
        snapshot: await repo.load(),
        repository: repo,
        clock: () => DateTime(2026, 10, 5, 9),
      );
      expect(garden.proceduresOn(garden.today).single.isCompleted, isTrue);
      expect(garden.plants.single.nextWatering, DateTime(2026, 10, 12));
      final plant = garden.savePlant(
        name: 'Новое растение',
        firstWatering: garden.today,
        weekdays: [1, 3, 5],
        times: [0, 1200],
      );
      final series = garden.procedures.last.id;
      garden.toggleProcedureCompleted(series, garden.today);
      garden.toggleProcedureCompleted(series, DateTime(2026, 10, 5, 20));
      await garden.flush();
      garden.dispose();
      await repo.close();
      repo = await SqliteGardenRepository.open(
        path: path,
        factory: databaseFactoryFfi,
      );
      final restarted = GardenViewModel(
        snapshot: await repo.load(),
        clock: () => DateTime(2026, 10, 5, 21),
      );
      expect(restarted.procedureById(series).weekdays, [1, 3, 5]);
      expect(restarted.procedureById(series).times, [0, 1200]);
      expect(
        restarted
            .proceduresOn(restarted.today)
            .where((p) => p.plantId == plant)
            .every((p) => p.isCompleted),
        isTrue,
      );
      expect(restarted.records.where((r) => r.plantId == plant).length, 2);
      expect(
        restarted.records.where((r) => r.plantId == 'old').single.note,
        'Прежняя запись',
      );
      expect(restarted.snapshot.completions[series]!.length, 2);
      restarted.toggleProcedureCompleted(series, DateTime(2026, 10, 5, 20));
      expect(
        restarted
            .proceduresOn(restarted.today)
            .where((p) => p.plantId == plant)
            .map((p) => p.isCompleted),
        [true, false],
      );
      restarted.dispose();
      await repo.close();
    },
  );

  testWidgets(
    'Compact procedure form selects weekdays and adds a second time',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final garden = GardenViewModel(
        snapshot: empty(),
        clock: () => DateTime(2026, 10, 5),
      );
      addTearDown(garden.dispose);
      garden.savePlant(name: 'Фикус');
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => ProcedureEditor(model: garden),
                ),
                child: const Text('Открыть'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Открыть'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('schedule-mode')));
      await tester.tap(find.byKey(const ValueKey('schedule-mode')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('По дням недели').last);
      await tester.pumpAndSettle();
      for (final day in [1, 3, 5]) {
        final chip = find.byKey(ValueKey('schedule-weekday-$day'));
        await tester.ensureVisible(chip);
        await tester.tap(chip);
        await tester.pumpAndSettle();
      }
      final timeSwitch = find.byKey(const ValueKey('schedule-times-enabled'));
      await tester.ensureVisible(timeSwitch);
      await tester.tap(timeSwitch);
      await tester.pumpAndSettle();
      final add = find.byKey(const ValueKey('schedule-add-time'));
      await tester.ensureVisible(add);
      await tester.tap(add);
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.keyboard_outlined));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).at(0), '20');
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).at(1), '00');
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('save-procedure')));
      await tester.pumpAndSettle();
      expect(find.byType(ProcedureEditor), findsNothing);
      expect(garden.procedures.single.weekdays, [1, 3, 5]);
      expect(garden.procedures.single.times, [540, 1200]);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'Calendar displays two separate slots and marks only the selected one',
    (tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final garden = GardenViewModel(
        snapshot: empty(),
        clock: () => DateTime(2026, 10, 5, 9),
      );
      addTearDown(garden.dispose);
      final plant = garden.savePlant(
        name: 'Фикус',
        firstWatering: garden.today,
        repeatEveryDays: 1,
        times: [480, 1200],
      );
      await tester.pumpWidget(
        MaterialApp(home: GardenScreen(viewModel: garden)),
      );
      await tester.tap(find.text('Календарь'));
      await tester.pumpAndSettle();
      expect(find.text('Полив · 08:00'), findsOneWidget);
      expect(find.text('Полив · 20:00'), findsOneWidget);
      final id = garden.procedures.single.id;
      final button = find.byKey(
        ValueKey('complete-$id-${DateTime(2026, 10, 5, 8).toIso8601String()}'),
      );
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(garden.records.where((r) => r.plantId == plant).length, 1);
      expect(garden.proceduresOn(garden.today).map((p) => p.isCompleted), [
        true,
        false,
      ]);
      expect(find.text('Отменить выполнение'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
