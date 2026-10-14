import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:installm/features/vault/application/vaults_controller.dart';
import 'package:installm/features/vault/domain/vault_registration.dart';
import 'package:installm/features/workspaces/application/workspaces_controller.dart';
import 'package:installm/i18n/strings.g.dart';

/// Registered vaults and their workspace links.
///
/// Road Map 2 Phase 2.5. The vault is the human-readable knowledge layer:
/// research, plans, decisions, reports and tasks live there as Markdown.
// The app only ever writes inside a linked project folder.
class VaultsPage extends ConsumerWidget {
  const VaultsPage({super.key});

  Future<void> _register(BuildContext context, WidgetRef ref) async {
    final dir = await getDirectoryPath();
    if (dir == null || !context.mounted) return;
    final name = dir
        .split(RegExp(r'[/\\]'))
        .lastWhere((part) => part.isNotEmpty, orElse: () => t.vault.title);
    final vault = await ref
        .read(vaultsProvider.notifier)
        .registerVault(name, dir);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          vault == null
              ? t.vault.registryError
              : t.vault.registered(name: name),
        ),
      ),
    );
  }

  Future<void> _link(
    BuildContext context,
    WidgetRef ref,
    VaultRegistration vault,
    String workspaceId,
  ) async {
    var draft = 'Projects/installm';
    final projectPath = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t.vault.linkTitle),
        content: TextFormField(
          initialValue: draft,
          onChanged: (value) => draft = value,
          autofocus: true,
          decoration: InputDecoration(
            labelText: t.vault.folder,
            hintText: 'Projects/installm',
          ),
          onFieldSubmitted: (value) => Navigator.of(context).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(t.vault.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(draft),
            child: Text(t.vault.link),
          ),
        ],
      ),
    );
    if (projectPath == null || projectPath.trim().isEmpty || !context.mounted) {
      return;
    }
    await ref
        .read(vaultsProvider.notifier)
        .linkWorkspace(
          workspaceId: workspaceId,
          vaultId: vault.id,
          projectPath: projectPath,
        );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ref.read(vaultsProvider).errorMessage == null
              ? t.vault.linked
              : t.vault.linkError,
        ),
      ),
    );
  }

  Future<void> _rename(
    BuildContext context,
    WidgetRef ref,
    VaultRegistration vault,
  ) async {
    var draft = vault.name;
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t.vault.renameTitle),
        content: TextFormField(
          initialValue: draft,
          autofocus: true,
          decoration: InputDecoration(labelText: t.vault.name),
          onChanged: (value) => draft = value,
          onFieldSubmitted: (value) => Navigator.pop(context, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(t.vault.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, draft),
            child: Text(t.vault.save),
          ),
        ],
      ),
    );
    if (name == null || name.trim().isEmpty || !context.mounted) return;
    final saved = await ref
        .read(vaultsProvider.notifier)
        .renameVault(vault.id, name);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(saved ? t.vault.renamed : t.vault.registryError),
        ),
      );
    }
  }

  Future<void> _remove(
    BuildContext context,
    WidgetRef ref,
    VaultRegistration vault,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t.vault.removeTitle),
        content: Text(t.vault.removeDescription(name: vault.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(t.vault.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(t.vault.remove),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    await ref.read(vaultsProvider.notifier).removeVault(vault.id);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ref.read(vaultsProvider).snapshot.vaultById(vault.id) == null
                ? t.vault.removed
                : t.vault.registryError,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(vaultsProvider);
    final workspaces = ref.watch(workspacesProvider);
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: Text(t.vault.manage)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: state.isReady && !state.isReadOnly
            ? () => _register(context, ref)
            : null,
        icon: const Icon(Icons.create_new_folder_outlined),
        label: Text(t.vault.register),
      ),
      body: !state.isReady
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
              children: [
                Text(t.vault.description, style: textTheme.bodySmall),
                const SizedBox(height: 12),
                if (state.vaults.isEmpty)
                  Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(t.vault.noVaults),
                    ),
                  ),
                for (final vault in state.vaults)
                  Card(
                    child: ExpansionTile(
                      leading: const Icon(Icons.folder_open),
                      title: Text(vault.name),
                      subtitle: Text(
                        vault.rootPath,
                        overflow: TextOverflow.ellipsis,
                      ),
                      children: [
                        for (final workspace in workspaces.workspaces)
                          Builder(
                            builder: (context) {
                              final binding = state.snapshot.bindingFor(
                                workspace.id,
                              );
                              final linked = binding?.vaultId == vault.id;
                              return ListTile(
                                title: Text(workspace.name),
                                subtitle: linked
                                    ? Text(
                                        binding!.projectPath,
                                        overflow: TextOverflow.ellipsis,
                                      )
                                    : Text(t.vault.notLinked),
                                trailing: linked
                                    ? TextButton(
                                        onPressed: state.isReadOnly
                                            ? null
                                            : () => ref
                                                  .read(vaultsProvider.notifier)
                                                  .unlinkWorkspace(
                                                    workspace.id,
                                                  ),
                                        child: Text(t.vault.unlink),
                                      )
                                    : TextButton(
                                        onPressed: state.isReadOnly
                                            ? null
                                            : () => _link(
                                                context,
                                                ref,
                                                vault,
                                                workspace.id,
                                              ),
                                        child: Text(t.vault.link),
                                      ),
                              );
                            },
                          ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: Wrap(
                              spacing: 8,
                              children: [
                                TextButton(
                                  onPressed: state.isReadOnly
                                      ? null
                                      : () => _rename(context, ref, vault),
                                  child: Text(t.vault.rename),
                                ),
                                if (!vault.isManaged)
                                  TextButton(
                                    onPressed: state.isReadOnly
                                        ? null
                                        : () => _remove(context, ref, vault),
                                    child: Text(t.vault.remove),
                                  ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
                    ),
                  ),
                if (state.errorMessage != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    state.errorMessage!,
                    style: textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
              ],
            ),
    );
  }
}
