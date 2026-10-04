import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:home_plants_organizer/main.dart';
import 'package:home_plants_organizer/services/android_reminder_service.dart';
import 'package:home_plants_organizer/services/sqlite_garden_repository.dart';
import 'package:home_plants_organizer/services/storage_bootstrap_native.dart';

/// Проверяет настоящий HTTP, распознавание, SQLite и системную очередь Android.
/// Второй запуск проверяет восстановление после остановки процесса приложения.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const restore = bool.fromEnvironment('LAB4_RESTORE_CHECK');
  testWidgets(
    restore
        ? 'Lab 4 restoration after process restart'
        : 'Lab 4 OCR, REST, database and Android reminders',
    (tester) async {
      final support = await getApplicationSupportDirectory();
      final directory = Directory('${support.path}/lab4_verification');
      await directory.create(recursive: true);
      var resources = await openGarden(directoryPath: directory.path);
      var garden = resources.garden;
      Future<void> app() async {
        await tester.pumpWidget(
          RepaintBoundary(
            key: const ValueKey('capture-surface'),
            child: PlantApp(viewModel: garden),
          ),
        );
        await tester.pump(const Duration(milliseconds: 600));
      }

      Future<void> waitFor(Finder finder) async {
        for (var i = 0; i < 150 && finder.evaluate().isEmpty; i++) {
          await tester.pump(const Duration(milliseconds: 200));
        }
        expect(finder, findsWidgets);
      }

      Future<void> tap(Finder finder) async {
        await tester.ensureVisible(finder);
        await tester.pump(const Duration(milliseconds: 150));
        await tester.tap(finder);
        await tester.pump(const Duration(milliseconds: 500));
      }

      Future<void> hideKeyboard() async {
        FocusManager.instance.primaryFocus?.unfocus();
        await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
        await tester.pump(const Duration(milliseconds: 400));
      }

      Future<void> shot(String name) async {
        ScaffoldMessenger.of(
          tester.element(find.byType(Scaffold).last),
        ).clearSnackBars();
        await tester.pumpAndSettle(const Duration(milliseconds: 200));
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const ValueKey('capture-surface')),
        );
        final image = await boundary.toImage(pixelRatio: 3);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();
        binding.reportData ??= {};
        final shots =
            binding.reportData!.putIfAbsent(
                  'screenshots',
                  () => <Map<String, dynamic>>[],
                )
                as List;
        shots.add({
          'screenshotName': name,
          'bytes': data!.buffer.asUint8List().toList(),
        });
      }

      Future<void> pendingMatches() async {
        await garden.flush();
        final service = garden.reminderService as AndroidReminderService;
        final native = await service.plugin.pendingNotificationRequests();
        expect(
          native.map((n) => n.id).toSet(),
          garden.scheduledReminders.map((n) => n.id).toSet(),
        );
        expect(
          native.map((n) => n.title).toList(),
          garden.scheduledReminders.map((n) => n.title).toList(),
        );
      }

      if (restore) {
        expect(garden.plants.length, 1);
        final plant = garden.plants.single;
        expect(plant.name, 'Фикус учебный');
        expect(garden.careGuideFor(plant.id)?.species, 'Ficus elastica');
        expect(garden.procedures.single.intervalDays, 10);
        expect(garden.reminderPreferences.enabled, isTrue);
        expect(garden.scheduledReminders, isNotEmpty);
        await pendingMatches();
        await app();
        await tap(find.byKey(ValueKey('details-${plant.id}')));
        await waitFor(find.text('Сохранённый регламент'));
        await shot('07_restored_guide');
        binding.reportData!['verification'] = {
          'restored': true,
          'plant': plant.name,
          'interval': garden.procedures.single.intervalDays,
          'pending': garden.scheduledReminders.length,
        };
        await garden.testNotification();
        await tester.pumpWidget(const SizedBox.shrink());
        await resources.close();
        return;
      }
      expect(
        garden.reminderService,
        isNotNull,
        reason: garden.notificationIssue,
      );
      await garden.configureReminders(enabled: false);
      for (final plant in List.of(garden.plants)) {
        garden.deletePlant(plant.id);
      }
      await garden.flush();
      await app();
      await tap(find.text('Сканировать этикетку'));
      await tap(find.widgetWithText(ActionChip, 'Фикус'));
      final speciesFinder = find.byKey(const ValueKey('scan-plant-species'));
      for (var i = 0; i < 100; i++) {
        await tester.pump(const Duration(milliseconds: 200));
        if (tester.widget<TextField>(speciesFinder).controller!.text ==
            'Ficus elastica') {
          break;
        }
      }
      expect(
        tester.widget<TextField>(speciesFinder).controller!.text,
        'Ficus elastica',
      );
      await tester.ensureVisible(speciesFinder);
      await shot('01_recognized_label');
      await tap(find.text('Добавить в мои растения'));
      await waitFor(find.text('Полученный регламент'));
      expect(garden.plants.length, 1);
      final plantId = garden.plants.single.id;
      await shot('02_downloaded_guide');
      await tester.ensureVisible(find.byKey(const ValueKey('care-interval')));
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('care-interval')))
            .controller!
            .text,
        '10',
      );
      await shot('03_schedule_settings');
      await tap(find.byKey(const ValueKey('save-care-guide')));
      await garden.flush();
      expect(garden.careGuideFor(plantId)?.species, 'Ficus elastica');
      expect(garden.procedures.single.intervalDays, 10);
      final downloaded = garden.careGuideFor(plantId)!;
      final repo = resources.gardenRepository as SqliteGardenRepository;
      expect((await repo.database.query('care_guides')).length, 1);
      await tap(find.text('Календарь'));
      final date = garden.procedures.single.date;
      await tap(find.byKey(ValueKey('day-${date.toIso8601String()}')));
      await tester.ensureVisible(
        find.byKey(ValueKey('procedure-${garden.procedures.single.id}')),
      );
      await shot('04_calendar_from_guide');
      await tap(find.text('Мой сад'));
      await tap(find.byKey(const ValueKey('reminders-screen')));
      debugPrint(
        'REMINDERS before enable: service=${garden.reminderService.runtimeType}, issue=${garden.notificationIssue}',
      );
      await tap(find.byKey(const ValueKey('enable-reminders')));
      for (var i = 0; i < 100 && !garden.reminderPreferences.enabled; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }
      debugPrint(
        'REMINDERS after enable: enabled=${garden.reminderPreferences.enabled}, issue=${garden.notificationIssue}',
      );
      await garden.flush();
      expect(garden.reminderPreferences.enabled, isTrue);
      expect(garden.scheduledReminders, isNotEmpty);
      await pendingMatches();
      await tester.ensureVisible(find.byKey(const ValueKey('reminder-count')));
      await shot('05_scheduled_reminders');
      await tap(find.byKey(const ValueKey('test-notification')));
      await tester.pump(const Duration(milliseconds: 500));
      await tap(find.byType(BackButton));
      await tester.pump(const Duration(milliseconds: 500));
      await tap(find.byKey(ValueKey('details-$plantId')));
      await waitFor(find.text('Сохранённый регламент'));
      await shot('06_saved_guide');
      await tap(find.byKey(const ValueKey('remote-care')));
      await waitFor(find.text('Полученный регламент'));
      await tester.enterText(
        find.byKey(const ValueKey('care-query')),
        'Unknown houseplant',
      );
      await hideKeyboard();
      await tap(find.byKey(const ValueKey('load-care-guide')));
      await waitFor(find.byKey(const ValueKey('care-network-error')));
      await shot('08_unknown_name');
      expect(garden.careGuideFor(plantId)?.species, downloaded.species);
      await tap(find.byType(BackButton));
      await tester.pump(const Duration(milliseconds: 300));
      await tap(find.byType(BackButton));
      await tester.pump(const Duration(milliseconds: 300));
      await tap(find.byKey(ValueKey('plant-menu-$plantId')));
      await tap(find.text('Редактировать'));
      await tester.enterText(
        find.byKey(const ValueKey('plant-name')),
        'Фикус учебный',
      );
      await hideKeyboard();
      await tap(find.byKey(const ValueKey('save-plant')));
      await garden.flush();
      await pendingMatches();
      expect(
        garden.scheduledReminders.every(
          (r) => r.title.contains('Фикус учебный'),
        ),
        isTrue,
      );
      await tap(find.byKey(ValueKey('plant-menu-$plantId')));
      await tap(find.text('Удалить'));
      await tap(find.byKey(const ValueKey('confirm-delete')));
      await garden.flush();
      await pendingMatches();
      expect(garden.plants, isEmpty);
      expect(garden.careGuideFor(plantId), isNull);
      expect(await repo.database.query('care_guides'), isEmpty);
      expect(garden.scheduledReminders, isEmpty);
      await tap(find.byKey(const ValueKey('reminders-screen')));
      await shot('09_cancelled_reminders');
      // Leave a separate saved sample for the second process; ordinary app data is untouched.
      final savedId = garden.savePlant(
        name: 'Фикус учебный',
        species: 'Ficus elastica',
        careConditions:
            'Мои условия содержания сохраняются отдельно от сетевого регламента.',
      );
      await garden.applyCareGuide(
        savedId,
        downloaded,
        firstWatering: date,
        intervalDays: 10,
      );
      await pendingMatches();
      binding.reportData!['verification'] = {
        'http': 'real GitHub REST',
        'ocr': 'ML Kit Ficus elastica',
        'source': downloaded.sourceName,
        'sqliteGuideRows': 1,
        'interval': 10,
        'pending': garden.scheduledReminders.length,
        'renameUpdatesNotifications': true,
        'deletionCancelsNotifications': true,
        'unknownNamePreservesGuide': true,
      };
      await tester.pumpWidget(const SizedBox.shrink());
      await resources.close();
    },
  );
}
