import 'package:installm/features/skills/presentation/skill_context_details.dart';
import 'package:installm/features/skills/application/skill_choices.dart';
import 'package:installm/features/skills/application/skills_controller.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:installm/core/navigation/app_router.dart';
import 'package:installm/core/widgets/chat_bubble.dart';
import 'package:installm/core/widgets/composer_model_pill.dart';
import 'package:installm/core/widgets/composer_reasoning_pill.dart';
import 'package:installm/core/widgets/default_bot_avatar.dart';
import 'package:installm/features/bots/application/bots_controller.dart';
import 'package:installm/features/bots/presentation/bot_editor_page.dart';
import 'package:installm/features/conversations/domain/message.dart';
import 'package:installm/features/group_chat/application/group_chat_controller.dart';
import 'package:installm/features/group_chat/application/room_board_service.dart';
import 'package:installm/features/group_chat/domain/group_chat.dart';
import 'package:installm/features/group_chat/presentation/room_mention_composer.dart';
import 'package:installm/features/group_chat/presentation/room_tasks_panel.dart';
import 'package:installm/features/model_selection/presentation/chat_models_provider.dart';
import 'package:installm/features/profile_images/domain/petdex_pet.dart';
import 'package:installm/features/profile_images/presentation/profile_avatar.dart';
import 'package:installm/features/profile_images/presentation/profile_image_picker.dart';
import 'package:installm/features/tools/application/tool_approval_controller.dart';
import 'package:installm/features/tools/application/tool_registry.dart';
import 'package:installm/features/tools/presentation/tool_approval_dialog.dart';
import 'package:installm/features/voice/application/composer_dictation_controller.dart';
import 'package:installm/i18n/strings.g.dart';

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
    GroupChat room,
  ) async {
    final text = message.text.trim();
    if (text.isEmpty) return;
    try {
      final task = await ref
          .read(roomBoardServiceProvider)
          .createFromMessage(room, message);
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
    final bots = ref.watch(botsProvider);
    final skills = ref.watch(skillsProvider);
    final bot = directBotId == null ? null : bots.botById(directBotId);
    final historyOnly = chat.isDirect && bots.isReady && bot == null;
    final chatModels = ref.watch(chatModelsProvider);
    final selectedModel = ref.watch(selectedChatModelProvider);
    // One resolution for the pill and for the reasoning chip beside it: the
    // chip belongs to the model that will answer, not to the room.
    final answerModel = roomAnswerModel(
      chat: chat,
      bot: bot,
      installed: chatModels,
      selected: selectedModel,
    );

    if (messages.isNotEmpty) _scrollDown();

    return Column(
      children: [
        if (!chat.isDirect) RoomTasksPanel(room: chat),
        Expanded(
          child: messages.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      historyOnly
                          ? t.botManagement.emptyHistory
                          : chat.isDirect
                          ? 'Say hello — ${bot?.name ?? chat.name} answers directly.'
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
                              onPressed: () =>
                                  _createTaskFromMessage(message, chat),
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
                        below:
                            message.isPending &&
                                bots.botById(message.authorBotId) != null
                            ? _PendingReplyCard(message: message)
                            : null,
                      ),
                    SkillContextDetails(sessionKey: 'room:${chat.id}'),
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
        if (historyOnly)
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(t.botManagement.unavailable),
            ),
          )
        else
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
              child: RoomMentionComposer(
                commands: SkillCommand.options(
                  skills.isReady
                      ? skills.skills
                            .where(
                              (skill) => chat.memberBotIds.any((id) {
                                final member = bots.botById(id);
                                return member != null &&
                                    eligibleSkill(
                                      skill,
                                      workspaceId: chat.workspaceId,
                                      botId: member.id,
                                      capabilities: member.toolPermissions,
                                      assignedSkillIds: member.skillIds,
                                    );
                              }),
                            )
                            .toList()
                      : const [],
                ),
                members: [
                  for (final id in chat.memberBotIds)
                    ?ref.watch(botsProvider).botById(id),
                ],
                controller: _inputController,
                enabled: !running && bots.isReady,
                hintText: chat.isDirect
                    ? t.skills.botHint(name: bot?.name ?? chat.name)
                    : t.skills.roomHint,
                leading: ComposerModelPill(
                  models: chatModels,
                  selected: answerModel,
                  enabled: !running,
                  tooltip: 'Switch model',
                  onSelected: (model) => unawaited(
                    notifier.updateChat(chat.copyWith(modelId: model.id)),
                  ),
                  onEmptyPressed: () => context.push(AppRoutes.modelSelection),
                ),
                reasoning: ComposerReasoningControl(
                  modelId: answerModel?.id ?? '',
                  enabled: !running,
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
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final members = room.memberBotIds.take(3).toList();
    final fallback = members.isEmpty
        ? const Icon(Icons.forum_outlined, size: 20)
        : SizedBox(
            width: members.length == 1 ? 24 : 56,
            height: 24,
            child: Stack(
              children: [
                for (var index = 0; index < members.length; index++)
                  Positioned(
                    left: index * 16.0,
                    child: ProfileAvatar(
                      profileKey: botProfileKey(members[index]),
                      size: 24,
                    ),
                  ),
              ],
            ),
          );
    final bot = room.isDirect
        ? ref.watch(botsProvider).botById(room.directBotId)
        : null;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ProfileAvatar(
          profileKey: room.isDirect
              ? botProfileKey(room.directBotId!)
              : roomProfileKey(room.id),
          size: room.isDirect ? 28 : 56,
          fallback: room.isDirect ? const DefaultBotAvatar(size: 28) : fallback,
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            bot?.name ?? room.name,
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
  final direct = ProviderScope.containerOf(context, listen: false)
      .read(groupChatsProvider)
      .snapshot
      .chats
      .any((room) => room.id == chatId && room.isDirect);
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: direct,
    constraints: direct ? const BoxConstraints(maxWidth: 552) : null,
    backgroundColor: direct ? Colors.transparent : null,
    elevation: direct ? 0 : null,
    builder: (context) => RoomSettingsSheet(chatId: chatId),
  );
}

class RoomSettingsSheet extends ConsumerWidget {
  const RoomSettingsSheet({super.key, required this.chatId});

  final String chatId;

  Future<void> _clearChat(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t.roomManagement.clearTitle),
        content: Text(t.roomManagement.clearHint),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(t.common.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(t.roomManagement.clear),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final cleared = await ref
        .read(groupChatsProvider.notifier)
        .clearChat(chatId);
    if (!context.mounted) return;
    if (cleared) {
      Navigator.of(context).pop();
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(t.roomManagement.clearError)));
    }
  }

  Future<void> _deleteBot(
    BuildContext context,
    WidgetRef ref,
    String botId,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t.botManagement.deleteTitle),
        content: Text(t.botManagement.deleteHint),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(t.common.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(t.botManagement.delete),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final state = ref.read(groupChatsProvider);
    final running = state.snapshot.chats.any(
      (chat) =>
          state.runningChatIds.contains(chat.id) &&
          (chat.directBotId == botId || chat.memberBotIds.contains(botId)),
    );
    final deleted =
        !running && await ref.read(botsProvider.notifier).removeBot(botId);
    if (!context.mounted) return;
    if (deleted) {
      Navigator.of(context).pop();
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(t.botManagement.deleteError)));
    }
  }

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
    final botRunning =
        bot != null &&
        state.snapshot.chats.any(
          (chat) =>
              state.runningChatIds.contains(chat.id) &&
              (chat.directBotId == bot.id ||
                  chat.memberBotIds.contains(bot.id)),
        );

    if (room.isDirect) {
      final colors = Theme.of(context).colorScheme;
      final text = Theme.of(context).textTheme;
      final profileKey = botProfileKey(room.directBotId!);
      final edit = bot == null
          ? null
          : TextButton(
              onPressed: bots.isReadOnly
                  ? null
                  : () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => BotEditorPage(botId: bot.id),
                      ),
                    ),
              style: TextButton.styleFrom(
                backgroundColor: colors.primary.withValues(alpha: 0.09),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 9,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(9),
                ),
              ),
              child: Text(t.botManagement.edit),
            );
      final identity = Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          ProfileAvatar(profileKey: profileKey, size: 58),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  bot?.name ?? room.name,
                  style: text.titleLarge?.copyWith(fontWeight: FontWeight.w600),
                ),
                TextButton(
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (_) => ProfileImagePicker(profileKey: profileKey),
                  ),
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    alignment: Alignment.centerLeft,
                    textStyle: text.labelLarge,
                  ),
                  child: Text(t.profileImages.change),
                ),
              ],
            ),
          ),
        ],
      );
      return SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            16,
            0,
            16,
            MediaQuery.viewInsetsOf(context).bottom + 16,
          ),
          child: Material(
            color:
                (colors.brightness == Brightness.light
                        ? colors.surfaceContainerLowest
                        : colors.surfaceContainerLow)
                    .withAlpha(255),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(
                color: colors.outlineVariant.withValues(alpha: 0.5),
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          bot == null && bots.isReady
                              ? t.roomManagement.chatSettings
                              : t.botManagement.settings,
                          style: text.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: t.common.close,
                        onPressed: () => Navigator.of(context).pop(),
                        color: colors.onSurfaceVariant,
                        icon: const Icon(Icons.close, size: 20),
                      ),
                    ],
                  ),
                  const SizedBox(height: 22),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final stack =
                          constraints.maxWidth <
                          MediaQuery.textScalerOf(context).scale(310);
                      if (edit == null) return identity;
                      if (stack) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            identity,
                            const SizedBox(height: 8),
                            Align(
                              alignment: Alignment.centerRight,
                              child: edit,
                            ),
                          ],
                        );
                      }
                      return Row(
                        children: [
                          Expanded(child: identity),
                          const SizedBox(width: 14),
                          edit,
                        ],
                      );
                    },
                  ),
                  if (bot == null && bots.isReady) ...[
                    const SizedBox(height: 12),
                    Text(t.botManagement.unavailable, style: text.bodySmall),
                  ],
                  const SizedBox(height: 28),
                  RoomTasksPanel(
                    room: room,
                    compact: true,
                    onOpenBoard: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(height: 22),
                  Text(
                    t.common.manage,
                    style: text.labelSmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 6),
                  _SettingsActionRow(
                    title: t.roomManagement.clear,
                    description: bot == null
                        ? t.roomManagement.clearSavedSummary
                        : t.roomManagement.clearSummary,
                    onPressed:
                        state.isReadOnly ||
                            state.runningChatIds.contains(room.id)
                        ? null
                        : () => _clearChat(context, ref),
                  ),
                  if (bot != null)
                    _SettingsActionRow(
                      title: t.botManagement.delete,
                      description: t.botManagement.deleteSummary,
                      destructive: true,
                      onPressed: bots.isReadOnly || botRunning
                          ? null
                          : () => _deleteBot(context, ref, bot.id),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
    }

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
            Row(
              children: [
                Expanded(
                  child: Text(
                    bot != null
                        ? t.botManagement.settings
                        : room.isDirect
                        ? t.roomManagement.chatSettings
                        : t.roomManagement.settings,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ProfileImageButton(
              profileKey: room.isDirect
                  ? botProfileKey(room.directBotId!)
                  : roomProfileKey(room.id),
              fallback: room.isDirect ? null : const Icon(Icons.forum_outlined),
            ),
            const SizedBox(height: 12),
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
                  secondary: ProfileAvatar(
                    profileKey: botProfileKey(candidate.id),
                  ),
                  title: Text(candidate.name),
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
            const SizedBox(height: 24),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed:
                      state.isReadOnly || state.runningChatIds.contains(room.id)
                      ? null
                      : () => _clearChat(context, ref),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.error,
                    side: BorderSide(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                  icon: const Icon(Icons.cleaning_services_outlined),
                  label: Text(t.roomManagement.clear),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsActionRow extends StatelessWidget {
  const _SettingsActionRow({
    required this.title,
    required this.description,
    required this.onPressed,
    this.destructive = false,
  });

  final String title;
  final String description;
  final VoidCallback? onPressed;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Semantics(
      button: true,
      enabled: onPressed != null,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(9),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: text.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                        color: onPressed == null
                            ? colors.onSurface.withValues(alpha: 0.38)
                            : destructive
                            ? colors.error
                            : colors.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      description,
                      style: text.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Icon(
                Icons.chevron_right,
                size: 20,
                color: colors.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
