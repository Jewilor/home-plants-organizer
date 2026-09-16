import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:home_plants_organizer/models/plant.dart';
import 'package:home_plants_organizer/viewmodels/garden_view_model.dart';
import 'package:home_plants_organizer/views/garden_screen.dart';

void main() {
  test(
    'Watering status compares local dates, including month/year boundaries',
    () {
      Plant plant(DateTime due) => Plant(
        id: 'x',
        name: 'X',
        species: 'X',
        room: 'X',
        nextWatering: due,
        art: 0,
      );
      final now = DateTime(2026, 1, 1, 23, 59);
      expect(
        plant(DateTime(2025, 12, 31)).statusAt(now),
        WateringStatus.overdue,
      );
      expect(plant(DateTime(2026, 1, 1)).statusAt(now), WateringStatus.today);
      expect(
        plant(DateTime(2026, 1, 2)).statusAt(now),
        WateringStatus.upcoming,
      );
    },
  );
  test(
    'Calendar changes month, filters events, handles leap year, returns to today',
    () {
      final model = GardenViewModel(clock: () => DateTime(2024, 2, 29));
      expect(model.proceduresOn(model.today).length, 2);
      model.changeMonth(1);
      expect(model.selectedDate, DateTime(2024, 3, 1));
      model.changeMonth(-1);
      expect(model.visibleMonth, DateTime(2024, 2));
      model.selectDay(DateTime(2024, 2, 10));
      expect(model.proceduresOn(model.selectedDate), isEmpty);
      expect(model.overdueCount, 1);
      model.goToToday();
      expect(model.selectedDate, DateTime(2024, 2, 29));
      model.dispose();
    },
  );
  test('Clock rollover updates status without changing calendar selection', () {
    var now = DateTime(2026, 12, 31);
    final model = GardenViewModel(clock: () => now);
    model.selectDay(DateTime(2027, 3, 1));
    now = DateTime(2027, 1, 1);
    model.refreshToday();
    expect(model.overdueCount, 2);
    expect(model.selectedDate, DateTime(2027, 3, 1));
    model.goToToday();
    expect(model.visibleMonth, DateTime(2027, 1));
    model.dispose();
  });
  testWidgets('Phone catalog displays cards and overdue background', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final model = GardenViewModel(clock: () => DateTime(2026, 9, 16));
    await tester.pumpWidget(MaterialApp(home: GardenScreen(viewModel: model)));
    expect(find.text('Монстера'), findsOneWidget);
    expect(find.text('Полив просрочен'), findsOneWidget);
    final card = tester.widget<Container>(
      find.byKey(const ValueKey('plant-monstera')),
    );
    expect((card.decoration as BoxDecoration).color, const Color(0xFFFFE8E2));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    model.dispose();
  });
  testWidgets(
    'Calendar day tap, next month, empty state and today action work',
    (tester) async {
      tester.view.physicalSize = const Size(390, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final model = GardenViewModel(clock: () => DateTime(2026, 9, 16));
      await tester.pumpWidget(
        MaterialApp(home: GardenScreen(viewModel: model)),
      );
      await tester.tap(find.text('Календарь'));
      await tester.pumpAndSettle();
      expect(find.text('Полив'), findsOneWidget);
      expect(find.text('Подкормка'), findsOneWidget);
      await tester.tap(
        find.byKey(ValueKey('day-${DateTime(2026, 9, 10).toIso8601String()}')),
      );
      await tester.pumpAndSettle();
      expect(find.text('На этот день процедур нет'), findsOneWidget);
      await tester.tap(find.byTooltip('Следующий месяц'));
      await tester.pumpAndSettle();
      expect(find.text('Октябрь 2026'), findsOneWidget);
      await tester.tap(find.text('Сегодня'));
      await tester.pumpAndSettle();
      expect(find.text('Сентябрь 2026'), findsOneWidget);
      expect(model.selectedDate, DateTime(2026, 9, 16));
      await tester.pumpWidget(const SizedBox());
      model.dispose();
    },
  );
  for (final width in [320.0, 1024.0]) {
    testWidgets('Layout at width $width with large text has no overflow', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.5)),
            child: child!,
          ),
          home: const GardenScreen(),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Календарь'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
