import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:installm/features/reminders/application/reminders_controller.dart';
import 'package:installm/features/reminders/domain/scheduled_task.dart';

/// Reminders: one screen for every scheduled task (Road Map 3 Phase 3.6).
///
/// Everything here is editable and deletable. Tasks fire a local notification
/// while the device is offline; opening the notice shows the content.
class RemindersPage extends ConsumerWidget {
  const RemindersPage({super.key});

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref,
    ScheduledTask? existing,
  ) async {
    final titleController = TextEditingController(text: existing?.title ?? '');
    DateTime at =
        existing?.nextRunAt ?? DateTime.now().add(const Duration(hours: 1));
    TaskRecurrence recurrence = existing?.recurrence ?? TaskRecurrence.once;
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(existing == null ? 'New reminder' : 'Edit reminder'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleController,
                decoration: const InputDecoration(labelText: 'What'),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${at.year}-${at.month.toString().padLeft(2, '0')}-${at.day.toString().padLeft(2, '0')} ${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}',
                    ),
                  ),
                  TextButton(
                    onPressed: () async {
                      final date = await showDatePicker(
                        context: context,
                        initialDate: at,
                        firstDate: DateTime.now().subtract(
                          const Duration(days: 1),
                        ),
                        lastDate: DateTime.now().add(
                          const Duration(days: 365 * 2),
                        ),
                      );
                      if (date == null) return;
                      if (!context.mounted) return;
                      final time = await showTimePicker(
                        context: context,
                        initialTime: TimeOfDay.fromDateTime(at),
                      );
                      if (time == null) return;
                      setDialogState(() {
                        at = DateTime(
                          date.year,
                          date.month,
                          date.day,
                          time.hour,
                          time.minute,
                        );
                      });
                    },
                    child: const Text('Pick'),
                  ),
                ],
              ),
              DropdownButtonFormField<TaskRecurrence>(
                initialValue: recurrence,
                decoration: const InputDecoration(labelText: 'Repeats'),
                items: [
                  for (final value in TaskRecurrence.values)
                    DropdownMenuItem(value: value, child: Text(value.label)),
                ],
                onChanged: (value) {
                  if (value != null) setDialogState(() => recurrence = value);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (result != true) return;
    final title = titleController.text.trim();
    if (title.isEmpty) return;
    final notifier = ref.read(remindersProvider.notifier);
    if (existing == null) {
      await notifier.addTask(
        title: title,
        nextRunAt: at,
        recurrence: recurrence,
      );
    } else {
      await notifier.updateTask(
        existing.copyWith(title: title, nextRunAt: at, recurrence: recurrence),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(remindersProvider);
    final notifier = ref.read(remindersProvider.notifier);
    return Scaffold(
      appBar: AppBar(title: const Text('Reminders')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _edit(context, ref, null),
        child: const Icon(Icons.add),
      ),
      body: !state.isOpen
          ? const Center(child: CircularProgressIndicator())
          : state.tasks.isEmpty
          ? const Center(
              child: Text(
                'No reminders. Add one with + or say "remind me …" in chat.',
              ),
            )
          : ListView(
              children: [
                for (final task in state.tasks)
                  Dismissible(
                    key: ValueKey(task.id),
                    background: Container(color: Colors.red),
                    onDismissed: (_) => notifier.removeTask(task.id),
                    child: SwitchListTile(
                      title: Text(task.title),
                      subtitle: Text(
                        '${task.recurrence.label} · ${task.nextRunAt}',
                      ),
                      value: task.enabled,
                      onChanged: state.isReadOnly
                          ? null
                          : (value) => notifier.updateTask(
                              task.copyWith(enabled: value),
                            ),
                      secondary: IconButton(
                        icon: const Icon(Icons.edit_outlined),
                        onPressed: () => _edit(context, ref, task),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}
