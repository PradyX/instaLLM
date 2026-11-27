import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:installm/core/github_star/star_prompt.dart';
import 'package:installm/core/navigation/app_router.dart';
import 'package:installm/core/navigation/navigation_panel_widgets.dart';
import 'package:installm/core/theme/appearance_surfaces.dart';
import 'package:installm/core/widgets/llm_chip_icon.dart';
import 'package:installm/core/widgets/name_prompt_dialog.dart';
import 'package:installm/features/bots/application/bots_controller.dart';
import 'package:installm/features/bots/presentation/create_bot_dialog.dart';
import 'package:installm/features/bots/domain/bot.dart';
import 'package:installm/features/conversations/domain/conversation.dart';
import 'package:installm/features/conversations/presentation/conversation_controller.dart';
import 'package:installm/features/group_chat/application/active_room.dart';
import 'package:installm/features/group_chat/application/group_chat_controller.dart';
import 'package:installm/features/group_chat/data/group_chat_store.dart';
import 'package:installm/features/group_chat/domain/group_chat.dart';
import 'package:installm/features/model_selection/presentation/model_selection_controller.dart';
import 'package:installm/features/personas/application/personas_controller.dart';
import 'package:installm/features/profile_images/domain/petdex_pet.dart';
import 'package:installm/features/profile_images/application/profile_images_controller.dart';
import 'package:installm/features/profile_images/presentation/profile_avatar.dart';
import 'package:installm/features/workspaces/application/workspaces_controller.dart';
import 'package:installm/i18n/strings.g.dart';

/// Which top-level surface the sidebar highlights.
enum AppSection { companion, chats, bots, rooms, more }

/// Which list the navigation panel shows under its Chats and Bots tabs.
enum _NavigationTab { chats, bots }

/// Lets an owning page protect unsaved work before shell actions replace it.
class ShellNavigationGuard extends InheritedWidget {
  const ShellNavigationGuard({
    super.key,
    required this.canLeave,
    required super.child,
  });
  final Future<bool> Function() canLeave;

  static Future<bool>? check(BuildContext context) =>
      context.getInheritedWidgetOfExactType<ShellNavigationGuard>()?.canLeave();

