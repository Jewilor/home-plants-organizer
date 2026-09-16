import 'dart:async';
import 'package:flutter/material.dart';
import '../models/plant.dart';
import '../viewmodels/garden_view_model.dart';

const forest = Color(0xFF285B43);
const ink = Color(0xFF20392D);
const muted = Color(0xFF69776C);
const months = [
  'Январь',
  'Февраль',
  'Март',
  'Апрель',
  'Май',
  'Июнь',
  'Июль',
  'Август',
  'Сентябрь',
  'Октябрь',
  'Ноябрь',
  'Декабрь',
];
String shortDate(DateTime date) =>
    '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}';

class GardenScreen extends StatefulWidget {
  const GardenScreen({super.key, this.viewModel});
  final GardenViewModel? viewModel;
  @override
  State<GardenScreen> createState() => _GardenScreenState();
}

class _GardenScreenState extends State<GardenScreen>
    with WidgetsBindingObserver {
  late final GardenViewModel model;
  late final Timer timer;
  int tab = 0;
  @override
  void initState() {
    super.initState();
    model = widget.viewModel ?? GardenViewModel();
    WidgetsBinding.instance.addObserver(this);
    timer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => model.refreshToday(),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) model.refreshToday();
  }

  @override
  void dispose() {
    timer.cancel();
    WidgetsBinding.instance.removeObserver(this);
    if (widget.viewModel == null) model.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: model,
    builder: (context, _) => Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFFF7F8F2),
        title: const Row(
          children: [
            Icon(Icons.spa_outlined, color: forest),
            SizedBox(width: 10),
            Flexible(
              child: Text(
                'Листва',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontWeight: FontWeight.w800, color: ink),
              ),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 20),
            child: Text(
              shortDate(model.today),
              style: const TextStyle(color: muted),
            ),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (value) => setState(() => tab = value),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.yard_outlined),
            selectedIcon: Icon(Icons.yard),
            label: 'Мой сад',
          ),
          NavigationDestination(
            icon: Icon(Icons.calendar_month_outlined),
            selectedIcon: Icon(Icons.calendar_month),
            label: 'Календарь',
          ),
        ],
      ),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1100),
            child: LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth >= 850) {
                  return SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: garden()),
                        const SizedBox(width: 28),
                        Expanded(child: calendar()),
                      ],
                    ),
                  );
                }
                return SingleChildScrollView(
                  key: ValueKey('page-$tab'),
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                  child: tab == 0 ? garden() : calendar(),
                );
              },
            ),
          ),
        ),
      ),
    ),
  );

  Widget garden() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text(
        'Мой домашний сад',
        style: TextStyle(
          fontSize: 28,
          height: 1.15,
          fontWeight: FontWeight.w800,
          color: ink,
        ),
      ),
      const SizedBox(height: 8),
      const Text(
        'Немного заботы каждый день',
        style: TextStyle(color: muted, fontSize: 15),
      ),
      const SizedBox(height: 22),
      Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: forest,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'ВРЕМЯ ПОЗАБОТИТЬСЯ',
                    style: TextStyle(
                      color: Color(0xFFC5DABB),
                      fontSize: 11,
                      letterSpacing: 1.6,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    model.overdueCount > 0
                        ? 'Есть просроченный полив'
                        : 'Полив под контролем',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 21,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Растений: ${model.plants.length}  ·  Просрочено: ${model.overdueCount}',
                    style: const TextStyle(
                      color: Color(0xFFDEE9D9),
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(
              Icons.water_drop_outlined,
              color: Color(0xFFBBD595),
              size: 44,
            ),
          ],
        ),
      ),
      const SizedBox(height: 24),
      Row(
        children: [
          const Expanded(
            child: Text(
              'Мои растения',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: ink,
              ),
            ),
          ),
          Text('${model.plants.length}', style: const TextStyle(color: muted)),
        ],
      ),
      const SizedBox(height: 12),
      if (model.plants.isEmpty) const Text('В саду пока нет растений.'),
      for (final plant in model.plants)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: PlantCard(plant: plant, today: model.today),
        ),
      const SizedBox(height: 8),
      const Text(
        'Учебная коллекция · данные в памяти',
        style: TextStyle(fontSize: 12, color: muted),
      ),
    ],
  );

  Widget calendar() {
    final month = model.visibleMonth;
    final offset = month.weekday - 1;
    final count = DateTime(month.year, month.month + 1, 0).day;
    final cells = ((offset + count) / 7).ceil() * 7;
    final selected = model.proceduresOn(model.selectedDate);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Календарь ухода',
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w800,
            color: ink,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Выберите день, чтобы увидеть процедуры',
          style: TextStyle(color: muted),
        ),
        const SizedBox(height: 22),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: const Color(0xFFE1E7DB)),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  IconButton(
                    tooltip: 'Предыдущий месяц',
                    onPressed: () => model.changeMonth(-1),
                    icon: const Icon(Icons.chevron_left),
                  ),
                  Expanded(
                    child: Text(
                      '${months[month.month - 1]} ${month.year}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: ink,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Следующий месяц',
                    onPressed: () => model.changeMonth(1),
                    icon: const Icon(Icons.chevron_right),
                  ),
                ],
              ),
              TextButton(
                onPressed: model.goToToday,
                child: const Text('Сегодня'),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  for (final day in ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'])
                    Expanded(
                      child: Center(
                        child: Text(
                          day,
                          style: const TextStyle(fontSize: 12, color: muted),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: cells,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 7,
                  mainAxisExtent: 52,
                ),
                itemBuilder: (context, index) {
                  final day = index - offset + 1;
                  if (day < 1 || day > count) return const SizedBox.shrink();
                  final date = DateTime(month.year, month.month, day);
                  final active = sameDay(date, model.selectedDate);
                  final isToday = sameDay(date, model.today);
                  final events = model.proceduresOn(date);
                  return Padding(
                    padding: const EdgeInsets.all(2),
                    child: Semantics(
                      label:
                          '${shortDate(date)}.${date.year}, процедур: ${events.length}${isToday ? ', сегодня' : ''}',
                      selected: active,
                      button: true,
                      child: Material(
                        color: active ? forest : Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                        shape: null,
                        child: InkWell(
                          key: ValueKey('day-${date.toIso8601String()}'),
                          borderRadius: BorderRadius.circular(12),
                          onTap: () => model.selectDay(date),
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              border: isToday && !active
                                  ? Border.all(color: forest)
                                  : null,
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(
                                    '$day',
                                    maxLines: 1,
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: active ? Colors.white : ink,
                                      fontWeight: isToday || active
                                          ? FontWeight.bold
                                          : FontWeight.normal,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 3),
                                SizedBox(
                                  height: 4,
                                  child: events.isEmpty
                                      ? null
                                      : Center(
                                          child: Container(
                                            width: 4,
                                            height: 4,
                                            decoration: BoxDecoration(
                                              shape: BoxShape.circle,
                                              color: active
                                                  ? Colors.white
                                                  : forest,
                                            ),
                                          ),
                                        ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
              const Padding(
                padding: EdgeInsets.all(8),
                child: Text(
                  '•  День с запланированными процедурами',
                  style: TextStyle(fontSize: 11, color: muted),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Text(
          'Процедуры на ${shortDate(model.selectedDate)}',
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: ink,
          ),
        ),
        const SizedBox(height: 12),
        if (selected.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFFEEF2E7),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Column(
              children: [
                Icon(Icons.event_available_outlined, color: forest, size: 32),
                SizedBox(height: 12),
                Text(
                  'На этот день процедур нет',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontWeight: FontWeight.w600, color: ink),
                ),
                SizedBox(height: 6),
                Text(
                  'Можно просто полюбоваться растениями',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: muted),
                ),
              ],
            ),
          ),
        for (final procedure in selected)
          Container(
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
            ),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 6,
              ),
              leading: CircleAvatar(
                backgroundColor: const Color(0xFFEDF2E6),
                foregroundColor: forest,
                child: Icon(switch (procedure.type) {
                  CareType.watering => Icons.water_drop_outlined,
                  CareType.feeding => Icons.eco_outlined,
                  CareType.repotting => Icons.yard_outlined,
                }),
              ),
              title: Text(
                procedure.type.label,
                style: const TextStyle(fontWeight: FontWeight.w700, color: ink),
              ),
              subtitle: Text(model.plantFor(procedure).name),
            ),
          ),
      ],
    );
  }
}

class PlantCard extends StatelessWidget {
  const PlantCard({super.key, required this.plant, required this.today});
  final Plant plant;
  final DateTime today;
  @override
  Widget build(BuildContext context) {
    final status = plant.statusAt(today);
    final (background, accent, label) = switch (status) {
      WateringStatus.overdue => (
        const Color(0xFFFFE8E2),
        const Color(0xFFA63825),
        'Полив просрочен',
      ),
      WateringStatus.today => (
        const Color(0xFFFFF1D6),
        const Color(0xFF855600),
        'Полить сегодня',
      ),
      WateringStatus.upcoming => (
        const Color(0xFFEDF3E6),
        forest,
        'Полив ${shortDate(plant.nextWatering)}',
      ),
    };
    return Container(
      key: ValueKey('plant-${plant.id}'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 62,
            height: 94,
            child: CustomPaint(painter: PlantPainter(plant.art)),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  plant.name,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: ink,
                  ),
                ),
                Text(
                  plant.species,
                  style: const TextStyle(
                    fontSize: 11,
                    color: muted,
                    fontStyle: FontStyle.italic,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  plant.room,
                  style: const TextStyle(fontSize: 12, color: muted),
                ),
                const SizedBox(height: 10),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      status == WateringStatus.overdue
                          ? Icons.warning_amber_rounded
                          : Icons.water_drop_outlined,
                      color: accent,
                      size: 17,
                    ),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        label,
                        style: TextStyle(
                          color: accent,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                if (status == WateringStatus.overdue)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(
                      'Срок: ${shortDate(plant.nextWatering)}',
                      style: TextStyle(color: accent, fontSize: 11),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Vector illustration drawn locally: no network or external image dependencies.
class PlantPainter extends CustomPainter {
  PlantPainter(this.variant);
  final int variant;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 80, size.height / 110);
    final stem = Paint()
      ..color = forest
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;
    canvas.drawLine(const Offset(40, 83), const Offset(40, 17), stem);
    for (var i = 0; i < 5; i++) {
      final y = 20.0 + i * 11;
      final right = i.isEven;
      final x = right ? 65.0 : 12.0;
      final path = Path()
        ..moveTo(40, y + 12)
        ..quadraticBezierTo(
          right ? 38 : 44,
          y - 13,
          x,
          y - (variant == 2 ? 22 : 4),
        )
        ..quadraticBezierTo(x + (right ? 8 : -7), y + 13, 40, y + 12);
      canvas.drawPath(
        path,
        Paint()
          ..color = i.isEven
              ? const Color(0xFF397B51)
              : const Color(0xFF709853),
      );
    }
    final pot = Path()
      ..moveTo(20, 77)
      ..lineTo(60, 77)
      ..lineTo(54, 104)
      ..lineTo(26, 104)
      ..close();
    canvas.drawPath(
      pot,
      Paint()
        ..color = variant.isEven
            ? const Color(0xFFB97853)
            : const Color(0xFFE0C9A7),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(18, 75, 44, 7),
        const Radius.circular(3),
      ),
      Paint()
        ..color = variant.isEven
            ? const Color(0xFFCF946F)
            : const Color(0xFFEDDABD),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(PlantPainter oldDelegate) =>
      oldDelegate.variant != variant;
}
