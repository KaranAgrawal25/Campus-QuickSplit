import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../data/database/tables.dart';
import '../../../data/database/app_database.dart';
import '../../../data/repositories/reminder_repository.dart';
import '../../providers/database_provider.dart';

class RemindersScreen extends ConsumerWidget {
  const RemindersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final schedules = ref.watch(reminderRepositoryProvider).watchSchedules();
    return Scaffold(
      appBar: AppBar(title: const Text('Balance reminders')),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'reminders-add',
        onPressed: () => _showEditor(context, ref),
        icon: const Icon(Icons.add_alert_outlined),
        label: const Text('Add reminder'),
      ),
      body: StreamBuilder<List<ReminderSchedule>>(
        stream: schedules,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(child: Text('Could not load reminders.'));
          }
          final items = snapshot.data;
          if (items == null) {
            return const Center(child: CircularProgressIndicator());
          }
          if (items.isEmpty) {
            return const _EmptyReminders();
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final item = items[index];
              return Card(
                child: ListTile(
                  leading: Icon(_icon(item.frequency)),
                  title: Text(item.title),
                  subtitle: Text(
                    '${_frequencyLabel(item)}\nNext: ${DateFormat('EEE, d MMM · h:mm a').format(item.nextScheduledAt)}',
                  ),
                  isThreeLine: true,
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Switch(
                        value: item.isEnabled,
                        onChanged: (value) async {
                          try {
                            await ref
                                .read(reminderRepositoryProvider)
                                .setEnabled(item, value);
                          } catch (error) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text(error.toString())),
                              );
                            }
                          }
                        },
                      ),
                      IconButton(
                        tooltip: 'Edit reminder',
                        icon: const Icon(Icons.edit_outlined),
                        onPressed: () => _showEditor(context, ref, item),
                      ),
                      IconButton(
                        tooltip: 'Delete reminder',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => ref
                            .read(reminderRepositoryProvider)
                            .delete(item.id),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _EmptyReminders extends StatelessWidget {
  const _EmptyReminders();
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.notifications_none_rounded,
            size: 56,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 16),
          Text(
            'Stay on top of balances',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          const Text(
            'Schedule a one-time, daily, weekly, or monthly balance reminder.',
            textAlign: TextAlign.center,
          ),
        ],
      ),
    ),
  );
}

Future<void> _showEditor(
  BuildContext context,
  WidgetRef ref, [
  ReminderSchedule? existing,
]) async {
  final title = TextEditingController(
    text: existing?.title ?? 'Check your QuickSplit balance',
  );
  final message = TextEditingController(
    text: existing?.body ?? 'Review what you owe and what friends owe you.',
  );
  var frequency = existing?.frequency ?? ReminderFrequency.weekly;
  var when =
      existing?.scheduledAt ?? DateTime.now().add(const Duration(hours: 1));
  var weekday = existing?.weekday ?? DateTime.sunday;
  var dayOfMonth = existing?.dayOfMonth ?? 1;
  try {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setState) => Padding(
          padding: EdgeInsets.fromLTRB(
            24,
            24,
            24,
            MediaQuery.viewInsetsOf(context).bottom + 24,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  existing == null ? 'Schedule reminder' : 'Edit reminder',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: title,
                  decoration: const InputDecoration(labelText: 'Title'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: message,
                  decoration: const InputDecoration(labelText: 'Message'),
                ),
                const SizedBox(height: 12),
                Text(
                  'Payment reminders',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: ReminderFrequency.values
                      .map(
                        (value) => ChoiceChip(
                          avatar: Icon(_icon(value), size: 18),
                          label: Text(_enumLabel(value.name)),
                          selected: frequency == value,
                          onSelected: (_) => setState(() => frequency = value),
                        ),
                      )
                      .toList(),
                ),
                if (frequency == ReminderFrequency.weekly) ...[
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int>(
                    initialValue: weekday,
                    decoration: const InputDecoration(labelText: 'Day of week'),
                    items: List.generate(7, (index) => index + 1)
                        .map(
                          (day) => DropdownMenuItem(
                            value: day,
                            child: Text(
                              DateFormat.EEEE().format(
                                DateTime(2026, 1, day + 4),
                              ),
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (value) => setState(() => weekday = value!),
                  ),
                ],
                if (frequency == ReminderFrequency.monthly) ...[
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int>(
                    initialValue: dayOfMonth,
                    decoration: const InputDecoration(
                      labelText: 'Day of month',
                    ),
                    items: List.generate(31, (index) => index + 1)
                        .map(
                          (day) =>
                              DropdownMenuItem(value: day, child: Text('$day')),
                        )
                        .toList(),
                    onChanged: (value) => setState(() => dayOfMonth = value!),
                  ),
                ],
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Reminder time'),
                  subtitle: Text(
                    DateFormat('EEE, d MMM · h:mm a').format(when),
                  ),
                  trailing: const Icon(Icons.schedule),
                  onTap: () async {
                    final date = await showDatePicker(
                      context: context,
                      initialDate: when,
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now().add(const Duration(days: 3650)),
                    );
                    if (date == null || !context.mounted) return;
                    final time = await showTimePicker(
                      context: context,
                      initialTime: TimeOfDay.fromDateTime(when),
                    );
                    if (time != null) {
                      setState(
                        () => when = DateTime(
                          date.year,
                          date.month,
                          date.day,
                          time.hour,
                          time.minute,
                        ),
                      );
                    }
                  },
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () async {
                      try {
                        final draft = ReminderDraft(
                          title: title.text,
                          body: message.text,
                          frequency: frequency,
                          scheduledAt: when,
                          weekday: frequency == ReminderFrequency.weekly
                              ? weekday
                              : null,
                          dayOfMonth: frequency == ReminderFrequency.monthly
                              ? dayOfMonth
                              : null,
                        );
                        if (existing == null) {
                          await ref
                              .read(reminderRepositoryProvider)
                              .create(draft);
                        } else {
                          await ref
                              .read(reminderRepositoryProvider)
                              .update(existing.id, draft);
                        }
                        if (context.mounted) Navigator.pop(context);
                      } catch (error) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(error.toString())),
                          );
                        }
                      }
                    },
                    child: Text(
                      existing == null ? 'Schedule reminder' : 'Save changes',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  } finally {
    title.dispose();
    message.dispose();
  }
}

IconData _icon(ReminderFrequency value) => switch (value) {
  ReminderFrequency.once => Icons.notifications_outlined,
  ReminderFrequency.daily => Icons.today_outlined,
  ReminderFrequency.weekly => Icons.date_range_outlined,
  ReminderFrequency.monthly => Icons.calendar_month_outlined,
};

String _frequencyLabel(ReminderSchedule item) => switch (item.frequency) {
  ReminderFrequency.once => 'Once',
  ReminderFrequency.daily => 'Daily',
  ReminderFrequency.weekly =>
    'Every ${DateFormat.EEEE().format(DateTime(2026, 1, item.weekday! + 4))}',
  ReminderFrequency.monthly => 'Monthly on day ${item.dayOfMonth}',
};

String _enumLabel(String value) => value[0].toUpperCase() + value.substring(1);
