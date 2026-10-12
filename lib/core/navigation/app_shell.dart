import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pocket_llm/core/navigation/app_router.dart';
import 'package:pocket_llm/core/widgets/name_prompt_dialog.dart';
import 'package:pocket_llm/features/bots/application/bots_controller.dart';
import 'package:pocket_llm/features/bots/presentation/bot_editor_page.dart';
import 'package:pocket_llm/features/bots/domain/bot.dart';
import 'package:pocket_llm/features/conversations/domain/conversation.dart';
import 'package:pocket_llm/features/conversations/presentation/conversation_controller.dart';
import 'package:pocket_llm/features/group_chat/application/active_room.dart';
import 'package:pocket_llm/features/group_chat/application/group_chat_controller.dart';
import 'package:pocket_llm/features/group_chat/data/group_chat_store.dart';
import 'package:pocket_llm/features/group_chat/domain/group_chat.dart';
import 'package:pocket_llm/features/kanban/application/kanban_controller.dart';
import 'package:pocket_llm/features/model_selection/presentation/model_selection_controller.dart';
import 'package:pocket_llm/features/personas/application/personas_controller.dart';
import 'package:pocket_llm/features/profile_images/domain/petdex_pet.dart';
import 'package:pocket_llm/features/profile_images/presentation/profile_avatar.dart';
import 'package:pocket_llm/features/workspaces/application/workspaces_controller.dart';

/// Which top-level surface the sidebar highlights.
enum AppSection { chats, bots, rooms, board, more }

/// The shared desk: a Hermes-style left sidebar beside every top-level
/// surface, so bots, rooms and the board live one tap away instead of
/// buried in Settings.
///
/// Wide screens (>= 900px) dock [AppNavigationPanel]; narrow pages use
/// [AppNavigationDrawer] to present that same panel from their hamburger.
/// [leading] optionally overrides the shared new-chat and search controls.
class AppShell extends ConsumerWidget {
  const AppShell({
    super.key,
    required this.section,
    required this.child,
    this.leading,
    this.isGenerating = false,
  });

  final AppSection section;
  final Widget child;
  final Widget? leading;

  /// True while an answer generates; chat switching pauses, like home.
  final bool isGenerating;

  static const double wideBreakpoint = 900;
  static const double railWidth = 280;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (MediaQuery.of(context).size.width < wideBreakpoint) return child;
    return Row(
      children: [
        AppNavigationPanel(
          section: section,
          leading: leading,
          isGenerating: isGenerating,
        ),
        Expanded(child: child),
      ],
    );
  }
}

/// The shared navigation content presented as a modal drawer on narrow screens.
class AppNavigationDrawer extends StatelessWidget {
  const AppNavigationDrawer({
    super.key,
    required this.section,
    this.isGenerating = false,
  });

  final AppSection section;
  final bool isGenerating;

  @override
  Widget build(BuildContext context) => Drawer(
    width: AppShell.railWidth,
    child: AppNavigationPanel(
      section: section,
      isGenerating: isGenerating,
      onNavigate: () {
        if (context.mounted) Scaffold.maybeOf(context)?.closeDrawer();
      },
    ),
  );
}

/// New chat and search belong to the shared panel in either presentation.
class ShellChatLeading extends ConsumerWidget {
  const ShellChatLeading({
    super.key,
    required this.isGenerating,
    this.onNavigate,
  });

  final bool isGenerating;
  final VoidCallback? onNavigate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: FilledButton.icon(
            onPressed: isGenerating
                ? null
                : () async {
                    final router = GoRouter.of(context);
                    final controller = ref.read(
                      conversationControllerProvider.notifier,
                    );
                    final modelId = ref
                        .read(modelSelectionControllerProvider)
                        .selectedModelId;
                    final personaId = ref
                        .read(personasProvider)
                        .defaultPersonaId;
                    showConversation(ref);
                    controller.setSearchQuery('');
                    onNavigate?.call();
                    await controller.createConversation(
                      activeModelId: modelId,
                      personaId: personaId,
                    );
                    router.go(AppRoutes.home);
                  },
            icon: const Icon(Icons.add, size: 18),
            label: const Text('New chat'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(40),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: _ChatSearchField(),
        ),
      ],
    );
  }
}

