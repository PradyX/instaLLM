import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:installm/core/navigation/app_router.dart';
import 'package:installm/features/group_chat/application/group_chat_controller.dart';
import 'package:installm/features/group_chat/application/room_board_service.dart';
import 'package:installm/features/group_chat/domain/group_chat.dart';
import 'package:installm/features/kanban/application/kanban_controller.dart';
import 'package:installm/features/kanban/domain/task.dart';
import 'package:installm/features/kanban/presentation/kanban_page.dart';
import 'package:installm/features/workspaces/application/workspaces_controller.dart';
import 'package:installm/i18n/strings.g.dart';

class RoomTasksPanel extends ConsumerStatefulWidget {
  const RoomTasksPanel({
    super.key,
    required this.room,
    this.onOpenBoard,
    this.compact = false,
  });
  final GroupChat room;
  final VoidCallback? onOpenBoard;
  final bool compact;

  @override
  ConsumerState<RoomTasksPanel> createState() => _RoomTasksPanelState();
}

class _RoomTasksPanelState extends ConsumerState<RoomTasksPanel> {
  final _busy = <String>{};
  bool _expanded = false;

  Future<void> _openBoard() async {
    final router = GoRouter.of(context);
    if (await _activateWorkspace() && mounted) {
      widget.onOpenBoard?.call();
      router.go(AppRoutes.kanban);
    }
  }

