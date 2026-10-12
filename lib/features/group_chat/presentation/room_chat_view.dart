import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pocket_llm/core/navigation/app_router.dart';
import 'package:pocket_llm/core/widgets/chat_bubble.dart';
import 'package:pocket_llm/core/widgets/chat_composer.dart';
import 'package:pocket_llm/core/widgets/composer_model_pill.dart';
import 'package:pocket_llm/features/bots/application/bots_controller.dart';
import 'package:pocket_llm/features/bots/presentation/bot_editor_page.dart';
import 'package:pocket_llm/features/conversations/domain/message.dart';
import 'package:pocket_llm/features/group_chat/application/group_chat_controller.dart';
import 'package:pocket_llm/features/group_chat/domain/group_chat.dart';
import 'package:pocket_llm/features/kanban/application/kanban_controller.dart';
import 'package:pocket_llm/features/kanban/application/kanban_tools.dart';
import 'package:pocket_llm/features/model_selection/presentation/chat_models_provider.dart';
import 'package:pocket_llm/features/tools/application/tool_approval_controller.dart';
import 'package:pocket_llm/features/tools/application/tool_registry.dart';
import 'package:pocket_llm/features/tools/presentation/tool_approval_dialog.dart';
import 'package:pocket_llm/features/voice/application/composer_dictation_controller.dart';

/// One room's lines, as the shared chat page draws them.
///
/// It has no Scaffold or AppBar of its own and never pushes a route: the page
/// owns the header (the room's name and settings) and the sidebar, so a bot's
/// chat and a conversation are the same surface with different content. The
/// messages go through [ChatBubble], the same widget home uses, so a bot's
/// answer looks like any other answer.
class RoomChatView extends ConsumerStatefulWidget {
  const RoomChatView({super.key, required this.chatId});

  final String chatId;

  @override
  ConsumerState<RoomChatView> createState() => _RoomChatViewState();
}

class _RoomChatViewState extends ConsumerState<RoomChatView> {
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  GroupChat? _chat(GroupChatsState state) {
    for (final chat in state.snapshot.chats) {
      if (chat.id == widget.chatId) return chat;
    }
    return null;
  }

