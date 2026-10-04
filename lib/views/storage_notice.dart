import 'package:flutter/material.dart';
import '../viewmodels/garden_view_model.dart';

/// Показывает подтверждение записи или возможность повторного сохранения.
class StorageNotice extends StatelessWidget {
  const StorageNotice({super.key, required this.garden});
  final GardenViewModel garden;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: garden,
    builder: (context, _) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          garden.storageError ??
              (garden.saving
                  ? 'Сохранение изменений…'
                  : garden.persistent
                  ? 'Изменения сохранены на устройстве.'
                  : 'Изменения хранятся до перезапуска приложения.'),
          key: const ValueKey('storage-status'),
          style: TextStyle(
            fontSize: 12,
            color: garden.storageError == null
                ? const Color(0xFF677B6B)
                : Theme.of(context).colorScheme.error,
          ),
        ),
        if (garden.storageError != null)
          TextButton(
            onPressed: garden.saving
                ? null
                : () async {
                    try {
                      await garden.persist();
                    } catch (_) {}
                  },
            child: const Text('Повторить сохранение'),
          ),
      ],
    ),
  );
}
