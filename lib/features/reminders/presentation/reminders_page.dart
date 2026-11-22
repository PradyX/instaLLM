import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:installm/features/model_selection/presentation/model_selection_controller.dart';
import 'package:installm/features/reminders/application/reminders_controller.dart';
import 'package:installm/features/reminders/application/scheduled_job_runner.dart';
import 'package:installm/features/reminders/application/scheduled_job_service.dart';
import 'package:installm/features/reminders/domain/scheduled_task.dart';

/// Reminders and scheduled AI jobs: one screen for every scheduled task
/// (Road Map 3 Phase 3.6, Road Map 5 Phase 5.4).
///
/// A task without a prompt only announces itself. A task with a prompt asks the
/// model when it falls due, records the attempt (state, start, finish, a short
/// summary) and notifies when it ends. Everything is local and offline, and a
/// job that could not run says so instead of pretending it did.
class RemindersPage extends ConsumerWidget {
  const RemindersPage({super.key, this.focusTaskId});

  /// A task a notification asked to show, highlighted in the list.
  final String? focusTaskId;

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref,
    ScheduledTask? existing,
  ) async {
    final titleController = TextEditingController(text: existing?.title ?? '');
    final promptController = TextEditingController(
      text: existing?.prompt ?? '',
    );
    DateTime at =
        existing?.nextRunAt ?? DateTime.now().add(const Duration(hours: 1));
    TaskRecurrence recurrence = existing?.recurrence ?? TaskRecurrence.once;
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(existing == null ? 'New task' : 'Edit task'),
          // The framework's own scrollable body: with a field focused the soft
          // keyboard leaves room for only part of the form, and a hand-rolled
          // SingleChildScrollView scrolled the fields out of sight entirely, so
          // a task could not be named at all on a tablet.
          scrollable: true,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleController,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: promptController,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Prompt (optional)',
                  helperText:
                      'With a prompt this is an AI job; without one '
                      'it is a plain reminder.',
                ),
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
                  if (value != null) {
                    setDialogState(() => recurrence = value);
                  }
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
    final prompt = promptController.text.trim();
    final modelName = prompt.isEmpty
        ? null
        : ref.read(modelSelectionControllerProvider).selectedModel?.name;
    final notifier = ref.read(remindersProvider.notifier);
    if (existing == null) {
      await notifier.addTask(
        title: title,
        nextRunAt: at,
        recurrence: recurrence,
        prompt: prompt,
        modelName: modelName,
      );
    } else {
      await notifier.updateTask(
        existing.copyWith(
          title: title,
          nextRunAt: at,
          recurrence: recurrence,
          prompt: prompt,
          modelName: modelName,
        ),
      );
    }
  }

  Future<void> _runNow(
    BuildContext context,
    WidgetRef ref,
    ScheduledTask task,
  ) async {
    final run = await ref.read(scheduledJobRunnerProvider).runNow(task);
    if (!context.mounted) return;
    final message = run == null
        ? 'A job is already running.'
        : run.state == TaskRunState.completed
        ? 'Done. The answer is in the chat.'
        : run.reason ?? 'The job did not run.';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(remindersProvider);
    final notifier = ref.read(remindersProvider.notifier);
    final focused = ref.watch(focusedScheduledTaskProvider);
    final highlight = focusTaskId ?? focused;
    return Scaffold(
      appBar: AppBar(title: const Text('Scheduled and reminders')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _edit(context, ref, null),
        child: const Icon(Icons.add),
      ),
      body: !state.isOpen
          ? const Center(child: CircularProgressIndicator())
          : state.tasks.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Nothing scheduled yet. Add one with +, with a prompt to '
                  'have InstaLLM run it, or say "remind me …" in chat.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : ListView(
              children: [
                for (final task in state.tasks)
                  _TaskTile(
                    task: task,
                    readOnly: state.isReadOnly,
                    highlighted: task.id == highlight,
                    onEdit: () => _edit(context, ref, task),
                    onRunNow: () => _runNow(context, ref, task),
                    onToggle: (value) =>
                        notifier.updateTask(task.copyWith(enabled: value)),
                    onDelete: () => notifier.removeTask(task.id),
                  ),
              ],
            ),
    );
  }
}

class _TaskTile extends StatelessWidget {
  const _TaskTile({
    required this.task,
    required this.readOnly,
    required this.highlighted,
    required this.onEdit,
    required this.onRunNow,
    required this.onToggle,
    required this.onDelete,
  });

  final ScheduledTask task;
  final bool readOnly;
  final bool highlighted;
  final VoidCallback onEdit;
  final VoidCallback onRunNow;
  final ValueChanged<bool> onToggle;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final latest = task.latestRun;
    final subtitle = StringBuffer()
      ..write(task.recurrence.label)
      ..write(' · ')
      ..write(_stamp(task.nextRunAt));
    if (task.isJob) {
      subtitle.write(' · AI job');
      if (task.modelName != null) subtitle.write(' on ${task.modelName}');
    }
    if (!task.enabled) subtitle.write(' · cancelled');

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: highlighted
          ? theme.colorScheme.primaryContainer.withValues(alpha: 0.5)
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            title: Text(task.title),
            subtitle: Text(subtitle.toString()),
            leading: Icon(
              task.isJob ? Icons.smart_toy_outlined : Icons.notifications_none,
            ),
            trailing: Switch(
              value: task.enabled,
              onChanged: readOnly ? null : onToggle,
            ),
            onTap: onEdit,
          ),
          if (task.isJob)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: Text(
                task.prompt,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall,
              ),
            ),
          if (latest != null) _RunLine(run: latest),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
            child: Row(
              children: [
                if (task.isJob)
                  TextButton.icon(
                    onPressed: readOnly ? null : onRunNow,
                    icon: const Icon(Icons.play_arrow_rounded, size: 18),
                    label: const Text('Run now'),
                  ),
                const Spacer(),
                TextButton(
                  onPressed: readOnly ? null : onEdit,
                  child: const Text('Edit'),
                ),
                TextButton(
                  onPressed: readOnly ? null : onDelete,
                  child: Text(
                    'Delete',
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _stamp(DateTime value) =>
      '${value.year}-${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')} '
      '${value.hour.toString().padLeft(2, '0')}:'
      '${value.minute.toString().padLeft(2, '0')}';
}

class _RunLine extends StatelessWidget {
  const _RunLine({required this.run});

  final TaskRun run;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = switch (run.state) {
      TaskRunState.completed => theme.colorScheme.primary,
      TaskRunState.skipped => theme.colorScheme.onSurfaceVariant,
      TaskRunState.failed => theme.colorScheme.error,
      TaskRunState.running => theme.colorScheme.primary,
    };
    final when = run.finishedAt ?? run.startedAt;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 5, right: 8),
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${run.state.label} · ${_TaskTile._stamp(when)}'
                  '${run.duration == null ? '' : ' · ${run.duration!.inSeconds}s'}',
                  style: theme.textTheme.labelSmall?.copyWith(color: color),
                ),
                Text(
                  run.headline,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
