import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:installm/features/group_chat/domain/group_chat.dart';
import 'package:installm/features/kanban/application/board_task_operations.dart';
import 'package:installm/features/kanban/application/kanban_controller.dart';
import 'package:installm/features/kanban/domain/task.dart';

final roomBoardServiceProvider = Provider((ref) => RoomBoardService(ref));

/// Only explicit user actions change a room's task links or status.
class RoomBoardService {
  const RoomBoardService(this._ref);
  final Ref _ref;

  Future<void> _refresh(String workspaceId) async {
    if (_ref.read(activeWorkspaceIdProvider) == workspaceId) {
      await _ref.read(kanbanProvider.notifier).reload();
    }
    _ref.invalidate(workspaceTasksProvider(workspaceId));
  }

  Future<ProjectTask> createFromMessage(
    GroupChat room,
    GroupMessage message,
  ) async {
    if (message.chatId != room.id) {
      throw ArgumentError('The message belongs to another room.');
    }
    final text = message.text.trim();
    if (text.isEmpty) throw ArgumentError('The message is empty.');
    final firstLine = text.split('\n').first.trim();
    final repository = await resolveTaskRepository(_ref.read, room.workspaceId);
    final task = await createBoardTask(
      repository: repository,
      workspaceId: room.workspaceId,
      title: firstLine.length > 160
          ? '${firstLine.substring(0, 157)}...'
          : firstLine,
      description: text,
      relatedMessages: [message.id],
      relatedRoomIds: [room.id],
      createdBy: 'user',
    );
    await _refresh(room.workspaceId);
    return task;
  }

  Future<void> linkTask(GroupChat room, String taskId) async {
    final repository = await resolveTaskRepository(_ref.read, room.workspaceId);
    await updateBoardTask(
      repository: repository,
      workspaceId: room.workspaceId,
      taskId: taskId,
      update: (task) => task.relatedRoomIds.contains(room.id)
          ? task
          : task.copyWith(
              relatedRoomIds: [...task.relatedRoomIds, room.id],
              comments: [
                ...task.comments,
                TaskComment(
                  author: 'user',
                  text: 'Linked room ${room.name}.',
                  createdAt: DateTime.now(),
                ),
              ],
            ),
    );
    await _refresh(room.workspaceId);
  }

  Future<void> moveTask(
    GroupChat room,
    String taskId,
    TaskStatus status,
  ) async {
    final repository = await resolveTaskRepository(_ref.read, room.workspaceId);
    await updateBoardTask(
      repository: repository,
      workspaceId: room.workspaceId,
      taskId: taskId,
      update: (task) => task.copyWith(
        status: status,
        relatedRoomIds: {...task.relatedRoomIds, room.id}.toList(),
      ),
    );
    await _refresh(room.workspaceId);
  }
}
