import 'package:installm/features/agents/domain/agent_run.dart';
import 'package:installm/features/skills/application/skill_usage.dart';
import 'package:installm/features/model_selection/data/model_compatibility_service.dart';
import 'package:installm/features/skills/application/skill_choices.dart';
import 'package:installm/features/skills/application/skill_script_runner.dart';
import 'package:installm/core/permissions/workspace_permission.dart';
import 'package:installm/features/skills/application/skill_session.dart';
import 'package:installm/features/context/application/context_budget_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:installm/core/services/service_providers.dart';
import 'package:installm/core/settings/reasoning_settings_provider.dart';
import 'package:installm/core/utils/logger.dart';
import 'package:installm/features/agents/application/agent_loop_service.dart';
import 'package:installm/features/agents/application/background_runs_controller.dart';
import 'package:installm/features/agents/application/delegation_service.dart';
import 'package:installm/features/agents/application/delegation_tools.dart';
import 'package:installm/features/agents/application/rewind_service.dart';
import 'package:installm/features/agents/application/run_checkpoint_session.dart';
import 'package:installm/features/agents/application/run_commands.dart';
import 'package:installm/features/agents/domain/review_finding.dart';
import 'package:installm/features/agents/domain/run_checkpoint.dart';
import 'package:installm/features/bots/application/bots_controller.dart';
import 'package:installm/features/bots/domain/bot.dart';
import 'package:installm/features/bots/domain/bot_prompt.dart';
import 'package:installm/features/group_chat/data/group_chat_store.dart';
import 'package:installm/features/group_chat/domain/group_chat.dart';
import 'package:installm/features/group_chat/domain/group_router.dart';
import 'package:installm/features/group_chat/application/room_board_service.dart';
import 'package:installm/features/kanban/domain/task.dart';
import 'package:installm/features/kanban/application/kanban_controller.dart';
import 'package:installm/features/kanban/application/kanban_tools.dart';
import 'package:installm/features/model_selection/domain/llm_model.dart';
import 'package:installm/features/memory/application/memory_controller.dart';
import 'package:installm/features/memory/application/memory_commands.dart';
import 'package:installm/features/memory/domain/memory_command.dart';
import 'package:installm/i18n/strings.g.dart';
import 'package:installm/features/model_selection/presentation/chat_models_provider.dart';
import 'package:installm/features/vault/application/vault_notes_service.dart';
import 'package:installm/features/vault/application/vaults_controller.dart';
import 'package:installm/features/vault/application/bot_journal_service.dart';
import 'package:installm/features/vault/data/journal_checkpoint_store.dart';
import 'package:installm/features/skills/application/skills_controller.dart';
import 'package:installm/features/skills/domain/skill_selector.dart';
import 'package:installm/features/tools/application/tools_providers.dart';

/// Group chat file, opened once per session.
final groupChatStoreProvider = FutureProvider<GroupChatStore>(
  (ref) => GroupChatStore.open(),
);

/// True when the room waits on the user: a bot's answer still needs
/// pasting in. Shared by the roster badge and the room itself.
bool roomNeedsUser(GroupChatsSnapshot snapshot, String chatId) {
  return snapshot.messagesFor(chatId).any((message) => message.isPending);
}

/// The model a bot's answer in [chat] runs on.
///
/// A room is a chat like any other, so with nothing chosen of its own it uses
/// the model the app is set to ([selected]), exactly as home does. A room's own
/// pick wins, then the bot's preferred model — the bot editor's "Conversation
/// model" option means the same thing there (see [Bot.modelId]) — and anything
/// no longer installed falls through rather than leaving the room unable to
/// answer. Null means nothing is installed at all.
LlmModel? roomAnswerModel({
  required GroupChat chat,
  required Bot? bot,
  required List<LlmModel> installed,
  LlmModel? selected,
}) {
  for (final id in [chat.modelId, bot?.modelId, selected?.id]) {
    if (id == null) continue;
    for (final model in installed) {
      if (model.id == id) return model;
    }
  }
  return installed.isEmpty ? null : installed.first;
}

class GroupChatsState {
  const GroupChatsState({
    this.snapshot = GroupChatsSnapshot.empty,
    this.isReady = false,
    this.errorMessage,
    this.isReadOnly = false,
    this.runningChatIds = const {},
  });

  final GroupChatsSnapshot snapshot;
  final bool isReady;
  final String? errorMessage;
  final bool isReadOnly;
  final Set<String> runningChatIds;

  List<GroupChat> chatsFor(String workspaceId) {
    return snapshot.chats
        .where((chat) => chat.workspaceId == workspaceId)
        .toList();
  }

  GroupChatsState copyWith({
    GroupChatsSnapshot? snapshot,
    bool? isReady,
    String? errorMessage,
    bool clearError = false,
    bool? isReadOnly,
    Set<String>? runningChatIds,
  }) {
    return GroupChatsState(
      snapshot: snapshot ?? this.snapshot,
      isReady: isReady ?? this.isReady,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
      isReadOnly: isReadOnly ?? this.isReadOnly,
      runningChatIds: runningChatIds ?? this.runningChatIds,
    );
  }
}

final groupChatsProvider =
    StateNotifierProvider<GroupChatsNotifier, GroupChatsState>(
      (ref) => GroupChatsNotifier(ref),
    );

/// Owns group chats: members, modes and turns.
///
/// A turn is bounded on every axis (§11.2): at most the chat's maxRounds bot
/// answers follow one user line, every answer shares the user's context
/// budget, and a run can be cancelled mid-turn. Each bot hears its Soul,
/// the relevant skills, shared workspace memory, the recent room history
/// and its assigned task — never the whole room history, and never another
/// bot's private reasoning.
class GroupChatsNotifier extends StateNotifier<GroupChatsState> {
  GroupChatsNotifier(this._ref) : super(const GroupChatsState()) {
    _load();
  }

  final Ref _ref;
  static const VaultNotesService _notes = VaultNotesService();

  /// Who posts a review's answer, so `/review list` can find it again.
  static const String _reviewAuthorId = 'installm-review';
  final _cancelRequested = <String>{};
  final _skillRunners = <String, SkillScriptRunner>{};

  @override
  void dispose() {
    for (final runner in _skillRunners.values) {
      runner.cancel();
    }
    super.dispose();
  }

  /// Recent room lines each bot hears.
  static const int recentHistoryLines = 20;

