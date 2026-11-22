/// Scheduled tasks and reminders (Road Map 3 Phase 3.6).
///
/// "Remind me ..." / "every morning ..." from chat or voice. A task fires a
/// local notification; its content runs only when opened. Everything is local
/// and offline: no server, no background daemon beyond the OS notification
/// service, no telemetry.
///
/// Times are stored as local wall-clock plus a recurrence, so a device that
/// travels keeps the reminder at the hour the user asked for.
enum TaskRecurrence {
  once('once', 'Once'),
  daily('daily', 'Daily'),
  weekly('weekly', 'Weekly');

  const TaskRecurrence(this.id, this.label);

  final String id;
  final String label;

  static TaskRecurrence byId(String? id) {
    for (final value in TaskRecurrence.values) {
      if (value.id == id) return value;
    }
    return TaskRecurrence.once;
  }
}

/// Limits that keep a hand-edited tasks file honest.
abstract final class ScheduledTaskLimits {
  static const int maxTitleLength = 120;
  static const int maxBodyLength = 500;
  static const int maxTasks = 200;
  static const int maxPromptLength = 2000;
  static const int maxRunSummaryLength = 600;
  static const int maxRunsPerTask = 20;
}

/// How one attempt at a scheduled AI job ended (Road Map 5 Phase 5.4).
///
/// `skipped` is a real outcome, not a failure: the platform did not allow the
/// work (no model, the app was not running at the time, another reply was
/// being generated) and the run says so instead of claiming success.
enum TaskRunState {
  running('running', 'Running'),
  completed('completed', 'Done'),
  skipped('skipped', 'Skipped'),
  failed('failed', 'Failed');

  const TaskRunState(this.id, this.label);

  final String id;
  final String label;

  static TaskRunState byId(String? id) {
    for (final value in TaskRunState.values) {
      if (value.id == id) return value;
    }
    return TaskRunState.skipped;
  }
}

/// One recorded attempt at a task: when it started and ended, how it ended,
/// and the short summary the list can show without opening the chat.
class TaskRun {
  const TaskRun({
    required this.id,
    required this.state,
    required this.startedAt,
    this.finishedAt,
    this.summary = '',
    this.reason,
    this.modelName,
  });

  final String id;
  final TaskRunState state;
  final DateTime startedAt;
  final DateTime? finishedAt;
  final String summary;

  /// Why a run was skipped or failed, phrased for the user.
  final String? reason;

  /// The model that produced the summary, recorded with it.
  final String? modelName;

  Duration? get duration => finishedAt?.difference(startedAt);

  String get headline {
    if (reason != null && reason!.trim().isNotEmpty) return reason!.trim();
    if (summary.trim().isNotEmpty) return summary.trim();
    return state.label;
  }

  TaskRun finish({
    required TaskRunState state,
    required DateTime finishedAt,
    String summary = '',
    String? reason,
    String? modelName,
  }) {
    return TaskRun(
      id: id,
      state: state,
      startedAt: startedAt,
      finishedAt: finishedAt,
      summary: _clamp(summary.trim(), ScheduledTaskLimits.maxRunSummaryLength),
      reason: reason,
      modelName: modelName ?? this.modelName,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'state': state.id,
    'startedAt': startedAt.toIso8601String(),
    if (finishedAt != null) 'finishedAt': finishedAt!.toIso8601String(),
    if (summary.isNotEmpty) 'summary': summary,
    if (reason != null && reason!.isNotEmpty) 'reason': reason,
    if (modelName != null && modelName!.isNotEmpty) 'modelName': modelName,
  };

  static TaskRun? fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final startedAt = DateTime.tryParse(json['startedAt'] as String? ?? '');
    if (id is! String || id.isEmpty || startedAt == null) return null;
    return TaskRun(
      id: id,
      state: TaskRunState.byId(json['state'] as String?),
      startedAt: startedAt,
      finishedAt: json['finishedAt'] is String
          ? DateTime.tryParse(json['finishedAt'] as String)
          : null,
      summary: json['summary'] is String ? json['summary'] as String : '',
      reason: json['reason'] is String ? json['reason'] as String : null,
      modelName: json['modelName'] is String
          ? json['modelName'] as String
          : null,
    );
  }
}

