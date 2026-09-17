import 'package:flutter/material.dart';
import '../models/plant.dart';
import '../viewmodels/garden_view_model.dart';

String fullDate(DateTime date) =>
    '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}';

class DateField extends StatelessWidget {
  const DateField({super.key, required this.date, required this.onChanged});
  final DateTime date;
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
        lastDate: DateTime(2200, 12, 31),
      );
      if (picked != null && context.mounted) onChanged(picked);
    },
  );
}

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
  late DateTime date;
  bool schedule = true;
  String? error;
  @override
  void initState() {
    super.initState();
    name = TextEditingController(text: widget.plant?.name ?? '');
    species = TextEditingController(text: widget.plant?.species ?? '');
    room = TextEditingController(text: widget.plant?.room ?? '');
    date = widget.model.today;
  }

  @override
  void dispose() {
    name.dispose();
    species.dispose();
    room.dispose();
    super.dispose();
  }

  void save() {
    if (!form.currentState!.validate()) return;
    try {
      widget.model.savePlant(
        id: widget.plant?.id,
        name: name.text,
        species: species.text,
        room: room.text,
        firstWatering: widget.plant == null && schedule ? date : null,
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
              if (widget.plant == null) ...[
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: schedule,
                  title: const Text('Запланировать первый полив'),
                  onChanged: (value) => setState(() => schedule = value!),
                ),
                if (schedule)
                  DateField(
                    date: date,
                    onChanged: (value) => setState(() => date = value),
                  ),
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
  String? error;
  @override
  void initState() {
    super.initState();
    plantId = widget.procedure?.plantId ?? widget.model.plants.first.id;
    type = widget.procedure?.type ?? CareType.watering;
    date = widget.procedure?.date ?? widget.model.selectedDate;
  }

  void save() {
    try {
      widget.model.saveProcedure(
        id: widget.procedure?.id,
        plantId: plantId,
        type: type,
        date: date,
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
            const SizedBox(height: 20),
            const Text('Дата процедуры'),
            DateField(
              date: date,
              onChanged: (value) => setState(() => date = value),
            ),
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