  Future<void> _load() async {
    try {
      final store = await _ref.read(groupChatStoreProvider.future);
      state = GroupChatsState(
        snapshot: store.load(),
        isReady: true,
        isReadOnly: store.isReadOnly,
        errorMessage: store.isReadOnly
            ? 'Group chats were written by a newer version of InstaLLM and '
                  'are read-only in this build.'
            : null,
      );
    } catch (error) {
      state = state.copyWith(
        isReady: true,
        errorMessage: 'Could not load group chats: $error',
      );
    }
  }

  Future<bool> _persist() async {
    try {
      final store = await _ref.read(groupChatStoreProvider.future);
      if (store.isReadOnly) {
        state = state.copyWith(
          errorMessage:
              'Group chats were written by a newer version and are '
              'read-only in this build.',
        );
        return false;
      }
      return store.save(state.snapshot);
    } catch (error) {
      state = state.copyWith(
        errorMessage: 'Could not save group chats: $error',
      );
      return false;
    }
  }

  List<Bot> _membersOf(GroupChat chat) {
    final bots = _ref.read(botsProvider);
    return [
      for (final id in chat.memberBotIds)
        if (bots.botById(id) != null) bots.botById(id)!,
    ];
  }

  Future<GroupChat?> createChat({
    required String workspaceId,
    required String name,
    List<String> memberBotIds = const [],
    String? directBotId,
  }) async {
    final chat = GroupChat.create(
      workspaceId: workspaceId,
      name: name,
      memberBotIds: memberBotIds,
      directBotId: directBotId,
    );
    state = state.copyWith(
      snapshot: state.snapshot.upsertChat(chat),
      clearError: true,
    );
    final saved = await _persist();
    return saved ? chat : null;
  }

  Future<void> updateChat(GroupChat chat) async {
    state = state.copyWith(
      snapshot: state.snapshot.upsertChat(chat),
      clearError: true,
    );
    await _persist();
  }

  Future<bool> removeChat(String chatId) async {
    try {
      final store = await _ref.read(groupChatStoreProvider.future);
      if (store.isReadOnly || state.runningChatIds.contains(chatId)) {
        state = state.copyWith(
          errorMessage:
              'This chat cannot be deleted while read-only or answering.',
        );
        return false;
      }
      if (_chatById(chatId) == null) return false;
      final snapshot = state.snapshot.removeChat(chatId);
      if (!store.save(snapshot)) {
        state = state.copyWith(errorMessage: 'Could not delete the chat.');
        return false;
      }
      state = state.copyWith(snapshot: snapshot, clearError: true);
      return true;
    } catch (error) {
      state = state.copyWith(errorMessage: 'Could not delete the chat: $error');
      return false;
    }
  }

  /// Clears messages after a successful write; the room and its settings stay.
  Future<bool> clearChat(String chatId) async {
    try {
      final store = await _ref.read(groupChatStoreProvider.future);
      if (store.isReadOnly || state.runningChatIds.contains(chatId)) {
        state = state.copyWith(
          errorMessage:
              'This chat cannot be cleared while read-only or answering.',
        );
        return false;
      }
      if (_chatById(chatId) == null) return false;
      final snapshot = state.snapshot.clearChat(chatId);
      if (!store.save(snapshot)) {
        state = state.copyWith(errorMessage: 'Could not clear the chat.');
        return false;
      }
      state = state.copyWith(snapshot: snapshot, clearError: true);
      return true;
    } catch (_) {
      state = state.copyWith(errorMessage: 'Could not clear the chat.');
      return false;
    }
  }

  /// Stops the running turn in [chatId], if any.
  ///
  /// The request is kept until the turn it belongs to ends, so a stop that
  /// arrives while the turn is still being set up is not lost before there is
  /// a generation to cancel.
  void cancelTurn(String chatId) {
    _cancelRequested.add(chatId);
    _skillRunners[chatId]?.cancel();
    try {
      _ref.read(agentLoopServiceProvider).cancel();
    } catch (_) {}
  }

  /// Forgets a stop asked for a turn that never began, so it cannot end the
  /// chat's next turn instead.
  void forgetStopRequest(String chatId) => _cancelRequested.remove(chatId);

  final _openingTaskRooms = <String, Future<String?>>{};

  /// Reopens a linked room; seeds a new discussion once without starting an
  /// inference turn. Double clicks share the same opening operation.
  Future<String?> discussTaskInRoom(ProjectTask task) {
    final key = '${task.workspaceId}/${task.id}';
    return _openingTaskRooms.putIfAbsent(
      key,
      () => _openTaskRoom(task).whenComplete(() {
        _openingTaskRooms.remove(key);
      }),
    );
  }

  Future<String?> _openTaskRoom(ProjectTask requested) async {
    final repository = await resolveTaskRepository(
      _ref.read,
      requested.workspaceId,
    );
    final tasks = await repository.load(requested.workspaceId);
    final task = tasks
        .where((candidate) => candidate.id == requested.id)
        .firstOrNull;
    if (task == null) {
      throw StateError('This task no longer exists. Reload the board.');
    }
    final candidates = state.chatsFor(task.workspaceId);
    for (final id in task.relatedRoomIds) {
      final room = candidates.where((chat) => chat.id == id).firstOrNull;
      if (room != null) return room.id;
    }
    // Adopt v1 message links or a discussion created by the old Board action.
    final legacy = candidates
        .where(
          (chat) =>
              state.snapshot
                  .messagesFor(chat.id)
                  .any(
                    (message) => task.relatedMessages.contains(message.id),
                  ) ||
              (!chat.isDirect && chat.name == '${task.id} ${task.title}'),
        )
        .firstOrNull;
    if (legacy != null) {
      await _ref.read(roomBoardServiceProvider).linkTask(legacy, task.id);
      return legacy.id;
    }
    final members =
        task.assignedBotId != null && _botById(task.assignedBotId!) != null
        ? [task.assignedBotId!]
        : const <String>[];
    final chat = await createChat(
      workspaceId: task.workspaceId,
      name: '${task.id} ${task.title}',
      memberBotIds: members,
    );
    if (chat == null) return null;
    final brief = StringBuffer('Working ${task.id}: ${task.title}');
    if (task.description.isNotEmpty) brief.write('\n${task.description}');
    _append(GroupMessage.user(chatId: chat.id, text: brief.toString()));
    if (!await _persist()) return null;
    await _ref.read(roomBoardServiceProvider).linkTask(chat, task.id);
    return chat.id;
  }

  /// Opens (or finds) one bot's canonical 1:1 room in the workspace.
  ///
  /// Tapping a bot always lands in the same room, Hermes-style: the room
  /// is created once, then reused, so the bot keeps one shared history
  /// with the user next to its group-room life.
  Future<GroupChat?> directChatWith({
    required String workspaceId,
    required String botId,
  }) async {
    for (final chat in state.snapshot.chats) {
      if (chat.workspaceId == workspaceId && chat.directBotId == botId) {
        return chat;
      }
    }
    return createChat(
      workspaceId: workspaceId,
      name: _botById(botId)?.name ?? 'Bot',
      memberBotIds: [botId],
      directBotId: botId,
    );
  }

