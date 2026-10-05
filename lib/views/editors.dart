import 'care_schedule_fields.dart';
import '../viewmodels/reference_view_model.dart';
import '../models/reference_entry.dart';
import 'reference_screen.dart';
import 'package:flutter/material.dart';
import '../models/plant.dart';
import '../viewmodels/garden_view_model.dart';

/// Форматирует дату для отображения в русскоязычном интерфейсе.
String fullDate(DateTime date) =>
    '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}';

/// Кнопка выбора даты с открытием стандартного календаря Flutter.
class DateField extends StatelessWidget {
  const DateField({
    super.key,
    required this.date,
    required this.onChanged,
    this.lastDate,
  });
  final DateTime date;
  final DateTime? lastDate;
  final ValueChanged<DateTime> onChanged;
  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
    key: const ValueKey('choose-date'),
    icon: const Icon(Icons.calendar_month_outlined),
    label: Text(fullDate(date)),
    onPressed: () async {
      final picked = await showDatePicker(
        context: context,
        initialDate: date,
        firstDate: DateTime(1900),
        lastDate: lastDate ?? DateTime(2200, 12, 31),
      );
      if (picked != null && context.mounted) onChanged(picked);
    },
  );
}

/// Диалог добавления или редактирования растения.
class PlantEditor extends StatefulWidget {
  const PlantEditor({super.key, required this.model, this.plant});
  final GardenViewModel model;
  final Plant? plant;
  @override
  State<PlantEditor> createState() => _PlantEditorState();
}

class _PlantEditorState extends State<PlantEditor> {
  final form = GlobalKey<FormState>();
  late final TextEditingController name;
  late final TextEditingController species;
  late final TextEditingController room;
  late final TextEditingController careConditions;
  late DateTime date;
  String familyId = '';
  bool schedule = true;
  final careSchedule = CareScheduleDraft();
  String? error;
  @override
  void initState() {
    super.initState();
    name = TextEditingController(text: widget.plant?.name ?? '');
    species = TextEditingController(text: widget.plant?.species ?? '');
    room = TextEditingController(text: widget.plant?.room ?? '');
    careConditions = TextEditingController(
      text: widget.plant?.careConditions ?? '',
    );
    familyId = widget.plant?.familyId ?? '';
    date = widget.model.today;
  }

  @override
  void dispose() {
    name.dispose();
    species.dispose();
    room.dispose();
    careConditions.dispose();
    super.dispose();
  }

  void save() {
    if (!form.currentState!.validate()) return;
    try {
      if (widget.plant == null && schedule) careSchedule.validate();
      widget.model.savePlant(
        id: widget.plant?.id,
        name: name.text,
        species: species.text,
        room: room.text,
        careConditions: careConditions.text,
        familyId: familyId,
        firstWatering: widget.plant == null && schedule ? date : null,
        repeatEveryDays: schedule ? careSchedule.repeatEveryDays : 0,
        weekdays: schedule ? careSchedule.selectedWeekdays : const [],
        times: schedule ? careSchedule.selectedTimes : const [],
      );
      Navigator.pop(context);
    } on ArgumentError catch (e) {
      setState(() => error = e.message.toString());
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
    title: Text(
      widget.plant == null ? 'Новое растение' : 'Редактировать растение',
    ),
    content: SizedBox(
      width: 420,
      child: SingleChildScrollView(
        child: Form(
          key: form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                key: const ValueKey('plant-name'),
                controller: name,
                maxLength: 80,
                decoration: const InputDecoration(labelText: 'Название *'),
                textCapitalization: TextCapitalization.sentences,
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Введите название'
                    : null,
              ),
              TextFormField(
                key: const ValueKey('plant-species'),
                controller: species,
                maxLength: 100,
                decoration: const InputDecoration(labelText: 'Вид растения'),
              ),
              TextFormField(
                key: const ValueKey('plant-room'),
                controller: room,
                maxLength: 60,
                decoration: const InputDecoration(labelText: 'Комната'),
              ),
              if (widget.model.references != null) ...[
                const SizedBox(height: 12),
                ReferenceSelector(
                  key: const ValueKey('plant-family'),
                  model: widget.model.references!,
                  kind: ReferenceKind.family,
                  value: familyId,
                  onChanged: (value) => setState(() => familyId = value),
                ),
              ],
              TextFormField(
                key: const ValueKey('plant-care-conditions'),
                controller: careConditions,
                minLines: 3,
                maxLines: 5,
                maxLength: 2000,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Условия содержания',
                  helperText: 'Освещение, влажность и другие условия ухода.',
                  helperMaxLines: 2,
                ),
              ),
              if (widget.plant == null) ...[
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: schedule,
                  title: const Text('Запланировать первый полив'),
                  onChanged: (value) => setState(() => schedule = value!),
                ),
                if (schedule) ...[
                  const Text('Дата начала расписания'),
                  DateField(
                    date: date,
                    onChanged: (value) => setState(() => date = value),
                  ),
                  const SizedBox(height: 12),
                  CareScheduleFields(draft: careSchedule, startDate: date),
                ],
              ] else
                const Text(
                  'Даты и процедуры ухода можно изменить в календаре.',
                ),
              if (error != null)
                Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Отмена'),
      ),
      FilledButton(
        key: const ValueKey('save-plant'),
        onPressed: save,
        child: const Text('Сохранить'),
      ),
    ],
  );
}

