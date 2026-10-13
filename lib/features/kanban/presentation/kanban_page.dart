import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:installm/core/navigation/app_shell.dart';
import 'package:installm/core/widgets/name_prompt_dialog.dart';
import 'package:installm/i18n/strings.g.dart';
import 'package:installm/features/bots/application/bots_controller.dart';
import 'package:installm/features/group_chat/application/group_chat_controller.dart';
import 'package:go_router/go_router.dart';
import 'package:installm/core/navigation/app_router.dart';
import 'package:installm/features/group_chat/application/active_room.dart';
import 'package:installm/features/kanban/application/kanban_controller.dart';
import 'package:installm/features/kanban/domain/task.dart';
import 'package:installm/features/workspaces/application/workspaces_controller.dart';

/// The project board: six columns, tap to move, assign and comment.
///
/// Road Map 2 Phase 2.6. Bots operate the same board through the controller;
/// every move and assignment is also an activity event, so the board's
/// history does not depend on reading chat.
class KanbanPage extends ConsumerWidget {
  const KanbanPage({super.key});

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final title = await NamePromptDialog.show(
      context,
      title: 'New task',
      hintText: 'What needs doing?',
      confirmLabel: 'Create',
    );
    if (title == null || title.trim().isEmpty || !context.mounted) return;
    await ref
        .read(kanbanProvider.notifier)
        .createTask(title: title.trim(), createdBy: 'user');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(kanbanProvider);
    final workspaces = ref.watch(workspacesProvider);
    final active = workspaces.active;
    final isWide = MediaQuery.sizeOf(context).width >= AppShell.wideBreakpoint;

