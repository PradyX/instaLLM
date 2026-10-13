import 'package:pocket_llm/features/kanban/data/task_repository.dart';
import 'package:pocket_llm/features/kanban/domain/task.dart';

final _pendingEdits = Expando<Map<String, Future<void>>>();

/// Serialize edits shared by the board, rooms and bot tools, loading the latest
/// tasks inside the queue so one action cannot overwrite another's change.
Future<T> editBoardTasks<T>(
  TaskRepository repository,
  String workspaceId,
  Future<(List<ProjectTask>, T)> Function(List<ProjectTask>) edit,
) {
  final queue = _pendingEdits[repository] ??= {};
  final previous = queue[workspaceId] ?? Future<void>.value();
  final result = previous.then((_) async {
    final tasks = await repository.load(workspaceId);
    final (next, value) = await edit(tasks);
    await repository.save(workspaceId, next);
    return value;
  });
  queue[workspaceId] = result.then<void>(
    (_) {},
    onError: (Object _, StackTrace _) {},
  );
  return result;
}

Future<ProjectTask> createBoardTask({
  required TaskRepository repository,
  required String workspaceId,
  required String title,
  String description = '',
  TaskPriority priority = TaskPriority.medium,
  List<String> relatedMessages = const [],
  List<String> relatedRoomIds = const [],
  String? createdBy,
}) => editBoardTasks(repository, workspaceId, (tasks) async {
  final number = await repository.nextNumber(workspaceId) ?? 1;
  var candidate = 'PL-${number.toString().padLeft(3, '0')}';
  final taken = {for (final task in tasks) task.id};
  while (taken.contains(candidate)) {
    final next = int.parse(candidate.substring(3)) + 1;
    candidate = 'PL-${next.toString().padLeft(3, '0')}';
  }
  final task = ProjectTask.create(
    id: candidate,
    workspaceId: workspaceId,
    title: title,
    description: description,
    priority: priority,
    createdBy: createdBy,
  ).copyWith(relatedMessages: relatedMessages, relatedRoomIds: relatedRoomIds);
  return ([...tasks, task], task);
});

Future<ProjectTask> updateBoardTask({
  required TaskRepository repository,
  required String workspaceId,
  required String taskId,
  required ProjectTask Function(ProjectTask) update,
}) => editBoardTasks(repository, workspaceId, (tasks) async {
  final index = tasks.indexWhere((task) => task.id == taskId);
  if (index < 0) throw StateError('There is no task $taskId on this board.');
  final updated = update(tasks[index]);
  return ([...tasks]..[index] = updated, updated);
});
