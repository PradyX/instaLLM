import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:installm/core/services/service_providers.dart';
import 'package:installm/core/settings/reasoning_settings_provider.dart';
import 'package:installm/features/agents/application/agent_loop_service.dart';
import 'package:installm/features/bots/application/bots_controller.dart';
import 'package:installm/features/bots/domain/bot.dart';
import 'package:installm/features/bots/domain/bot_prompt.dart';
import 'package:installm/features/group_chat/data/group_chat_store.dart';
import 'package:installm/features/group_chat/domain/group_chat.dart';
import 'package:installm/features/group_chat/domain/group_router.dart';
import 'package:installm/features/group_chat/application/room_board_service.dart';
import 'package:installm/features/kanban/domain/task.dart';
import 'package:installm/features/home/presentation/home_controller.dart';
import 'package:installm/features/kanban/application/kanban_controller.dart';
import 'package:installm/features/kanban/application/kanban_tools.dart';
import 'package:installm/features/model_selection/domain/llm_model.dart';
import 'package:installm/features/model_selection/presentation/chat_models_provider.dart';
import 'package:installm/features/obsidian/application/vault_notes_service.dart';
import 'package:installm/features/obsidian/application/vaults_controller.dart';
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
  final _cancelRequested = <String>{};

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

  Future<void> removeChat(String chatId) async {
    _cancelRequested.add(chatId);
    state = state.copyWith(
      snapshot: state.snapshot.removeChat(chatId),
      clearError: true,
    );
    await _persist();
  }

  /// Stops the running turn in [chatId], if any.
  void cancelTurn(String chatId) {
    _cancelRequested.add(chatId);
    try {
      _ref.read(agentLoopServiceProvider).cancel();
    } catch (_) {}
  }

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
    if (trimmed.isEmpty || state.runningChatIds.contains(chatId)) return;
    await _ref.read(botsProvider.notifier).whenReady;
    final chat = _chatById(chatId);
    if (chat == null) return;
    if (chat.isDirect && _botById(chat.directBotId!) == null) return;
    _append(GroupMessage.user(chatId: chatId, text: trimmed));
    await _persist();
    await _runTurn(chatId, firstText: trimmed, roundsUsed: 0);
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
  }) async {
    final found = _chatById(chatId);
    if (found == null) return;
    GroupChat chat = found;
    _cancelRequested.remove(chatId);
    state = state.copyWith(runningChatIds: {...state.runningChatIds, chatId});
    try {
      var text = firstText;
      var rounds = roundsUsed;
      var speaker = GroupRouter.nextSpeaker(
        chat: chat,
        members: _membersOf(chat),
        userText: text,
      );
      while (speaker != null && rounds < chat.maxRounds) {
        if (_cancelRequested.contains(chatId)) break;
        final bot = _botById(speaker);
        if (bot == null) break;
        rounds++;
        await _answerAsBot(chat, bot);
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

  /// Runs one bot's answer: the local model the room resolves to, else a
  /// pending prompt the user (or a pasted reply) completes.
  ///
  /// Any installed chat model may answer; a model that cannot call tools simply
  /// answers without them, the way it does in a normal chat.
  Future<void> _answerAsBot(GroupChat chat, Bot bot) async {
    final prompt = await _assemblePrompt(chat, bot);
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
          pendingPrompt: prompt,
        ),
      );
      await _persist();
      return;
    }
    // The room's board, through the same registry, validation and
    // permission gates as every other tool: listing is free, creating
    // and moving ask the user first.
    final registry = _ref
        .read(toolRegistryProvider)
        .extendedWith(
          buildKanbanTools(
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
        );
    try {
      // What the model's own template writes where its reply begins, so a
      // bot answers in the reasoning state this user set for that model.
      final reasoning = await _ref
          .read(modelReasoningServiceProvider)
          .resolve(model);
      final assistantPrefill =
          reasoning?.prefillFor(
            _ref.read(reasoningSettingsProvider).choiceFor(model.id),
          ) ??
          '';

      final run = await _ref
          .read(agentLoopServiceProvider)
          .run(
            model: model,
            goal: prompt,
            registry: registry,
            maxIterations: 6,
            systemPrompt: BotPrompt.assemble(bot: bot),
            assistantPrefill: assistantPrefill,
          );
      final answer = run.answer.trim().isEmpty
          ? '(The model gave no answer.)'
          : run.answer.trim();
      _append(
        GroupMessage.bot(
          chatId: chat.id,
          botId: bot.id,
          botName: bot.name,
          text: answer,
        ),
      );
    } catch (error) {
      _append(
        GroupMessage.bot(
          chatId: chat.id,
          botId: bot.id,
          botName: bot.name,
          text:
              'I could not run just now ($error). '
              'Paste my reply to continue, or try again.',
          pendingPrompt: prompt,
        ),
      );
    }
    await _persist();
  }

  /// What one bot hears: soul, relevant skills, shared memory, recent room
  /// and assigned task — as the goal of its run.
  Future<String> _assemblePrompt(GroupChat chat, Bot bot) async {
    final messages = state.snapshot.messagesFor(chat.id);
    final recent = messages.length > recentHistoryLines
        ? messages.sublist(messages.length - recentHistoryLines)
        : messages;
    final room = StringBuffer();
    for (final message in recent) {
      room.writeln('${message.authorName}: ${message.text}');
    }

    final skills = _ref.read(skillsProvider);
    final ranked = SkillSelector.rank(
      skills: skills.skills,
      taskText: room.toString(),
      botId: bot.id,
      workspaceId: chat.workspaceId,
    );
    // The same window a chat request would get; without a model selected
    // the selector still works against a conservative fallback.
    final window = _ref.read(selectedContextWindowProvider);
    final usable = window?.resolvedConfig.contextTokens ?? 4000;
    final selected = SkillSelector.select(
      ranked: [
        for (final skill in ranked)
          if (bot.skillIds.contains(skill.id)) skill,
      ],
      usableInputTokens: usable,
    );
    final skillSections = [
      for (final item in selected) SkillSelector.sectionFor(item.skill),
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
    ];
    return [
      BotPrompt.assemble(
        bot: bot,
        skillSections: skillSections,
        projectMemory: '',
      ),
      ...parts,
    ].join('\n\n');
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