  /// True when the room waits on the user: a bot's answer needs pasting
  /// in, so the roster can badge it needs-you.
  bool needsUser(String chatId) => roomNeedsUser(state.snapshot, chatId);

  /// Posts the user's line and runs whoever should answer.
  Future<void> sendUserMessage(String chatId, String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    // `/background` is served even while this room is answering, because its
    // `stop`, `list` and `start` answers are exactly the ones a busy room
    // needs — and a stop that waited for the turn it wants to end would never
    // arrive.
    final background = BackgroundCommand.parse(trimmed);
    if (background != null) {
      final chat = _chatById(chatId);
      if (chat == null) return;
      await _handleBackground(chat, background, trimmed);
      return;
    }
    if (state.runningChatIds.contains(chatId)) return;
    // `/review` is a command, not a skill choice in a room: what it reviews is
    // this room's own changes, which a chat has none of. A command carrying
    // skill flags is still left to the skill path.
    final review = ReviewCommand.parse(trimmed);
    if (review != null) {
      final chat = _chatById(chatId);
      if (chat == null) return;
      await _handleReview(chat, review, trimmed);
      return;
    }
    final rewind = RewindCommand.parse(trimmed);
    if (rewind != null) {
      final chat = _chatById(chatId);
      if (chat == null) return;
      await _handleRewind(chat, rewind, trimmed);
      return;
    }
    final command = MemoryCommand.parse(trimmed);
    final commandChat = _chatById(chatId);
    if (command != null && commandChat != null) {
      state = state.copyWith(runningChatIds: {...state.runningChatIds, chatId});
      try {
        final response = await applyMemoryCommand(
          _ref.read(memoryProvider.notifier),
          command,
          conversationId: chatId,
          workspaceId: commandChat.workspaceId,
        );
        _append(GroupMessage.user(chatId: chatId, text: trimmed));
        _append(
          GroupMessage.bot(
            chatId: chatId,
            botId: 'installm-memory',
            botName: t.memory.title,
            text: response,
          ),
        );
        await _persist();
      } finally {
        state = state.copyWith(
          runningChatIds: state.runningChatIds
              .where((id) => id != chatId)
              .toSet(),
        );
      }
      return;
    }
    await _ref.read(botsProvider.notifier).whenReady;
    final chat = _chatById(chatId);
    if (chat == null) return;
    if (chat.isDirect && _botById(chat.directBotId!) == null) return;
    var task = trimmed;
    if (trimmed.startsWith('/')) {
      await _ref.read(skillsProvider.notifier).whenReady;
      await _ref.read(skillChoicesProvider.notifier).whenReady;
      final eligible = _ref
          .read(skillsProvider)
          .skills
          .where(
            (skill) => _membersOf(chat).any(
              (bot) => eligibleSkill(
                skill,
                workspaceId: chat.workspaceId,
                botId: bot.id,
                capabilities: bot.toolPermissions,
                assignedSkillIds: bot.skillIds,
              ),
            ),
          )
          .toList();
      final command = SkillCommand.parse(trimmed, eligible)!;
      var message = command.message;
      if ((command.choice != null || command.clear) &&
          !await _ref
              .read(skillChoicesProvider.notifier)
              .select('room:$chatId', command.choice)) {
        message = t.skills.saveError;
      }
      if (message != null) {
        _append(GroupMessage.user(chatId: chatId, text: trimmed));
        _append(
          GroupMessage.bot(
            chatId: chatId,
            botId: 'installm-skills',
            botName: t.skills.title,
            text: message,
          ),
        );
        await _persist();
        return;
      }
      task = command.task;
    }
    _append(GroupMessage.user(chatId: chatId, text: task));
    await _persist();
    await _runTurn(chatId, firstText: task, roundsUsed: 0);
  }

  /// `/rewind` — the files an agent run in this room wrote, put back.
  ///
  /// Listing is the default: the runs of this room and the exact command that
  /// puts one back, so a restore is a decision rather than a guess. The files
  /// go back through the vault service, under the same workspace link and
  /// permissions as every other write, and nothing else is touched.
  Future<void> _handleRewind(
    GroupChat chat,
    RewindCommand command,
    String text,
  ) async {
    state = state.copyWith(runningChatIds: {...state.runningChatIds, chat.id});
    try {
      _append(GroupMessage.user(chatId: chat.id, text: text));
      await _persist();
      if (command.message != null) {
        await _sayRewind(chat.id, command.message!);
        return;
      }
      final store = await _ref.read(runCheckpointStoreProvider.future);
      final runs = store.load().forContext('room:${chat.id}');
      if (command.list) {
        await _sayRewind(chat.id, rewindListing(runs));
        return;
      }
      final matches = command.runId == 'last'
          ? (runs.isEmpty ? <RunCheckpoint>[] : [runs.first])
          : [
              for (final run in runs)
                if (run.id == command.runId) run,
            ];
      if (matches.isEmpty) {
        await _sayRewind(
          chat.id,
          'No run of this chat has the id “${command.runId}”.\n\n'
          '${rewindListing(runs)}',
        );
        return;
      }
      final vaults = _ref.read(vaultsProvider.notifier);
      await vaults.whenReady;
      final paths = vaults.pathsFor(chat.workspaceId);
      final binding = _ref
          .read(vaultsProvider)
          .snapshot
          .bindingFor(chat.workspaceId);
      if (paths == null || binding == null) {
        await _sayRewind(
          chat.id,
          'This workspace is not linked to a vault folder, so there is nowhere '
          'to put the files back.',
        );
        return;
      }
      final outcome = await const RewindService().rewind(
        run: matches.single,
        paths: paths,
      );
      AppLogger.info(
        'Rewind of run ${matches.single.id} in room ${chat.id}: '
        'restored=${outcome.restored} files=${outcome.restoredPaths}',
      );
      await _sayRewind(chat.id, outcome.message);
    } finally {
      state = state.copyWith(
        runningChatIds: state.runningChatIds
            .where((id) => id != chat.id)
            .toSet(),
      );
    }
  }

  /// Runs one turn whose visible line and task differ.
  ///
  /// A command that assembles its own evidence (`/review`) shows the user the
  /// command they typed, while the model is given the changes themselves.
  Future<void> sendTurn(
    String chatId, {
    required String line,
    required String task,
  }) async {
    if (state.runningChatIds.contains(chatId)) return;
    _append(GroupMessage.user(chatId: chatId, text: line));
    await _persist();
    await _runTurn(chatId, firstText: task, roundsUsed: 0, taskOverride: task);
  }

