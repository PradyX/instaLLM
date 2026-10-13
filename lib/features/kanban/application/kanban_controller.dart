import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pocket_llm/features/kanban/application/board_task_operations.dart';
import 'package:pocket_llm/features/kanban/data/task_repository.dart';
import 'package:pocket_llm/features/kanban/domain/task.dart';
import 'package:pocket_llm/features/obsidian/application/vaults_controller.dart';
import 'package:pocket_llm/features/workspaces/application/workspaces_controller.dart';

/// Active workspace id, shared by every workspace-scoped screen.
final activeWorkspaceIdProvider = Provider<String?>((ref) {
  return ref.watch(workspacesProvider).active?.id;
});

/// Reads one provider. Controllers pass their `Ref.read`, widgets their
/// `WidgetRef.read` — both spell the same read, so rooms resolve the same
/// repository as the board without caring which ref they hold.
typedef BoardReader = T Function<T>(ProviderListenable<T> provider);

/// Opens the repository a workspace currently boards from: vault notes when
/// the workspace links a vault, the local store otherwise.
///
/// Shared by the board screen, the board tools bots call from rooms and
/// the room's message-to-task action, so every side reads and writes the
/// same tasks.
Future<TaskRepository> resolveTaskRepository(
  BoardReader read,
  String workspaceId,
) => read(taskRepositoryProvider(workspaceId).future);

final taskRepositoryProvider = FutureProvider.family<TaskRepository, String>((
  ref,
  workspaceId,
) async {
  final vaults = ref.watch(vaultsProvider);
  final binding = vaults.snapshot.bindingFor(workspaceId);
  if (binding != null) {
    final paths = ref.read(vaultsProvider.notifier).pathsFor(workspaceId);
    if (paths != null) {
      return VaultTaskRepository(
        paths: paths,
        permissions: binding.permissions,
      );
    }
  }
  return LocalTaskRepository.open();
});

/// Rooms read the same live state as the active board, or their own workspace
/// repository when the user has switched workspaces with a room still open.
final workspaceTasksProvider = FutureProvider.autoDispose
    .family<List<ProjectTask>, String>((ref, workspaceId) async {
      final active = ref.watch(activeWorkspaceIdProvider);
      final board = ref.watch(kanbanProvider);
      if (active == workspaceId && board.isReady) {
        if (board.errorMessage != null) throw StateError(board.errorMessage!);
        return board.tasks;
      }
      final repository = await ref.watch(
        taskRepositoryProvider(workspaceId).future,
      );
      return repository.load(workspaceId);
    });

class KanbanState {
  const KanbanState({
    this.tasks = const [],
    this.isReady = false,
    this.errorMessage,
    this.usesVault = false,
  });

  final List<ProjectTask> tasks;
  final bool isReady;
  final String? errorMessage;
  final bool usesVault;

  Map<String, ProjectTask> get byId => {
    for (final task in tasks) task.id: task,
  };

  List<ProjectTask> inStatus(TaskStatus status) {
    return tasks.where((task) => task.status == status).toList();
  }

  KanbanState copyWith({
    List<ProjectTask>? tasks,
    bool? isReady,
    String? errorMessage,
    bool clearError = false,
    bool? usesVault,
  }) {
    return KanbanState(
      tasks: tasks ?? this.tasks,
      isReady: isReady ?? this.isReady,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
      usesVault: usesVault ?? this.usesVault,
    );
  }
}

final kanbanProvider = StateNotifierProvider<KanbanNotifier, KanbanState>(
  (ref) => KanbanNotifier(ref),
);

/// Owns one workspace's board: tasks, moves, assignments and comments.
///
/// Bots use the same operations the UI does (§9.3): create, assign, move,
/// comment, link document, mark blocked, mark complete.
class KanbanNotifier extends StateNotifier<KanbanState> {
  KanbanNotifier(this._ref) : super(const KanbanState()) {
    _ref.listen<String?>(
      activeWorkspaceIdProvider,
      (previous, next) => Future.microtask(() {
        if (mounted) reload();
      }),
    );
    _ref.listen(
      vaultsProvider,
      (previous, next) => Future.microtask(() {
        if (mounted) reload();
      }),
    );
    reload();
  }