/// Диалог добавления или редактирования процедуры ухода.
class ProcedureEditor extends StatefulWidget {
  const ProcedureEditor({super.key, required this.model, this.procedure});
  final GardenViewModel model;
  final CareProcedure? procedure;
  @override
  State<ProcedureEditor> createState() => _ProcedureEditorState();
}

class _ProcedureEditorState extends State<ProcedureEditor> {
  late String plantId;
  late CareType type;
  late DateTime date;
  late final CareScheduleDraft careSchedule;
  String fertilizerId = '';
  String? error;
  @override
  void initState() {
    super.initState();
    plantId = widget.procedure?.plantId ?? widget.model.plants.first.id;
    type = widget.procedure?.type ?? CareType.watering;
    date = widget.procedure?.date ?? widget.model.selectedDate;
    careSchedule = CareScheduleDraft(widget.procedure);
    fertilizerId = widget.procedure?.fertilizerId ?? '';
  }

  void save() {
    try {
      careSchedule.validate();
      widget.model.saveProcedure(
        id: widget.procedure?.id,
        plantId: plantId,
        type: type,
        date: date,
        fertilizerId: fertilizerId,
        repeatEveryDays: careSchedule.repeatEveryDays,
        weekdays: careSchedule.selectedWeekdays,
        times: careSchedule.selectedTimes,
      );
      Navigator.pop(context);
    } on ArgumentError catch (e) {
      setState(() => error = e.message.toString());
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
    title: Text(
      widget.procedure == null ? 'Новая процедура' : 'Редактировать процедуру',
    ),
    content: SizedBox(
      width: 420,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DropdownButtonFormField<String>(
              key: const ValueKey('procedure-plant'),
              initialValue: plantId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Растение'),
              items: [
                for (final plant in widget.model.plants)
                  DropdownMenuItem(
                    value: plant.id,
                    child: Text(
                      plant.room.isEmpty
                          ? plant.name
                          : '${plant.name} · ${plant.room}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (value) => setState(() => plantId = value!),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<CareType>(
              key: const ValueKey('procedure-type'),
              initialValue: type,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Процедура'),
              items: [
                for (final value in CareType.values)
                  DropdownMenuItem(value: value, child: Text(value.label)),
              ],
              onChanged: (value) => setState(() => type = value!),
            ),
            if (type == CareType.feeding &&
                widget.model.references != null) ...[
              const SizedBox(height: 16),
              ReferenceSelector(
                key: const ValueKey('procedure-fertilizer'),
                model: widget.model.references!,
                kind: ReferenceKind.fertilizer,
                value: fertilizerId,
                onChanged: (value) => setState(() => fertilizerId = value),
              ),
            ],
            const SizedBox(height: 20),
            const Text('Дата начала расписания'),
            DateField(
              date: date,
              onChanged: (value) => setState(() => date = value),
            ),
            const SizedBox(height: 12),
            CareScheduleFields(
              draft: careSchedule,
              startDate: date,
              defaultMinutes:
                  widget.model.wateringTimeFor(plantId).hour * 60 +
                  widget.model.wateringTimeFor(plantId).minute,
            ),
            if (widget.procedure?.repeats ?? false)
              const Text('Изменения применяются ко всей серии повторений.'),
            if (widget.procedure?.isCompleted ?? false)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Text(
                  'При смене даты, растения или вида процедуры отметка выполнения будет снята.',
                ),
              ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Отмена'),
      ),
      FilledButton(
        key: const ValueKey('save-procedure'),
        onPressed: save,
        child: const Text('Сохранить'),
      ),
    ],
  );
}

/// Выбор записи справочника по идентификатору с возможностью снять связь.
class ReferenceSelector extends StatelessWidget {
  const ReferenceSelector({
    super.key,
    required this.model,
    required this.kind,
    required this.value,
    required this.onChanged,
  });
  final ReferenceViewModel model;
  final ReferenceKind kind;
  final String value;
  final ValueChanged<String> onChanged;
  @override
  Widget build(BuildContext context) => DropdownButtonFormField<String>(
    initialValue: value,
    isExpanded: true,
    decoration: InputDecoration(
      labelText: kind == ReferenceKind.family
          ? 'Семейство растения'
          : 'Тип удобрения',
    ),
    items: [
      const DropdownMenuItem(value: '', child: Text('Не выбрано')),
      if (value.isNotEmpty && model.find(kind, value) == null)
        DropdownMenuItem(value: value, child: const Text('Запись недоступна')),
      for (final entry in model.entries(kind))
        DropdownMenuItem(
          value: entry.id,
          child: Row(
            children: [
              Icon(referenceIcon(entry.icon), size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  entry.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
    ],
    onChanged: (value) {
      if (value != null) onChanged(value);
    },
  );
}