/// The query is shared state, so reopening the drawer or resizing preserves
/// both the list filter and what the search field displays.
class _ChatSearchField extends ConsumerStatefulWidget {
  @override
  ConsumerState<_ChatSearchField> createState() => _ChatSearchFieldState();
}

class _ChatSearchFieldState extends ConsumerState<_ChatSearchField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: ref.read(conversationControllerProvider).searchQuery,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<String>(
      conversationControllerProvider.select((state) => state.searchQuery),
      (_, query) {
        if (_controller.text != query) {
          _controller.value = TextEditingValue(
            text: query,
            selection: TextSelection.collapsed(offset: query.length),
          );
        }
      },
    );
    final colorScheme = Theme.of(context).colorScheme;
    return TextField(
      controller: _controller,
      onChanged: (value) => ref
          .read(conversationControllerProvider.notifier)
          .setSearchQuery(value),
      decoration: InputDecoration(
        hintText: 'Search chats',
        prefixIcon: const Icon(Icons.search, size: 18),
        isDense: true,
        filled: true,
        fillColor: colorScheme.surfaceContainerHighest,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}

/// One layout and one set of actions for the docked rail and modal drawer.
class AppNavigationPanel extends ConsumerWidget {
  const AppNavigationPanel({
    super.key,
    required this.section,
    this.leading,
    this.isGenerating = false,
    this.onNavigate,
  });

  final AppSection section;
  final Widget? leading;
  final bool isGenerating;
  final VoidCallback? onNavigate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final workspace = ref.watch(workspacesProvider).active;
    // Drawer content is disposed after closing. Dialogs/routes use the owning
    // Scaffold's context so their work can finish after the drawer is gone.
    final actionContext = onNavigate == null
        ? context
        : Scaffold.of(context).context;
    void navigate(String route) {
      onNavigate?.call();
      actionContext.push(route);
    }

    // The shell sits above each page's Scaffold, so no page Material covers
    // this rail: this Material paints the background and hosts every ink
    // response (header, tiles) below it.
    return Container(
      width: AppShell.railWidth,
      decoration: BoxDecoration(
        border: Border(
          right: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
      ),
      child: Material(
        color: colorScheme.surfaceContainerLow,
        child: ListTileTheme.merge(
          style: ListTileStyle.list,
          child: SafeArea(
            minimum: EdgeInsets.only(
              bottom: MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                InkWell(
                  onTap: () => navigate(AppRoutes.workspaces),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: colorScheme.primary,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(6),
                            child: Image.asset(
                              'assets/icons/pocketllm_new.png',
                              fit: BoxFit.contain,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Pocket LLM',
                                style: textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                workspace?.name ?? 'No workspace',
                                style: textTheme.labelSmall?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.swap_horiz_rounded, size: 18),
                      ],
                    ),
                  ),
                ),
                leading ??
                    ShellChatLeading(
                      isGenerating: isGenerating,
                      onNavigate: onNavigate,
                    ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _sectionHeader(
                        context,
                        label: 'Chats',
                        onSeeMore: () => navigate(AppRoutes.conversations),
                      ),
                      _ChatRows(
                        current: section == AppSection.chats,
                        isGenerating: isGenerating,
                        onOpened: onNavigate,
                      ),
                      _sectionHeader(
                        context,
                        label: 'Bots',
                        onCreate: () => _createBot(
                          actionContext,
                          ref,
                          onCreated: onNavigate,
                        ),
                        createTooltip: 'New bot',
                      ),
                      BotChatRows(
                        workspaceId: workspace?.id,
                        onOpened: onNavigate,
                      ),
                      _sectionHeader(
                        context,
                        label: 'Rooms',
                        onCreate: workspace == null
                            ? null
                            : () => _createRoom(
                                actionContext,
                                ref,
                                workspace.id,
                                onCreated: onNavigate,
                              ),
                        createTooltip: 'New room',
                      ),
                      RoomChatRows(
                        workspaceId: workspace?.id,
                        onOpened: onNavigate,
                      ),
                      _sectionLabel(context, 'Board'),
                      _BoardTile(
                        current: section == AppSection.board,
                        onOpened: onNavigate,
                      ),
                      _sectionLabel(context, 'More'),
                      _navTile(
                        context,
                        icon: Icons.smart_toy_outlined,
                        label: 'Models',
                        route: AppRoutes.modelSelection,
                        onOpened: onNavigate,
                      ),
                      _navTile(
                        context,
                        icon: Icons.settings_outlined,
                        label: 'Settings',
                        route: AppRoutes.settings,
                        onOpened: onNavigate,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// How many recent chats the sidebar lists before "See more".
///
/// Pinned chats are not counted against it: they are listed because the user
/// pinned them, and this caps only the chats underneath. The sidebar is for the
/// chats in play, not the whole archive — "See more" opens the Conversations
/// page, which owns the full list and its management.
const int sidebarRecentChatCount = 5;

/// The chats the sidebar lists: every pinned chat, then the most recent
/// [sidebarRecentChatCount] of the rest, keeping the order [ordered] already
/// has — pinned first, each group newest first, as
/// [ConversationListState.visibleSummaries] returns it.
List<ConversationSummary> sidebarChatSummaries(
  List<ConversationSummary> ordered,
) {
  final shown = <ConversationSummary>[];
  var recent = 0;
  for (final summary in ordered) {
    if (summary.conversation.isPinned) {
      shown.add(summary);
    } else if (recent < sidebarRecentChatCount) {
      shown.add(summary);
      recent++;
    }
  }
  return shown;
}

/// Pinned chats and the five most recent 1:1 chats; the rest stay behind "See
/// more", which opens the Conversations page.
class _ChatRows extends ConsumerWidget {
  const _ChatRows({
    required this.current,
    required this.isGenerating,
    this.onOpened,
  });

  final bool current;
  final bool isGenerating;
  final VoidCallback? onOpened;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(conversationControllerProvider);
    final summaries = sidebarChatSummaries(state.visibleSummaries);
    final activeId = state.activeConversationId;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (summaries.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'No conversations yet.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          )
        else
          for (final summary in summaries)
            ListTile(
              dense: true,
              selected: current && activeId == summary.conversation.id,
              selectedTileColor: Theme.of(
                context,
              ).colorScheme.primaryContainer.withValues(alpha: 0.5),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              leading: Icon(
                summary.conversation.isPinned
                    ? Icons.push_pin_outlined
                    : Icons.chat_bubble_outline,
                size: 18,
              ),
              title: Text(
                summary.conversation.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                summary.lastMessagePreview.isEmpty
                    ? 'No messages yet'
                    : summary.lastMessagePreview,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              onTap: isGenerating
                  ? null
                  : () {
                      // A conversation is what the page shows when no room is
                      // open, so choosing one here also leaves the room.
                      showConversation(ref);
                      ref
                          .read(conversationControllerProvider.notifier)
                          .openConversation(summary.conversation.id);
                      if (!current) context.go(AppRoutes.home);
                      onOpened?.call();
                    },
            ),
      ],
    );
  }
}

/// Creates a bot, then opens its editor: a new bot is shaped before it is
/// talked to, and it appears in the Bots section from then on.
///
/// This replaces the roster page that used to own creation — the sidebar is
/// the bot list now, and a bot's chat is a chat on the app's chat page.
Future<void> _createBot(
  BuildContext context,
  WidgetRef ref, {
  VoidCallback? onCreated,
}) async {
  final bots = ref.read(botsProvider.notifier);
  final name = await NamePromptDialog.show(
    context,
    title: 'New bot',
    hintText: 'Bot name',
    confirmLabel: 'Create',
  );
  if (name == null || name.trim().isEmpty || !context.mounted) return;
  final bot = await bots.createBot(name.trim());
  if (bot == null || !context.mounted) return;
  onCreated?.call();
  await Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (context) => BotEditorPage(botId: bot.id)),
  );
}

/// Creates a room in [workspaceId] and opens it on the chat page.
Future<void> _createRoom(
  BuildContext context,
  WidgetRef ref,
  String workspaceId, {
  VoidCallback? onCreated,
}) async {
  final rooms = ref.read(groupChatsProvider.notifier);
  final activeRoom = ref.read(activeRoomIdProvider.notifier);
  final name = await NamePromptDialog.show(
    context,
    title: 'New group chat',
    hintText: 'Room name',
    confirmLabel: 'Create',
  );
  if (name == null || name.trim().isEmpty || !context.mounted) return;
  final room = await rooms.createChat(
    workspaceId: workspaceId,
    name: name.trim(),
  );
  if (room == null || !context.mounted) return;
  activeRoom.state = room.id;
  onCreated?.call();
  context.go(AppRoutes.home);
}

/// Every bot with its 1:1 room preview; tapping lands in that same room, on
/// the app's chat page.
class BotChatRows extends ConsumerWidget {
  const BotChatRows({super.key, required this.workspaceId, this.onOpened});

  final String? workspaceId;

  /// Called after a bot's chat opens; the drawer closes itself with it.
  final VoidCallback? onOpened;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bots = ref.watch(botsProvider);
    final rooms = ref.watch(groupChatsProvider);
    final colorScheme = Theme.of(context).colorScheme;
    if (!bots.isReady) return const SizedBox();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final bot in bots.bots)
          _botTile(context, ref, rooms.snapshot, bot, colorScheme),
      ],
    );
  }

  Widget _botTile(
    BuildContext context,
    WidgetRef ref,
    GroupChatsSnapshot snapshot,
    Bot bot,
    ColorScheme colorScheme,
  ) {
    GroupChat? direct;
    for (final chat in snapshot.chats) {
      if (chat.workspaceId == workspaceId && chat.directBotId == bot.id) {
        direct = chat;
      }
    }
    final lines = direct == null
        ? const <GroupMessage>[]
        : snapshot.messagesFor(direct.id);
    final preview = lines.isEmpty
        ? (bot.description.isEmpty ? 'Say hello' : bot.description)
        : lines.last.text;
    final needsYou = direct != null && roomNeedsUser(snapshot, direct.id);
    return ListTile(
      dense: true,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      leading: Stack(
        children: [
          ProfileAvatar(profileKey: botProfileKey(bot.id)),
          if (needsYou)
            Positioned(
              right: 0,
              top: 0,
              child: Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: colorScheme.error,
                  shape: BoxShape.circle,
                ),
              ),
            ),
        ],
      ),
      title: Text(bot.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(preview, maxLines: 1, overflow: TextOverflow.ellipsis),
      onTap: workspaceId == null
          ? null
          : () async {
              final chat = await ref
                  .read(groupChatsProvider.notifier)
                  .directChatWith(workspaceId: workspaceId!, botId: bot.id);
              if (chat == null || !context.mounted) return;
              // A bot's chat is the app's chat page, not a page of its own.
              showRoom(ref, chat.id);
              onOpened?.call();
              context.go(AppRoutes.home);
            },
    );
  }
}

