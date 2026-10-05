import 'package:flutter/material.dart';
import '../models/plant.dart';

/// Способ повторения процедуры, выбранный в форме расписания.
enum CareRepeatMode { once, interval, weekdays }

/// Черновик формы; изменения применяются к саду только после сохранения.
class CareScheduleDraft {
  CareScheduleDraft([CareProcedure? source]) {
    interval = (source?.intervalDays ?? 1).toString();
    mode = source?.weekdays.isNotEmpty == true
        ? CareRepeatMode.weekdays
        : source?.repeats == true
        ? CareRepeatMode.interval
        : CareRepeatMode.once;
    weekdays.addAll(source?.weekdays ?? []);
    times.addAll(source?.times ?? []);
    timed = times.isNotEmpty;
  }
  late CareRepeatMode mode;
  late String interval;
  late bool timed;
  final Set<int> weekdays = {};
  final List<int> times = [];
  int get repeatEveryDays =>
      mode == CareRepeatMode.interval ? int.tryParse(interval) ?? -1 : 0;
  List<int> get selectedWeekdays =>
      mode == CareRepeatMode.weekdays ? (weekdays.toList()..sort()) : [];
  List<int> get selectedTimes => timed ? (List<int>.of(times)..sort()) : [];

  /// Не позволяет сохранить пустой недельный режим или расписание без времени.
  void validate() {
    if (mode == CareRepeatMode.weekdays && weekdays.isEmpty) {
      throw ArgumentError('Выберите хотя бы один день недели.');
    }
    if (mode == CareRepeatMode.interval &&
        (repeatEveryDays < 1 || repeatEveryDays > 365)) {
      throw ArgumentError('Введите интервал от 1 до 365 дней.');
    }
    if (timed && times.isEmpty) {
      throw ArgumentError('Добавьте хотя бы одно время процедуры.');
    }
  }
}

/// Общие поля гибкого расписания для форм растения и процедуры.
class CareScheduleFields extends StatefulWidget {
  const CareScheduleFields({
    super.key,
    required this.draft,
    required this.startDate,
    this.defaultMinutes = 540,
  });
  final CareScheduleDraft draft;
  final DateTime startDate;
  final int defaultMinutes;
  @override
  State<CareScheduleFields> createState() => _CareScheduleFieldsState();
}

class _CareScheduleFieldsState extends State<CareScheduleFields> {
  late final TextEditingController interval;
  String? error;
  @override
  void initState() {
    super.initState();
    interval = TextEditingController(text: widget.draft.interval);
  }

  @override
  void dispose() {
    interval.dispose();
    super.dispose();
  }

  /// Выбирает одно из времён суток и предотвращает дублирование событий.
  Future<void> chooseTime([int? previous]) async {
    final draft = widget.draft;
    final initial =
        previous ??
        (draft.times.isEmpty
            ? widget.defaultMinutes
            : (draft.times.last + 240) % 1440);
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: initial ~/ 60, minute: initial % 60),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (picked == null || !mounted) return;
    final minutes = picked.hour * 60 + picked.minute;
    setState(() {
      if (minutes != previous && draft.times.contains(minutes)) {
        error = 'Это время уже добавлено.';
        return;
      }
      error = null;
      if (previous != null) draft.times.remove(previous);
      draft.times.add(minutes);
      draft.times.sort();
    });
  }

  @override
  Widget build(BuildContext context) {
    final draft = widget.draft;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<CareRepeatMode>(
          key: const ValueKey('schedule-mode'),
          initialValue: draft.mode,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Повторение'),
          items: const [
            DropdownMenuItem(
              value: CareRepeatMode.once,
              child: Text('Одна дата'),
            ),
            DropdownMenuItem(
              value: CareRepeatMode.interval,
              child: Text('Через заданное число дней'),
            ),
            DropdownMenuItem(
              value: CareRepeatMode.weekdays,
              child: Text('По дням недели'),
            ),
          ],
          onChanged: (mode) => setState(() {
            draft.mode = mode!;
            error = null;
          }),
        ),
        const SizedBox(height: 12),
        if (draft.mode == CareRepeatMode.interval) ...[
          TextField(
            key: const ValueKey('procedure-interval'),
            controller: interval,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Интервал повторения, дней',
              helperText: '1 — ежедневно, 2 — через день; от 1 до 365.',
              helperMaxLines: 2,
            ),
            onChanged: (text) => draft.interval = text,
          ),
          const SizedBox(height: 8),
          const Text('Повторение отсчитывается от даты начала расписания.'),
        ],
        if (draft.mode == CareRepeatMode.weekdays) ...[
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              for (var day = 1; day <= 7; day++)
                FilterChip(
                  key: ValueKey('schedule-weekday-$day'),
                  label: Text(weekdayLabels[day - 1]),
                  selected: draft.weekdays.contains(day),
                  onSelected: (selected) => setState(() {
                    if (selected) {
                      draft.weekdays.add(day);
                    } else {
                      draft.weekdays.remove(day);
                    }
                  }),
                ),
            ],
          ),
          const Text(
            'Выбранные дни повторяются каждую неделю, начиная с даты начала. Можно выбрать один или несколько дней.',
          ),
        ],
        SwitchListTile(
          key: const ValueKey('schedule-times-enabled'),
          contentPadding: EdgeInsets.zero,
          title: const Text('Задать время процедур'),
          subtitle: const Text(
            'Для нескольких процедур в день добавьте несколько времён.',
          ),
          value: draft.timed,
          onChanged: (enabled) => setState(() {
            draft.timed = enabled;
            error = null;
            if (enabled && draft.times.isEmpty) {
              draft.times.add(widget.defaultMinutes);
            }
          }),
        ),
        if (draft.timed) ...[
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final minutes in draft.times)
                InputChip(
                  key: ValueKey('schedule-time-$minutes'),
                  label: Text(clockLabel(minutes)),
                  avatar: const Icon(Icons.schedule, size: 18),
                  onPressed: () => chooseTime(minutes),
                  onDeleted: () => setState(() => draft.times.remove(minutes)),
                ),
            ],
          ),
          OutlinedButton.icon(
            key: const ValueKey('schedule-add-time'),
            onPressed: () => chooseTime(),
            icon: const Icon(Icons.add),
            label: const Text('Добавить время'),
          ),
          const Text(
            'Каждое время — отдельное событие календаря и отдельное уведомление. Выполнение одного события не закрывает остальные.',
          ),
        ] else
          const Text(
            'Без отдельных часов уведомления используют общее время или время растения из раздела «Напоминания».',
          ),
        if (error != null)
          Text(
            error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
      ],
    );
  }
}
