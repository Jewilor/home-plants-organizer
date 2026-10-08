import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:timezone/timezone.dart' as tz;
import 'package:home_plants_organizer/services/android_reminder_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:home_plants_organizer/models/care_guide.dart';
import 'package:home_plants_organizer/models/garden_snapshot.dart';
import 'package:home_plants_organizer/models/plant.dart';
import 'package:home_plants_organizer/models/reminder.dart';
import 'package:home_plants_organizer/services/plant_encyclopedia.dart';
import 'package:home_plants_organizer/services/reminder_service.dart';
import 'package:home_plants_organizer/services/sqlite_garden_repository.dart';
import 'package:home_plants_organizer/viewmodels/care_guide_view_model.dart';
import 'package:home_plants_organizer/viewmodels/garden_view_model.dart';
import 'package:home_plants_organizer/views/care_guide_screen.dart';
import 'package:home_plants_organizer/views/reminders_screen.dart';

CareGuide guide({int? days = 10}) => CareGuide(
  species: 'Ficus elastica',
  light: 'Рассеянный свет.',
  humidity: 'Умеренная влажность.',
  watering: 'Проверять почву.',
  sourceName: 'Тестовая энциклопедия',
  sourceUrl: 'https://example.org/care',
  downloadedAt: DateTime(2026, 10, 4),
  wateringIntervalDays: days,
);

class FakeReminderService implements ReminderService {
  bool allowed = true;
  bool fail = false;
  int testCount = 0;
  List<CareReminder> pending = [];
  @override
  Future<bool> permitted() async => allowed;
  @override
  Future<bool> requestPermission() async => allowed;
  @override
  Future<void> replace(List<CareReminder> reminders) async {
    if (fail) throw StateError('Notification error');
    pending = List.of(reminders);
  }

  @override
  Future<void> showTest() async {
    testCount++;
  }
}

class FakeEncyclopedia implements PlantEncyclopedia {
  final List<Completer<CareGuide>> requests = [];
  @override
  String get sourceLabel => 'Тестовая энциклопедия';
  @override
  Future<CareGuide> fetch(String query) {
    final result = Completer<CareGuide>();
    requests.add(result);
    return result.future;
  }

