import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:home_plants_organizer/main.dart';
import 'package:home_plants_organizer/models/plant.dart';
import 'package:home_plants_organizer/services/label_recognition_service.dart';
import 'package:home_plants_organizer/viewmodels/garden_view_model.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Lab 2 Android OCR and complete user scenarios', (tester) async {
    final recognition = MlKitLabelRecognitionService();
    for (final sample in [
      ('monstera', 'Monstera deliciosa'),
      ('ficus', 'Ficus elastica'),
      ('peace_lily', 'Spathiphyllum wallisii'),
    ]) {
      final text = await recognition.recognizeSample(
        'assets/labels/${sample.$1}.png',
      );
      expect(text.toLowerCase(), contains(sample.$2.toLowerCase()));
    }
    await recognition.close();
    final model = GardenViewModel(clock: () => DateTime(2026, 9, 30));
    await tester.pumpWidget(
      RepaintBoundary(
        key: const ValueKey('capture-surface'),
        child: PlantApp(viewModel: model),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
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

    Future<void> tap(Finder finder) async {
      debugPrint('TAP: $finder');
      await tester.ensureVisible(finder);
      debugPrint('VISIBLE');
      await tester.tap(finder);
      await tester.pump(const Duration(milliseconds: 500));
    }

    debugPrint('SCENARIO: weekly editor');
    await tap(find.text('Календарь'));
    await tap(find.byKey(const ValueKey('add-procedure')));
    await tap(find.byKey(const ValueKey('weekly-choice')));
    await shot('01_weekly_editor');
    await tap(find.byKey(const ValueKey('save-procedure')));
    await tap(find.byTooltip('Следующий месяц'));
    await tap(
      find.byKey(ValueKey('day-${DateTime(2026, 10, 7).toIso8601String()}')),
    );
    expect(
      model.proceduresOn(DateTime(2026, 10, 7)).where((p) => p.weekly).length,
      1,
    );
    await shot('02_weekly_calendar');
    await tap(find.text('Мой сад'));
    await tap(find.byKey(const ValueKey('details-monstera')));
    debugPrint('SCENARIO: details');
    await shot('03_botanical_profile');
    await tap(find.byTooltip('Назад'));
    await tap(find.byKey(const ValueKey('add-plant')));
    await tester.enterText(
      find.byKey(const ValueKey('plant-name')),
      'Аглаонема',
    );
    await tester.enterText(
      find.byKey(const ValueKey('plant-species')),
      'Aglaonema commutatum',
    );
    await tester.enterText(
      find.byKey(const ValueKey('plant-room')),
      'Гостиная',
    );
    final conditionsField = find.byKey(const ValueKey('plant-care-conditions'));
    await tester.ensureVisible(conditionsField);
    await tester.enterText(
      conditionsField,
      'Рассеянный свет. Повышенная влажность воздуха.',
    );
    FocusManager.instance.primaryFocus?.unfocus();
    await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
    await tester.pump(const Duration(milliseconds: 600));
    await shot('04_manual_add');
    await tap(find.byKey(const ValueKey('save-plant')));
    final aglaonema = model.plants.singleWhere((p) => p.name == 'Аглаонема');
    expect(
      aglaonema.careConditions,
      'Рассеянный свет. Повышенная влажность воздуха.',
    );
    await tap(find.byKey(ValueKey('plant-menu-${aglaonema.id}')));
    await tap(find.text('Редактировать'));
    expect(
      tester.widget<TextFormField>(conditionsField).controller!.text,
      aglaonema.careConditions,
    );
    await tester.ensureVisible(conditionsField);
    await tester.enterText(
      conditionsField,
      'Рассеянный свет. Повышенная влажность воздуха. Беречь от прямых солнечных лучей.',
    );
    FocusManager.instance.primaryFocus?.unfocus();
    await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
    await tester.pump(const Duration(milliseconds: 600));
    await shot('05_manual_edit');
    await tap(find.byKey(const ValueKey('save-plant')));
    await tap(find.byKey(ValueKey('details-${aglaonema.id}')));
    expect(find.text('Сведения введены пользователем.'), findsOneWidget);
    expect(
      find.text(
        'Рассеянный свет. Повышенная влажность воздуха. Беречь от прямых солнечных лучей.',
      ),
      findsOneWidget,
    );
    await shot('06_manual_profile');
    await tap(find.byTooltip('Назад'));
    await tap(find.byKey(const ValueKey('details-monstera')));
    await tap(find.text('Все'));
    await tester.drag(
      find.byType(SingleChildScrollView).first,
      const Offset(0, -350),
    );
    await shot('07_care_history');
    await tap(find.byKey(const ValueKey('record-care')));
    await tester.enterText(
      find.byType(TextField).last,
      'Проверка состояния почвы перед поливом',
    );
    FocusManager.instance.primaryFocus?.unfocus();
    await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
    await tester.pump(const Duration(milliseconds: 600));
    await shot('08_record_care');
    await tap(find.widgetWithText(FilledButton, 'Сохранить'));
    expect(
      model.records
          .where(
            (r) =>
                r.plantId == 'monstera' && sameDay(r.performedOn, model.today),
          )
          .length,
      1,
    );
    await tap(find.text('Полив').first);
    await shot('09_history_filter');
    await tap(find.byTooltip('Назад'));
    await tester.pump(const Duration(milliseconds: 500));
    debugPrint('SCENARIO: scan');
    await tap(find.byKey(const ValueKey('scan-label')));
    await shot('10_label_sources');
    await tap(find.widgetWithText(ActionChip, 'Монстера'));
    for (
      var i = 0;
      i < 80 && find.byType(LinearProgressIndicator).evaluate().isNotEmpty;
      i++
    ) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.textContaining('Monstera deliciosa'), findsWidgets);
    await tester.drag(
      find.byType(SingleChildScrollView).first,
      const Offset(0, -260),
    );
    await shot('11_label_result');
    await tap(find.widgetWithText(FilledButton, 'Добавить в мои растения'));
    expect(model.plants.length, 6);
    await tester.pumpWidget(const SizedBox.shrink());
    model.dispose();
  });
}