/// Group rooms of the active workspace with previews and needs-you badges.
class RoomChatRows extends ConsumerWidget {
  const RoomChatRows({super.key, required this.workspaceId, this.onOpened});

  final String? workspaceId;

  /// Called after a room opens; the drawer closes itself with it.
  final VoidCallback? onOpened;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(groupChatsProvider);
    final colorScheme = Theme.of(context).colorScheme;
    final rooms = [
      for (final chat in state.snapshot.chats)
        if (!chat.isDirect && chat.workspaceId == workspaceId) chat,
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (rooms.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'No rooms yet.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          )
        else
          for (final chat in rooms)
            ListTile(
              dense: true,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              leading: ProfileAvatar(
                profileKey: roomProfileKey(chat.id),
                fallback: _memberStack(chat, colorScheme),
              ),
              title: Text(
                chat.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: _roomPreview(state.snapshot, chat),
              trailing: roomNeedsUser(state.snapshot, chat.id)
                  ? Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: colorScheme.error,
                        shape: BoxShape.circle,
                      ),
                    )
                  : Text(
                      '${chat.memberBotIds.length}',
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
              onTap: () {
                showRoom(ref, chat.id);
                onOpened?.call();
                context.go(AppRoutes.home);
              },
            ),
      ],
    );
  }

  Widget _memberStack(GroupChat chat, ColorScheme colorScheme) {
    final members = chat.memberBotIds.take(2).toList();
    Widget face(String id, double size) =>
        ProfileAvatar(profileKey: botProfileKey(id), size: size);
    if (members.isEmpty) {
      return const Icon(Icons.forum_outlined, size: 20);
    }
    if (members.length == 1) {
      return face(members.first, 28);
    }
    return SizedBox(
      width: 32,
      height: 32,
      child: Stack(
        children: [
          face(members[0], 24),
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerLow,
                shape: BoxShape.circle,
              ),
              child: face(members[1], 20),
            ),
          ),
        ],
      ),
    );
  }

  Widget _roomPreview(GroupChatsSnapshot snapshot, GroupChat chat) {
    final lines = snapshot.messagesFor(chat.id);
    final text = lines.isEmpty ? '${chat.mode.label} mode' : lines.last.text;
    return Text(text, maxLines: 1, overflow: TextOverflow.ellipsis);
  }
}