  final Ref _ref;
  String? _workspaceId;
  var _loadEpoch = 0;

  Future<TaskRepository> _resolveRepository(String workspaceId) =>
      resolveTaskRepository(_ref.read, workspaceId);

  Future<void> reload() async {
    final workspaceId = _ref.read(activeWorkspaceIdProvider);
    final epoch = ++_loadEpoch;
    final changedWorkspace = _workspaceId != workspaceId;
    _workspaceId = workspaceId;
    state = state.copyWith(
      tasks: changedWorkspace ? const [] : null,
      isReady: false,
      clearError: true,
    );
    if (workspaceId == null) {
      state = state.copyWith(tasks: const [], isReady: true);
      return;
    }
    try {
      final repository = await _resolveRepository(workspaceId);
      final tasks = await repository.load(workspaceId);
      if (!mounted ||
          epoch != _loadEpoch ||
          _ref.read(activeWorkspaceIdProvider) != workspaceId) {
        return;
      }
      state = KanbanState(
        tasks: tasks,
        isReady: true,
        usesVault: repository is VaultTaskRepository,
      );
    } catch (error) {
      if (!mounted ||
          epoch != _loadEpoch ||
          _ref.read(activeWorkspaceIdProvider) != workspaceId) {
        return;
      }
      state = state.copyWith(
        isReady: true,
        errorMessage: 'Could not load tasks: $error',
      );
    }
  }

  Future<T?> _edit<T>(Future<T> Function(TaskRepository, String) action) async {
    final workspaceId = _ref.read(activeWorkspaceIdProvider);
    if (workspaceId == null) return null;
    try {
      final repository = await _resolveRepository(workspaceId);
      final result = await action(repository, workspaceId);
      if (!mounted) return result;
      if (_workspaceId == workspaceId) await reload();
      return result;
    } catch (error) {
      if (mounted && _workspaceId == workspaceId) {
        state = state.copyWith(errorMessage: 'Could not save tasks: $error');
      }
      return null;
    }
  }

  /// Creates a task with the next `PL-<n>` id in this workspace.
  Future<ProjectTask?> createTask({
    required String title,
    String description = '',
    TaskPriority priority = TaskPriority.medium,
    String? createdBy,
  }) => _edit(
    (repository, workspaceId) => createBoardTask(
      repository: repository,
      workspaceId: workspaceId,
      title: title,
      description: description,
      priority: priority,
      createdBy: createdBy,
    ),
  );

  Future<void> _updateTask(
    String taskId,
    ProjectTask Function(ProjectTask) update,
  ) async {
    await _edit(
      (repository, workspaceId) => updateBoardTask(
        repository: repository,
        workspaceId: workspaceId,
        taskId: taskId,
        update: update,
      ),
    );
  }

  Future<void> moveTask(String taskId, TaskStatus status) async {
    await _updateTask(taskId, (task) => task.copyWith(status: status));
  }

  Future<void> assignTask(String taskId, String? botId) async {
    await _updateTask(
      taskId,
      (task) =>
          task.copyWith(assignedBotId: botId, clearAssignee: botId == null),
    );
  }

  Future<void> addComment(String taskId, String author, String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    await _updateTask(
      taskId,
      (task) => task.copyWith(
        comments: [
          ...task.comments,
          TaskComment(author: author, text: trimmed, createdAt: DateTime.now()),
        ],
      ),
    );
  }

  Future<void> linkDocument(String taskId, String documentPath) async {
    await _updateTask(
      taskId,
      (task) => task.copyWith(
        relatedDocuments: {...task.relatedDocuments, documentPath}.toList(),
      ),
    );
  }

  Future<void> deleteTask(String taskId) async {
    await _edit(
      (repository, workspaceId) => editBoardTasks(
        repository,
        workspaceId,
        (tasks) async =>
            (tasks.where((task) => task.id != taskId).toList(), true),
      ),
    );
  }

  void clearError() {
    state = state.copyWith(clearError: true);
  }
}