  Future<void> _change(String key, Future<void> Function() action) async {
    if (_busy.contains(key)) return;
    setState(() => _busy.add(key));
    try {
      await action();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${t.roomBoard.saveError}: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy.remove(key));
    }
  }

  Future<bool> _activateWorkspace() async {
    if (ref.read(activeWorkspaceIdProvider) == widget.room.workspaceId) {
      return true;
    }
    await ref
        .read(workspacesProvider.notifier)
        .setActive(widget.room.workspaceId);
    return mounted &&
        ref.read(activeWorkspaceIdProvider) == widget.room.workspaceId;
  }

  Future<void> _link(List<ProjectTask> candidates) async {
    final id = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t.roomBoard.linkTask),
        content: SizedBox(
          width: 420,
          child: candidates.isEmpty
              ? Text(t.roomBoard.noTasks)
              : ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 360),
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final task in candidates)
                        ListTile(
                          title: Text(task.title),
                          subtitle: Text('${task.id} · ${task.status.label}'),
                          onTap: () => Navigator.of(context).pop(task.id),
                        ),
                    ],
                  ),
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(t.common.cancel),
          ),
        ],
      ),
    );
    if (id == null || !mounted) return;
    await _change(
      'link',
      () => ref.read(roomBoardServiceProvider).linkTask(widget.room, id),
    );
  }

  @override
  Widget build(BuildContext context) {
    final room = widget.room;
    final data = ref.watch(workspaceTasksProvider(room.workspaceId));
    final messageIds = ref
        .watch(groupChatsProvider)
        .snapshot
        .messagesFor(room.id)
        .map((message) => message.id)
        .toSet();
    final all = data.valueOrNull ?? const <ProjectTask>[];
    final linked = all
        .where(
          (task) =>
              task.relatedRoomIds.contains(room.id) ||
              task.relatedMessages.any(messageIds.contains),
        )
        .toList();
    final contents = <Widget>[
      if (data.isLoading && !data.hasValue) const LinearProgressIndicator(),
      if (data.hasError)
        Padding(
          padding: const EdgeInsets.all(8),
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(t.roomBoard.loadError),
              TextButton(
                onPressed: () {
                  ref.invalidate(workspaceTasksProvider(room.workspaceId));
                  if (ref.read(activeWorkspaceIdProvider) == room.workspaceId) {
                    ref.read(kanbanProvider.notifier).reload();
                  }
                },
                child: Text(t.profileImages.retry),
              ),
            ],
          ),
        ),
      if (linked.isNotEmpty)
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 200),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            children: [
              for (final task in linked)
                Padding(
                  key: ValueKey('room-task-${task.id}'),
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextButton(
                          style: TextButton.styleFrom(
                            alignment: Alignment.centerLeft,
                          ),
                          onPressed: () async {
                            if (await _activateWorkspace() && context.mounted) {
                              await ref.read(kanbanProvider.notifier).reload();
                              if (context.mounted) {
                                await showBoardTaskDetails(
                                  context,
                                  ref,
                                  task.id,
                                );
                              }
                            }
                          },
                          child: Text(
                            '${task.id} · ${task.title}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      PopupMenuButton<TaskStatus>(
                        key: ValueKey('room-task-status-${task.id}'),
                        tooltip: t.roomBoard.changeStatus,
                        enabled: !_busy.contains(task.id) && !data.hasError,
                        initialValue: task.status,
                        onSelected: (status) => _change(
                          task.id,
                          () => ref
                              .read(roomBoardServiceProvider)
                              .moveTask(room, task.id, status),
                        ),
                        itemBuilder: (_) => [
                          for (final status in TaskStatus.values)
                            PopupMenuItem(
                              value: status,
                              child: Text(status.label),
                            ),
                        ],
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                task.status.label,
                                style: Theme.of(context).textTheme.labelMedium,
                              ),
                              const Icon(Icons.expand_more, size: 16),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
    ];
    final onLink = !data.hasValue || data.hasError || _busy.contains('link')
        ? null
        : () => _link(all.where((task) => !linked.contains(task)).toList());
    if (widget.compact) {
      final colors = Theme.of(context).colorScheme;
      final text = Theme.of(context).textTheme;
      final toggle = TextButton(
        onPressed: () => setState(() => _expanded = !_expanded),
        style: TextButton.styleFrom(
          foregroundColor: colors.onSurface,
          padding: EdgeInsets.zero,
          alignment: Alignment.centerLeft,
        ),
        child: Semantics(
          expanded: _expanded,
          child: Wrap(
            spacing: 9,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                t.roomBoard.linkedTasks,
                style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
              ),
              Text(
                '${linked.length}',
                style: text.bodySmall?.copyWith(color: colors.onSurfaceVariant),
              ),
            ],
          ),
        ),
      );
      final link = Tooltip(
        message: t.roomBoard.linkTask,
        child: TextButton.icon(
          onPressed: onLink,
          style: TextButton.styleFrom(padding: EdgeInsets.zero),
          icon: const Icon(Icons.add, size: 16),
          label: Text(t.roomBoard.linkTask),
        ),
      );
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Divider(
            height: 1,
            color: colors.outlineVariant.withValues(alpha: 0.5),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth <
                    MediaQuery.textScalerOf(context).scale(290)) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      toggle,
                      Align(alignment: Alignment.centerRight, child: link),
                    ],
                  );
                }
                return Row(
                  children: [
                    Expanded(child: toggle),
                    const SizedBox(width: 12),
                    link,
                  ],
                );
              },
            ),
          ),
          Divider(
            height: 1,
            color: colors.outlineVariant.withValues(alpha: 0.5),
          ),
          if (_expanded) ...[
            const SizedBox(height: 12),
            if (linked.isEmpty && data.hasValue && !data.hasError)
              Text(
                t.roomBoard.emptyLinkedTasks,
                style: text.bodySmall?.copyWith(color: colors.onSurfaceVariant),
              ),
            ...contents,
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: _openBoard,
                child: Text(t.roomBoard.openBoard),
              ),
            ),
          ],
        ],
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Card(
        margin: EdgeInsets.zero,
        child: ExpansionTile(
          key: PageStorageKey('room-tasks-${room.id}'),
          initiallyExpanded: true,
          title: Text(
            '${t.roomBoard.linkedTasks} (${linked.length})',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          leading: IconButton(
            tooltip: t.roomBoard.openBoard,
            icon: const Icon(Icons.view_kanban_outlined),
            onPressed: _openBoard,
          ),
          trailing: IconButton(
            tooltip: t.roomBoard.linkTask,
            icon: const Icon(Icons.add_link),
            onPressed: onLink,
          ),
          children: contents,
        ),
      ),
    );
  }
}
