import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:installm/core/services/local_notification_service.dart';
import 'package:installm/features/home/presentation/home_controller.dart';
import 'package:installm/features/model_selection/presentation/model_selection_controller.dart';
import 'package:installm/features/reminders/application/reminders_controller.dart';
import 'package:installm/features/reminders/domain/job_policy.dart';
import 'package:installm/features/reminders/domain/scheduled_task.dart';

/// Runs scheduled AI jobs (Road Map 5 Phase 5.4).
///
/// The run itself is the app's ordinary chat turn: the prompt goes through
/// `HomeController.sendMessage`, so the job uses the same model, system prompt,
/// retrieval and tool boundary a typed message would, and its answer is visible
/// in the conversation. What this adds is the record around it: state, start,
/// finish, a short summary and the reason when the platform did not allow the
/// run. Nothing runs while the app is denied the CPU, and nothing here loads a
/// second model.
final scheduledJobRunnerProvider = Provider<ScheduledJobRunner>(
  ScheduledJobRunner.new,
);

class ScheduledJobRunner {
  ScheduledJobRunner(this._ref);

  final Ref _ref;
  bool _busy = false;

  bool get isRunning => _busy;

  /// Runs every due task at [now], including the ones that must be skipped.
  ///
  /// Returns the runs it recorded. A skipped run is still a record: the task
  /// advances to its next slot so it is not retried every tick, and the reason
  /// is kept for the list.
  Future<List<TaskRun>> runDue({DateTime? now}) async {
    if (_busy) return const [];
    // Nothing is known about the tasks until the store has opened; the next
    // tick is seconds away and well inside the grace window.
    if (!_ref.read(remindersProvider).isOpen) return const [];
    final at = now ?? DateTime.now();
    final due = [
      for (final task in _ref.read(remindersProvider).tasks)
        if (task.isDueAt(at)) task,
    ];
    if (due.isEmpty) return const [];

    _busy = true;
    final runs = <TaskRun>[];
    try {
      for (final task in due) {
        final run = await _runTask(task, at);
        if (run != null) runs.add(run);
      }
    } finally {
      _busy = false;
    }
    return runs;
  }

  /// Runs one task now, whatever its schedule says. Used by the re-run action.
  Future<TaskRun?> runNow(ScheduledTask task, {DateTime? now}) async {
    if (_busy) return null;
    _busy = true;
    try {
      return await _runTask(task, now ?? DateTime.now(), ignoreDue: true);
    } finally {
      _busy = false;
    }
  }

  Future<TaskRun?> _runTask(
    ScheduledTask task,
    DateTime at, {
    bool ignoreDue = false,
  }) async {
    final notifier = _ref.read(remindersProvider.notifier);

    // A plain reminder is unchanged by this phase: it still only announces
    // itself, and never runs a prompt.
    if (!task.isJob) {
      await _advance(task, at);
      await _notify(
        title: task.title,
        body: task.body.isEmpty ? 'Reminder' : task.body,
        payload: 'job:${task.id}',
      );
      return null;
    }

    final model = _ref.read(modelSelectionControllerProvider).selectedModel;
    final gate = ScheduledJobPolicy.gate(
      task: task,
      now: at,
      modelReady: model != null && model.isDownloaded,
      generating: _ref.read(homeGenerationStatusProvider).isGenerating,
      selectedModelName: model?.name,
      manual: ignoreDue,
    );

    if (!gate.shouldRun) {
      final run = TaskRun(
        id: 'run-${at.microsecondsSinceEpoch}',
        state: TaskRunState.skipped,
        startedAt: at,
        finishedAt: at,
        reason: gate.reason,
        modelName: model?.name,
      );
      final advanced = _advanced(task, at);
      await notifier.updateTask(advanced.withRun(run));
      await _notify(
        title: 'Skipped: ${task.title}',
        body: gate.reason ?? 'This job could not run.',
        payload: 'job:${task.id}',
      );
      return run;
    }

    // A re-run keeps the existing schedule; a firing job advances it first, so
    // a failure or a long run cannot make the same slot fire twice.
    final base = ignoreDue ? task : _advanced(task, at);
    final run = TaskRun(
      id: 'run-${at.microsecondsSinceEpoch}',
      state: TaskRunState.running,
      startedAt: at,
      modelName: model?.name,
    );
    await notifier.updateTask(base.withRun(run));

    try {
      await _ref.read(homeControllerProvider.notifier).sendMessage(task.prompt);
      final reply = _lastAssistantReply();
      final finished = run.finish(
        state: TaskRunState.completed,
        finishedAt: DateTime.now(),
        summary: reply.isEmpty
            ? 'The model returned an answer with no text.'
            : reply,
        modelName: model?.name,
      );
      await notifier.updateRun(task.id, finished);
      await _notify(
        title: 'Done: ${task.title}',
        body: _preview(finished.summary),
        payload: 'job:${task.id}',
      );
      return finished;
    } catch (error) {
      final failed = run.finish(
        state: TaskRunState.failed,
        finishedAt: DateTime.now(),
        reason: 'The run stopped early: ${error.runtimeType}.',
        modelName: model?.name,
      );
      await notifier.updateRun(task.id, failed);
      await _notify(
        title: 'Failed: ${task.title}',
        body: failed.reason ?? 'The run stopped early.',
        payload: 'job:${task.id}',
      );
      return failed;
    }
  }

  /// The task after its slot at [at]: one-shot jobs disable, recurring ones
  /// move to the next slot. This is the existing reminder rule, unchanged.
  ScheduledTask _advanced(ScheduledTask task, DateTime at) => task.firedAt(at);

  Future<void> _advance(ScheduledTask task, DateTime at) async {
    await _ref.read(remindersProvider.notifier).updateTask(_advanced(task, at));
  }

  String _lastAssistantReply() {
    final messages = _ref.read(homeControllerProvider);
    for (final message in messages.reversed) {
      if (message.isAssistant && message.content.trim().isNotEmpty) {
        return message.content;
      }
    }
    return '';
  }

  String _preview(String text) {
    final single = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    return single.length <= 160 ? single : '${single.substring(0, 160)}…';
  }

  Future<void> _notify({
    required String title,
    required String body,
    required String payload,
  }) async {
    try {
      await LocalNotificationService.instance.showScheduledJob(
        title: title,
        body: body,
        payload: payload,
      );
    } catch (_) {
      // A notice that cannot be shown must not lose the run record.
    }
  }
}