  @override
  bool updateShouldNotify(ShellNavigationGuard oldWidget) =>
      canLeave != oldWidget.canLeave;
}

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
    return Padding(
      // The same 8 px side margin the tabs and chat rows use, so the search
      // card, the tab strip and the list share one left and right edge.
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
      child: Material(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.only(right: 4),
          child: Row(
            children: [
              Expanded(child: _ChatSearchField()),
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'New chat',
                onPressed: isGenerating
                    ? null
                    : () async {
                        final leave = ShellNavigationGuard.check(context);
                        if (leave != null && !await leave || !context.mounted) {
                          return;
                        }
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
                style: IconButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.primary,
                ),
              ),
            ],
          ),
        ),
      ),
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
      style: Theme.of(context).textTheme.bodySmall,
      onChanged: (value) => ref
          .read(conversationControllerProvider.notifier)
          .setSearchQuery(value),
      decoration: InputDecoration(
        hintText: t.navigation.searchChats,
        hintMaxLines: 1,
        prefixIcon: const Icon(Icons.search, size: 18),
        prefixIconConstraints: const BoxConstraints(
          minWidth: 40,
          minHeight: 40,
        ),
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

/// Fixture data for the panel's lists, used by widget tests only.
///
/// Nothing in the app supplies it, so real chats, bots and rooms are never
/// replaced by test data at runtime.
@visibleForTesting
class NavigationPanelFixture {
  const NavigationPanelFixture({
    this.chats,
    this.bots,
    this.rooms,
    this.onCreateBot,
    this.onCreateRoom,
    this.onOpenChat,
    this.onOpenBot,
    this.onOpenRoom,
  });

  final List<ConversationSummary>? chats;
  final List<Bot>? bots;
  final List<GroupChat>? rooms;
  final VoidCallback? onCreateBot;
  final VoidCallback? onCreateRoom;
  final void Function(ConversationSummary)? onOpenChat;
  final void Function(Bot)? onOpenBot;
  final void Function(GroupChat)? onOpenRoom;
}

/// One layout and one set of actions for the docked rail and modal drawer.
class AppNavigationPanel extends ConsumerStatefulWidget {
  const AppNavigationPanel({
    super.key,
    required this.section,
    this.leading,
    this.isGenerating = false,
    this.onNavigate,
    this.fixture,
  });

  final AppSection section;
  final Widget? leading;
  final bool isGenerating;
  final VoidCallback? onNavigate;

  /// Test-only data and callbacks, so widget tests can drive the real panel
  /// with empty and long lists without touching stored chats, bots or rooms.
  @visibleForTesting
  final NavigationPanelFixture? fixture;

  @override
  ConsumerState<AppNavigationPanel> createState() => _AppNavigationPanelState();
}

class _AppNavigationPanelState extends ConsumerState<AppNavigationPanel> {
  _NavigationTab? _pickedTab;

  @override
  Widget build(BuildContext context) {
    final section = widget.section;
    final leading = widget.leading;
    final isGenerating = widget.isGenerating;
    final onNavigate = widget.onNavigate;
    final fixture = widget.fixture;
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final workspace = ref.watch(workspacesProvider).active;
    // Opening a bot or room switches to the tab that owns it, until the user
    // picks a tab themselves.
    final tab =
        _pickedTab ??
        (section == AppSection.bots || section == AppSection.rooms
            ? _NavigationTab.bots
            : _NavigationTab.chats);
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
    return FrostedPanel(
      child: Container(
        width: AppShell.railWidth,
        decoration: BoxDecoration(
          border: Border(
            right: BorderSide(
              color: colorScheme.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
        ),
        child: Material(
          color: appearanceSurfaceColor(
            context,
            colorScheme.surfaceContainerLow,
          ),
          child: ListTileTheme.merge(
            style: ListTileStyle.list,
            child: SafeArea(
              minimum: EdgeInsets.only(
                bottom: MediaQuery.viewInsetsOf(context).bottom,
              ),
              child: Column(
                children: [
                  Expanded(
                    child: CustomScrollView(
                      slivers: [
                        SliverList.list(
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(
                                16,
                                16,
                                16,
                                16,
                              ),
                              child: _WorkspacePicker(
                                onManage: () => navigate(AppRoutes.workspaces),
                                enabled: !isGenerating,
                                child: Row(
                                  children: [
                                    Image.asset(
                                      'assets/icons/installm.png',
                                      width: 34,
                                      height: 34,
                                      fit: BoxFit.contain,
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'InstaLLM',
                                            style: textTheme.titleSmall
                                                ?.copyWith(
                                                  fontWeight: FontWeight.bold,
                                                ),
                                          ),
                                          Text(
                                            workspace?.name ??
                                                t.navigation.noWorkspace,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: textTheme.labelSmall
                                                ?.copyWith(
                                                  color: colorScheme
                                                      .onSurfaceVariant,
                                                ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Icon(
                                      Icons.keyboard_arrow_down_rounded,
                                      size: 18,
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                              child: LayoutBuilder(
                                builder: (context, constraints) {
                                  const gap = 8.0;
                                  final scale =
                                      MediaQuery.textScalerOf(
                                        context,
                                      ).scale(12) /
                                      12;
                                  final columns =
                                      ((constraints.maxWidth + gap) /
                                              (72 * scale + gap))
                                          .floor()
                                          .clamp(1, 3);
                                  final width =
                                      (constraints.maxWidth -
                                          gap * (columns - 1)) /
                                      columns;
                                  return Wrap(
                                    spacing: gap,
                                    runSpacing: gap,
                                    children: [
                                      for (final (icon, label, route) in [
                                        (
                                          const LlmChipIcon(),
                                          t.navigation.models,
                                          AppRoutes.modelSelection,
                                        ),
                                        (
                                          const Icon(Icons.speed_outlined),
                                          t.navigation.benchmark,
                                          AppRoutes.benchmark,
                                        ),
                                        (
                                          const NavigationSettingsIcon(),
                                          t.navigation.settings,
                                          AppRoutes.settings,
                                        ),
                                      ])
                                        SizedBox(
                                          width: width,
                                          child: NavigationShortcutTile(
                                            icon: icon,
                                            label: label,
                                            onPressed: () => navigate(route),
                                          ),
                                        ),
                                    ],
                                  );
                                },
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
                              child: NavigationVoiceEntry(
                                key: const ValueKey('navigation-companion'),
                                selected: section == AppSection.companion,
                                onPressed: () => navigate(AppRoutes.companion),
                              ),
                            ),
                            leading ??
                                ShellChatLeading(
                                  isGenerating: isGenerating,
                                  onNavigate: onNavigate,
                                ),
                          ],
                        ),
                        // The tabs stay pinned: a long chat or bot list scrolls
                        // under them instead of carrying them off screen.
                        SliverPersistentHeader(
                          pinned: true,
                          delegate: _NavigationTabsHeader(
                            background: colorScheme.surfaceContainerLow,
                            child: _NavigationTabs(
                              tab: tab,
                              onChanged: (next) =>
                                  setState(() => _pickedTab = next),
                            ),
                          ),
                        ),
                        SliverList.list(
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (tab == _NavigationTab.chats) ...[
                                    _ChatRows(
                                      current: section == AppSection.chats,
                                      isGenerating: isGenerating,
                                      onOpened: onNavigate,
                                      summaries: fixture?.chats,
                                      onSelect: fixture?.onOpenChat,
                                      onSeeAll: () =>
                                          navigate(AppRoutes.conversations),
                                    ),
                                  ] else ...[
                                    _sectionHeader(
                                      context,
                                      label: t.navigation.bots,
                                      onCreate:
                                          fixture?.onCreateBot ??
                                          () => _createBot(
                                            actionContext,
                                            ref,
                                            onCreated: onNavigate,
                                          ),
                                      createTooltip: 'New bot',
                                    ),
                                    BotChatRows(
                                      workspaceId: workspace?.id,
                                      onOpened: onNavigate,
                                      bots: fixture?.bots,
                                      onOpenBot: fixture?.onOpenBot,
                                    ),
                                    _sectionHeader(
                                      context,
                                      label: t.navigation.rooms,
                                      onCreate:
                                          fixture?.onCreateRoom ??
                                          (workspace == null
                                              ? null
                                              : () => _createRoom(
                                                  actionContext,
                                                  ref,
                                                  workspace.id,
                                                  onCreated: onNavigate,
                                                )),
                                      createTooltip: 'New room',
                                    ),
                                    RoomChatRows(
                                      workspaceId: workspace?.id,
                                      onOpened: onNavigate,
                                      rooms: fixture?.rooms,
                                      bots: fixture?.bots,
                                      onOpenRoom: fixture?.onOpenRoom,
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  _CommunityDock(
                    onStar: () => unawaited(openGitHubRepository()),
                    onSponsor: () => unawaited(openSponsorPage()),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The rail's two optional community actions, pinned under the chat list.
///
/// Pinned rather than scrolled: a long list of chats must not push them out of
/// reach, and a hairline-joined pair reads as one quiet place instead of two
/// competing buttons. Neither opens anything inside the app — both hand off to
/// the browser, so nothing is sent from here.
class _CommunityDock extends StatelessWidget {
  const _CommunityDock({required this.onStar, required this.onSponsor});

  final VoidCallback onStar;
  final VoidCallback onSponsor;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
      child: Material(
        color: appearanceSurfaceColor(context, colors.surfaceContainerHigh),
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _CommunityDockAction(
              icon: Icons.star_outline_rounded,
              label: 'Star this project on GitHub',
              onPressed: onStar,
            ),
            Divider(
              height: 1,
              thickness: 1,
              color: colors.outlineVariant.withValues(alpha: 0.5),
            ),
            _CommunityDockAction(
              icon: Icons.favorite_border_rounded,
              label: 'Sponsor this project',
              onPressed: onSponsor,
            ),
          ],
        ),
      ),
    );
  }
}

class _CommunityDockAction extends StatelessWidget {
  const _CommunityDockAction({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Semantics(
      button: true,
      label: label,
      child: InkWell(
        onTap: onPressed,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              children: [
                Icon(icon, size: 17, color: colors.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: 12,
                      letterSpacing: 0,
                      color: colors.onSurface,
                    ),
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

typedef _WorkspaceMenuChoice = ({String? id, bool manage});

class _WorkspacePicker extends ConsumerWidget {
  const _WorkspacePicker({
    required this.onManage,
    required this.enabled,
    required this.child,
  });

  final VoidCallback onManage;
  final bool enabled;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(workspacesProvider);
    return PopupMenuButton<_WorkspaceMenuChoice>(
      key: const ValueKey('workspace-picker'),
      tooltip: t.navigation.switchWorkspace,
      enabled: enabled && state.isReady,
      onSelected: (choice) async {
        if (choice.manage) {
          onManage();
          return;
        }
        await ref.read(workspacesProvider.notifier).setActive(choice.id);
        if (!context.mounted) return;
        final error = ref.read(workspacesProvider).errorMessage;
        if (error != null) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(error)));
        }
      },
      itemBuilder: (context) => [
        for (final workspace in state.workspaces)
          PopupMenuItem<_WorkspaceMenuChoice>(
            value: (id: workspace.id, manage: false),
            enabled: !state.isReadOnly,
            child: Row(
              children: [
                Icon(
                  state.active?.id == workspace.id
                      ? Icons.check_rounded
                      : Icons.folder_outlined,
                  size: 18,
                ),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    workspace.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        PopupMenuItem<_WorkspaceMenuChoice>(
          value: (id: null, manage: true),
          child: Text(t.navigation.manageWorkspaces),
        ),
      ],
      child: child,
    );
  }
}

/// How many recent chats the sidebar lists before "See all".
///
/// Pinned chats are not counted against it: they are listed because the user
/// pinned them, and this caps only the chats underneath. The sidebar is for the
/// chats in play, not the whole archive — "See all" opens the Conversations
/// page, which owns the full list and its management.
const int sidebarRecentChatCount = 30;

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

/// Pinned chats and the thirty most recent 1:1 chats; the rest stay behind
/// "See all", which opens the Conversations page.
class _ChatRows extends ConsumerWidget {
  const _ChatRows({
    required this.current,
    required this.isGenerating,
    this.onOpened,
    this.summaries,
    this.onSelect,
    this.onSeeAll,
  });

  final bool current;
  final bool isGenerating;
  final VoidCallback? onOpened;

  /// Test fixture: replaces the stored conversations when present.
  final List<ConversationSummary>? summaries;
  final void Function(ConversationSummary)? onSelect;
  final VoidCallback? onSeeAll;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // A fixture keeps the test off the stored conversations entirely.
    final state = summaries == null
        ? ref.watch(conversationControllerProvider)
        : null;
    final shown = sidebarChatSummaries(summaries ?? state!.visibleSummaries);
    final activeId = state?.activeConversationId;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (shown.isEmpty)
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
          for (final summary in shown)
            NavigationChatTile(
              key: ValueKey('conversation-${summary.conversation.id}'),
              selected: current && activeId == summary.conversation.id,
              leading: Icon(
                summary.conversation.isPinned
                    ? Icons.push_pin_outlined
                    : Icons.chat_bubble_outline,
                size: 18,
              ),
              title: summary.conversation.title,
              onPressed: isGenerating
                  ? null
                  : () async {
                      if (onSelect != null) {
                        onSelect!(summary);
                        return;
                      }
                      final leave = ShellNavigationGuard.check(context);
                      if (leave != null && !await leave || !context.mounted) {
                        return;
                      }
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
        if (shown.isNotEmpty && onSeeAll != null)
          Align(
            alignment: Alignment.center,
            child: TextButton(
              onPressed: onSeeAll,
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.primary,
                textStyle: Theme.of(context).textTheme.labelMedium,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(t.navigation.seeAll),
            ),
          ),
      ],
    );
  }
}

/// Creates a bot from the complete draft, then opens its chat.
///
/// This replaces the roster page that used to own creation — the sidebar is
/// the bot list now, and a bot's chat is a chat on the app's chat page.
Future<void> _createBot(
  BuildContext context,
  WidgetRef ref, {
  VoidCallback? onCreated,
}) async {
  final leave = ShellNavigationGuard.check(context);
  if (leave != null && !await leave || !context.mounted) return;
  final bots = ref.read(botsProvider.notifier);
  final profiles = ref.read(profileImagesProvider.notifier);
  final chats = ref.read(groupChatsProvider.notifier);
  final workspaceId = ref.read(workspacesProvider).active?.id;
  final selection = ref.read(activeRoomIdProvider.notifier);
  final router = GoRouter.of(context);
  // Resizing replaces the page Scaffold and its drawer, but the sheet's
  // Navigator and the application controllers still own the creation draft.
  final navigator = Navigator.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final draft = await showCreateBotSheet(context);
  if (draft == null || !navigator.mounted) return;
  final bot = await bots.createBot(
    draft.name,
    templateId: draft.templateId,
    soul: draft.soul,
  );
  if (!navigator.mounted) return;
  if (bot == null) {
    messenger.showSnackBar(SnackBar(content: Text(t.botCreation.saveError)));
    return;
  }
  if (draft.portrait != null) {
    final saved = await profiles.select(botProfileKey(bot.id), draft.portrait);
    if (!navigator.mounted) return;
    if (!saved) {
      messenger.showSnackBar(
        SnackBar(content: Text(t.profileImages.saveError)),
      );
    }
  }
  if (workspaceId != null) {
    final chat = await chats.directChatWith(
      workspaceId: workspaceId,
      botId: bot.id,
    );
    if (!navigator.mounted) return;
    if (chat != null) {
      selection.select(chat.id);
    } else {
      messenger.showSnackBar(SnackBar(content: Text(t.botCreation.chatError)));
    }
  }
  onCreated?.call();
  router.go(AppRoutes.home);
}

/// Creates a room in [workspaceId] and opens it on the chat page.
Future<void> _createRoom(
  BuildContext context,
  WidgetRef ref,
  String workspaceId, {
  VoidCallback? onCreated,
}) async {
  final leave = ShellNavigationGuard.check(context);
  if (leave != null && !await leave || !context.mounted) return;
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
  activeRoom.select(room.id);
  onCreated?.call();
  context.go(AppRoutes.home);
}

/// Every bot with its 1:1 room selection; tapping lands in that same room, on
/// the app's chat page.
class BotChatRows extends ConsumerWidget {
  const BotChatRows({
    super.key,
    required this.workspaceId,
    this.onOpened,
    this.bots,
    this.onOpenBot,
  });

  final String? workspaceId;

  /// Called after a bot's chat opens; the drawer closes itself with it.
  final VoidCallback? onOpened;

  /// Test fixture: replaces the stored bots when present.
  final List<Bot>? bots;
  final void Function(Bot)? onOpenBot;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(botsProvider);
    final rooms = ref.watch(groupChatsProvider);
    final colorScheme = Theme.of(context).colorScheme;
    final listed = bots ?? state.bots;
    if (bots == null && !state.isReady) return const SizedBox();
    if (listed.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Text(t.botCreation.empty),
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final bot in listed)
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
    final needsYou = direct != null && roomNeedsUser(snapshot, direct.id);
    return NavigationChatTile(
      key: ValueKey('bot-${bot.id}'),
      selected: direct != null && ref.watch(activeRoomIdProvider) == direct.id,
      leading: Stack(
        children: [
          ProfileAvatar(profileKey: botProfileKey(bot.id), size: 24),
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
      title: bot.name,
      onPressed: onOpenBot != null
          ? () => onOpenBot!(bot)
          : workspaceId == null
          ? null
          : () async {
              final leave = ShellNavigationGuard.check(context);
              if (leave != null && !await leave || !context.mounted) {
                return;
              }
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

/// Group rooms of the active workspace with selection and needs-you badges.
class RoomChatRows extends ConsumerWidget {
  const RoomChatRows({
    super.key,
    required this.workspaceId,
    this.onOpened,
    this.rooms,
    this.bots,
    this.onOpenRoom,
  });

  final String? workspaceId;

  /// Called after a room opens; the drawer closes itself with it.
  final VoidCallback? onOpened;

  /// Test fixture: replaces the stored rooms and bots when present.
  final List<GroupChat>? rooms;
  final List<Bot>? bots;
  final void Function(GroupChat)? onOpenRoom;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(groupChatsProvider);
    final colorScheme = Theme.of(context).colorScheme;
    final activeId = ref.watch(activeRoomIdProvider);
    final botState = ref.watch(botsProvider);
    final listed = [
      for (final chat in rooms ?? state.snapshot.chats)
        if (chat.workspaceId == workspaceId &&
            (!chat.isDirect ||
                (bots != null
                    ? !bots!.any((bot) => bot.id == chat.directBotId)
                    : botState.isReady &&
                          botState.botById(chat.directBotId) == null)))
          chat,
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (listed.isEmpty)
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
          for (final chat in listed)
            NavigationChatTile(
              key: ValueKey('room-${chat.id}'),
              selected: activeId == chat.id,
              leading: ProfileAvatar(
                profileKey: chat.isDirect
                    ? botProfileKey(chat.directBotId!)
                    : roomProfileKey(chat.id),
                fallback: chat.isDirect
                    ? const Icon(Icons.history_rounded)
                    : _memberStack(chat, colorScheme),
                size: 24,
              ),
              title: chat.name,
              trailing: chat.isDirect
                  ? Tooltip(
                      message: t.botManagement.historyOnly,
                      child: const Icon(Icons.history_rounded, size: 16),
                    )
                  : roomNeedsUser(state.snapshot, chat.id)
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
              onPressed: onOpenRoom != null
                  ? () => onOpenRoom!(chat)
                  : () async {
                      final leave = ShellNavigationGuard.check(context);
                      if (leave != null && !await leave || !context.mounted) {
                        return;
                      }
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
}

/// Keeps [child] (the Chats/Bots tabs) at the top while the lists scroll.
class _NavigationTabsHeader extends SliverPersistentHeaderDelegate {
  _NavigationTabsHeader({required this.child, required this.background});

  final Widget child;
  final Color background;

  static const double _extent = 48;

  @override
  double get minExtent => _extent;

  @override
  double get maxExtent => _extent;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    // On the glass panel the rail behind this header is already one layer of
    // [background]; painting another full-strength layer on top of it came out
    // as an opaque, whiter band across the panel. The pinned bar is a blur with
    // a light tint instead, so it hides rows scrolling under it and still
    // carries the panel's colour.
    return FrostedPanel(
      child: ColoredBox(
        color: usesTranslucentSurfaces(context)
            ? background.withValues(alpha: 0.35)
            : background,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
          child: child,
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(_NavigationTabsHeader oldDelegate) =>
      oldDelegate.child != child || oldDelegate.background != background;
}

/// Chats and Bots, the two lists the panel shows, one at a time.
class _NavigationTabs extends StatelessWidget {
  const _NavigationTabs({required this.tab, required this.onChanged});

  final _NavigationTab tab;
  final ValueChanged<_NavigationTab> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Container(
      height: 36,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: appearanceSurfaceColor(context, colors.surfaceContainerHigh),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          for (final (value, label) in [
            (_NavigationTab.chats, t.navigation.chats),
            (_NavigationTab.bots, t.navigation.bots),
          ])
            Expanded(
              child: Material(
                // The selected tab is a wash of the accent rather than a light
                // chip: every near-white fill (surface, then the panel colour)
                // still read as a white block on the glass panel, where
                // everything else shows the tint behind it.
                color: tab == value
                    ? colors.primary.withValues(alpha: 0.16)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => onChanged(value),
                  child: Center(
                    child: Text(
                      label,
                      style: textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: tab == value
                            ? colors.primary
                            : colors.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
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
    padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
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
                textStyle: Theme.of(context).textTheme.labelSmall,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(t.navigation.seeAll),
            ),
        ],
      ),
    ),
  );
}
