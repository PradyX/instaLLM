import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:installm/core/navigation/app_router.dart';
import 'package:installm/features/git/application/git_service.dart';
import 'package:installm/features/workspaces/application/workspaces_controller.dart';
import 'package:go_router/go_router.dart';

/// One project screen for everything in the workspace (Road Map 2 §13).
///
/// Chat, documents, bots, skills and MCP stay separate screens; this is the
/// map that links them, plus the repository state that needs a home.
class WorkspaceDetailPage extends ConsumerStatefulWidget {
  const WorkspaceDetailPage({super.key, required this.workspaceId});

  final String workspaceId;

  @override
  ConsumerState<WorkspaceDetailPage> createState() =>
      _WorkspaceDetailPageState();
}

class _WorkspaceDetailPageState extends ConsumerState<WorkspaceDetailPage> {
  static const GitService _git = GitService();

  Future<void> _pickRepository(String workspaceId) async {
    final dir = await getDirectoryPath();
    if (dir == null) return;
    final notifier = ref.read(workspacesProvider.notifier);
    final workspace = ref
        .read(workspacesProvider)
        .workspaces
        .where((w) => w.id == workspaceId)
        .firstOrNull;
    if (workspace == null) return;
    await notifier.updateWorkspace(workspace.copyWith(repositoryPath: dir));
  }

  @override
  Widget build(BuildContext context) {
    final workspaces = ref.watch(workspacesProvider);
    final workspace = workspaces.workspaces
        .where((w) => w.id == widget.workspaceId)
        .firstOrNull;
    if (workspace == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Workspace')),
        body: const Center(child: Text('This workspace no longer exists.')),
      );
    }
    final textTheme = Theme.of(context).textTheme;
    final active = workspaces.active?.id == workspace.id;

    return Scaffold(
      appBar: AppBar(
        title: Text(workspace.name),
        actions: [
          if (!active)
            TextButton(
              onPressed: () =>
                  ref.read(workspacesProvider.notifier).setActive(workspace.id),
              child: const Text('Set active'),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
        children: [
          if (workspace.description.isNotEmpty)
            Text(workspace.description, style: textTheme.bodyMedium),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _GoChip(
                icon: Icons.chat_bubble_outline,
                label: 'Chat',
                route: AppRoutes.home,
              ),
              _GoChip(
                icon: Icons.extension_outlined,
                label: 'Skills',
                route: AppRoutes.skills,
              ),
              _GoChip(
                icon: Icons.hub_outlined,
                label: 'MCP',
                route: AppRoutes.mcp,
              ),
            ],
          ),
          const SizedBox(height: 16),
          _Section(
            title: 'Repository',
            child: _Repo(
              workspaceId: workspace.id,
              repositoryPath: workspace.repositoryPath,
              onPick: () => _pickRepository(workspace.id),
            ),
          ),
        ],
      ),
    );
  }
}

class _GoChip extends StatelessWidget {
  const _GoChip({required this.icon, required this.label, required this.route});

  final IconData icon;
  final String label;
  final String route;

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      avatar: Icon(icon, size: 18),
      label: Text(label),
      onPressed: () => context.push(route),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            child,
          ],
        ),
      ),
    );
  }
}

class _Repo extends StatelessWidget {
  const _Repo({
    required this.workspaceId,
    required this.repositoryPath,
    required this.onPick,
  });

  final String workspaceId;
  final String? repositoryPath;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    final path = repositoryPath;
    if (path == null) {
      return ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.source_outlined),
        title: const Text('No repository set'),
        trailing: TextButton(onPressed: onPick, child: const Text('Choose')),
      );
    }
    return FutureBuilder<GitResult<GitStatus>>(
      future: _WorkspaceDetailPageState._git.status(path),
      builder: (context, snapshot) {
        final status = snapshot.data?.value;
        final subtitle = status == null
            ? path
            : '${status.branch} · '
                  '${status.isClean ? 'clean' : '${status.changedFiles.length} changed'}';
        return ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.source_outlined),
          title: const Text('Repository'),
          subtitle: Text(subtitle, overflow: TextOverflow.ellipsis),
          trailing: TextButton(onPressed: onPick, child: const Text('Change')),
        );
      },
    );
  }
}