  /// Starts one supervised run in [chat] and says what happened.
  ///
  /// Shared by `/background` and the `/review fix` hand-off: both start the
  /// same kind of run, so they resolve the bot and record it the same way.
  Future<void> _startSupervisedRun({
    required GroupChat chat,
    required String task,
    String? requestedBot,
  }) async {
    final runs = _ref.read(backgroundRunsProvider.notifier);
    await runs.whenReady;
    await _ref.read(botsProvider.notifier).whenReady;
    final members = _membersOf(chat);
    final bot = requestedBot == null
        ? (members.isEmpty ? null : members.first)
        : delegatedTarget(members: members, requested: requestedBot);
    if (bot == null) {
      await _sayRewind(
        chat.id,
        requestedBot == null
            ? 'This chat has no bot to run the task, so nothing was started.'
            : 'No bot in this chat is called “$requestedBot”. Members: '
                  '${members.map((member) => member.name).join(', ')}.',
      );
      return;
    }
    final run = await runs.start(
      chatId: chat.id,
      chatName: chat.name,
      botId: bot.id,
      botName: bot.name,
      task: task,
    );
    if (run == null) {
      await _sayRewind(
        chat.id,
        _ref.read(backgroundRunsProvider).errorMessage ??
            'The run could not be started.',
      );
      return;
    }
    AppLogger.info(
      'Room ${chat.id} started background run ${run.id} for ${bot.name}.',
    );
    await _sayRewind(
      chat.id,
      'Started ${run.id} — ${bot.name} is working on “${run.task}” in the '
      'background. You can leave this screen; you get one notice when it '
      'finishes or needs you, and /background stop ends it early.',
    );
  }

  /// `/background` — a task this chat's bot works on while the user is away.
  ///
  /// The run itself is an ordinary turn of this room, started through the same
  /// controller, so it obeys the same tools, permission questions and hooks.
  /// All this adds is the record, the cancel, and the notice when it is done or
  /// needs an answer.
  Future<void> _handleBackground(
    GroupChat chat,
    BackgroundCommand command,
    String text,
  ) async {
    // Deliberately not marked as running here: this command starts no
    // generation of its own, and marking it busy would make the supervised run
    // it just started return without doing anything.
    _append(GroupMessage.user(chatId: chat.id, text: text));
    await _persist();
    {
      final runs = _ref.read(backgroundRunsProvider.notifier);
      await runs.whenReady;
      if (command.message != null) {
        await _sayRewind(chat.id, command.message!);
        return;
      }
      final mine = [
        for (final run in _ref.read(backgroundRunsProvider).runs)
          if (run.chatId == chat.id) run,
      ];
      if (command.list) {
        await _sayRewind(chat.id, backgroundRunListing(mine));
        return;
      }
      if (command.stopCurrent || command.stopId != null) {
        final target = command.stopId == null
            ? _ref.read(backgroundRunsProvider).runningIn(chat.id)
            : _ref.read(backgroundRunsProvider).byId(command.stopId!);
        if (target == null || !target.isRunning) {
          await _sayRewind(
            chat.id,
            command.stopId == null
                ? 'No run is going in this chat.'
                : 'Run ${command.stopId} is not going.',
          );
          return;
        }
        if (target.chatId != chat.id) {
          await _sayRewind(
            chat.id,
            'Run ${target.id} belongs to ${target.chatName}. Stop it from '
            'there.',
          );
          return;
        }
        final stopped = await runs.stop(target.id);
        await _sayRewind(
          chat.id,
          stopped
              ? 'Stopping run ${target.id} (${target.botName}). '
                    'Whatever it produced so far stays in this chat.'
              : 'That run is no longer going.',
        );
        return;
      }
      if (state.runningChatIds.contains(chat.id) &&
          _ref.read(backgroundRunsProvider).runningIn(chat.id) == null) {
        await _sayRewind(
          chat.id,
          'This chat is answering right now, so a run was not started. Try '
          'again when it is free.',
        );
        return;
      }
      final task = (command.task ?? '').trim();
      if (task.isEmpty) {
        await _sayRewind(chat.id, BackgroundCommand.usage);
        return;
      }
      var goal = task;
      String? requestedBot;
      if (goal.startsWith('@')) {
        final split = goal.indexOf(RegExp(r'\s'));
        requestedBot = split < 0 ? goal.substring(1) : goal.substring(1, split);
        goal = split < 0 ? '' : goal.substring(split).trim();
      }
      if (goal.isEmpty) {
        await _sayRewind(chat.id, BackgroundCommand.usage);
        return;
      }
      await _startSupervisedRun(
        chat: chat,
        task: goal,
        requestedBot: requestedBot,
      );
    }
  }

  /// `/review` — a reviewer's pass over this chat's changes, and the hand-off
  /// that puts one finding in front of a bot.
  ///
  /// The pass is one ordinary turn of this chat, so it runs on the room's own
  /// model, tools and permissions: what makes it a review is what it is given
  /// (the changes) and what it is asked for (findings with a severity).
  Future<void> _handleReview(
    GroupChat chat,
    ReviewCommand command,
    String text,
  ) async {
    if (command.message != null) {
      await _sayReview(chat.id, command.message!);
      return;
    }
    if (command.list) {
      await _sayReview(
        chat.id,
        _lastReview(chat.id) ??
            'Nothing has been reviewed in this chat yet. Use /review.',
      );
      return;
    }
    if (command.fixIndex != null) {
      await _handFindingToBot(chat, command.fixIndex!, command.botName);
      return;
    }
    await _reviewChanges(chat, command, text);
  }