/// The board with its open-task count.
class _BoardTile extends ConsumerWidget {
  const _BoardTile({required this.current, this.onOpened});

  final bool current;
  final VoidCallback? onOpened;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final board = ref.watch(kanbanProvider);
    final open = board.tasks.where((task) => !task.isDone).length;
    return ListTile(
      dense: true,
      selected: current,
      selectedTileColor: Theme.of(
        context,
      ).colorScheme.primaryContainer.withValues(alpha: 0.5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      leading: const Icon(Icons.view_kanban_outlined, size: 18),
      title: const Text('Board'),
      subtitle: !board.isReady ? null : Text('$open open'),
      onTap: () {
        onOpened?.call();
        context.push(AppRoutes.kanban);
      },
    );
  }
}

/// Section header: a create action where a section owns its contents, and
/// "See more" where a fuller page does.
///
/// Bots and rooms are created here because there is no separate roster page to
/// create them on: the sidebar is the list, and tapping a row opens that chat
/// on the app's one chat page.
Widget _sectionHeader(
  BuildContext context, {
  required String label,
  VoidCallback? onSeeMore,
  VoidCallback? onCreate,
  String createTooltip = 'New',
}) {
  final colorScheme = Theme.of(context).colorScheme;
  return Padding(
    padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
    child: SizedBox(
      width: double.infinity,
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            label.toUpperCase(),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.bold,
              letterSpacing: 0.08,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          if (onCreate != null)
            IconButton(
              tooltip: createTooltip,
              onPressed: onCreate,
              icon: const Icon(Icons.add_rounded, size: 18),
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              color: colorScheme.primary,
            ),
          if (onSeeMore != null)
            TextButton(
              onPressed: onSeeMore,
              style: TextButton.styleFrom(
                foregroundColor: colorScheme.primary,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('See more'),
            ),
        ],
      ),
    ),
  );
}

Widget _sectionLabel(BuildContext context, String label) {
  return Padding(
    padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
    child: Text(
      label.toUpperCase(),
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        fontWeight: FontWeight.bold,
        letterSpacing: 0.08,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    ),
  );
}

Widget _navTile(
  BuildContext context, {
  required IconData icon,
  required String label,
  required String route,
  VoidCallback? onOpened,
}) {
  return ListTile(
    dense: true,
    leading: Icon(icon, size: 18),
    title: Text(label),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    onTap: () {
      onOpened?.call();
      context.push(route);
    },
  );
}
