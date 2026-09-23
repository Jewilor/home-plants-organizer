import 'dart:async';
import 'package:flutter/material.dart';
import '../models/plant.dart';
import '../viewmodels/garden_view_model.dart';
import 'editors.dart';

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
const heading = TextStyle(
  fontSize: 26,
  fontWeight: FontWeight.w800,
  color: ink,
);

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

  void editPlant([Plant? plant]) {
    showDialog<void>(
      context: context,
      builder: (_) => PlantEditor(model: model, plant: plant),
    );
  }

  void editProcedure([CareProcedure? procedure]) {
    if (model.plants.isEmpty) return;
    showDialog<void>(
      context: context,
      builder: (_) => ProcedureEditor(model: model, procedure: procedure),
    );
  }

  Future<void> confirmDelete(
    String title,
    String description,
    VoidCallback remove,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(description),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            key: const ValueKey('confirm-delete'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) remove();
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
            padding: const EdgeInsets.only(right: 16),
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
            label: 'Мой сад',
          ),
          NavigationDestination(
            icon: Icon(Icons.calendar_month_outlined),
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
              builder: (context, constraints) => SingleChildScrollView(
                key: ValueKey('page-$tab'),
                // Ограниченная прокрутка убирает эффект растягивания на Android.
                physics: const ClampingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                child: constraints.maxWidth >= 850
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: garden()),
                          const SizedBox(width: 28),
                          Expanded(child: calendar()),
                        ],
                      )
                    : tab == 0
                    ? garden()
                    : calendar(),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  Widget garden() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text('Мой домашний сад', style: heading),
      const SizedBox(height: 8),
      const Text('Немного заботы каждый день', style: TextStyle(color: muted)),
      const SizedBox(height: 20),
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: forest,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'ВРЕМЯ ПОЗАБОТИТЬСЯ',
              style: TextStyle(
                color: Color(0xFFC5DABB),
                fontSize: 11,
                letterSpacing: 1.4,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              model.plants.isEmpty
                  ? 'Начните свой домашний сад'
                  : model.overdueCount > 0
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
              style: const TextStyle(color: Color(0xFFDEE9D9)),
            ),
          ],
        ),
      ),
      const SizedBox(height: 20),
      const Text(
        'Мои растения',
        style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: ink),
      ),
      const SizedBox(height: 8),
      FilledButton.icon(
        key: const ValueKey('add-plant'),
        onPressed: () => editPlant(),
        icon: const Icon(Icons.add),
        label: const Text('Добавить растение'),
      ),
      const SizedBox(height: 12),
      if (model.plants.isEmpty)
        const Text('В саду пока нет растений. Добавьте первое растение.'),
      for (final plant in model.plants)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: PlantCard(
            plant: plant,
            today: model.today,
            onEdit: () => editPlant(plant),
            onDelete: () => confirmDelete(
              'Удалить растение?',
              '«${plant.name}» и все его процедуры будут удалены из календаря.',
              () => model.deletePlant(plant.id),
            ),
            onWater: () => model.toggleWateredToday(plant.id),
          ),
        ),
      const SizedBox(height: 8),
      const Text(
        'Изменения хранятся до перезапуска приложения.',
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
        const Text('Календарь ухода', style: heading),
        const SizedBox(height: 8),
        const Text(
          'Выберите день, чтобы увидеть процедуры',
          style: TextStyle(color: muted),
        ),
        const SizedBox(height: 16),
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
              Row(
                children: [
                  for (final day in ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'])
                    Expanded(
                      child: Center(
                        child: FittedBox(
                          child: Text(
                            day,
                            style: const TextStyle(fontSize: 12, color: muted),
                          ),
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
                  final events = model.proceduresOn(date);
                  return Padding(
                    padding: const EdgeInsets.all(2),
                    child: Semantics(
                      label: '${fullDate(date)}, процедур: ${events.length}',
                      selected: active,
                      button: true,
                      child: Material(
                        color: active ? forest : Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                        child: InkWell(
                          key: ValueKey('day-${date.toIso8601String()}'),
                          borderRadius: BorderRadius.circular(12),
                          onTap: () => model.selectDay(date),
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              border: sameDay(date, model.today) && !active
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
                                      fontWeight: active
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
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  '•  День с процедурами',
                  style: TextStyle(fontSize: 12, color: muted),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Text(
          'Процедуры на ${fullDate(model.selectedDate)}',
          style: const TextStyle(
            fontSize: 19,
            fontWeight: FontWeight.w700,
            color: ink,
          ),
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          key: const ValueKey('add-procedure'),
          onPressed: model.plants.isEmpty ? null : () => editProcedure(),
          icon: const Icon(Icons.add),
          label: const Text('Добавить процедуру'),
        ),
        if (model.plants.isEmpty)
          const Text('Сначала добавьте растение во вкладке «Мой сад».'),
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
              ],
            ),
          ),
        for (final procedure in selected)
          Container(
            key: ValueKey('procedure-${procedure.id}'),
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color: procedure.isCompleted
                  ? const Color(0xFFE6F2E3)
                  : Colors.white,
              borderRadius: BorderRadius.circular(18),
            ),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 6,
              ),
              title: Text(
                procedure.type.label,
                style: const TextStyle(fontWeight: FontWeight.w700, color: ink),
              ),
              subtitle: Text(
                '${model.plantFor(procedure).name}${procedure.isCompleted ? '\nВыполнено ${fullDate(procedure.completedOn!)}' : ''}',
              ),
              trailing: PopupMenuButton<String>(
                key: ValueKey('procedure-menu-${procedure.id}'),
                tooltip: 'Действия с процедурой',
                onSelected: (action) {
                  if (action == 'edit') {
                    editProcedure(procedure);
                  } else {
                    confirmDelete(
                      'Удалить процедуру?',
                      '${procedure.type.label}: ${model.plantFor(procedure).name}, ${fullDate(procedure.date)}.',
                      () => model.deleteProcedure(procedure.id),
                    );
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'edit', child: Text('Редактировать')),
                  PopupMenuItem(value: 'delete', child: Text('Удалить')),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class PlantCard extends StatelessWidget {
  const PlantCard({
    super.key,
    required this.plant,
    required this.today,
    this.onEdit,
    this.onDelete,
    this.onWater,
  });
  final Plant plant;
  final DateTime today;
  final VoidCallback? onEdit, onDelete, onWater;
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
        'Полив сегодня',
      ),
      WateringStatus.upcoming => (
        const Color(0xFFEDF3E6),
        forest,
        'Полив ${fullDate(plant.nextWatering!)}',
      ),
      WateringStatus.watered => (
        const Color(0xFFE1F1DD),
        forest,
        'Полито сегодня',
      ),
      WateringStatus.unscheduled => (
        const Color(0xFFEEF0EC),
        muted,
        'Полив не запланирован',
      ),
    };
    return Container(
      key: ValueKey('plant-${plant.id}'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 48,
                height: 82,
                child: CustomPaint(painter: PlantPainter(plant.art)),
              ),
              const SizedBox(width: 12),
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
                    if (plant.species.isNotEmpty)
                      Text(
                        plant.species,
                        style: const TextStyle(
                          fontSize: 12,
                          color: muted,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    if (plant.room.isNotEmpty)
                      Text(
                        plant.room,
                        style: const TextStyle(fontSize: 12, color: muted),
                      ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                key: ValueKey('plant-menu-${plant.id}'),
                tooltip: 'Действия с растением',
                onSelected: (value) =>
                    value == 'edit' ? onEdit?.call() : onDelete?.call(),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'edit', child: Text('Редактировать')),
                  PopupMenuItem(value: 'delete', child: Text('Удалить')),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(
                status == WateringStatus.watered
                    ? Icons.check_circle_outline
                    : status == WateringStatus.overdue
                    ? Icons.warning_amber_rounded
                    : Icons.water_drop_outlined,
                color: accent,
                size: 18,
              ),
              const SizedBox(width: 6),
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
            Text(
              'Срок: ${fullDate(plant.nextWatering!)}',
              style: TextStyle(color: accent, fontSize: 12),
            ),
          if (status == WateringStatus.watered)
            Text(
              plant.nextWatering == null
                  ? 'Следующий полив не запланирован'
                  : 'Следующий полив: ${fullDate(plant.nextWatering!)}',
              style: const TextStyle(fontSize: 12, color: muted),
            ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            key: ValueKey('water-${plant.id}'),
            onPressed: onWater,
            icon: Icon(
              status == WateringStatus.watered
                  ? Icons.undo
                  : Icons.water_drop_outlined,
              size: 18,
            ),
            label: Text(
              status == WateringStatus.watered
                  ? 'Отменить отметку'
                  : 'Полить сегодня',
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