  /// Runs the reviewer over the changes, then lists what it found.
  Future<void> _reviewChanges(
    GroupChat chat,
    ReviewCommand command,
    String text,
  ) async {
    final vaults = _ref.read(vaultsProvider.notifier);
    await vaults.whenReady;
    final paths = vaults.pathsFor(chat.workspaceId);
    final binding = _ref
        .read(vaultsProvider)
        .snapshot
        .bindingFor(chat.workspaceId);
    if (paths == null || binding == null) {
      await _sayReview(
        chat.id,
        'This chat’s workspace is not linked to a folder, so there are no '
        'changes to review.',
      );
      return;
    }
    await _ref.read(botsProvider.notifier).whenReady;
    final members = _membersOf(chat);
    Bot? actor;
    if (command.botName != null) {
      actor = delegatedTarget(members: members, requested: command.botName!);
      if (actor == null) {
        await _sayReview(
          chat.id,
          'No bot in this chat is called “${command.botName}”. Members: '
          '${members.map((member) => member.name).join(', ')}.',
        );
        return;
      }
    } else {
      actor = members.isEmpty ? null : members.first;
    }
    if (actor == null) {
      await _sayReview(
        chat.id,
        'This chat has no bot to review with, so nothing was reviewed.',
      );
      return;
    }

    final evidence = <ReviewFile>[];
    final notes = <String>[];
    var total = 0;
    String context;
    final requested = command.files;
    if (requested.isEmpty) {
      final store = await _ref.read(runCheckpointStoreProvider.future);
      final runs = store.load().forContext('room:${chat.id}');
      if (runs.isEmpty) {
        await _sayReview(
          chat.id,
          'No run of this chat has written a file yet, so there is nothing '
          'recorded to review. Name files instead: /review notes/plan.md',
        );
        return;
      }
      final run = runs.first;
      context = 'the latest run (${run.id}, ${run.label})';
      for (final entry in run.entries) {
        if (evidence.length >= ReviewLimits.maxFiles) {
          notes.add(
            '${run.entries.length - evidence.length} further file(s) of this '
            'run were not shown.',
          );
          break;
        }
        final (note, error) = await _notes.readNote(
          paths: paths,
          permissions: binding.permissions,
          relativePath: entry.relativePath,
        );
        if (error != null) {
          notes.add('${entry.relativePath}: ${error.message}, not shown.');
          continue;
        }
        final after = _clip(note?.content ?? '', ReviewLimits.maxFileBytes);
        final before = entry.beforeExists
            ? _clip(entry.beforeContent ?? '', ReviewLimits.maxFileBytes)
            : null;
        total += after.text.length + (before?.text.length ?? 0);
        if (total > ReviewLimits.maxReviewBytes) {
          notes.add('The review reached its size limit; later files follow.');
          break;
        }
        evidence.add(
          ReviewFile(
            relativePath: entry.relativePath,
            after: after.text,
            before: before?.text,
            createdByRun: !entry.beforeExists,
            truncated: after.truncated || (before?.truncated ?? false),
          ),
        );
      }
    } else {
      context = '${requested.length} named file(s)';
      for (final path in requested) {
        final (note, error) = await _notes.readNote(
          paths: paths,
          permissions: binding.permissions,
          relativePath: path,
        );
        if (error != null) {
          notes.add('$path: ${error.message}, not shown.');
          continue;
        }
        final after = _clip(note?.content ?? '', ReviewLimits.maxFileBytes);
        total += after.text.length;
        if (total > ReviewLimits.maxReviewBytes) {
          notes.add('The review reached its size limit; later files follow.');
          break;
        }
        evidence.add(
          ReviewFile(
            relativePath: path,
            after: after.text,
            truncated: after.truncated,
          ),
        );
      }
    }
    if (evidence.isEmpty) {
      await _sayReview(
        chat.id,
        'Nothing could be read for this review:\n'
        '${notes.map((note) => '- $note').join('\n')}',
      );
      return;
    }

    // A reviewer is a model. Without one the room would only be handed a
    // prompt to paste elsewhere, and calling that “No findings” would be a
    // claim about the changes that nothing checked.
    if (roomAnswerModel(
          chat: chat,
          bot: actor,
          installed: _ref.read(chatModelsProvider),
          selected: _ref.read(selectedChatModelProvider),
        ) ==
        null) {
      await _sayReview(
        chat.id,
        'No model is installed, so nothing could be reviewed. Install or choose '
        'a model in Models, then run /review again.',
      );
      return;
    }

    final task =
        '@${actor.name}\n\n${reviewTask(subject: '$context in this chat', files: evidence, notes: notes)}';
    final before = state.snapshot.messagesFor(chat.id).length;
    await sendTurn(chat.id, line: text, task: task);
    String? answer;
    final messages = state.snapshot.messagesFor(chat.id);
    for (var index = messages.length - 1; index >= before; index--) {
      final message = messages[index];
      // A pending prompt is the room asking for a reply, not the reviewer's
      // answer, so it is never read as findings.
      if (message.authorBotId != null &&
          !message.isPending &&
          message.text.trim().isNotEmpty) {
        answer = message.text.trim();
        break;
      }
    }
    if (answer == null) {
      await _sayReview(
        chat.id,
        'The reviewer did not answer, so there is nothing to list. Run '
        '/review again, or name a file: /review notes/plan.md',
      );
      return;
    }
    final findings = ReviewFindings.parse(answer);
    final listing = reviewListing(
      context: context,
      files: [for (final file in evidence) file.relativePath],
      findings: findings,
    );
    AppLogger.info(
      'Review of ${chat.id}: ${findings.length} finding(s) over '
      '${evidence.length} file(s).',
    );
    await _sayReview(chat.id, listing);
  }

  /// Hands one finding of this chat's last review to a bot as a run.
  Future<void> _handFindingToBot(
    GroupChat chat,
    int index,
    String? botName,
  ) async {
    final listing = _lastReview(chat.id);
    if (listing == null) {
      await _sayReview(
        chat.id,
        'Nothing has been reviewed in this chat yet. Use /review first.',
      );
      return;
    }
    final findings = ReviewFindings.parse(listing);
    if (findings.isEmpty) {
      await _sayReview(
        chat.id,
        'The last review found nothing to fix. Run /review again after more '
        'work, or name a file: /review notes/plan.md',
      );
      return;
    }
    if (index > findings.length) {
      await _sayReview(
        chat.id,
        'The last review has ${findings.length} '
        '${findings.length == 1 ? 'finding' : 'findings'}; /review fix takes '
        'one of those numbers.',
      );
      return;
    }
    final finding = findings[index - 1];
    final buffer = StringBuffer(
      'Fix this review finding (${finding.severity.label}): '
      '${finding.summary}',
    );
    if (finding.detail.isNotEmpty) buffer.write('\n${finding.detail}');
    buffer.write(
      '\nWork in the linked project folder, keep the change as small as the '
      'finding, and say what you changed.',
    );
    await _startSupervisedRun(
      chat: chat,
      task: buffer.toString(),
      requestedBot: botName,
    );
  }

  /// The last review this chat was shown, or null when it has none.
  String? _lastReview(String chatId) {
    final messages = state.snapshot.messagesFor(chatId);
    for (var index = messages.length - 1; index >= 0; index--) {
      final message = messages[index];
      if (message.authorBotId == _reviewAuthorId &&
          message.text.startsWith('Review of ')) {
        return message.text;
      }
    }
    return null;
  }

