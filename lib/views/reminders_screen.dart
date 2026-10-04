import 'package:flutter/material.dart';
import '../viewmodels/garden_view_model.dart';
import 'editors.dart';

/// Настройка локальных напоминаний и просмотр реально зарегистрированной очереди.
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

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.garden,
    builder: (context, _) {
      final garden = widget.garden;
      final prefs = garden.reminderPreferences;
      final supported = garden.reminderService != null;
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
                onChanged: !supported || busy || garden.saving
                    ? null
                    : (v) => run(() async {
                        await garden.configureReminders(enabled: v);
                      }),
              ),
              OutlinedButton.icon(
                key: const ValueKey('reminder-time'),
                onPressed: !supported || busy
                    ? null
                    : () async {
                        final value = await showTimePicker(
                          context: context,
                          initialTime: TimeOfDay(
                            hour: prefs.hour,
                            minute: prefs.minute,
                          ),
                        );
                        if (value != null && mounted) {
                          await run(() async {
                            await garden.configureReminders(
                              enabled: prefs.enabled,
                              hour: value.hour,
                              minute: value.minute,
                            );
                          });
                        }
                      },
                icon: const Icon(Icons.schedule),
                label: Text('Время: ${time(prefs.hour, prefs.minute)}'),
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
                onPressed: !supported || busy
                    ? null
                    : () => run(garden.refreshReminders),
                child: const Text('Обновить напоминания'),
              ),
              OutlinedButton(
                key: const ValueKey('test-notification'),
                onPressed: !supported || busy
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