String _clamp(String value, int max) =>
    value.length <= max ? value : value.substring(0, max);

/// One reminder the device fires itself.
class ScheduledTask {
  const ScheduledTask({
    required this.id,
    required this.title,
    this.body = '',
    required this.nextRunAt,
    this.recurrence = TaskRecurrence.once,
    this.enabled = true,
    required this.createdAt,
    required this.updatedAt,
    this.lastFiredAt,
    this.prompt = '',
    this.modelName,
    this.runs = const [],
  });

  factory ScheduledTask.create({
    String? id,
    required String title,
    String body = '',
    required DateTime nextRunAt,
    TaskRecurrence recurrence = TaskRecurrence.once,
    bool enabled = true,
    String prompt = '',
    String? modelName,
    DateTime? now,
  }) {
    final timestamp = now ?? DateTime.now();
    return ScheduledTask(
      id: id ?? 'task-${timestamp.microsecondsSinceEpoch}',
      title: title,
      body: body,
      nextRunAt: nextRunAt,
      recurrence: recurrence,
      enabled: enabled,
      createdAt: timestamp,
      updatedAt: timestamp,
      prompt: prompt,
      modelName: modelName,
    ).normalized();
  }

  final String id;
  final String title;
  final String body;

  /// Next local wall-clock time the task fires.
  final DateTime nextRunAt;
  final TaskRecurrence recurrence;
  final bool enabled;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Last time the task fired, or null when it never has.
  final DateTime? lastFiredAt;

  /// What the task asks the model, or empty for a plain reminder
  /// (Road Map 5 Phase 5.4).
  final String prompt;

  /// The model the user picked for this job, or null for "whatever the app
  /// has selected when it runs". A name is stored rather than an id so a job
  /// survives a model being redownloaded under a new record.
  final String? modelName;

  /// Most recent runs first: state, start, finish and a short summary.
  final List<TaskRun> runs;

  /// True when the task runs a prompt instead of only showing its text.
  bool get isJob => prompt.trim().isNotEmpty;

  /// The latest record, if it ever ran.
  TaskRun? get latestRun => runs.isEmpty ? null : runs.first;

  ScheduledTask withRun(TaskRun run) {
    return copyWith(
      runs: [
        run,
        ...runs,
      ].take(ScheduledTaskLimits.maxRunsPerTask).toList(growable: false),
    );
  }

  ScheduledTask replaceRun(TaskRun run) {
    return copyWith(
      runs: [
        for (final existing in runs)
          if (existing.id == run.id) run else existing,
      ],
    );
  }

  /// True when the task should fire at [now]: enabled and due.
  bool isDueAt(DateTime now) => enabled && !now.isBefore(nextRunAt);

  /// The task after it fired at [now]: one-shot disables, recurring advances
  /// to the next slot after now. Pure and testable: no clock, no I/O.
  ScheduledTask firedAt(DateTime now) {
    switch (recurrence) {
      case TaskRecurrence.once:
        return copyWith(enabled: false, lastFiredAt: now, updatedAt: now);
      case TaskRecurrence.daily:
        return copyWith(
          nextRunAt: _nextAfter(nextRunAt, now, const Duration(days: 1)),
          lastFiredAt: now,
          updatedAt: now,
        );
      case TaskRecurrence.weekly:
        return copyWith(
          nextRunAt: _nextAfter(nextRunAt, now, const Duration(days: 7)),
          lastFiredAt: now,
          updatedAt: now,
        );
    }
  }

  /// Advances [scheduled] by [step] until it lies after [now].
  static DateTime _nextAfter(DateTime scheduled, DateTime now, Duration step) {
    var next = scheduled;
    // Bounded: a device asleep for months must not loop forever.
    for (var i = 0; i < 366 * 2; i++) {
      next = next.add(step);
      if (next.isAfter(now)) return next;
    }
    return next;
  }