  /// Cuts [text] to [limit] characters, saying so when it was cut.
  static ({String text, bool truncated}) _clip(String text, int limit) {
    if (text.length <= limit) return (text: text, truncated: false);
    return (
      text: '${text.substring(0, limit)}\n… (cut at $limit characters)',
      truncated: true,
    );
  }

  /// One review answer, under the app's own name rather than a bot's.
  Future<void> _sayReview(String chatId, String text) async {
    _append(
      GroupMessage.bot(
        chatId: chatId,
        botId: _reviewAuthorId,
        botName: 'Review',
        text: text,
      ),
    );
    await _persist();
  }

  /// One `/rewind` answer, under the app's own name rather than a bot's.
  Future<void> _sayRewind(String chatId, String text) async {
    _append(
      GroupMessage.bot(
        chatId: chatId,
        botId: 'installm-rewind',
        botName: 'Rewind',
        text: text,
      ),
    );
    await _persist();
  }

  /// Records a pasted answer for a pending bot turn, then routes onward.
  Future<void> answerPending(
    String chatId,
    String messageId,
    String text,
  ) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    await _ref.read(botsProvider.notifier).whenReady;
    final messages = state.snapshot.messagesFor(chatId);
    GroupMessage? pending;
    for (final message in messages) {
      if (message.id == messageId && message.isPending) pending = message;
    }
    if (pending == null ||
        pending.authorBotId == null ||
        _botById(pending.authorBotId!) == null) {
      return;
    }
    final chat = _chatById(chatId);
    if (chat == null) return;
    _replace(pending.copyWith(text: trimmed, pendingPrompt: null));
    await _persist();
    await _runTurn(chatId, firstText: trimmed, roundsUsed: 1);
  }

  Future<void> _runTurn(
    String chatId, {
    required String firstText,
    required int roundsUsed,
    String? taskOverride,
  }) async {
    final found = _chatById(chatId);
    if (found == null) return;
    GroupChat chat = found;
    state = state.copyWith(runningChatIds: {...state.runningChatIds, chatId});
    try {
      var text = firstText;
      var rounds = roundsUsed;
      // Only the first answer of this turn is given the assembled task: the
      // follow-up rounds of a hand-off answer each other, not the task again.
      var turnTask = taskOverride;
      var speaker = GroupRouter.nextSpeaker(
        chat: chat,
        members: _membersOf(chat),
        userText: text,
      );
      if (speaker == null) {
        final choice = _ref.read(skillChoicesProvider)['room:$chatId'];
        final skill = _ref.read(skillsProvider).skillById(choice?.skillId);
        if (skill != null) {
          for (final member in _membersOf(chat)) {
            if (eligibleSkill(
              skill,
              workspaceId: chat.workspaceId,
              botId: member.id,
              capabilities: member.toolPermissions,
              assignedSkillIds: member.skillIds,
            )) {
              speaker = member.id;
              break;
            }
          }
        }
      }
      while (speaker != null && rounds < chat.maxRounds) {
        if (_cancelRequested.contains(chatId)) break;
        final bot = _botById(speaker);
        if (bot == null) break;
        rounds++;
        await _answerAsBot(chat, bot, taskOverride: turnTask);
        turnTask = null;
        chat = _chatById(chatId) ?? chat;
        final answer = _latestBotText(chatId, speaker);
        if (answer == null || _cancelRequested.contains(chatId)) break;
        // A direct chat is one question, one answer — the floor always
        // returns to the user instead of chaining follow-ups.
        speaker = chat.isDirect
            ? null
            : GroupRouter.followUpSpeaker(
                members: _membersOf(chat),
                botText: answer,
                roundsUsed: rounds,
                maxRounds: chat.maxRounds,
              );
        text = answer;
      }
    } finally {
      _cancelRequested.remove(chatId);
      state = state.copyWith(
        runningChatIds: state.runningChatIds
            .where((id) => id != chatId)
            .toSet(),
      );
      await _persist();
    }
  }

  /// What the model's own template writes where its reply begins, so a bot
  /// answers in the reasoning state this user set for that model.
  Future<String> _assistantPrefillFor(LlmModel model) async {
    final reasoning = await _ref
        .read(modelReasoningServiceProvider)
        .resolve(model);
    return reasoning?.prefillFor(
          _ref.read(reasoningSettingsProvider).choiceFor(model.id),
        ) ??
        '';
  }

  /// Runs one bot's answer: the local model the room resolves to, else a
  /// pending prompt the user (or a pasted reply) completes.
  ///
  /// Any installed chat model may answer; a model that cannot call tools simply
  /// answers without them, the way it does in a normal chat.
  Future<void> _answerAsBot(
    GroupChat chat,
    Bot bot, {
    String? taskOverride,
  }) async {
    late final ({String systemPrompt, String goal, SkillSession skills}) prompt;
    try {
      prompt = await _assemblePrompt(chat, bot, turnTask: taskOverride);
    } catch (error) {
      _append(
        GroupMessage.bot(
          chatId: chat.id,
          botId: bot.id,
          botName: bot.name,
          text: error is FormatException
              ? error.message.toString()
              : t.skills.unavailable,
        ),
      );
      await _persist();
      return;
    }
    final pendingPrompt = '${prompt.systemPrompt}\n\n${prompt.goal}'.trim();
    final model = roomAnswerModel(
      chat: chat,
      bot: bot,
      installed: _ref.read(chatModelsProvider),
      selected: _ref.read(selectedChatModelProvider),
    );
    if (model == null) {
      _append(
        GroupMessage.bot(
          chatId: chat.id,
          botId: bot.id,
          botName: bot.name,
          text:
              'No model is installed, so I cannot answer yet. The prompt '
              'below is ready — paste my reply to continue.',
          pendingPrompt: pendingPrompt,
        ),
      );
      await _persist();
      return;
    }
    // The room's board, through the same registry, validation and
    // permission gates as every other tool: listing is free, creating
    // and moving ask the user first.
    final vaults = _ref.read(vaultsProvider.notifier);
    await vaults.whenReady;
    final paths = vaults.pathsFor(chat.workspaceId);
    final binding = _ref
        .read(vaultsProvider)
        .snapshot
        .bindingFor(chat.workspaceId);
    // What this run writes is snapshotted, so `/rewind` can put those files
    // back. A run that writes nothing never appears in the store, and a
    // snapshot that cannot be stored does not stop the work.
    RunCheckpointSession? runCheckpoints;
    try {
      runCheckpoints = RunCheckpointSession(
        store: await _ref.read(runCheckpointStoreProvider.future),
        contextKey: 'room:${chat.id}',
        label: bot.name,
      );
    } catch (_) {
      // Without snapshots the bot still works; only rewind has nothing to offer.
    }
    BotJournalSession? journal;
    if (model.supportsToolCalling && paths != null && binding != null) {
      try {
        journal = await BotJournalSession.open(
          paths: paths,
          permissions: binding.permissions,
          botId: bot.id,
          checkpoints: await _ref.read(journalCheckpointStoreProvider.future),
          runCheckpoints: runCheckpoints,
          contextKey: '${binding.vaultId}|${chat.workspaceId}',
          resolvePermissions: () {
            final current = _ref
                .read(vaultsProvider)
                .snapshot
                .bindingFor(chat.workspaceId);
            return current?.vaultId == binding.vaultId &&
                    current?.projectPath == binding.projectPath
                ? current?.permissions
                : null;
          },
        );
      } catch (_) {
        // Optional journals must not prevent the ordinary local answer.
      }
    }
    final scripts = SkillScriptRunner(
      isCurrent: prompt.skills.isCurrent,
      onResult: prompt.skills.recordScriptResult,
    );
    _skillRunners[chat.id] = scripts;
    // The other bots this one may hand a task to. Each keeps its own soul and
    // gets a read-only copy of this registry, so a delegation can never widen
    // what the asking bot could do itself.
    final delegatable = [
      for (final id in chat.memberBotIds)
        if (id != bot.id) ?_botById(id),
    ];
    final registry = _ref.read(toolRegistryProvider).extendedWith([
      ...buildKanbanTools(
        KanbanToolContext(
          workspaceId: chat.workspaceId,
          roomId: chat.id,
          repositoryFor: (workspaceId) =>
              resolveTaskRepository(_ref.read, workspaceId),
          actorName: bot.name,
          onBoardChanged: () async {
            if (_ref.read(activeWorkspaceIdProvider) == chat.workspaceId) {
              await _ref.read(kanbanProvider.notifier).reload();
            }
            _ref.invalidate(workspaceTasksProvider(chat.workspaceId));
          },
        ),
      ),
      ...?journal?.tools(),
      ...prompt.skills.tools(),
      ...scripts.tools(prompt.skills.skills),
    ]);
    final assistantPrefill = await _assistantPrefillFor(model);
    final answerRegistry = delegatable.isEmpty
        ? registry
        : registry.extendedWith([
            buildDelegationTool(
              actor: bot,
              members: delegatable,
              model: model,
              budget: _ref.read(contextBudgetProvider).budget,
              registry: registry,
              runner: DelegationRunner(
                loop: _ref.read(agentLoopServiceProvider),
              ),
              assistantPrefill: assistantPrefill,
              readSlice: (requested) {
                if (paths == null || binding == null) {
                  return Future.value(
                    'No workspace folder is linked, so no files could be '
                    'passed along.',
                  );
                }
                return const DelegationRunner().readSlice(
                  paths: paths,
                  permissions: binding.permissions,
                  requested: requested,
                );
              },
            ),
          ]);
    try {
      final run = await _ref
          .read(agentLoopServiceProvider)
          .run(
            model: model,
            goal: prompt.goal,
            registry: answerRegistry,
            maxIterations: 6,
            budget: _ref.read(contextBudgetProvider).budget,
            onContext: (input, reserved, window) {
              if (!mounted) return;
              _ref.read(skillUsageProvider.notifier).state = {
                ..._ref.read(skillUsageProvider),
                'room:${chat.id}': SkillUsage.capture(
                  prompt.skills,
                  input: input,
                  reserved: reserved,
                  window: window,
                ),
              };
            },
            systemPrompt: model.supportsToolCalling
                ? '${prompt.systemPrompt}\n\n${AgentLoopService.systemPrompt}\n\n${answerRegistry.describeForPrompt()}'
                : prompt.systemPrompt,
            assistantPrefill: assistantPrefill,
            // The room owns the stop, so a turn stopped while it was still
            // being set up is honoured instead of answering anyway.
            stopRequested: () => _cancelRequested.contains(chat.id),
            // This goal is the room itself — history, notes and skills — so it
            // is bounded by the context budget rather than by the limit meant
            // for a goal the user typed (which it would always exceed).
            userSuppliedGoal: false,
          );
      final answer = run.answer.trim().isEmpty
          ? (run.status == AgentRunStatus.budgetReached
                ? run.steps.last.text
                : '(The model gave no answer.)')
          : run.answer.trim();
      // A turn the user stopped before it answered adds nothing: the stop is
      // reported where the run is tracked, and “(The model gave no answer.)”
      // would read as a failure.
      if (answer.trim().isNotEmpty || !_cancelRequested.contains(chat.id)) {
        _append(
          GroupMessage.bot(
            chatId: chat.id,
            botId: bot.id,
            botName: bot.name,
            text: answer,
          ),
        );
      }
    } catch (error) {
      _append(
        GroupMessage.bot(
          chatId: chat.id,
          botId: bot.id,
          botName: bot.name,
          text:
              'I could not run just now ($error). '
              'Paste my reply to continue, or try again.',
          pendingPrompt: pendingPrompt,
        ),
      );
    }
    scripts.cancel();
    _skillRunners.remove(chat.id);
    await _persist();
  }

  /// Stable instructions and facts stay in the system prefix; the goal is
  /// the recent room and assigned task. Both are charged by the agent loop.
  Future<({String systemPrompt, String goal, SkillSession skills})>
  _assemblePrompt(GroupChat chat, Bot bot, {String? turnTask}) async {
    var projectMemory = '';
    if (bot.memoryScope != BotMemoryScope.none) {
      final memory = _ref.read(memoryProvider.notifier);
      await memory.whenReady;
      projectMemory = memory.promptFacts(
        scope: bot.memoryScope,
        conversationId: chat.id,
        workspaceId: chat.workspaceId,
      );
    }
    final messages = state.snapshot.messagesFor(chat.id);
    final recent = messages.length > recentHistoryLines
        ? messages.sublist(messages.length - recentHistoryLines)
        : messages;
    final room = StringBuffer();
    for (final message in recent) {
      room.writeln('${message.authorName}: ${message.text}');
    }
    // A command that assembles its own evidence (`/review`) ran the bot on a
    // goal the room never saw, so the goal is carried here rather than read
    // back out of the transcript.
    final rankText = turnTask == null
        ? room.toString()
        : '${room.toString()}\n$turnTask';

    await _ref.read(skillsProvider.notifier).whenReady;
    final skills = _ref.read(skillsProvider);
    final ranked = SkillSelector.rank(
      skills: skills.skills,
      taskText: rankText,
      botId: bot.id,
      botCapabilities: bot.toolPermissions.map(Capability.new).toSet(),
      workspaceId: chat.workspaceId,
    );
    // The same window a chat request would get; without a model selected
    // the selector still works against a conservative fallback.
    final answerModel = roomAnswerModel(
      chat: chat,
      bot: bot,
      installed: _ref.read(chatModelsProvider),
      selected: _ref.read(selectedChatModelProvider),
    );
    final usable = _ref
        .read(contextBudgetProvider)
        .budget
        .resolvePolicy(
          runtimeContextTokens: ModelCompatibilityService.defaultContextTokens,
          declaredContextTokens: answerModel?.ggufMetadata?.contextLength,
          reservedOutputTokens: AgentLoopService.defaultMaxTokens,
        )
        .usableInputTokens;
    await _ref.read(skillChoicesProvider.notifier).whenReady;
    final choice = _ref.read(skillChoicesProvider)['room:${chat.id}'];
    final explicit = choice == null ? null : skills.skillById(choice.skillId);
    final selected = SkillSelector.select(
      ranked: [
        if (explicit != null &&
            eligibleSkill(
              explicit,
              workspaceId: chat.workspaceId,
              botId: bot.id,
              capabilities: bot.toolPermissions,
              assignedSkillIds: bot.skillIds,
            ))
          explicit,
        if (choice == null)
          for (final skill in ranked)
            if (bot.skillIds.contains(skill.id)) skill,
      ],
      usableInputTokens: usable,
    );
    if (explicit != null &&
        eligibleSkill(
          explicit,
          workspaceId: chat.workspaceId,
          botId: bot.id,
          capabilities: bot.toolPermissions,
          assignedSkillIds: bot.skillIds,
        ) &&
        selected.isEmpty) {
      throw FormatException(t.skills.budgetError);
    }
    final skillSession = SkillSession(
      skills: [for (final item in selected) item.skill],
      tokenBudget: usable ~/ SkillSelector.maximumSkillShare,
      isCurrent: (skill) {
        final current = _ref.read(skillsProvider).skillById(skill.id);
        final currentBot = _botById(bot.id);
        return current != null &&
            current.enabled &&
            identical(current, skill) &&
            currentBot != null &&
            currentBot.skillIds.contains(skill.id) &&
            (skill.assignedBotIds.isEmpty ||
                skill.assignedBotIds.contains(bot.id)) &&
            _chatById(chat.id)?.workspaceId == chat.workspaceId &&
            skill.allowedFor(
              currentBot.toolPermissions.map(Capability.new).toSet(),
            ) &&
            (skill.workspaceId == null ||
                skill.workspaceId == chat.workspaceId) &&
            !_cancelRequested.contains(chat.id);
      },
    );
    if (choice != null &&
        explicit != null &&
        selected.any((item) => item.skill.id == explicit.id)) {
      for (final path in choice.resources) {
        final loaded = skillSession.readResource(explicit.id, path);
        if (!loaded.startsWith('Skill resource ')) {
          throw FormatException(loaded);
        }
      }
    }
    final skillSections = [
      ...skillSession.sections,
      ...skillSession.resourceSections,
    ];

    var memory = '';
    final paths = _ref.read(vaultsProvider.notifier).pathsFor(chat.workspaceId);
    final binding = _ref
        .read(vaultsProvider)
        .snapshot
        .bindingFor(chat.workspaceId);
    if (paths != null && binding != null) {
      try {
        final lines = room.toString().split('\n');
        final hits = await _notes.searchNotes(
          paths: paths,
          permissions: binding.permissions,
          query: lines.isEmpty ? '' : lines.last,
        );
        if (hits.isNotEmpty) {
          memory = [
            for (final hit in hits.take(3))
              '${hit.relativePath}: ${hit.snippet}',
          ].join('\n');
        }
      } catch (_) {}
    }

    List<ProjectTask> boardTasks = const [];
    try {
      final repository = await resolveTaskRepository(
        _ref.read,
        chat.workspaceId,
      );
      boardTasks = await repository.load(chat.workspaceId);
    } catch (_) {
      /* An unavailable board must not prevent local chat. */
    }
    final assigned = [
      for (final task in boardTasks)
        if (task.assignedBotId == bot.id && !task.isDone) task,
    ];
    final taskLine = assigned.isEmpty
        ? ''
        : 'Assigned tasks: ${assigned.map((t) => '${t.id} ${t.title}').join('; ')}';
    final linked = boardTasks
        .where((task) => task.relatedRoomIds.contains(chat.id))
        .take(12);
    final linkedLine = linked
        .map((task) => '${task.id} [${task.status.key}] ${task.title}')
        .join('; ');

    final parts = [
      'You are ${bot.name} in the group chat "${chat.name}". '
          'Answer as ${bot.name}, briefly and in character. '
          'Mention another bot as @name to hand them the floor.',
      if (taskLine.isNotEmpty) taskLine,
      if (linkedLine.isNotEmpty) 'Tasks linked to this room: $linkedLine',
      'Board tools for this workspace: kanban_list_tasks, '
          'kanban_create_task, kanban_move_task. When the room agrees on '
          'work, create the task; when you finish a step, move it. '
          'Moves appear on the Board.',
      if (memory.isNotEmpty) 'Relevant project notes:\n$memory',
      'Recent room:\n${room.toString().trim()}',
      ?turnTask,
    ];
    return (
      systemPrompt: BotPrompt.assemble(
        bot: bot,
        skillSections: skillSections,
        projectMemory: projectMemory,
      ),
      goal: parts.join('\n\n'),
      skills: skillSession,
    );
  }

  String? _latestBotText(String chatId, String botId) {
    final messages = state.snapshot.messagesFor(chatId);
    for (var index = messages.length - 1; index >= 0; index--) {
      final message = messages[index];
      if (message.authorBotId == botId && !message.isPending) {
        return message.text;
      }
    }
    return null;
  }

  GroupChat? _chatById(String chatId) {
    for (final chat in state.snapshot.chats) {
      if (chat.id == chatId) return chat;
    }
    return null;
  }

  Bot? _botById(String botId) {
    return _ref.read(botsProvider).botById(botId);
  }

  void _append(GroupMessage message) {
    state = state.copyWith(
      snapshot: state.snapshot.appendMessage(message),
      clearError: true,
    );
  }

  void _replace(GroupMessage message) {
    state = state.copyWith(
      snapshot: state.snapshot.replaceMessage(message),
      clearError: true,
    );
  }

  void clearError() {
    state = state.copyWith(clearError: true);
  }
}
