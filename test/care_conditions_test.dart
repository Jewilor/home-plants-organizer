import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:home_plants_organizer/models/plant.dart';
import 'package:home_plants_organizer/viewmodels/garden_view_model.dart';
import 'package:home_plants_organizer/views/editors.dart';
import 'package:home_plants_organizer/views/plant_detail_screen.dart';

Future<void> openEditor(
  WidgetTester tester,
  GardenViewModel garden, [
  Plant? plant,
]) async {
  await tester.pumpWidget(
    MaterialApp(
      key: UniqueKey(),
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => PlantEditor(model: garden, plant: plant),
            ),
            child: const Text('Открыть форму'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Открыть форму'));
  await tester.pumpAndSettle();
}

void main() {
  test('Conditions survive watering and rename, can be edited and cleared', () {
    final garden = GardenViewModel();
    addTearDown(garden.dispose);
    final id = garden.savePlant(
      name: 'Мой цветок',
      species: 'Unknown plant',
      careConditions: '  Рассеянный свет.\nУмеренная влажность.  ',
      firstWatering: garden.today,
    );
    Plant current() => garden.plants.firstWhere((plant) => plant.id == id);
    expect(current().careConditions, 'Рассеянный свет.\nУмеренная влажность.');
    garden.toggleWateredToday(id);
    expect(current().careConditions, 'Рассеянный свет.\nУмеренная влажность.');
    garden.savePlant(id: id, name: 'Переименованный цветок');
    expect(current().careConditions, 'Рассеянный свет.\nУмеренная влажность.');
    garden.savePlant(
      id: id,
      name: current().name,
      careConditions: 'Новые условия',
    );
    expect(current().careConditions, 'Новые условия');
    expect(
      () => garden.savePlant(
        id: id,
        name: current().name,
        careConditions: List.filled(2001, 'а').join(),
      ),
      throwsArgumentError,
    );
    expect(current().careConditions, 'Новые условия');
    garden.savePlant(id: id, name: current().name, careConditions: '  ');
    expect(current().careConditions, isEmpty);
  });

  testWidgets('Add and edit forms save conditions on a small phone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final garden = GardenViewModel();
    addTearDown(garden.dispose);
    await openEditor(tester, garden);
    await tester.enterText(
      find.byKey(const ValueKey('plant-name')),
      'Аглаонема',
    );
    final field = find.byKey(const ValueKey('plant-care-conditions'));
    await tester.ensureVisible(field);
    await tester.enterText(field, 'Рассеянный свет. Повышенная влажность.');
    await tester.tap(find.byKey(const ValueKey('save-plant')));
    await tester.pumpAndSettle();
    final added = garden.plants.last;
    expect(added.careConditions, 'Рассеянный свет. Повышенная влажность.');
    await openEditor(tester, garden, added);
    await tester.ensureVisible(field);
    expect(
      tester.widget<TextFormField>(field).controller!.text,
      added.careConditions,
    );
    await tester.enterText(field, 'Условия изменены вручную.');
    await tester.tap(find.byKey(const ValueKey('save-plant')));
    await tester.pumpAndSettle();
    expect(garden.plants.last.careConditions, 'Условия изменены вручную.');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'Manual conditions take priority over the local reference and update',
    (tester) async {
      final garden = GardenViewModel();
      addTearDown(garden.dispose);
      garden.savePlant(
        id: 'monstera',
        name: 'Монстера',
        species: 'Monstera deliciosa',
        careConditions: 'Место у окна с рассеянным светом.',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: PlantDetailScreen(garden: garden, plantId: 'monstera'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Место у окна с рассеянным светом.'), findsOneWidget);
      expect(find.text('Сведения введены пользователем.'), findsOneWidget);
      expect(find.text('Освещение'), findsNothing);
      garden.savePlant(
        id: 'monstera',
        name: 'Монстера',
        species: 'Monstera deliciosa',
        careConditions: 'Новые условия содержания.',
      );
      await tester.pumpAndSettle();
      expect(find.text('Новые условия содержания.'), findsOneWidget);
      expect(find.text('Место у окна с рассеянным светом.'), findsNothing);
      garden.savePlant(
        id: 'monstera',
        name: 'Монстера',
        species: 'Monstera deliciosa',
        careConditions: '',
      );
      await tester.pumpAndSettle();
      expect(find.text('Освещение'), findsOneWidget);
      expect(find.text('Сведения введены пользователем.'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
