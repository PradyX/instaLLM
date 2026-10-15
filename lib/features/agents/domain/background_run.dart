/// Limits that keep supervised runs bounded (Road Map 3 Phase 3.3.4).
abstract final class BackgroundRunLimits {
  /// Runs kept in the store, newest first.
  static const int maxRecords = 20;

  /// Longest task accepted, so a run cannot be started with a document.
  static const int maxTaskCharacters = 2000;

  /// Characters kept of what happened, for the notice and the list.
  static const int maxNoticeCharacters = 240;
}

/// Where a supervised run stands.
///
/// Every state is reached by the run itself: there is no state a caller can
/// set to make a run look finished.
enum BackgroundRunStatus {
  running('Running'),
  done('Finished'),
  needsInput('Needs you'),
  stopped('Stopped'),
  failed('Failed');

  const BackgroundRunStatus(this.label);

  final String label;

  bool get isFinished => this != BackgroundRunStatus.running;
}

/// One task the user started to run while they are elsewhere.
///
/// The run is the room turn it names — same controller, same registry, same
/// permission gate, same hooks — so a supervised run can never do something
/// the same task could not do with the room open. What this record adds is
/// that it is visible from anywhere, it is cancellable, and it tells the user
/// when it is done or needs them.
class BackgroundRun {
  const BackgroundRun({
    required this.id,
    required this.chatId,
    required this.chatName,
    required this.botId,
    required this.botName,
    required this.task,
    required this.startedAt,
    this.finishedAt,
    this.status = BackgroundRunStatus.running,
    this.notice = '',
    this.notified = false,
  });

  factory BackgroundRun.create({
    required String id,
    required String chatId,
    required String chatName,
    required String botId,
    required String botName,
    required String task,
    DateTime? now,
  }) {
    final startedAt = now ?? DateTime.now();
    final trimmed = task.trim();
    return BackgroundRun(
      id: id,
      chatId: chatId,
      chatName: chatName,
      botId: botId,
      botName: botName,
      task: trimmed.length > BackgroundRunLimits.maxTaskCharacters
          ? trimmed.substring(0, BackgroundRunLimits.maxTaskCharacters)
          : trimmed,
      startedAt: startedAt,
    );
  }

  final String id;
  final String chatId;
  final String chatName;
  final String botId;
  final String botName;
  final String task;
  final DateTime startedAt;
  final DateTime? finishedAt;
  final BackgroundRunStatus status;

  /// One line about how it ended, written when it ends.
  final String notice;

  /// True once a notice was shown for this run, so a restart does not repeat it.
  final bool notified;

  /// True while the run has not reached a state it cannot leave.
  bool get isRunning => status == BackgroundRunStatus.running;

  /// What the list shows first: who ran where.
  String get title => '$botName · $chatName';

  /// What a notice says: what happened, or what is still being asked.
  String get body {
    final text = notice.trim();
    final fallback = switch (status) {
      BackgroundRunStatus.running => 'Working on: $task',
      BackgroundRunStatus.done => 'Finished: $task',
      BackgroundRunStatus.needsInput => 'Needs you: $task',
      BackgroundRunStatus.stopped => 'Stopped: $task',
      BackgroundRunStatus.failed => 'Failed: $task',
    };
    return text.isEmpty ? fallback : text;
  }

  BackgroundRun finished({
    required BackgroundRunStatus status,
    required String notice,
    DateTime? now,
  }) {
    final trimmed = notice.trim();
    return BackgroundRun(
      id: id,
      chatId: chatId,
      chatName: chatName,
      botId: botId,
      botName: botName,
      task: task,
      startedAt: startedAt,
      finishedAt: now ?? DateTime.now(),
      status: status,
      notice: trimmed.length > BackgroundRunLimits.maxNoticeCharacters
          ? trimmed.substring(0, BackgroundRunLimits.maxNoticeCharacters)
          : trimmed,
      notified: notified,
    );
  }

  BackgroundRun markedNotified() => BackgroundRun(
    id: id,
    chatId: chatId,
    chatName: chatName,
    botId: botId,
    botName: botName,
    task: task,
    startedAt: startedAt,
    finishedAt: finishedAt,
    status: status,
    notice: notice,
    notified: true,
  );

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'chatId': chatId,
      'chatName': chatName,
      'botId': botId,
      'botName': botName,
      'task': task,
      'startedAt': startedAt.toIso8601String(),
      'finishedAt': finishedAt?.toIso8601String(),
      'status': status.name,
      'notice': notice,
      'notified': notified,
    };
  }

  /// Reads one stored run. Null when the entry cannot be a run of this build,
  /// so the store keeps the original file instead of rewriting it away.
  static BackgroundRun? fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final chatId = json['chatId'];
    if (id is! String || id.isEmpty || chatId is! String || chatId.isEmpty) {
      return null;
    }
    BackgroundRunStatus? status;
    for (final value in BackgroundRunStatus.values) {
      if (value.name == json['status']) status = value;
    }
    if (status == null) return null;
    final startedAt = json['startedAt'];
    final finishedAt = json['finishedAt'];
    if (json['task'] is! String ||
        (finishedAt != null && finishedAt is! String)) {
      return null;
    }
    return BackgroundRun(
      id: id,
      chatId: chatId,
      chatName: json['chatName'] is String ? json['chatName'] as String : '',
      botId: json['botId'] is String ? json['botId'] as String : '',
      botName: json['botName'] is String ? json['botName'] as String : '',
      task: json['task'] as String,
      startedAt: startedAt is String
          ? DateTime.tryParse(startedAt) ??
                DateTime.fromMillisecondsSinceEpoch(0)
          : DateTime.fromMillisecondsSinceEpoch(0),
      finishedAt: finishedAt is String ? DateTime.tryParse(finishedAt) : null,
      status: status,
      notice: json['notice'] is String ? json['notice'] as String : '',
      notified: json['notified'] is bool ? json['notified'] as bool : false,
    );
  }
}
