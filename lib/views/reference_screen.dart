import 'package:flutter/material.dart';
import '../models/reference_entry.dart';
import '../viewmodels/reference_view_model.dart';

/// Возвращает значок по обозначению, сохранённому в справочнике.
IconData referenceIcon(ReferenceIcon icon) => switch (icon) {
  ReferenceIcon.leaf => Icons.eco_outlined,
  ReferenceIcon.tree => Icons.park_outlined,
  ReferenceIcon.flower => Icons.local_florist_outlined,
  ReferenceIcon.nutrients => Icons.science_outlined,
  ReferenceIcon.water => Icons.water_drop_outlined,
  ReferenceIcon.sun => Icons.wb_sunny_outlined,
};
String referenceIconLabel(ReferenceIcon icon) => switch (icon) {
  ReferenceIcon.leaf => 'Лист',
  ReferenceIcon.tree => 'Дерево',
  ReferenceIcon.flower => 'Цветок',
  ReferenceIcon.nutrients => 'Удобрение',
  ReferenceIcon.water => 'Капля',
  ReferenceIcon.sun => 'Солнце',
};

/// Экран постоянных справочников семейств растений и типов удобрений.
class ReferenceScreen extends StatefulWidget {
  const ReferenceScreen({super.key, required this.model});
  final ReferenceViewModel model;
  @override
  State<ReferenceScreen> createState() => _ReferenceScreenState();
}

class _ReferenceScreenState extends State<ReferenceScreen> {
  ReferenceKind kind = ReferenceKind.family;
  void edit([ReferenceEntry? entry]) => showDialog<void>(
    context: context,
    builder: (_) =>
        ReferenceEditor(model: widget.model, kind: kind, entry: entry),
  );

  Future<void> remove(ReferenceEntry entry) async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить запись?'),
        content: Text('Удалить «${entry.name}» из справочника?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (accepted != true || !mounted) return;
    try {
      await widget.model.deleteEntry(kind, entry.id);
    } on ArgumentError catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message.toString())));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Не удалось удалить запись. Повторите попытку.'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.model,
    builder: (context, _) => Scaffold(
      appBar: AppBar(title: const Text('Справочники')),
      body: SingleChildScrollView(
        physics: const ClampingScrollPhysics(),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SegmentedButton<ReferenceKind>(
              segments: const [
                ButtonSegment(
                  value: ReferenceKind.family,
                  label: Text('Семейства'),
                ),
                ButtonSegment(
                  value: ReferenceKind.fertilizer,
                  label: Text('Удобрения'),
                ),
              ],
              selected: {kind},
              onSelectionChanged: widget.model.saving
                  ? null
                  : (value) => setState(() => kind = value.first),
            ),
            const SizedBox(height: 16),
            Text(
              kind == ReferenceKind.family
                  ? 'Семейства растений'
                  : 'Типы удобрений',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              key: const ValueKey('add-reference'),
              onPressed: widget.model.saving ? null : () => edit(),
              icon: const Icon(Icons.add),
              label: Text(
                kind == ReferenceKind.family
                    ? 'Добавить семейство'
                    : 'Добавить удобрение',
              ),
            ),
            const SizedBox(height: 12),
            if (widget.model.saving) const LinearProgressIndicator(),
            if (widget.model.entries(kind).isEmpty)
              const Text('В справочнике пока нет записей.'),
            for (final entry in widget.model.entries(kind))
              Card(
                child: ListTile(
                  key: ValueKey('reference-${entry.id}'),
                  leading: Icon(
                    referenceIcon(entry.icon),
                    color: const Color(0xFF285B43),
                  ),
                  title: Text(entry.name),
                  trailing: PopupMenuButton<String>(
                    key: ValueKey('reference-menu-${entry.id}'),
                    enabled: !widget.model.saving,
                    onSelected: (action) =>
                        action == 'edit' ? edit(entry) : remove(entry),
                    itemBuilder: (_) => const [
                      PopupMenuItem(
                        value: 'edit',
                        child: Text('Редактировать'),
                      ),
                      PopupMenuItem(value: 'delete', child: Text('Удалить')),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 12),
            const Text(
              'Справочники сохраняются на устройстве.',
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Форма названия и значка записи справочника.
class ReferenceEditor extends StatefulWidget {
  const ReferenceEditor({
    super.key,
    required this.model,
    required this.kind,
    this.entry,
  });
  final ReferenceViewModel model;
  final ReferenceKind kind;
  final ReferenceEntry? entry;
  @override
  State<ReferenceEditor> createState() => _ReferenceEditorState();
}

class _ReferenceEditorState extends State<ReferenceEditor> {
  late final TextEditingController name;
  late ReferenceIcon icon;
  bool saving = false;
  String? error;
  @override
  void initState() {
    super.initState();
    name = TextEditingController(text: widget.entry?.name ?? '');
    icon =
        widget.entry?.icon ??
        (widget.kind == ReferenceKind.family
            ? ReferenceIcon.leaf
            : ReferenceIcon.nutrients);
  }

  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (saving) return;
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await widget.model.saveEntry(
        kind: widget.kind,
        id: widget.entry?.id,
        name: name.text,
        icon: icon,
      );
      if (mounted) Navigator.pop(context);
    } on ArgumentError catch (e) {
      if (mounted) setState(() => error = e.message.toString());
    } catch (_) {
      if (mounted) {
        setState(
          () => error = 'Не удалось сохранить запись. Повторите попытку.',
        );
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.entry == null
          ? (widget.kind == ReferenceKind.family
                ? 'Новое семейство'
                : 'Новое удобрение')
          : 'Редактировать запись',
    ),
    content: SizedBox(
      width: 420,
      child: SingleChildScrollView(
        physics: const ClampingScrollPhysics(),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              key: const ValueKey('reference-name'),
              controller: name,
              maxLength: 80,
              decoration: const InputDecoration(labelText: 'Название *'),
            ),
            const SizedBox(height: 12),
            const Text('Значок'),
            const SizedBox(height: 8),
            DropdownButtonFormField<ReferenceIcon>(
              key: const ValueKey('reference-icon'),
              initialValue: icon,
              isExpanded: true,
              items: [
                for (final value in ReferenceIcon.values)
                  DropdownMenuItem(
                    value: value,
                    child: Row(
                      children: [
                        Icon(referenceIcon(value), size: 18),
                        const SizedBox(width: 8),
                        Text(referenceIconLabel(value)),
                      ],
                    ),
                  ),
              ],
              onChanged: saving
                  ? null
                  : (value) {
                      if (value != null) setState(() => icon = value);
                    },
            ),
            if (error != null)
              Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            if (saving) const LinearProgressIndicator(),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: saving ? null : () => Navigator.pop(context),
        child: const Text('Отмена'),
      ),
      FilledButton(
        onPressed: saving ? null : save,
        child: const Text('Сохранить'),
      ),
    ],
  );
}
