import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:installm/core/services/local_notification_service.dart';
import 'package:installm/core/utils/id_generator.dart';
import 'package:installm/core/utils/logger.dart';
import 'package:installm/features/agents/data/background_run_store.dart';
import 'package:installm/features/agents/domain/background_run.dart';
import 'package:installm/features/group_chat/application/group_chat_controller.dart';

/// Run records, opened once per session.
final backgroundRunStoreProvider = FutureProvider<BackgroundRunStore>(
  (ref) => BackgroundRunStore.open(),
);

/// How a supervised run tells the user it is done or needs them.
///
/// Injected rather than called directly so a test can see exactly what would
/// have been shown, and so a platform without notifications can substitute a
/// no-op.
final backgroundRunNoticeProvider =
    Provider<Future<void> Function(String title, String body)>(
      (ref) =>
          (title, body) => LocalNotificationService.instance.showBackgroundRun(
            title: title,
            body: body,
          ),
    );

class BackgroundRunsState {
  const BackgroundRunsState({
    this.runs = const [],
    this.isReady = false,
    this.errorMessage,
  });

  final List<BackgroundRun> runs;
  final bool isReady;
  final String? errorMessage;

  BackgroundRun? byId(String runId) {
    for (final run in runs) {
      if (run.id == runId) return run;
    }
    return null;
  }

  /// The supervised run still going in [chatId], if any.
  BackgroundRun? runningIn(String chatId) {
    for (final run in runs) {
      if (run.chatId == chatId && run.isRunning) return run;
    }
    return null;
  }

  BackgroundRun? get running {
    for (final run in runs) {
      if (run.isRunning) return run;
    }
    return null;
  }

  BackgroundRunsState copyWith({
    List<BackgroundRun>? runs,
    bool? isReady,
    String? errorMessage,
    bool clearError = false,
  }) {
    return BackgroundRunsState(
      runs: runs ?? this.runs,
      isReady: isReady ?? this.isReady,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
    );
  }
}

final backgroundRunsProvider =
    StateNotifierProvider<BackgroundRunsController, BackgroundRunsState>(
      (ref) => BackgroundRunsController(ref),
    );

/// Runs one room turn out of sight and tells the user how it ended
/// (Road Map 3 Phase 3.3.4).
///
/// The supervised run *is* the room turn: it goes through the same controller,
/// the same registry, the same permission questions and the same hooks, so
/// running a task in the background can never do something the same task could
/// not do with the room open. What this adds is a record the user can see from
/// anywhere, a cancel that reaches the run, and a notice when it finishes or
/// needs an answer — without which \"background\" would only mean \"hidden\".
class BackgroundRunsController extends StateNotifier<BackgroundRunsState> {
  BackgroundRunsController(this._ref) : super(const BackgroundRunsState()) {
    _ready = _load();
  }

  final Ref _ref;
  late final Future<void> _ready;
  final Set<String> _stopping = {};

  Future<void> get whenReady => _ready;

  Future<void> _load() async {
    try {
      final store = await _ref.read(backgroundRunStoreProvider.future);
      final snapshot = store.load();
      // A record still marked running belongs to a process that is gone: no
      // run survives a restart, and a stale "Running" would be a lie about
      // work nobody is doing. It is corrected without a notice — the user was
      // there when the app closed.
      final recovered = <BackgroundRun>[];
      var repaired = false;
      for (final run in snapshot.runs) {
        if (!run.isRunning) {
          recovered.add(run);
          continue;
        }
        repaired = true;
        recovered.add(
          run.finished(
            status: BackgroundRunStatus.failed,
            notice:
                'The app closed while this run was going, so it did not '
                'finish.',
          ),
        );
      }
      if (repaired) {
        store.save(BackgroundRunsSnapshot(runs: recovered));
      }
      state = BackgroundRunsState(runs: recovered, isReady: true);
    } catch (error) {
      state = state.copyWith(
        isReady: true,
        errorMessage: 'Could not read the run list: $error',
      );
    }
  }

  Future<bool> _persist(BackgroundRunsSnapshot snapshot) async {
    try {
      final store = await _ref.read(backgroundRunStoreProvider.future);
      return store.save(snapshot);
    } catch (error) {
      state = state.copyWith(errorMessage: 'Could not save the run: $error');
      return false;
    }
  }