  ScheduledTask normalized() {
    String clamp(String value, int max) =>
        value.length <= max ? value : value.substring(0, max);
    return ScheduledTask(
      id: id,
      title: clamp(title.trim(), ScheduledTaskLimits.maxTitleLength),
      body: clamp(body.trim(), ScheduledTaskLimits.maxBodyLength),
      nextRunAt: nextRunAt,
      recurrence: recurrence,
      enabled: enabled,
      createdAt: createdAt,
      updatedAt: updatedAt,
      lastFiredAt: lastFiredAt,
      prompt: clamp(prompt.trim(), ScheduledTaskLimits.maxPromptLength),
      modelName: modelName?.trim().isEmpty ?? true ? null : modelName!.trim(),
      runs: runs
          .take(ScheduledTaskLimits.maxRunsPerTask)
          .toList(growable: false),
    );
  }

  ScheduledTask copyWith({
    String? title,
    String? body,
    DateTime? nextRunAt,
    TaskRecurrence? recurrence,
    bool? enabled,
    DateTime? updatedAt,
    DateTime? lastFiredAt,
    String? prompt,
    String? modelName,
    List<TaskRun>? runs,
  }) {
    return ScheduledTask(
      id: id,
      title: title ?? this.title,
      body: body ?? this.body,
      nextRunAt: nextRunAt ?? this.nextRunAt,
      recurrence: recurrence ?? this.recurrence,
      enabled: enabled ?? this.enabled,
      createdAt: createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
      lastFiredAt: lastFiredAt ?? this.lastFiredAt,
      prompt: prompt ?? this.prompt,
      modelName: modelName ?? this.modelName,
      runs: runs ?? this.runs,
    ).normalized();
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'body': body,
    'nextRunAt': nextRunAt.toIso8601String(),
    'recurrence': recurrence.id,
    'enabled': enabled,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'lastFiredAt': lastFiredAt?.toIso8601String(),
    if (prompt.isNotEmpty) 'prompt': prompt,
    if (modelName != null) 'modelName': modelName,
    if (runs.isNotEmpty)
      'runs': runs.map((run) => run.toJson()).toList(growable: false),
  };

  /// Reads one stored task. Null when it has no usable identity or time, so
  /// the store can keep the original file instead of rewriting it away.
  static ScheduledTask? fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final title = json['title'];
    if (id is! String || id.isEmpty) return null;
    if (title is! String || title.trim().isEmpty) return null;
    final nextRunAt = DateTime.tryParse(json['nextRunAt'] as String? ?? '');
    if (nextRunAt == null) return null;
    DateTime parseDate(Object? value) {
      if (value is String) {
        return DateTime.tryParse(value) ??
            DateTime.fromMillisecondsSinceEpoch(0);
      }
      return DateTime.fromMillisecondsSinceEpoch(0);
    }

    final runs = <TaskRun>[];
    final rawRuns = json['runs'];
    if (rawRuns is List) {
      for (final entry in rawRuns) {
        final map = entry is Map<String, dynamic>
            ? entry
            : entry is Map
            ? Map<String, dynamic>.from(entry)
            : null;
        if (map == null) continue;
        final run = TaskRun.fromJson(map);
        if (run != null) runs.add(run);
        if (runs.length >= ScheduledTaskLimits.maxRunsPerTask) break;
      }
    }

    return ScheduledTask(
      id: id,
      title: title,
      body: json['body'] is String ? json['body'] as String : '',
      nextRunAt: nextRunAt,
      recurrence: TaskRecurrence.byId(json['recurrence'] as String?),
      enabled: json['enabled'] is bool ? json['enabled'] as bool : true,
      createdAt: parseDate(json['createdAt']),
      updatedAt: parseDate(json['updatedAt']),
      lastFiredAt: json['lastFiredAt'] is String
          ? DateTime.tryParse(json['lastFiredAt'] as String)
          : null,
      prompt: json['prompt'] is String ? json['prompt'] as String : '',
      modelName: json['modelName'] is String
          ? json['modelName'] as String
          : null,
      runs: runs,
    ).normalized();
  }
}