  /// Asks the room's permission question: a bot's board move waits for the
  /// user, and silence refuses — a prompt that disappears is never consent.
  Future<void> _askForToolApproval(ToolApprovalRequest request) async {
    if (!mounted) return;
    final approved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => ToolApprovalDialog(
        request: request,
        onDecision: (value) => Navigator.of(dialogContext).pop(value),
      ),
    );
    if (!mounted) return;
    final controller = ref.read(toolApprovalControllerProvider.notifier);
    if (approved == true) {
      controller.approve();
    } else {
      controller.deny();
    }
  }

  void _scrollDown() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _send(String text) async {
    if (text.trim().isEmpty) return;
    _inputController.clear();
    await ref
        .read(groupChatsProvider.notifier)
        .sendUserMessage(widget.chatId, text);
  }

  /// Turns one room line into a board task, linked back to the message — the
  /// chat-to-board half of the Hermes loop, one tap.
  Future<void> _createTaskFromMessage(
    GroupMessage message,
    String workspaceId,
  ) async {
    final text = message.text.trim();
    if (text.isEmpty) return;
    final firstLine = text.split('\n').first.trim();
    final title = firstLine.length > 160
        ? '${firstLine.substring(0, 157)}...'
        : firstLine;
    try {
      final repository = await resolveTaskRepository(ref.read, workspaceId);
      final task = await createBoardTask(
        repository: repository,
        workspaceId: workspaceId,
        title: title.isEmpty ? 'From the room' : title,
        description: text,
        relatedMessages: [message.id],
        createdBy: 'user',
      );
      if (ref.read(activeWorkspaceIdProvider) == workspaceId) {
        await ref.read(kanbanProvider.notifier).reload();
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Created ${task.id} on the board.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not create the task: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(groupChatsProvider);
    ref.listen<DictationState>(composerDictationProvider, (previous, next) {
      final error = next.errorMessage;
      if (error != null && error != previous?.errorMessage) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error), behavior: SnackBarBehavior.floating),
        );
      }
    });
    final dictation = ref.watch(composerDictationProvider);
    ref.listen<ToolApprovalRequest?>(toolApprovalControllerProvider, (
      previous,
      next,
    ) {
      if (next == null) return;
      unawaited(_askForToolApproval(next));
    });
    final chat = _chat(state);
    if (chat == null) {
      return const Center(child: Text('This room no longer exists.'));
    }
    final notifier = ref.read(groupChatsProvider.notifier);
    final messages = state.snapshot.messagesFor(chat.id);
    final running = state.runningChatIds.contains(chat.id);
    final textTheme = Theme.of(context).textTheme;
    // The pill switches the model this room answers with, and every room shows
    // it: a direct room has exactly one bot and so exactly one answer model,
    // and a group room's own pick outranks its bots' preferences, which is
    // what lets a room speak as one. Picking here is what keeps a model choice
    // for one room from moving a built-in bot in every other room. The pill
    // lists the same models home does — any installed chat model may answer.
    final directBotId = chat.directBotId;
    final bot = directBotId == null
        ? null
        : ref.watch(botsProvider).botById(directBotId);
    final chatModels = ref.watch(chatModelsProvider);
    final selectedModel = ref.watch(selectedChatModelProvider);

    if (messages.isNotEmpty) _scrollDown();

    return Column(
      children: [
        Expanded(
          child: messages.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      chat.isDirect
                          ? 'Say hello — ${chat.name} answers directly.'
                          : 'Say hello with @name to bring a bot in.\n'
                                'Mode: ${chat.mode.label}.',
                      style: textTheme.bodyMedium,
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : ListView(
                  controller: _scrollController,
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  children: [
                    for (final message in messages)
                      ChatBubble(
                        key: ValueKey(message.id),
                        message: roomLineAsMessage(message),
                        authorLabel: message.authorName,
                        extraActions: [
                          if (message.text.trim().isNotEmpty)
                            OutlinedButton.icon(
                              onPressed: () => _createTaskFromMessage(
                                message,
                                chat.workspaceId,
                              ),
                              icon: const Icon(
                                Icons.playlist_add_check_rounded,
                                size: 16,
                              ),
                              label: const Text('Create task'),
                              style: OutlinedButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                foregroundColor: Theme.of(
                                  context,
                                ).colorScheme.primary,
                                side: BorderSide(
                                  color: Theme.of(context).colorScheme.outline,
                                ),
                              ),
                            ),
                        ],
                        below: message.isPending
                            ? _PendingReplyCard(message: message)
                            : null,
                      ),
                  ],
                ),
        ),
        if (running)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 4),
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
            child: ChatComposer(
              controller: _inputController,
              enabled: !running,
              hintText: chat.isDirect
                  ? 'Message ${chat.name}...'
                  : 'Message the room (@name for a bot)...',
              leading: ComposerModelPill(
                models: chatModels,
                selected: roomAnswerModel(
                  chat: chat,
                  bot: bot,
                  installed: chatModels,
                  selected: selectedModel,
                ),
                enabled: !running,
                tooltip: 'Switch model',
                onSelected: (model) => unawaited(
                  notifier.updateChat(chat.copyWith(modelId: model.id)),
                ),
                onCleared: () => unawaited(
                  notifier.updateChat(chat.copyWith(clearModel: true)),
                ),
                onEmptyPressed: () => context.push(AppRoutes.modelSelection),
              ),
              onSend: () => _send(_inputController.text),
              onMicPressed: () => unawaited(
                ref
                    .read(composerDictationProvider.notifier)
                    .toggle(_inputController),
              ),
              micState: dictation.microphone,
            ),
          ),
        ),
      ],
    );
  }
}

/// A room line as the shared bubble reads it.
///
/// The bubble speaks the conversation's language: who spoke, what was said and
/// when. A room keeps its own store — the mapping is for drawing only, so the
/// bot's name lands where home shows the model and nothing is migrated.
Message roomLineAsMessage(GroupMessage line) {
  return Message(
    id: line.id,
    conversationId: line.chatId,
    role: line.isUser ? MessageRole.user : MessageRole.assistant,
    content: line.text,
    createdAt: line.createdAt,
    modelName: line.authorName,
  );
}

/// The room's answer is missing: the user pastes it, or copies the prompt to a
/// model they can reach. Shown inside the bubble that waits for it.
class _PendingReplyCard extends ConsumerStatefulWidget {
  const _PendingReplyCard({required this.message});

  final GroupMessage message;

  @override
  ConsumerState<_PendingReplyCard> createState() => _PendingReplyCardState();
}

class _PendingReplyCardState extends ConsumerState<_PendingReplyCard> {
  final _controller = TextEditingController();
  var _showPrompt = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Waiting for a reply — paste it to continue the room.',
          style: textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _controller,
          minLines: 2,
          maxLines: 4,
          decoration: const InputDecoration(
            hintText: 'Paste the bot reply',
            border: OutlineInputBorder(),
          ),
          textCapitalization: TextCapitalization.sentences,
        ),
        Row(
          children: [
            FilledButton.tonal(
              onPressed: () {
                if (_controller.text.trim().isEmpty) return;
                ref
                    .read(groupChatsProvider.notifier)
                    .answerPending(
                      widget.message.chatId,
                      widget.message.id,
                      _controller.text,
                    );
              },
              child: const Text('Record reply'),
            ),
            TextButton(
              onPressed: () => setState(() => _showPrompt = !_showPrompt),
              child: Text(_showPrompt ? 'Hide prompt' : 'Show prompt'),
            ),
          ],
        ),
        if (_showPrompt && widget.message.pendingPrompt != null)
          SelectableText(
            widget.message.pendingPrompt!,
            style: textTheme.bodySmall,
          ),
      ],
    );
  }
}

