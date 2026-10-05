import 'package:flutter/material.dart';
import '../models/reminder.dart';
import '../viewmodels/garden_view_model.dart';
import 'editors.dart';

/// Настройка общего или отдельного времени полива и системной очереди уведомлений.
class RemindersScreen extends StatefulWidget {
  const RemindersScreen({super.key, required this.garden});
  final GardenViewModel garden;
  @override
  State<RemindersScreen> createState() => _RemindersScreenState();
}

class _RemindersScreenState extends State<RemindersScreen> {
  bool busy = false;
  String? error;
  String time(int h, int m) =>
      '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';

  /// Показывает состояние выполнения и сообщение об ошибке настройки.
  Future<void> run(Future<void> Function() action) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await action();
    } on ArgumentError catch (e) {
      if (mounted) setState(() => error = e.message.toString());
    } catch (_) {
      if (mounted) {
        setState(() => error = 'Операция не выполнена. Повторите попытку.');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  /// Выбирает часы и минуты и передаёт их общей либо отдельной настройке.
  Future<void> chooseTime(
    ReminderTime initial,
    Future<void> Function(ReminderTime) save,
  ) async {
    final value = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: initial.hour, minute: initial.minute),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (value != null && mounted) {
      await run(
        () => save(ReminderTime(hour: value.hour, minute: value.minute)),
      );
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.garden,
    builder: (context, _) {
      final garden = widget.garden;
      final prefs = garden.reminderPreferences;
      final supported = garden.reminderService != null;
      final editable = supported && !busy && !garden.saving;
      return Scaffold(
        appBar: AppBar(title: const Text('Напоминания')),
        body: SingleChildScrollView(
          physics: const ClampingScrollPhysics(),
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Напоминания о поливе, подкормке и пересадке создаются по календарю ухода.',
              ),
              if (!supported)
                const Text(
                  'Системные напоминания доступны в приложении для Android.',
                ),
              SwitchListTile(
                key: const ValueKey('enable-reminders'),
                contentPadding: EdgeInsets.zero,
                title: const Text('Напоминать об уходе'),
                value: prefs.enabled,
                onChanged: !editable
                    ? null
                    : (v) => run(() async {
                        await garden.configureReminders(enabled: v);
                      }),
              ),
              OutlinedButton.icon(
                key: const ValueKey('reminder-time'),
                onPressed: !editable
                    ? null
                    : () => chooseTime(prefs.commonTime, (value) async {
                        await garden.configureReminders(
                          enabled: garden.reminderPreferences.enabled,
                          hour: value.hour,
                          minute: value.minute,
                        );
                      }),
                icon: const Icon(Icons.schedule),
                label: Text('Общее время: ${time(prefs.hour, prefs.minute)}'),
              ),
              const SizedBox(height: 16),
              Text(
                'Время полива',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              SwitchListTile(
                key: const ValueKey('individual-watering-times'),
                contentPadding: EdgeInsets.zero,
                title: const Text('Отдельно для каждого растения'),
                subtitle: Text(
                  prefs.individualWateringTimes
                      ? 'Задайте своё время. Без отдельной настройки используется общее.'
                      : 'Все растения используют общее время: ${time(prefs.hour, prefs.minute)}.',
                ),
                value: prefs.individualWateringTimes,
                onChanged: !editable
                    ? null
                    : (value) => run(
                        () => garden.configureWateringReminders(
                          individual: value,
                        ),
                      ),
              ),
              if (prefs.individualWateringTimes) ...[
                if (garden.plants.isEmpty)
                  const Text(
                    'Добавьте растение, чтобы выбрать для него время полива.',
                  ),
                for (final plant in garden.plants)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            plant.name,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          Text(
                            garden.customWateringTimeFor(plant.id) == null
                                ? 'Используется общее время'
                                : 'Своё время полива',
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 4,
                            children: [
                              OutlinedButton.icon(
                                key: ValueKey(
                                  'watering-reminder-time-${plant.id}',
                                ),
                                onPressed: !editable
                                    ? null
                                    : () => chooseTime(
                                        garden.wateringTimeFor(plant.id),
                                        (value) =>
                                            garden.setWateringReminderTime(
                                              plant.id,
                                              value,
                                            ),
                                      ),
                                icon: const Icon(Icons.schedule),
                                label: Text(
                                  time(
                                    garden.wateringTimeFor(plant.id).hour,
                                    garden.wateringTimeFor(plant.id).minute,
                                  ),
                                ),
                              ),
                              if (garden.customWateringTimeFor(plant.id) !=
                                  null)
                                TextButton(
                                  key: ValueKey(
                                    'reset-watering-time-${plant.id}',
                                  ),
                                  onPressed: !editable
                                      ? null
                                      : () => run(
                                          () => garden.setWateringReminderTime(
                                            plant.id,
                                            null,
                                          ),
                                        ),
                                  child: const Text('Использовать общее время'),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                const Text(
                  'Отдельные часы сохраняются при переключении к общему времени.',
                ),
              ],
              const SizedBox(height: 12),
              const Text(
                'Даты и интервалы полива задаются в календаре. Подкормка и пересадка используют общее время.',
              ),
              const Text(
                'Время указано в часовом поясе устройства. Android может отложить уведомление в режиме энергосбережения.',
              ),
              const SizedBox(height: 12),
              if (busy) const LinearProgressIndicator(),
              if (error != null)
                Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              if (garden.notificationIssue != null)
                Text(
                  garden.notificationIssue!,
                  key: const ValueKey('reminder-error'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              OutlinedButton(
                key: const ValueKey('refresh-reminders'),
                onPressed: !editable
                    ? null
                    : () => run(garden.refreshReminders),
                child: const Text('Обновить напоминания'),
              ),
              OutlinedButton(
                key: const ValueKey('test-notification'),
                onPressed: !editable
                    ? null
                    : () => run(() async {
                        await garden.testNotification();
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Проверочное уведомление отправлено. Откройте панель уведомлений Android.',
                              ),
                            ),
                          );
                        }
                      }),
                child: const Text('Проверить уведомление'),
              ),
              const SizedBox(height: 20),
              Text(
                'Запланировано: ${garden.scheduledReminders.length}',
                key: const ValueKey('reminder-count'),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const Text(
                'Цепочка формируется на ближайшие 30 дней, не более 64 уведомлений. При запуске приложения она обновляется.',
              ),
              const SizedBox(height: 12),
              if (garden.scheduledReminders.isEmpty)
                const Text('В очереди нет будущих напоминаний.'),
              for (final reminder in garden.scheduledReminders)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.notifications_outlined),
                    title: Text(reminder.title),
                    subtitle: Text(
                      '${fullDate(reminder.date)} в ${time(reminder.date.hour, reminder.date.minute)}',
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    },
  );
}
