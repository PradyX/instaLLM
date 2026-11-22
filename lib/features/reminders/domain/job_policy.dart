import 'package:installm/features/reminders/domain/scheduled_task.dart';

/// Whether a due job may run now, and why not when it may not
/// (Road Map 5 Phase 5.4).
///
/// The rule the roadmap states is the one this encodes: Android background
/// execution is not guaranteed, so a job that could not run is recorded as
/// `skipped` with a reason instead of being run late and reported as if it had
/// happened on time. Nothing here wakes the device and nothing here starts a
/// second model load.
enum JobDecision { run, skip }

class JobGate {
  const JobGate.run() : decision = JobDecision.run, reason = null;
  const JobGate.skip(this.reason) : decision = JobDecision.skip;

  final JobDecision decision;
  final String? reason;

  bool get shouldRun => decision == JobDecision.run;
}

abstract final class ScheduledJobPolicy {
  /// How late a job may still be run.
  ///
  /// The ticker wakes well inside this, so lateness beyond it means the app was
  /// not running when the job fell due — the platform's limit, not a failure of
  /// the job.
  static const Duration grace = Duration(minutes: 5);

  /// Decides one due job. Pure: every input is passed in, so the rule can be
  /// tested without a clock, a device or a model.
  static JobGate gate({
    required ScheduledTask task,
    required DateTime now,
    required bool modelReady,
    required bool generating,
    required String? selectedModelName,
    bool manual = false,
  }) {
    if (!task.isJob) {
      return const JobGate.skip('This task has no prompt to run');
    }

    // A run the user asked for right now is not late: the lateness rule only
    // explains why a scheduled slot could not be honoured.
    final overdue = now.difference(task.nextRunAt);
    if (!manual && overdue > grace) {
      final minutes = overdue.inMinutes;
      final late = minutes < 60
          ? '$minutes min'
          : '${(minutes / 60).round()} h';
      return JobGate.skip(
        'Due at ${_clock(task.nextRunAt)}, when the app was not running '
        '($late late). Android does not let an app start work in the '
        'background here, so nothing was sent to the model.',
      );
    }

    if (!modelReady) {
      return const JobGate.skip(
        'No model is ready on this device, so the prompt was not sent.',
      );
    }

    final scheduledFor = task.modelName;
    if (scheduledFor != null &&
        scheduledFor.isNotEmpty &&
        selectedModelName != null &&
        selectedModelName != scheduledFor) {
      return JobGate.skip(
        'Scheduled for $scheduledFor, which is not the selected model '
        '($selectedModelName). Pick it again to run this job.',
      );
    }

    if (generating) {
      return const JobGate.skip(
        'Another reply was being generated, and two models are not loaded '
        'at once here.',
      );
    }

    return const JobGate.run();
  }

  static String _clock(DateTime value) =>
      '${value.hour.toString().padLeft(2, '0')}:'
      '${value.minute.toString().padLeft(2, '0')}';
}
