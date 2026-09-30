import 'package:flutter/material.dart';
import '../services/botanical_repository.dart';
import '../services/label_recognition_service.dart';
import '../viewmodels/garden_view_model.dart';
import '../viewmodels/label_scan_view_model.dart';

/// Экран съёмки этикетки и подтверждения распознанного названия растения.
class LabelScanScreen extends StatefulWidget {
  const LabelScanScreen({super.key, required this.garden});
  final GardenViewModel garden;
  @override
  State<LabelScanScreen> createState() => _LabelScanScreenState();
}

class _LabelScanScreenState extends State<LabelScanScreen> {
  late final LabelScanViewModel model;
  final name = TextEditingController();
  final species = TextEditingController();
  final room = TextEditingController();
  String _lastSuggestion = '';
  String? saveError;
  @override
  void initState() {
    super.initState();
    model = LabelScanViewModel(
      service: MlKitLabelRecognitionService(),
      repository: AssetBotanicalRepository(),
    );
    model.addListener(_update);
    model.recover();
  }

  void _update() {
    if (model.suggestion != _lastSuggestion) {
      _lastSuggestion = model.suggestion;
      name.text = model.profile?.name ?? model.suggestion;
      species.text = model.profile?.species ?? model.suggestion;
    }
  }

  @override
  void dispose() {
    model.removeListener(_update);
    model.dispose();
    name.dispose();
    species.dispose();
    room.dispose();
    super.dispose();
  }

  void save() {
    try {
      widget.garden.savePlant(
        name: name.text,
        species: species.text,
        room: room.text,
      );
      Navigator.pop(context);
    } on ArgumentError catch (e) {
      setState(() => saveError = e.message.toString());
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: model,
    builder: (context, _) => Scaffold(
      appBar: AppBar(title: const Text('Сканировать этикетку')),
      body: SingleChildScrollView(
        physics: const ClampingScrollPhysics(),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Снимите этикетку с латинским названием растения. Распознанный текст можно исправить перед сохранением.',
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: model.busy ? null : model.scanCamera,
              icon: const Icon(Icons.camera_alt_outlined),
              label: const Text('Снять этикетку'),
            ),
            OutlinedButton.icon(
              onPressed: model.busy ? null : model.scanGallery,
              icon: const Icon(Icons.photo_library_outlined),
              label: const Text('Выбрать изображение'),
            ),
            const SizedBox(height: 16),
            const Text(
              'Образцы этикеток для эмулятора',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const Text(
              'Изображения проходят настоящее распознавание текста, как снимок камеры.',
            ),
            Wrap(
              spacing: 8,
              children: [
                for (final sample in [
                  ('monstera', 'Монстера'),
                  ('ficus', 'Фикус'),
                  ('peace_lily', 'Спатифиллум'),
                ])
                  ActionChip(
                    label: Text(sample.$2),
                    onPressed: model.busy
                        ? null
                        : () => model.scanSample(
                            'assets/labels/${sample.$1}.png',
                          ),
                  ),
              ],
            ),
            if (model.busy)
              const Padding(
                padding: EdgeInsets.all(12),
                child: LinearProgressIndicator(),
              ),
            if (model.error != null)
              Text(
                model.error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            if (model.rawText.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Text(
                'Распознанный текст',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              SelectableText(model.rawText),
            ],
            const SizedBox(height: 20),
            TextField(
              controller: name,
              maxLength: 80,
              decoration: const InputDecoration(
                labelText: 'Название растения *',
              ),
            ),
            TextField(
              controller: species,
              maxLength: 100,
              decoration: const InputDecoration(labelText: 'Вид растения'),
            ),
            TextField(
              controller: room,
              maxLength: 60,
              decoration: const InputDecoration(labelText: 'Комната'),
            ),
            if (saveError != null)
              Text(
                saveError!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            FilledButton.icon(
              onPressed: model.busy ? null : save,
              icon: const Icon(Icons.add),
              label: const Text('Добавить в мои растения'),
            ),
            const Text(
              'Расписание ухода можно настроить в календаре после добавления.',
            ),
          ],
        ),
      ),
    ),
  );
}