  @override
  void close() {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  test(
    'Android timezone aliases GMT and UTC and local Minsk are supported',
    () {
      for (final identifier in ['GMT', 'UTC', 'Europe/Minsk']) {
        AndroidReminderService.initializeTimeZone(identifier);
        expect(tz.local.name, identifier);
        final local = tz.TZDateTime(tz.local, 2026, 10, 4, 9);
        expect(local.hour, 9);
        expect(
          local.timeZoneOffset.inHours,
          identifier == 'Europe/Minsk' ? 3 : 0,
        );
      }
    },
  );
  test(
    'HTTP sends encoded query, validates the response and returns exact match',
    () async {
      final data = jsonDecode(
        File('demo_api/encyclopedia.json').readAsStringSync(),
      );
      final api = HttpPlantEncyclopedia(
        client: MockClient((request) async {
          expect(request.url.queryParameters['q'], 'Ficus elastica');
          expect(request.headers['Accept'], 'application/vnd.github.raw+json');
          return http.Response.bytes(utf8.encode(jsonEncode(data)), 200);
        }),
      );
      addTearDown(api.close);
      final result = await api.fetch('  Ficus elastica  ');
      expect(result.wateringIntervalDays, 10);
      expect(result.species, 'Ficus elastica');
      expect(result.family, 'Тутовые');
    },
  );
  test(
    'Unknown plant and malformed guide are not replaced with arbitrary care',
    () async {
      final api = HttpPlantEncyclopedia(
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'data': [
                {
                  'aliases': ['Ficus elastica'],
                  'species': 'Ficus elastica',
                },
              ],
            }),
            200,
          ),
        ),
      );
      addTearDown(api.close);
      await expectLater(
        api.fetch('Unknown'),
        throwsA(isA<EncyclopediaException>()),
      );
      await expectLater(
        api.fetch('Ficus elastica'),
        throwsA(isA<EncyclopediaException>()),
      );
    },
  );
  for (final status in [401, 403, 404, 429, 500]) {
    test('HTTP $status becomes a readable network error', () async {
      final api = HttpPlantEncyclopedia(
        client: MockClient((_) async => http.Response('{}', status)),
      );
      addTearDown(api.close);
      await expectLater(
        api.fetch('Ficus elastica'),
        throwsA(isA<EncyclopediaException>()),
      );
    });
  }
  test('Timeout is handled without waiting indefinitely', () async {
    final response = Completer<http.Response>();
    final api = HttpPlantEncyclopedia(
      timeout: const Duration(milliseconds: 5),
      client: MockClient((_) => response.future),
    );
    addTearDown(api.close);
    await expectLater(
      api.fetch('Ficus elastica'),
      throwsA(isA<EncyclopediaException>()),
    );
    response.complete(http.Response('{}', 200));
  });
  test(
    'Perenual search and details decode interval without inventing humidity',
    () async {
      final api = HttpPlantEncyclopedia(
        apiKey: 'test-key',
        client: MockClient((request) async {
          expect(request.url.queryParameters['key'], 'test-key');
          if (request.url.path.endsWith('species-list')) {
            expect(request.url.queryParameters['q'], 'Ficus elastica');
            return http.Response(
              jsonEncode({
                'data': [
                  {
                    'id': 21,
                    'scientific_name': ['Ficus elastica'],
                  },
                ],
              }),
              200,
            );
          }
          expect(request.url.path, '/api/v2/species/details/21');
          return http.Response(
            jsonEncode({
              'id': 21,
              'scientific_name': ['Ficus elastica'],
              'family': 'Moraceae',
              'watering': 'Average',
              'sunlight': ['Part shade'],
              'watering_general_benchmark': {'value': '5-10', 'unit': 'days'},
            }),
            200,
          );
        }),
      );
      addTearDown(api.close);
      final result = await api.fetch('Ficus elastica');
      expect(result.wateringIntervalDays, 10);
      expect(result.light, 'Полутень');
      expect(result.family, 'Тутовые');
      expect(result.humidity, contains('не предоставлены'));
    },
  );
  test('Last asynchronous result wins and disposal does not notify', () async {
    final api = FakeEncyclopedia();
    final model = CareGuideViewModel(api);
    final first = model.load('First');
    final second = model.load('Second');
    api.requests[1].complete(guide());
    await second;
    api.requests[0].complete(guide(days: 7));
    await first;
    expect(model.guide!.wateringIntervalDays, 10);
    final third = model.load('Third');
    model.dispose();
    api.requests[2].complete(guide());
    await third;
  });
  test(
    'Ten-day repeats use calendar dates and pending overdue care survives',
    () {
      final garden = GardenViewModel(clock: () => DateTime(2026, 10, 24));
      addTearDown(garden.dispose);
      final id = garden.savePlant(name: 'Фикус');
      garden.saveProcedure(
        plantId: id,
        type: CareType.watering,
        date: DateTime(2026, 10, 4),
        repeatEveryDays: 10,
      );
      expect(
        garden.proceduresOn(DateTime(2026, 10, 14)).any((p) => p.plantId == id),
        isTrue,
      );
      expect(
        garden.proceduresOn(DateTime(2026, 10, 11)).any((p) => p.plantId == id),
        isFalse,
      );
      garden.toggleWateredToday(id);
      expect(garden.plants.last.nextWatering, DateTime(2026, 11, 3));
      garden.toggleWateredToday(id);
      expect(garden.plants.last.nextWatering, DateTime(2026, 10, 4));
    },
  );
  test(
    'Intersecting periodic schedules are rejected even with different intervals',
    () {
      final garden = GardenViewModel();
      addTearDown(garden.dispose);
      final id = garden.savePlant(name: 'Фикус');
      garden.saveProcedure(
        plantId: id,
        type: CareType.watering,
        date: DateTime(2026, 10, 4),
        repeatEveryDays: 10,
      );
      expect(
        () => garden.saveProcedure(
          plantId: id,
          type: CareType.watering,
          date: DateTime(2026, 10, 6),
          repeatEveryDays: 12,
        ),
        throwsArgumentError,
      );
    },
  );
  test(
    'Reminder queue respects time, completion, interval and bounded capacity',
    () async {
      final service = FakeReminderService();
      final garden = GardenViewModel(
        clock: () => DateTime(2026, 10, 4, 8),
        reminderService: service,
      );
      addTearDown(garden.dispose);
      final id = garden.savePlant(
        name: 'Фикус',
        careConditions: 'Мои условия.',
      );
      await garden.applyCareGuide(
        id,
        guide(),
        firstWatering: DateTime(2026, 10, 4),
        intervalDays: 10,
      );
      expect(garden.records.where((r) => r.plantId == id), isEmpty);
      await garden.configureReminders(enabled: true);
      var pending = service.pending.where((r) => r.plantId == id).toList();
      expect(pending.map((r) => r.date.day), [4, 14, 24, 3]);
      garden.toggleWateredToday(id);
      await garden.flush();
      pending = service.pending.where((r) => r.plantId == id).toList();
      expect(pending.length, 3);
      garden.savePlant(id: id, name: 'Новый фикус');
      await garden.flush();
      expect(
        service.pending
            .where((r) => r.plantId == id)
            .every((r) => r.title.contains('Новый фикус')),
        isTrue,
      );
      expect(garden.plants.last.careConditions, 'Мои условия.');
      expect(
        planReminders(
          garden.snapshot,
          DateTime(2026, 10, 4, 8),
          limit: 2,
        ).length,
        2,
      );
      garden.deletePlant(id);
      await garden.flush();
      expect(service.pending.any((r) => r.plantId == id), isFalse);
      expect(garden.careGuideFor(id), isNull);
      await garden.configureReminders(enabled: false);
      expect(service.pending, isEmpty);
    },
  );
  test(
    'Permission denial and scheduling failure do not corrupt garden state',
    () async {
      final service = FakeReminderService()..allowed = false;
      final garden = GardenViewModel(reminderService: service);
      addTearDown(garden.dispose);
      expect(await garden.configureReminders(enabled: true), isFalse);
      expect(garden.reminderPreferences.enabled, isFalse);
      expect(garden.notificationIssue, isNotNull);
      service.allowed = true;
      service.fail = true;
      await garden.configureReminders(enabled: true);
      expect(garden.notificationIssue, isNotNull);
      expect(garden.storageError, isNull);
      service.fail = false;
      await garden.refreshReminders();
      expect(garden.notificationIssue, isNull);
    },
  );
  test(
    'Version two migration preserves data and stores a guide, interval and time',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'plants_lab4_test_',
      );
      final dbPath = '${directory.path}/garden.sqlite';
      final old = await databaseFactoryFfi.openDatabase(
        dbPath,
        options: OpenDatabaseOptions(
          version: 2,
          onCreate: (db, _) async {
            await SqliteGardenRepository.createVersionOne(db);
            await SqliteGardenRepository.upgradeToVersionTwo(db);
          },
        ),
      );
      await old.insert('plants', {
        'id': 'legacy',
        'name': 'Мой фикус',
        'species': 'Ficus elastica',
        'room': 'Кабинет',
        'care_conditions': 'Ручные условия.',
        'art': 1,
      });
      await old.insert('settings', {'key': 'initialized', 'value': '1'});
      await old.close();
      final repo = await SqliteGardenRepository.open(
        path: dbPath,
        factory: databaseFactoryFfi,
      );
      expect(
        await repo.database.getVersion(),
        SqliteGardenRepository.schemaVersion,
      );
      final garden = GardenViewModel(
        repository: repo,
        snapshot: await repo.load(),
      );
      await garden.applyCareGuide(
        'legacy',
        guide(),
        firstWatering: DateTime(2026, 10, 5),
        intervalDays: 10,
      );
      final snapshot = garden.snapshot;
      await repo.save(
        GardenSnapshot(
          plants: snapshot.plants,
          procedures: snapshot.procedures,
          records: snapshot.records,
          completions: snapshot.completions,
          sequence: snapshot.sequence,
          careGuides: snapshot.careGuides,
          reminderPreferences: const ReminderPreferences(
            enabled: true,
            hour: 18,
            minute: 30,
          ),
        ),
      );
      garden.dispose();
      await repo.close();
      final reopened = await SqliteGardenRepository.open(
        path: dbPath,
        factory: databaseFactoryFfi,
      );
      final restored = (await reopened.load())!;
      expect(restored.plants.single.careConditions, 'Ручные условия.');
      expect(restored.careGuides['legacy']!.species, 'Ficus elastica');
      expect(restored.procedures.single.intervalDays, 10);
      expect(restored.reminderPreferences.hour, 18);
      expect(restored.reminderPreferences.minute, 30);
      await reopened.close();
      final resolved = directory.absolute;
      if (resolved.parent.path == Directory.systemTemp.absolute.path &&
          resolved.path.contains('plants_lab4_test_')) {
        await resolved.delete(recursive: true);
      }
    },
  );
  testWidgets(
    'Downloaded guide can be saved on a compact phone without overflow',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = FakeEncyclopedia();
      final garden = GardenViewModel(encyclopedia: api);
      addTearDown(garden.dispose);
      final id = garden.savePlant(
        name: 'Фикус',
        species: 'Ficus elastica',
        careConditions: 'Ручные условия.',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: CareGuideScreen(garden: garden, plantId: id),
        ),
      );
      api.requests.single.complete(guide());
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('save-care-guide')));
      await tester.tap(find.byKey(const ValueKey('save-care-guide')));
      await tester.pumpAndSettle();
      expect(garden.careGuideFor(id), isNotNull);
      expect(garden.plants.last.careConditions, 'Ручные условия.');
      expect(garden.procedures.last.intervalDays, 10);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets('Reminder screen handles permission denial on a compact phone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final service = FakeReminderService()..allowed = false;
    final garden = GardenViewModel(reminderService: service);
    addTearDown(garden.dispose);
    await tester.pumpWidget(MaterialApp(home: RemindersScreen(garden: garden)));
    await tester.tap(find.byKey(const ValueKey('enable-reminders')));
    await tester.pumpAndSettle();
    expect(garden.reminderPreferences.enabled, isFalse);
    expect(find.byKey(const ValueKey('reminder-error')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