/// Parses "remind me ..." phrases into task drafts (Road Map 3 Phase 3.6).
///
/// Chat and voice share this: "remind me in 10 minutes to stretch",
/// "remind me tomorrow at 9 to call", "every morning at 8 standup".
/// Returns null when the text is not a reminder request — the chat then
/// answers normally instead of inventing a task.
abstract final class ReminderParser {
  static ScheduledTaskDraft? parse(String text, DateTime now) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return null;
    final lower = trimmed.toLowerCase();
    if (!lower.contains('remind me') && !lower.startsWith('every ')) {
      return null;
    }

    TaskRecurrence recurrence = TaskRecurrence.once;
    if (RegExp(r'\bevery\s+(morning|day|daily)\b').hasMatch(lower)) {
      recurrence = TaskRecurrence.daily;
    } else if (RegExp(r'\bevery\s+week\b').hasMatch(lower)) {
      recurrence = TaskRecurrence.weekly;
    }

    DateTime? at;
    String remainder = trimmed;

    final inMinutes = RegExp(r'in\s+(\d+)\s+minutes?').firstMatch(lower);
    if (inMinutes != null) {
      final minutes = int.tryParse(inMinutes.group(1) ?? '');
      if (minutes != null && minutes > 0 && minutes <= 60 * 24 * 7) {
        at = now.add(Duration(minutes: minutes));
        remainder = _removeRange(trimmed, inMinutes.start, inMinutes.end);
      }
    }

    at ??= _parseAtTime(lower, now, (String s) {
      remainder = s;
    });

    if (at == null) {
      // "every morning" without a time means 8:00.
      if (recurrence == TaskRecurrence.daily) {
        at = DateTime(now.year, now.month, now.day, 8);
        if (!at.isAfter(now)) at = at.add(const Duration(days: 1));
      } else {
        return null;
      }
    }

    final title = _titleOf(remainder);
    if (title.isEmpty) return null;
    return ScheduledTaskDraft(
      title: title,
      nextRunAt: at,
      recurrence: recurrence,
    );
  }

  static DateTime? _parseAtTime(
    String lower,
    DateTime now,
    void Function(String remainder) setRemainder,
  ) {
    // "tomorrow at 9", "tomorrow at 9:30", "at 8", "at 18:30".
    final match = RegExp(
      r'(tomorrow\s+)?at\s+(\d{1,2})(?::(\d{2}))?\s*(am|pm)?',
    ).firstMatch(lower);
    if (match == null) return null;
    var hour = int.tryParse(match.group(2) ?? '');
    if (hour == null) return null;
    final minute = int.tryParse(match.group(3) ?? '0') ?? 0;
    final meridiem = match.group(4);
    if (meridiem == 'pm' && hour < 12) hour += 12;
    if (meridiem == 'am' && hour == 12) hour = 0;
    if (hour > 23 || minute > 59) return null;
    var day = now;
    if (match.group(1) != null) day = day.add(const Duration(days: 1));
    var at = DateTime(day.year, day.month, day.day, hour, minute);
    if (!at.isAfter(now)) at = at.add(const Duration(days: 1));
    return at;
  }

  static String _removeRange(String text, int start, int end) {
    return '${text.substring(0, start)} ${text.substring(end)}'.trim();
  }

  static String _titleOf(String remainder) {
    var title = remainder.trim();
    title = title
        .replaceAll(
          RegExp(r'^(remind me|every\s+\w+(\s+\w+)?)\s*', caseSensitive: false),
          '',
        )
        .trim();
    title = title
        .replaceAll(RegExp(r'^(to|that|about)\s+', caseSensitive: false), '')
        .trim();
    title = title
        .replaceAll(RegExp(r'\s+at\s+\d.*$', caseSensitive: false), '')
        .trim();
    if (title.length > ScheduledTaskLimits.maxTitleLength) {
      title = title.substring(0, ScheduledTaskLimits.maxTitleLength).trim();
    }
    return title;
  }
}

/// A reminder request without storage identity: what the chat confirms.
class ScheduledTaskDraft {
  const ScheduledTaskDraft({
    required this.title,
    required this.nextRunAt,
    this.recurrence = TaskRecurrence.once,
  });

  final String title;
  final DateTime nextRunAt;
  final TaskRecurrence recurrence;
}
