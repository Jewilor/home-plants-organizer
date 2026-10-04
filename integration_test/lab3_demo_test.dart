import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:home_plants_organizer/main.dart';
import 'package:home_plants_organizer/models/plant.dart';
import 'package:home_plants_organizer/models/reference_entry.dart';
import 'package:home_plants_organizer/services/storage_bootstrap_native.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Lab 3 two databases, editing, reopening and saved relationships',
    (tester) async {
      final directory = await Directory.systemTemp.createTemp(
        'plants_lab3_demo_',
      );
      DateTime clock() => DateTime(2026, 10, 4);
      var resources = await openGarden(
        directoryPath: directory.path,
        clock: clock,
      );
      var garden = resources.garden;
      var references = resources.references!;
      Future<void> showApp() async {
        await tester.pumpWidget(
          RepaintBoundary(
            key: const ValueKey('capture-surface'),
            child: PlantApp(viewModel: garden),
          ),
        );
        await tester.pump(const Duration(milliseconds: 600));
      }

      Future<void> tap(Finder finder) async {
        debugPrint('TAP: $finder');
        await tester.ensureVisible(finder);
        await tester.pump(const Duration(milliseconds: 200));
        await tester.tap(finder);
        await tester.pump(const Duration(milliseconds: 600));
      }

      Future<void> hideKeyboard() async {
        FocusManager.instance.primaryFocus?.unfocus();
        await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
        await tester.pump(const Duration(milliseconds: 600));
      }

      Future<void> shot(String name) async {
        await tester.pump(const Duration(milliseconds: 500));
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

      Future<void> select(String key, String value) async {
        await tap(find.byKey(ValueKey(key)));
        await tap(find.text(value).last);
      }

      await showApp();
      debugPrint('SCENARIO: reference editor');
      await tap(find.byKey(const ValueKey('reference-catalog')));
      await tap(find.byKey(const ValueKey('add-reference')));
      await tester.enterText(
        find.byKey(const ValueKey('reference-name')),
        'Марантовые',
      );
      await hideKeyboard();
      await select('reference-icon', 'Цветок');
      await shot('01_reference_editor');
      await tap(find.text('Сохранить'));
      for (var i = 0; i < 30 && references.saving; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }
      expect(references.entries(ReferenceKind.family).length, 4);
      await shot('02_families');
      final familyId = references
          .entries(ReferenceKind.family)
          .firstWhere((entry) => entry.name == 'Марантовые')
          .id;
      await tap(find.byKey(ValueKey('reference-menu-$familyId')));
      await tap(find.text('Редактировать'));
      await tester.enterText(
        find.byKey(const ValueKey('reference-name')),
        'Марантовые растения',
      );
      await hideKeyboard();
      await tap(find.text('Сохранить'));
      for (var i = 0; i < 30 && references.saving; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }
      expect(
        references.find(ReferenceKind.family, familyId)!.name,
        'Марантовые растения',
      );
      await tap(find.text('Удобрения'));
      await tap(find.byKey(const ValueKey('add-reference')));
      await tester.enterText(
        find.byKey(const ValueKey('reference-name')),
        'Комплексное',
      );
      await hideKeyboard();
      await tap(find.text('Сохранить'));
      for (var i = 0; i < 30 && references.saving; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }
      final fertilizer = references
          .entries(ReferenceKind.fertilizer)
          .firstWhere((entry) => entry.name == 'Комплексное');
      await shot('03_fertilizers');
      await tap(find.byTooltip('Назад'));

      debugPrint('SCENARIO: plant and catalog association');
      await tap(find.byKey(const ValueKey('add-plant')));
      await tester.enterText(
        find.byKey(const ValueKey('plant-name')),
        'Учебная аглаонема',
      );
      await tester.enterText(
        find.byKey(const ValueKey('plant-species')),
        'Aglaonema commutatum',
      );
      await tester.enterText(
        find.byKey(const ValueKey('plant-room')),
        'Гостиная',
      );
      await hideKeyboard();
      await select('plant-family', 'Ароидные');
      await tester.ensureVisible(
        find.byKey(const ValueKey('plant-care-conditions')),
      );
      await tester.enterText(
        find.byKey(const ValueKey('plant-care-conditions')),
        'Рассеянный свет. Повышенная влажность воздуха.',
      );
      await hideKeyboard();
      await tap(find.byKey(const ValueKey('weekly-choice')));
      await tester.drag(
        find
            .descendant(
              of: find.byType(AlertDialog),
              matching: find.byType(SingleChildScrollView),
            )
            .first,
        const Offset(0, 500),
      );
      await tester.pump(const Duration(milliseconds: 500));
      await shot('04_plant_editor');
      await tap(find.byKey(const ValueKey('save-plant')));
      await garden.flush();
      final plant = garden.plants.firstWhere(
        (plant) => plant.name == 'Учебная аглаонема',
      );
      expect(plant.familyId, 'family-aroids');
      expect(
        plant.careConditions,
        'Рассеянный свет. Повышенная влажность воздуха.',
      );

      debugPrint('SCENARIO: fertilizer and weekly schedule');
      await tap(find.text('Календарь'));
      await tap(find.byKey(const ValueKey('add-procedure')));
      await select('procedure-plant', 'Учебная аглаонема · Гостиная');
      await select('procedure-type', 'Подкормка');
      await select('procedure-fertilizer', 'Комплексное');
      await tap(find.byKey(const ValueKey('weekly-choice')));
      await shot('05_procedure_editor');
      await tap(find.byKey(const ValueKey('save-procedure')));
      await garden.flush();
      expect(
        garden.procedures
            .where((p) => p.plantId == plant.id && p.type == CareType.feeding)
            .single
            .fertilizerId,
        fertilizer.id,
      );

      await tap(find.text('Мой сад'));
      await tap(find.byKey(ValueKey('water-${plant.id}')));
      await garden.flush();
      await tap(find.byKey(ValueKey('details-${plant.id}')));
      await tap(find.byKey(const ValueKey('record-care')));
      await tap(find.byType(DropdownButtonFormField<CareType>));
      await tap(find.text('Подкормка').last);
      await tester.enterText(
        find.byType(TextField).last,
        'Подкормка выполнена',
      );
      await hideKeyboard();
      await tap(find.text('Сохранить'));
      await garden.flush();
      expect(garden.records.where((r) => r.plantId == plant.id).length, 2);
      await tester.drag(
        find.byType(SingleChildScrollView).first,
        const Offset(0, -280),
      );
      await tester.pump(const Duration(milliseconds: 500));
      await shot('06_saved_journal');

      debugPrint('SCENARIO: closing and reopening both actual database files');
      await tester.pumpWidget(const SizedBox.shrink());
      await resources.close();
      resources = await openGarden(directoryPath: directory.path, clock: clock);
      garden = resources.garden;
      references = resources.references!;
      final restored = garden.plants.firstWhere((p) => p.id == plant.id);
      expect(restored.name, plant.name);
      expect(restored.familyId, plant.familyId);
      expect(restored.careConditions, plant.careConditions);
      expect(restored.nextWatering, DateTime(2026, 10, 11));
      expect(restored.statusAt(garden.today), WateringStatus.watered);
      expect(
        references.find(ReferenceKind.fertilizer, fertilizer.id)!.name,
        'Комплексное',
      );
      expect(
        references.find(ReferenceKind.family, familyId)!.name,
        'Марантовые растения',
      );
      expect(garden.records.where((r) => r.plantId == plant.id).length, 2);
      await showApp();
      await tap(find.byKey(ValueKey('details-${plant.id}')));
      expect(find.text('Семейство: Ароидные'), findsOneWidget);
      expect(
        find.text('Рассеянный свет. Повышенная влажность воздуха.'),
        findsOneWidget,
      );
      await shot('07_after_reopen');
      await tap(find.byTooltip('Назад'));
      await tap(find.text('Календарь'));
      garden.selectDay(DateTime(2026, 10, 11));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.drag(
        find.byKey(const ValueKey('page-1')),
        const Offset(0, -500),
      );
      await tester.pump(const Duration(milliseconds: 500));
      expect(
        garden
            .proceduresOn(DateTime(2026, 10, 11))
            .where((p) => p.plantId == plant.id)
            .length,
        2,
      );
      await shot('08_saved_schedule');

      debugPrint('SCENARIO: preventing dangling references');
      await tap(find.byKey(const ValueKey('reference-catalog')));
      await tap(find.byKey(const ValueKey('reference-menu-family-aroids')));
      await tap(find.text('Удалить'));
      await tap(find.widgetWithText(FilledButton, 'Удалить'));
      expect(find.textContaining('Запись используется.'), findsOneWidget);
      await shot('09_reference_guard');
      await tester.pump(const Duration(seconds: 5));
      await tap(find.byKey(ValueKey('reference-menu-$familyId')));
      await tap(find.text('Удалить'));
      await tap(find.widgetWithText(FilledButton, 'Удалить'));
      for (var i = 0; i < 30 && references.saving; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }
      expect(references.find(ReferenceKind.family, familyId), isNull);
      await shot('10_reference_deleted');
      await tester.pumpWidget(const SizedBox.shrink());
      await resources.close();

    },
  );
}