/// The room's name where the app bar is, with its members' faces: a room is
/// recognisable by who is in it.
class RoomHeaderTitle extends ConsumerWidget {
  const RoomHeaderTitle({super.key, required this.room});

  final GroupChat room;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bots = ref.watch(botsProvider);
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final faces = [
      for (final id in room.memberBotIds.take(3))
        bots.botById(id)?.icon ?? '🤖',
    ];
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (faces.isNotEmpty) ...[
          SizedBox(
            width: faces.length == 1 ? 24 : 40,
            height: 24,
            child: Stack(
              children: [
                for (var index = 0; index < faces.length; index++)
                  Positioned(
                    left: index * 16.0,
                    child: Text(
                      faces[index],
                      style: const TextStyle(fontSize: 18),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
        ],
        Flexible(
          child: Text(
            room.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurface,
            ),
          ),
        ),
      ],
    );
  }
}

/// Opens the settings for whatever is on screen: a bot's own settings for a
/// direct room, the room's mode, members and rounds for a group room.
Future<void> showRoomSettings(BuildContext context, String chatId) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) => RoomSettingsSheet(chatId: chatId),
  );
}

class RoomSettingsSheet extends ConsumerWidget {
  const RoomSettingsSheet({super.key, required this.chatId});

  final String chatId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(groupChatsProvider);
    GroupChat? chat;
    for (final candidate in state.snapshot.chats) {
      if (candidate.id == chatId) chat = candidate;
    }
    if (chat == null) return const SizedBox();
    final notifier = ref.read(groupChatsProvider.notifier);
    final bots = ref.watch(botsProvider);
    final room = chat;
    final bot = room.directBotId == null
        ? null
        : bots.botById(room.directBotId);

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 32,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Room settings',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            if (room.isDirect) ...[
              Text(
                '${room.name} answers every line here — no @mentions, '
                'no rounds to tune.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (bot != null) ...[
                const SizedBox(height: 12),
                Text(
                  'Bot settings',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                if (bot.description.trim().isNotEmpty)
                  Text(
                    bot.description,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                const SizedBox(height: 4),
                // A template is read-only code; editing it means taking a
                // copy, which is the same rule the roster followed.
                Row(
                  children: [
                    FilledButton.tonalIcon(
                      onPressed: () async {
                        if (!bot.isBuiltIn) {
                          await Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (context) =>
                                  BotEditorPage(botId: bot.id),
                            ),
                          );
                          return;
                        }
                        final copy = await ref
                            .read(botsProvider.notifier)
                            .duplicateTemplate(bot.id);
                        if (copy == null || !context.mounted) return;
                        await Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (context) => BotEditorPage(botId: copy.id),
                          ),
                        );
                      },
                      icon: const Icon(Icons.tune_rounded, size: 18),
                      label: Text(bot.isBuiltIn ? 'Copy to edit' : 'Edit bot'),
                    ),
                  ],
                ),
              ],
            ],
            if (!room.isDirect) ...[
              DropdownButtonFormField<SpeakerMode>(
                initialValue: room.mode,
                decoration: const InputDecoration(
                  labelText: 'Who answers',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final mode in SpeakerMode.values)
                    DropdownMenuItem(value: mode, child: Text(mode.label)),
                ],
                onChanged: (mode) {
                  if (mode != null) {
                    notifier.updateChat(room.copyWith(mode: mode));
                  }
                },
              ),
              const SizedBox(height: 8),
              Text(
                'Manual answers @mentions only. Auto lets a local relevance '
                'vote pick — optional.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              Text('Members', style: Theme.of(context).textTheme.titleSmall),
              for (final candidate in bots.bots)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('${candidate.icon} ${candidate.name}'),
                  value: room.memberBotIds.contains(candidate.id),
                  onChanged: (selected) {
                    final ids = room.memberBotIds.toSet();
                    if (selected == true) {
                      ids.add(candidate.id);
                    } else {
                      ids.remove(candidate.id);
                    }
                    notifier.updateChat(
                      room.copyWith(memberBotIds: ids.toList()),
                    );
                  },
                ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'At most ${room.maxRounds} bot answers per line.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Fewer rounds',
                    icon: const Icon(Icons.remove),
                    onPressed: () => notifier.updateChat(
                      room.copyWith(maxRounds: room.maxRounds - 1),
                    ),
                  ),
                  Text('${room.maxRounds}'),
                  IconButton(
                    tooltip: 'More rounds',
                    icon: const Icon(Icons.add),
                    onPressed: () => notifier.updateChat(
                      room.copyWith(maxRounds: room.maxRounds + 1),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
