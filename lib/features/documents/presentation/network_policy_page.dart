import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:installm/features/documents/application/network_policy_controller.dart';
import 'package:installm/features/documents/domain/network_policy.dart';
import 'package:installm/features/kanban/application/kanban_controller.dart'
    show activeWorkspaceIdProvider;
import 'package:installm/features/workspaces/application/workspaces_controller.dart';

/// Settings › Network: explicit web use, off by default (Road Map 3 Phase 3.4).
///
/// One policy per workspace, per tool. Nothing is fetched until the workspace
/// enables it; the search key itself lives in secure storage and never in the
/// policy file. Retrieved web text is labelled with its source URL and fetch
/// time wherever it appears.
class NetworkPolicyPage extends ConsumerStatefulWidget {
  const NetworkPolicyPage({super.key});

  @override
  ConsumerState<NetworkPolicyPage> createState() => _NetworkPolicyPageState();
}

class _NetworkPolicyPageState extends ConsumerState<NetworkPolicyPage> {
  final Map<String, TextEditingController> _keyControllers = {};
  final Map<String, TextEditingController> _providerControllers = {};

  @override
  void dispose() {
    for (final controller in _keyControllers.values) {
      controller.dispose();
    }
    for (final controller in _providerControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  TextEditingController _keyControllerFor(String workspaceId) {
    return _keyControllers.putIfAbsent(
      workspaceId,
      () => TextEditingController(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final policyState = ref.watch(networkPolicyControllerProvider);
    final workspaces = ref.watch(workspacesProvider).workspaces;
    final activeId = ref.watch(activeWorkspaceIdProvider);
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Network')),
      body: !policyState.isOpen
          ? const Center(child: CircularProgressIndicator())
          : workspaces.isEmpty
          ? Center(
              child: Text(
                'Create a workspace first; web use is enabled per workspace.',
                style: textTheme.bodyMedium,
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
              children: [
                Text(
                  'Off until enabled in each workspace. Fetching and search '
                  'leave the device with your permission per call; no '
                  'background fetching, no prefetching.',
                  style: textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                for (final workspace in workspaces)
                  _WorkspacePolicyCard(
                    workspaceId: workspace.id,
                    workspaceName: workspace.name,
                    isActive: workspace.id == activeId,
                    policy: policyState.snapshot.forWorkspace(workspace.id),
                    isReadOnly: policyState.isReadOnly,
                    keyController: _keyControllerFor(workspace.id),
                  ),
              ],
            ),
    );
  }
}

class _WorkspacePolicyCard extends ConsumerWidget {
  const _WorkspacePolicyCard({
    required this.workspaceId,
    required this.workspaceName,
    required this.isActive,
    required this.policy,
    required this.isReadOnly,
    required this.keyController,
  });

  final String workspaceId;
  final String workspaceName;
  final bool isActive;
  final NetworkPolicy policy;
  final bool isReadOnly;
  final TextEditingController keyController;

  Future<void> _save(
    WidgetRef ref,
    NetworkPolicy next, {
    String? apiKey,
    bool clearKey = false,
  }) async {
    final notifier = ref.read(networkPolicyControllerProvider.notifier);
    await notifier.setWorkspace(workspaceId, next);
    if (apiKey != null) {
      await notifier.setSearchKey(
        workspaceId: workspaceId,
        provider: next.webSearchProvider,
        apiKey: apiKey,
      );
    }
    if (clearKey) {
      await notifier.clearSearchKey(
        workspaceId: workspaceId,
        provider: policy.webSearchProvider,
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textTheme = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    workspaceName,
                    style: textTheme.titleSmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (isActive)
                  Text(
                    'active',
                    style: textTheme.labelSmall?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
              ],
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Fetch URLs'),
              subtitle: const Text('fetch_url for pages you name'),
              value: policy.fetchUrlEnabled,
              onChanged: isReadOnly
                  ? null
                  : (value) =>
                        _save(ref, policy.copyWith(fetchUrlEnabled: value)),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Web search'),
              subtitle: const Text('Needs a provider plus key below'),
              value: policy.webSearchEnabled,
              onChanged: isReadOnly
                  ? null
                  : (value) =>
                        _save(ref, policy.copyWith(webSearchEnabled: value)),
            ),
            if (policy.webSearchEnabled) ...[
              DropdownButtonFormField<String>(
                initialValue:
                    WebFetchLimits.knownProviders.contains(
                      policy.webSearchProvider,
                    )
                    ? policy.webSearchProvider
                    : null,
                decoration: const InputDecoration(labelText: 'Provider'),
                items: [
                  for (final provider in WebFetchLimits.knownProviders)
                    DropdownMenuItem(value: provider, child: Text(provider)),
                ],
                onChanged: isReadOnly
                    ? null
                    : (value) {
                        if (value == null) return;
                        _save(ref, policy.copyWith(webSearchProvider: value));
                      },
              ),
              const SizedBox(height: 8),
              TextField(
                controller: keyController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'API key (stored securely)',
                  hintText: 'Paste key, saved on submit',
                ),
                onSubmitted: (value) => _save(ref, policy, apiKey: value),
              ),
            ],
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('YouTube transcripts'),
              subtitle: const Text('Needs Fetch URLs as well'),
              value: policy.youtubeEnabled,
              onChanged: isReadOnly
                  ? null
                  : (value) =>
                        _save(ref, policy.copyWith(youtubeEnabled: value)),
            ),
            if (isReadOnly)
              Text(
                'Read-only: the policy file belongs to a newer build.',
                style: textTheme.bodySmall,
              ),
          ],
        ),
      ),
    );
  }
}
