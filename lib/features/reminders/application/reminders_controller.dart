import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:installm/core/services/local_notification_service.dart';
import 'package:installm/features/reminders/data/scheduled_task_store.dart';
import 'package:installm/features/reminders/domain/scheduled_task.dart';

/// The task store on this device, opened once per session.
final scheduledTaskStoreProvider = FutureProvider<ScheduledTaskStore>((
  ref,
) async {
  return ScheduledTaskStore.open();
});

class RemindersState {
  const RemindersState({
    this.tasks = const [],
    this.isOpen = false,
    this.isReadOnly = false,
  });

  final List<ScheduledTask> tasks;
  final bool isOpen;
  final bool isReadOnly;

  RemindersState copyWith({
    List<ScheduledTask>? tasks,
    bool? isOpen,
    bool? isReadOnly,
  }) {
    return RemindersState(
      tasks: tasks ?? this.tasks,
      isOpen: isOpen ?? this.isOpen,
      isReadOnly: isReadOnly ?? this.isReadOnly,
    );
  }
}

final remindersProvider = NotifierProvider<RemindersNotifier, RemindersState>(
  RemindersNotifier.new,
);

/// Owns scheduled tasks: create, edit, delete and fire due ones.
///
/// Everything is local and offline. Firing shows a local notification; the
/// task content runs only when the user opens it. Due tasks are fired by an
/// explicit `fireDue` call from the app lifecycle, never by a background
/// daemon this file invents.
class RemindersNotifier extends Notifier<RemindersState> {
  @override
  RemindersState build() {
    _open();
    return const RemindersState();
  }

  Future<void> _open() async {
    try {
      final store = await ref.read(scheduledTaskStoreProvider.future);
      state = state.copyWith(
        tasks: store.load(),
        isOpen: true,
        isReadOnly: store.isReadOnly,
      );
    } catch (_) {
      state = state.copyWith(isOpen: true);
    }
  }

  Future<bool> _persist(List<ScheduledTask> tasks) async {
    try {
      final store = await ref.read(scheduledTaskStoreProvider.future);
      if (store.isReadOnly) return false;
      tasks.sort((a, b) => a.nextRunAt.compareTo(b.nextRunAt));
      if (!store.save(tasks)) return false;
      state = state.copyWith(tasks: tasks, isReadOnly: store.isReadOnly);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<ScheduledTask?> addTask({
    required String title,
    String body = '',
    required DateTime nextRunAt,
    TaskRecurrence recurrence = TaskRecurrence.once,
  }) async {
    final task = ScheduledTask.create(
      title: title,
      body: body,
      nextRunAt: nextRunAt,
      recurrence: recurrence,
    );
    if (task.title.isEmpty) return null;
    final next = [...state.tasks, task];
    if (!await _persist(next)) return null;
    return task;
  }

  Future<bool> updateTask(ScheduledTask task) async {
    final next = [
      for (final existing in state.tasks)
        if (existing.id == task.id) task else existing,
    ];
    if (next.length == state.tasks.length &&
        !state.tasks.any((entry) => entry.id == task.id)) {
      return false;
    }
    return _persist(next);
  }

  Future<bool> removeTask(String id) async {
    final next = [
      for (final task in state.tasks)
        if (task.id != id) task,
    ];
    if (next.length == state.tasks.length) return false;
    return _persist(next);
  }

  /// Fires every due task at [now] through the local notification service.
  ///
  /// Returns what fired. One-shot tasks disable; recurring tasks advance.
  /// Offline by construction: no network, no server, just the OS notice.
  Future<List<ScheduledTask>> fireDue(
    DateTime now, {
    Future<void> Function(String title, String body)? notify,
  }) async {
    final due = state.tasks.where((task) => task.isDueAt(now)).toList();
    if (due.isEmpty) return const [];
    final fired = <ScheduledTask>[];
    var next = state.tasks;
    for (final task in due) {
      final updated = task.firedAt(now);
      next = [
        for (final existing in next)
          if (existing.id == task.id) updated else existing,
      ];
      fired.add(updated);
      try {
        if (notify != null) {
          await notify(task.title, task.body);
        } else {
          await LocalNotificationService.instance.showBackgroundRun(
            title: task.title,
            body: task.body.isEmpty ? 'Reminder' : task.body,
          );
        }
      } catch (_) {
        // A notice that cannot be shown must not lose the task update.
      }
    }
    await _persist(next);
    return fired;
  }
}
