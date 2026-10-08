import 'package:flutter/material.dart';
import '../models/care_guide.dart';
import '../models/plant.dart';
import '../viewmodels/garden_view_model.dart';
import '../viewmodels/care_guide_view_model.dart';
import 'editors.dart';

/// Показывает полученные сведения, их источник и дату получения.
class CareGuideCard extends StatelessWidget {
  const CareGuideCard({super.key, required this.guide, this.saved = false});
  final CareGuide guide;
  final bool saved;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            saved ? 'Сохранённый регламент' : 'Полученный регламент',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(guide.species),
          const SizedBox(height: 8),
          Text(
            guide.family.isEmpty
                ? 'Семейство: не указано в энциклопедии.'
                : 'Семейство: ${guide.family}',
            key: const ValueKey('care-guide-family'),
          ),
          const SizedBox(height: 12),
          const Text(
            'Освещение',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          Text(guide.light),
          const SizedBox(height: 8),
          const Text(
            'Влажность воздуха',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          Text(guide.humidity),
          const SizedBox(height: 8),
          const Text('Полив', style: TextStyle(fontWeight: FontWeight.bold)),
          Text(guide.watering),
          const SizedBox(height: 12),
          Text('Источник: ${guide.sourceName}'),
          SelectableText(
            guide.sourceUrl,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          Text('Получено: ${fullDate(guide.downloadedAt.toLocal())}'),
          if (saved)
            const Text('Сведения доступны без подключения к интернету.'),
        ],
      ),
    ),
  );
}

/// Отправляет имя растения в энциклопедию и сохраняет выбранный регламент в базе.
class CareGuideScreen extends StatefulWidget {
  const CareGuideScreen({
    super.key,
    required this.garden,
    required this.plantId,
  });
  final GardenViewModel garden;
  final String plantId;
  @override
  State<CareGuideScreen> createState() => _CareGuideScreenState();
}

class _CareGuideScreenState extends State<CareGuideScreen> {
  late final CareGuideViewModel model;
  late final TextEditingController query;
  final interval = TextEditingController();
  late DateTime firstWatering;
  bool schedule = true;
  bool saving = false;
  String? saveError;
  CareGuide? lastGuide;
  @override
  void initState() {
    super.initState();
    final plant = widget.garden.plants.firstWhere(
      (p) => p.id == widget.plantId,
    );
    query = TextEditingController(
      text: plant.species.isEmpty ? plant.name : plant.species,
    );
    firstWatering = addDays(widget.garden.today, 1);
    model = CareGuideViewModel(widget.garden.encyclopedia!);
    model.addListener(_updated);
    model.load(query.text);
  }

  void _updated() {
    if (model.guide != null && !identical(lastGuide, model.guide)) {
      lastGuide = model.guide;
      interval.text = model.guide!.wateringIntervalDays?.toString() ?? '';
      schedule = model.guide!.wateringIntervalDays != null;
    }
  }

  @override
  void dispose() {
    model.removeListener(_updated);
    model.dispose();
    query.dispose();
    interval.dispose();
    super.dispose();
  }

  /// Сохраняет справку после проверки данных и выбранного пользователем интервала.
  Future<void> save() async {
    final guide = model.guide;
    if (guide == null || saving) return;
    setState(() {
      saving = true;
      saveError = null;
    });
    try {
      await widget.garden.applyCareGuide(
        widget.plantId,
        guide,
        firstWatering: schedule ? firstWatering : null,
        intervalDays: schedule ? int.tryParse(interval.text) : null,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Регламент сохранён.')));
      Navigator.pop(context);
    } on ArgumentError catch (e) {
      if (mounted) setState(() => saveError = e.message.toString());
    } catch (_) {
      if (mounted) {
        setState(
          () => saveError =
              'Не удалось сохранить регламент. Повторите сохранение.',
        );
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: model,
    builder: (context, _) => Scaffold(
      appBar: AppBar(title: const Text('Регламент ухода')),
      body: SingleChildScrollView(
        physics: const ClampingScrollPhysics(),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Источник поиска: ${model.encyclopedia.sourceLabel}'),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('care-query'),
              controller: query,
              maxLength: 100,
              enabled: !saving,
              decoration: const InputDecoration(
                labelText: 'Название или вид растения',
              ),
            ),
            OutlinedButton.icon(
              key: const ValueKey('load-care-guide'),
              onPressed: model.loading || saving
                  ? null
                  : () {
                      saveError = null;
                      model.load(query.text);
                    },
              icon: const Icon(Icons.travel_explore),
              label: const Text('Найти в энциклопедии'),
            ),
            if (model.loading) ...[
              const LinearProgressIndicator(),
              const Text('Получение регламента…'),
            ],
            if (model.error != null)
              Text(
                model.error!,
                key: const ValueKey('care-network-error'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            if (model.guide != null) ...[
              const SizedBox(height: 12),
              CareGuideCard(guide: model.guide!),
              if (model.guide!.family.isNotEmpty &&
                  widget.garden.references != null)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    'При сохранении семейство будет выбрано для растения. '
                    'Если его нет в справочнике, оно добавится автоматически.',
                  ),
                ),
              CheckboxListTile(
                key: const ValueKey('care-create-schedule'),
                value: schedule,
                contentPadding: EdgeInsets.zero,
                title: const Text('Создать расписание полива'),
                onChanged: saving ? null : (v) => setState(() => schedule = v!),
              ),
              if (schedule) ...[
                TextField(
                  key: const ValueKey('care-interval'),
                  controller: interval,
                  keyboardType: TextInputType.number,
                  enabled: !saving,
                  decoration: const InputDecoration(
                    labelText: 'Интервал полива, дней',
                    helperText: 'От 1 до 365 дней',
                  ),
                ),
                const SizedBox(height: 12),
                const Text('Первый полив'),
                DateField(
                  date: firstWatering,
                  onChanged: (v) => setState(() => firstWatering = v),
                ),
                if (widget.garden.procedures.any(
                  (p) =>
                      p.plantId == widget.plantId &&
                      p.type == CareType.watering,
                ))
                  const Text(
                    'Текущее расписание полива будет заменено. Выполненные процедуры сохранятся в журнале.',
                  ),
              ],
              const SizedBox(height: 12),
              if (saveError != null)
                Text(
                  saveError!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              FilledButton.icon(
                key: const ValueKey('save-care-guide'),
                onPressed: saving ? null : save,
                icon: const Icon(Icons.save_outlined),
                label: const Text('Сохранить регламент'),
              ),
              const Text(
                'Ручные условия содержания сохранятся отдельно. Напоминания включаются в разделе «Напоминания».',
              ),
            ],
          ],
        ),
      ),
    ),
  );
}
