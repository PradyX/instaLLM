import 'package:pocket_llm/features/kanban/data/task_repository.dart';
import 'package:pocket_llm/features/kanban/domain/task.dart';
import 'package:pocket_llm/features/kanban/application/board_task_operations.dart';
export 'package:pocket_llm/features/kanban/application/board_task_operations.dart'
    show createBoardTask;
import 'package:pocket_llm/features/tools/application/tool_registry.dart';
import 'package:pocket_llm/features/tools/domain/tool_definition.dart';

/// What a board-bound tool call needs. Resolved per call so the tools work
/// for whatever workspace the run belongs to — never just the active one.
class KanbanToolContext {
  const KanbanToolContext({
    required this.workspaceId,
    required this.repositoryFor,
    this.actorName = 'bot',
    this.onBoardChanged,
    this.roomId,
  });

  final String workspaceId;
  final String? roomId;

  /// Opens the task repository the workspace currently boards from (vault
  /// notes when linked, the local store otherwise).
  final Future<TaskRepository> Function(String workspaceId) repositoryFor;

  /// Name recorded on comments.
  final String actorName;

  /// Runs after a tool saves, so an open board can refresh. Null in tests.
  final Future<void> Function()? onBoardChanged;
}

/// Native board tools, so a bot can work the Kanban from chat or a room —
/// the Hermes `kanban_create` flow, through the same registry, validation
/// and permission gates as every other tool.
///
/// Listing is read-only; creating and moving change the shared board, so
/// they run as sensitive and the user is asked first.
List<ToolEntry> buildKanbanTools(KanbanToolContext context) {
  return [
    ToolEntry(
      definition: const ToolDefinition(
        name: 'kanban_list_tasks',
        description:
            'Lists this workspace\u2019s board tasks with their ids, titles, '
            'statuses and assignees.',
        risk: ToolRiskLevel.readOnly,
        parameters: [],
      ),
      handler: (arguments) => _listTasks(context),
    ),
    ToolEntry(
      definition: const ToolDefinition(
        name: 'kanban_create_task',
        description:
            'Creates a board task in this workspace and returns its PL id. '
            'Use it when the user asks to track work, or when a plan needs '
            'tasks before anything is implemented.',
        risk: ToolRiskLevel.sensitive,
        parameters: [
          ToolParameter(
            name: 'title',
            type: ToolParameterType.string,
            description: 'Short task title.',
            maxLength: 160,
          ),
          ToolParameter(
            name: 'description',
            type: ToolParameterType.string,
            description: 'What the task involves.',
            required: false,
            maxLength: 2000,
          ),
        ],
      ),
      handler: (arguments) => _createTask(
        context,
        title: arguments['title'] as String,
        description: (arguments['description'] as String?) ?? '',
      ),
    ),
    ToolEntry(
      definition: const ToolDefinition(
        name: 'kanban_move_task',
        description:
            'Moves a board task to another status: backlog, todo, '
            'in-progress, review, blocked or done.',
        risk: ToolRiskLevel.sensitive,
        parameters: [
          ToolParameter(
            name: 'taskId',
            type: ToolParameterType.string,
            description: 'The PL id, for example PL-001.',
            maxLength: 32,
          ),
          ToolParameter(
            name: 'status',
            type: ToolParameterType.string,
            description: 'Target status.',
            allowedValues: [
              'backlog',
              'todo',
              'in-progress',
              'review',
              'blocked',
              'done',
            ],
          ),
        ],
      ),
      handler: (arguments) => _moveTask(
        context,
        taskId: arguments['taskId'] as String,
        status: TaskStatus.fromKey(arguments['status'] as String),
      ),
    ),
  ];
}

Future<String> _listTasks(KanbanToolContext context) async {
  final repository = await context.repositoryFor(context.workspaceId);
  final tasks = await repository.load(context.workspaceId);
  if (tasks.isEmpty) return 'The board is empty.';
  return [
    for (final task in tasks)
      '${task.id} [${task.status.key}] ${task.title}'
          '${task.assignedBotId == null ? '' : ' (assignee: ${task.assignedBotId})'}',
  ].join('\n');
}

Future<String> _createTask(
  KanbanToolContext context, {
  required String title,
  required String description,
}) async {
  final repository = await context.repositoryFor(context.workspaceId);
  final task = await createBoardTask(
    repository: repository,
    workspaceId: context.workspaceId,
    title: title,
    description: description,
    createdBy: context.actorName,
    relatedRoomIds: context.roomId == null ? const [] : [context.roomId!],
  );
  await context.onBoardChanged?.call();
  return 'Created ${task.id}: ${task.title}';
}

Future<String> _moveTask(
  KanbanToolContext context, {
  required String taskId,
  required TaskStatus status,
}) async {
  final repository = await context.repositoryFor(context.workspaceId);
  await updateBoardTask(
    repository: repository,
    workspaceId: context.workspaceId,
    taskId: taskId,
    update: (task) => task.copyWith(status: status),
  );
  await context.onBoardChanged?.call();
  return 'Moved $taskId to ${status.label}.';
}
