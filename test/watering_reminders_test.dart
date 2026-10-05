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
import 'package:home_plants_organizer/views/reminders_screen.dart';

class RecordingReminders implements ReminderService {
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

GardenSnapshot emptyGarden() => GardenSnapshot(
  plants: [],
  procedures: [],
  records: [],
  completions: {},
  sequence: 0,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  test(
    'Older preferences use common time and malformed times are rejected',
    () {
      final restored = ReminderPreferences.fromJson({
        'enabled': true,
        'hour': 9,
        'minute': 0,
      });
      expect(restored.individualWateringTimes, isFalse);
      expect(restored.commonTime.hour, 9);
      expect(
        () => ReminderTime.fromJson({'hour': 24, 'minute': 0}),
        throwsFormatException,
      );
      expect(
        () => ReminderTime.fromJson({'hour': 9, 'minute': -1}),
        throwsFormatException,
      );
      expect(
        () => ReminderPreferences.fromJson({
          'enabled': true,
          'hour': 9,
          'minute': 0,
          'individualWateringTimes': 'yes',
        }),
        throwsFormatException,
      );
    },
  );

  test(
    'Shared and individual modes use effective time, order and care type',
    () async {
      final service = RecordingReminders();
      final garden = GardenViewModel(
        snapshot: emptyGarden(),
        clock: () => DateTime(2026, 10, 5, 8, 30),
        reminderService: service,
      );
      addTearDown(garden.dispose);
      final late = garden.savePlant(name: 'Фикус');
      final early = garden.savePlant(name: 'Монстера');
      final common = garden.savePlant(name: 'Аглаонема');
      for (final id in [late, early, common]) {
        garden.saveProcedure(
          plantId: id,
          type: CareType.watering,
          date: garden.today,
        );
      }
      garden.saveProcedure(
        plantId: late,
        type: CareType.feeding,
        date: garden.today,
      );
      await garden.setWateringReminderTime(
        late,
        const ReminderTime(hour: 18, minute: 30),
      );
      await garden.setWateringReminderTime(
        early,
        const ReminderTime(hour: 8, minute: 45),
      );
      await garden.configureReminders(enabled: true);
      expect(service.pending.length, 4);
      expect(
        service.pending.every((r) => r.date.hour == 9 && r.date.minute == 0),
        isTrue,
      );

      await garden.configureWateringReminders(individual: true);
      expect(service.pending.map((r) => r.date.hour), [8, 9, 9, 18]);
      expect(service.pending.map((r) => r.date.minute), [45, 0, 0, 30]);
      expect(service.pending.first.plantId, early);
      final nearest = planReminders(
        garden.snapshot,
        DateTime(2026, 10, 5, 8, 30),
        limit: 1,
      );
      expect(nearest.single.plantId, early);
      expect(service.pending.map((r) => r.id).toSet().length, 4);

      await garden.configureReminders(enabled: true, hour: 10, minute: 15);
      expect(garden.reminderPreferences.individualWateringTimes, isTrue);
      expect(
        service.pending.where((r) => r.plantId == common).single.date.hour,
        10,
      );
      expect(
        service.pending
            .where((r) => r.title.startsWith('Подкормка'))
            .single
            .date
            .hour,
        10,
      );
      expect(garden.wateringTimeFor(late).hour, 18);
      await garden.setWateringReminderTime(early, null);
      expect(garden.wateringTimeFor(early).hour, 10);
      await garden.configureWateringReminders(individual: false);
      expect(service.pending.every((r) => r.date.hour == 10), isTrue);
      expect(garden.customWateringTimeFor(late)!.hour, 18);
      await garden.configureWateringReminders(individual: true);
      expect(garden.wateringTimeFor(late).hour, 18);
      garden.savePlant(id: late, name: 'Большой фикус');
      await garden.flush();
      expect(
        service.pending
            .where((r) => r.plantId == late)
            .every((r) => r.title.contains('Большой фикус')),
        isTrue,
      );
      garden.deletePlant(late);
      await garden.flush();
      expect(garden.customWateringTimeFor(late), isNull);
      expect(service.pending.any((r) => r.plantId == late), isFalse);
      await expectLater(
        garden.setWateringReminderTime(
          common,
          const ReminderTime(hour: 24, minute: 0),
        ),
        throwsArgumentError,
      );
      await expectLater(
        garden.setWateringReminderTime(
          'deleted',
          const ReminderTime(hour: 9, minute: 0),
        ),
        throwsArgumentError,
      );
    },
  );

  test(
    'A passed individual time is excluded without losing later events',
    () async {
      final garden = GardenViewModel(
        snapshot: emptyGarden(),
        clock: () => DateTime(2026, 10, 5, 8, 30),
      );
      addTearDown(garden.dispose);
      final past = garden.savePlant(name: 'Фикус');
      final future = garden.savePlant(name: 'Монстера');
      for (final id in [past, future]) {
        garden.saveProcedure(
          plantId: id,
          type: CareType.watering,
          date: garden.today,
          weekly: true,
        );
      }
      await garden.setWateringReminderTime(
        past,
        const ReminderTime(hour: 8, minute: 0),
      );
      await garden.setWateringReminderTime(
        future,
        const ReminderTime(hour: 18, minute: 0),
      );
      await garden.configureWateringReminders(individual: true);
      final planned = planReminders(
        garden.snapshot,
        DateTime(2026, 10, 5, 8, 30),
      );
      expect(
        planned.any((r) => r.plantId == past && sameDay(r.date, garden.today)),
        isFalse,
      );
      expect(
        planned.any(
          (r) => r.plantId == future && sameDay(r.date, garden.today),
        ),
        isTrue,
      );
      expect(
        planned.any(
          (r) => r.plantId == past && sameDay(r.date, DateTime(2026, 10, 12)),
        ),
        isTrue,
      );
    },
  );

  test('Individual settings survive database reopening and deletion', () async {
    final directory = await Directory.systemTemp.createTemp(
      'plant_watering_times_',
    );
    final repositories = <SqliteGardenRepository>[];
    addTearDown(() async {
      for (final repo in repositories) {
        if (repo.database.isOpen) await repo.close();
      }
      final resolved = directory.absolute;
      if (resolved.parent.path == Directory.systemTemp.absolute.path &&
          resolved.path.contains('plant_watering_times_')) {
        await resolved.delete(recursive: true);
      }
    });
    Future<SqliteGardenRepository> open() async {
      final repo = await SqliteGardenRepository.open(
        path: '${directory.path}/garden.sqlite',
        factory: databaseFactoryFfi,
      );
      repositories.add(repo);
      return repo;
    }

    var repo = await open();
    final garden = GardenViewModel(
      repository: repo,
      snapshot: emptyGarden(),
      reminderService: RecordingReminders(),
    );
    final id = garden.savePlant(name: 'Фикус');
    garden.saveProcedure(
      plantId: id,
      type: CareType.watering,
      date: DateTime(2026, 10, 6),
    );
    await garden.configureReminders(enabled: true, hour: 10, minute: 15);
    await garden.setWateringReminderTime(
      id,
      const ReminderTime(hour: 18, minute: 30),
    );
    await garden.configureWateringReminders(individual: true);
    final captured = garden.snapshot;
    await garden.setWateringReminderTime(
      id,
      const ReminderTime(hour: 19, minute: 0),
    );
    expect(captured.wateringReminderTimes[id]!.hour, 18);
    garden.dispose();
    await repo.close();

    repo = await open();
    var restored = (await repo.load())!;
    expect(restored.reminderPreferences.individualWateringTimes, isTrue);
    expect(restored.reminderPreferences.hour, 10);
    expect(restored.wateringReminderTimes[id]!.hour, 19);
    final service = RecordingReminders();
    final restarted = GardenViewModel(
      repository: repo,
      snapshot: restored,
      reminderService: service,
      clock: () => DateTime(2026, 10, 5),
    );
    await restarted.refreshReminders();
    expect(service.pending.single.date.hour, 19);
    await restarted.configureWateringReminders(individual: false);
    restored = (await repo.load())!;
    expect(restored.reminderPreferences.individualWateringTimes, isFalse);
    expect(restored.wateringReminderTimes[id]!.hour, 19);
    restarted.deletePlant(id);
    await restarted.flush();
    restored = (await repo.load())!;
    expect(restored.wateringReminderTimes, isEmpty);
    expect(service.pending, isEmpty);
    restarted.dispose();
  });

  testWidgets('Individual time can be selected and reset on a compact phone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final garden = GardenViewModel(
      snapshot: emptyGarden(),
      reminderService: RecordingReminders(),
    );
    addTearDown(garden.dispose);
    final id = garden.savePlant(
      name: 'Фикус с длинным названием для проверки ширины карточки',
    );
    await garden.flush();
    await tester.pumpWidget(MaterialApp(home: RemindersScreen(garden: garden)));
    final mode = find.byKey(const ValueKey('individual-watering-times'));
    await tester.ensureVisible(mode);
    await tester.tap(mode);
    await tester.pumpAndSettle();
    expect(garden.reminderPreferences.individualWateringTimes, isTrue);
    final choose = find.byKey(ValueKey('watering-reminder-time-$id'));
    await tester.ensureVisible(choose);
    await tester.tap(choose);
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.keyboard_outlined));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), '18');
    await tester.enterText(find.byType(TextField).at(1), '30');
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(garden.customWateringTimeFor(id)!.hour, 18);
    expect(garden.customWateringTimeFor(id)!.minute, 30);
    final reset = find.byKey(ValueKey('reset-watering-time-$id'));
    await tester.ensureVisible(reset);
    await tester.tap(reset);
    await tester.pumpAndSettle();
    expect(garden.customWateringTimeFor(id), isNull);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