    return AppShell(
      section: AppSection.board,
      child: Scaffold(
        appBar: AppBar(
          title: Text(active == null ? 'Board' : '${active.name} board'),
          leading: isWide
              ? null
              : Builder(
                  builder: (context) => IconButton(
                    tooltip: 'Menu',
                    icon: const Icon(Icons.menu_rounded),
                    onPressed: () => Scaffold.of(context).openDrawer(),
                  ),
                ),
          actions: [
            IconButton(
              tooltip: 'Reload',
              icon: const Icon(Icons.refresh),
              onPressed: () => ref.read(kanbanProvider.notifier).reload(),
            ),
          ],
        ),
        drawer: isWide
            ? null
            : const AppNavigationDrawer(section: AppSection.board),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: active == null ? null : () => _create(context, ref),
          icon: const Icon(Icons.add),
          label: const Text('New task'),
        ),
        body: active == null
            ? const Center(child: Text('No workspace selected.'))
            : !state.isReady
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  if (state.usesVault)
                    const Padding(
                      padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
                      child: Row(
                        children: [
                          Icon(Icons.folder_open, size: 16),
                          SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Stored as vault notes under Tasks/',
                              style: TextStyle(fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                  Expanded(
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.all(12),
                      children: [
                        for (final status in TaskStatus.values)
                          _Column(status: status),
                      ],
                    ),
                  ),
                  if (state.errorMessage != null)
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text(
                        state.errorMessage!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}

class _Column extends ConsumerWidget {
  const _Column({required this.status});

  final TaskStatus status;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasks = ref.watch(
      kanbanProvider.select((state) => state.inStatus(status)),
    );
    final textTheme = Theme.of(context).textTheme;
    return Container(
      width: 280,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      child: Card(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  '${status.label} (${tasks.length})',
                  style: textTheme.titleSmall,
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: tasks.isEmpty
                    ? const SizedBox()
                    : ListView(
                        children: [for (final task in tasks) _Card(task: task)],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Card extends ConsumerWidget {
  const _Card({required this.task});

  final ProjectTask task;

  String _botLabel(String? botId, WidgetRef ref) {
    if (botId == null) return 'Unassigned';
    final bot = ref.watch(botsProvider).botById(botId);
    return bot?.name ?? botId;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final blocked =
        !task.unblockedBy(ref.watch(kanbanProvider).byId) && !task.isDone;
    return Card(
      child: ListTile(
        title: Text(task.title, maxLines: 3, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          '${task.id} · ${_botLabel(task.assignedBotId, ref)}'
          '${blocked ? ' · waiting on dependencies' : ''}',
        ),
        trailing: switch (task.priority) {
          TaskPriority.urgent => const Icon(Icons.priority_high),
          TaskPriority.high => const Icon(Icons.arrow_upward),
          TaskPriority.low => const Icon(Icons.arrow_downward),
          TaskPriority.medium => null,
        },
        onTap: () => showBoardTaskDetails(context, ref, task.id),
      ),
    );
  }
}

/// Navigation happens using the owning page after the sheet is removed.
Future<void> showBoardTaskDetails(
  BuildContext context,
  WidgetRef ref,
  String taskId,
) async {
  final roomSelection = ref.read(activeRoomIdProvider.notifier);
  final router = GoRouter.of(context);
  final roomId = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _TaskSheet(taskId: taskId),
  );
  if (!context.mounted || roomId == null) return;
  roomSelection.state = roomId;
  router.go(AppRoutes.home);
}

class _TaskSheet extends ConsumerStatefulWidget {
  const _TaskSheet({required this.taskId});

  final String taskId;

  @override
  ConsumerState<_TaskSheet> createState() => _TaskSheetState();
}

class _TaskSheetState extends ConsumerState<_TaskSheet> {
  final _commentController = TextEditingController();
  var _openingRoom = false;

  Future<void> _discuss(ProjectTask task) async {
    setState(() => _openingRoom = true);
    try {
      final id = await ref
          .read(groupChatsProvider.notifier)
          .discussTaskInRoom(task);
      if (!mounted) return;
      if (id == null) throw StateError(t.roomBoard.openError);
      Navigator.of(context).pop(id);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${t.roomBoard.openError}: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _openingRoom = false);
    }
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final board = ref.watch(kanbanProvider);
    final task = board.byId[widget.taskId];
    if (task == null) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Text('This task no longer exists.'),
      );
    }
    final notifier = ref.read(kanbanProvider.notifier);
    final bots = ref.watch(botsProvider);
    final textTheme = Theme.of(context).textTheme;
    final linkedRooms = ref
        .watch(groupChatsProvider)
        .chatsFor(task.workspaceId)
        .where((room) => task.relatedRoomIds.contains(room.id))
        .toList();

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
              '${task.id} · ${task.status.label}',
              style: textTheme.bodySmall,
            ),
            Text(task.title, style: textTheme.titleMedium),
            if (task.description.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(task.description),
            ],
            const SizedBox(height: 12),
            DropdownButtonFormField<TaskStatus>(
              key: ValueKey('${task.id}:${task.status.key}'),
              initialValue: task.status,
              decoration: const InputDecoration(
                labelText: 'Status',
                border: OutlineInputBorder(),
              ),
              items: [
                for (final status in TaskStatus.values)
                  DropdownMenuItem(value: status, child: Text(status.label)),
              ],
              onChanged: (status) {
                if (status != null) notifier.moveTask(task.id, status);
              },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String?>(
              initialValue: task.assignedBotId,
              decoration: const InputDecoration(
                labelText: 'Assignee',
                border: OutlineInputBorder(),
              ),
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('Unassigned'),
                ),
                if (task.assignedBotId != null &&
                    bots.botById(task.assignedBotId) == null)
                  DropdownMenuItem<String?>(
                    value: task.assignedBotId,
                    enabled: false,
                    child: Text(t.botManagement.unavailableAssignee),
                  ),
                for (final bot in bots.bots)
                  DropdownMenuItem<String?>(
                    value: bot.id,
                    child: Text('${bot.icon} ${bot.name}'),
                  ),
              ],
              onChanged: (botId) => notifier.assignTask(task.id, botId),
            ),
            if (task.dependencies.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Depends on: ${task.dependencies.join(', ')}',
                style: textTheme.bodySmall,
              ),
            ],
            if (task.relatedDocuments.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                'Documents: ${task.relatedDocuments.join(', ')}',
                style: textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 12),
            if (linkedRooms.isNotEmpty) ...[
              Text(t.roomBoard.linkedRooms, style: textTheme.titleSmall),
              Wrap(
                spacing: 8,
                children: [
                  for (final room in linkedRooms)
                    TextButton.icon(
                      onPressed: () => Navigator.of(context).pop(room.id),
                      icon: const Icon(Icons.forum_outlined),
                      label: Text(room.name),
                    ),
                ],
              ),
            ],
            Text('Activity', style: textTheme.titleSmall),
            for (final comment in task.comments)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  '${comment.author}: ${comment.text}',
                  style: textTheme.bodySmall,
                ),
              ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _commentController,
                    decoration: const InputDecoration(
                      hintText: 'Add a comment',
                    ),
                    textCapitalization: TextCapitalization.sentences,
                  ),
                ),
                IconButton(
                  tooltip: 'Add comment',
                  icon: const Icon(Icons.send),
                  onPressed: () {
                    notifier.addComment(
                      task.id,
                      'user',
                      _commentController.text,
                    );
                    _commentController.clear();
                  },
                ),
              ],
            ),
            Wrap(
              spacing: 12,
              children: [
                FilledButton.tonalIcon(
                  onPressed: _openingRoom ? null : () => _discuss(task),
                  icon: const Icon(Icons.forum_outlined),
                  label: Text(
                    linkedRooms.isEmpty
                        ? t.roomBoard.discuss
                        : t.roomBoard.openRoom,
                  ),
                ),
                TextButton.icon(
                  onPressed: () {
                    notifier.deleteTask(task.id);
                    Navigator.of(context).pop();
                  },
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Delete'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