  /// Starts one supervised run in [chatId] and returns its record.
  ///
  /// Null (with the reason in [BackgroundRunsState.errorMessage]) when the room
  /// already has a run going or the record could not be stored: a run the user
  /// cannot see and stop is exactly what this feature must not create.
  Future<BackgroundRun?> start({
    required String chatId,
    required String chatName,
    required String botId,
    required String botName,
    required String task,
  }) async {
    await whenReady;
    if (task.trim().isEmpty) {
      state = state.copyWith(
        errorMessage: 'Describe the task the run should work on.',
      );
      return null;
    }
    if (state.runningIn(chatId) != null) {
      state = state.copyWith(
        errorMessage:
            'This chat already has a run going. Stop it, or wait for it to '
            'finish.',
      );
      return null;
    }
    final run = BackgroundRun.create(
      id: IdGenerator.generate('run'),
      chatId: chatId,
      chatName: chatName,
      botId: botId,
      botName: botName,
      task: task,
    );
    final stored = await _persist(
      BackgroundRunsSnapshot(runs: [run, ...state.runs]),
    );
    if (!stored) {
      state = state.copyWith(
        errorMessage: 'The run could not be recorded, so it was not started.',
      );
      return null;
    }
    state = state.copyWith(runs: [run, ...state.runs], clearError: true);
    AppLogger.info('Background run ${run.id} started in ${run.chatName}.');
    unawaited(_supervise(run));
    return run;
  }

  /// Stops a run the user no longer wants, from anywhere in the app.
  Future<bool> stop(String runId) async {
    await whenReady;
    final run = state.byId(runId);
    if (run == null || !run.isRunning) return false;
    _stopping.add(run.id);
    _ref.read(groupChatsProvider.notifier).cancelTurn(run.chatId);
    AppLogger.info('Background run ${run.id} was stopped by the user.');
    return true;
  }

  /// Waits for the turn, then says how it ended — and tells the user once.
  Future<void> _supervise(BackgroundRun run) async {
    final chats = _ref.read(groupChatsProvider.notifier);
    if (_ref.read(groupChatsProvider).runningChatIds.contains(run.chatId)) {
      chats.forgetStopRequest(run.chatId);
      await _finish(
        run,
        BackgroundRunStatus.failed,
        'This chat was in the middle of another turn, so the run did not '
        'start. Try again when it is free.',
      );
      return;
    }
    try {
      await chats.sendUserMessage(run.chatId, '@${run.botName} ${run.task}');
    } catch (error) {
      chats.forgetStopRequest(run.chatId);
      await _finish(
        run,
        BackgroundRunStatus.failed,
        'The run could not start: $error',
      );
      return;
    }
    if (_stopping.remove(run.id)) {
      await _finish(
        run,
        BackgroundRunStatus.stopped,
        'You stopped this run; what it produced so far is in ${run.chatName}.',
      );
      return;
    }
    final snapshot = _ref.read(groupChatsProvider).snapshot;
    final messages = snapshot.messagesFor(run.chatId);
    String? answer;
    for (final message in messages.reversed) {
      if (message.authorBotId == run.botId && message.text.trim().isNotEmpty) {
        answer = message.text.trim();
        break;
      }
    }
    // A turn that could not run at all is reported as the failure it is, even
    // though it also leaves the room asking for a reply: “needs you” would hide
    // what actually went wrong.
    if (answer != null &&
        (answer.startsWith('I could not run just now') ||
            answer == _noAnswerText)) {
      await _finish(run, BackgroundRunStatus.failed, answer);
      return;
    }
    if (roomNeedsUser(snapshot, run.chatId)) {
      await _finish(
        run,
        BackgroundRunStatus.needsInput,
        '${run.botName} is waiting for your answer in ${run.chatName}.',
      );
      return;
    }
    if (answer == null) {
      await _finish(
        run,
        BackgroundRunStatus.failed,
        'The run ended without an answer.',
      );
      return;
    }
    await _finish(run, BackgroundRunStatus.done, _firstLine(answer));
  }

  /// What a room writes when its turn produced nothing to say.
  ///
  /// Matched exactly, because a room line may quote anything at all; the same
  /// string is what `GroupChatsNotifier` uses in that position.
  static const String _noAnswerText = '(The model gave no answer.)';

  /// Marks a run finished, stores that, and shows the one notice it owes.
  Future<void> _finish(
    BackgroundRun run,
    BackgroundRunStatus status,
    String notice,
  ) async {
    final finished = run.finished(status: status, notice: notice);
    final stored = await _persist(
      BackgroundRunsSnapshot(
        runs: state.runs.map((existing) {
          return existing.id == finished.id ? finished : existing;
        }).toList(),
      ),
    );
    var next = finished;
    if (stored && !finished.notified) {
      try {
        await _ref.read(backgroundRunNoticeProvider)(
          finished.title,
          finished.body,
        );
        next = finished.markedNotified();
        await _persist(
          BackgroundRunsSnapshot(
            runs: state.runs.map((existing) {
              return existing.id == next.id ? next : existing;
            }).toList(),
          ),
        );
      } catch (error) {
        // A refused or failed notice must not change what happened.
        AppLogger.warning('Background run notice was not shown: $error');
      }
    }
    state = state.copyWith(
      runs: [
        for (final existing in state.runs)
          if (existing.id == next.id) next else existing,
      ],
      clearError: true,
    );
    AppLogger.info('Background run ${run.id} ${status.name}: ${finished.body}');
  }

  /// The first line of an answer, which is what the notice and the list show.
  static String _firstLine(String text) {
    final first = text.split('\n').first.trim();
    return first.isEmpty ? text.trim() : first;
  }
}
