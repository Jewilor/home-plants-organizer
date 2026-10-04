import '../models/reference_entry.dart';
import 'storage_notice.dart';
import 'package:flutter/material.dart';
import '../models/plant.dart';
import '../services/botanical_repository.dart';
import '../viewmodels/garden_view_model.dart';
import '../viewmodels/plant_detail_view_model.dart';
import 'editors.dart';
import 'care_guide_screen.dart';

/// Детальный экран растения с ботанической справкой и журналом ухода.
class PlantDetailScreen extends StatefulWidget {
  const PlantDetailScreen({
    super.key,
    required this.garden,
    required this.plantId,
  });
  final GardenViewModel garden;
  final String plantId;
  @override
  State<PlantDetailScreen> createState() => _PlantDetailScreenState();
}

class _PlantDetailScreenState extends State<PlantDetailScreen> {
  late final PlantDetailViewModel model;
  @override
  void initState() {
    super.initState();
    model = PlantDetailViewModel(
      garden: widget.garden,
      plantId: widget.plantId,
      repository: AssetBotanicalRepository(),
    );
    model.load();
  }

  @override
  void dispose() {
    model.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: model,
    builder: (context, _) {
      final plant = model.plant;
      final profile = model.profile;
      return Scaffold(
        appBar: AppBar(title: Text(plant?.name ?? 'Растение удалено')),
        body: plant == null
            ? const Center(child: Text('Растение удалено из каталога.'))
            : SingleChildScrollView(
                physics: const ClampingScrollPhysics(),
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      plant.name,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    if (plant.species.isNotEmpty) Text(plant.species),
                    if (plant.room.isNotEmpty) Text('Комната: ${plant.room}'),
                    if (plant.familyId.isNotEmpty)
                      Text(
                        'Семейство: ${widget.garden.references?.find(ReferenceKind.family, plant.familyId)?.name ?? 'Запись недоступна'}',
                      ),
                    const SizedBox(height: 24),
                    if (widget.garden.encyclopedia != null) ...[
                      FilledButton.icon(
                        key: const ValueKey('remote-care'),
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute<void>(
                            builder: (_) => CareGuideScreen(
                              garden: widget.garden,
                              plantId: widget.plantId,
                            ),
                          ),
                        ),
                        icon: const Icon(Icons.travel_explore),
                        label: const Text('Получить регламент ухода'),
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (widget.garden.careGuideFor(widget.plantId)
                        case final guide?)
                      CareGuideCard(guide: guide, saved: true),
                    Text(
                      'Ботаническая справка',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 12),
                    if (plant.careConditions.isNotEmpty)
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Условия содержания',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 12),
                              SelectableText(plant.careConditions),
                              const SizedBox(height: 12),
                              const Text('Сведения введены пользователем.'),
                            ],
                          ),
                        ),
                      )
                    else if (model.loading)
                      const LinearProgressIndicator()
                    else if (model.error != null) ...[
                      Text(model.error!),
                      TextButton(
                        onPressed: model.load,
                        child: const Text('Повторить'),
                      ),
                    ] else if (profile == null)
                      const Text(
                        'Сведения для этого растения пока не добавлены в локальный справочник. Введите условия содержания в форме редактирования растения или проверьте написание поля «Вид растения».',
                      )
                    else
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                profile.species,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 12),
                              const Text(
                                'Освещение',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                              Text(profile.light),
                              const SizedBox(height: 12),
                              const Text(
                                'Влажность воздуха',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                              Text(profile.humidity),
                              const SizedBox(height: 12),
                              Text('Источник: ${profile.sourceName}'),
                              SelectableText(
                                profile.source,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                      ),
                    const SizedBox(height: 24),
                    StorageNotice(garden: widget.garden),
                    const SizedBox(height: 12),
                    Text(
                      'Журнал ухода',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      key: const ValueKey('record-care'),
                      icon: const Icon(Icons.add_task),
                      onPressed: () => showDialog<void>(
                        context: context,
                        builder: (_) => CareRecordEditor(
                          garden: widget.garden,
                          plantId: widget.plantId,
                        ),
                      ),
                      label: const Text('Записать уход'),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      children: [
                        ChoiceChip(
                          label: const Text('Все'),
                          selected: model.filter == null,
                          onSelected: (_) => model.selectFilter(null),
                        ),
                        for (final type in CareType.values)
                          ChoiceChip(
                            label: Text(type.label),
                            selected: model.filter == type,
                            onSelected: (_) => model.selectFilter(type),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (model.history.isEmpty)
                      const Text('Записей ухода пока нет.'),
                    for (final record in model.history)
                      Card(
                        child: ListTile(
                          leading: const Icon(Icons.check_circle_outline),
                          title: Text(record.type.label),
                          subtitle: Text(
                            '${fullDate(record.performedOn)}${record.note.isEmpty ? '' : '\n${record.note}'}',
                          ),
                        ),
                      ),
                    const SizedBox(height: 12),
                    Text(
                      widget.garden.persistent
                          ? 'История и расписание восстанавливаются после повторного запуска приложения.'
                          : 'История и расписание сохраняются до полного перезапуска приложения.',
                    ),
                  ],
                ),
              ),
      );
    },
  );
}

/// Ввод фактически выполненной процедуры, её даты и примечания.
class CareRecordEditor extends StatefulWidget {
  const CareRecordEditor({
    super.key,
    required this.garden,
    required this.plantId,
  });
  final GardenViewModel garden;
  final String plantId;
  @override
  State<CareRecordEditor> createState() => _CareRecordEditorState();
}

class _CareRecordEditorState extends State<CareRecordEditor> {
  CareType type = CareType.watering;
  late DateTime date;
  final note = TextEditingController();
  String? error;
  @override
  void initState() {
    super.initState();
    date = widget.garden.today;
  }

  @override
  void dispose() {
    note.dispose();
    super.dispose();
  }

  void save() {
    try {
      widget.garden.recordCare(
        plantId: widget.plantId,
        type: type,
        performedOn: date,
        note: note.text,
      );
      Navigator.pop(context);
    } on ArgumentError catch (e) {
      setState(() => error = e.message.toString());
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Записать уход'),
    content: SizedBox(
      width: 420,
      child: SingleChildScrollView(
        physics: const ClampingScrollPhysics(),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DropdownButtonFormField<CareType>(
              initialValue: type,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Вид ухода'),
              items: [
                for (final t in CareType.values)
                  DropdownMenuItem(value: t, child: Text(t.label)),
              ],
              onChanged: (v) => setState(() => type = v!),
            ),
            const SizedBox(height: 12),
            DateField(
              date: date,
              lastDate: widget.garden.today,
              onChanged: (v) => setState(() => date = v),
            ),
            TextField(
              controller: note,
              maxLength: 300,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Примечание'),
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
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Отмена'),
      ),
      FilledButton(onPressed: save, child: const Text('Сохранить')),
    ],
  );
}
