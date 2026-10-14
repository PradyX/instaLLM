import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:installm/core/services/app_storage_service.dart';
import 'package:installm/features/vault/application/vault_notes_service.dart';
import 'package:installm/features/vault/data/vault_store.dart';
import 'package:installm/features/vault/domain/vault_paths.dart';
import 'package:installm/features/vault/domain/vault_registration.dart';
import 'package:installm/features/workspaces/application/workspaces_controller.dart';

/// Vault registry file, opened once per session.
final vaultStoreProvider = FutureProvider<VaultStore>(
  (ref) => VaultStore.open(),
);
final vaultStorageProvider = Provider<AppStorageService>(
  (ref) => AppStorageService(),
);

class VaultsState {
  const VaultsState({
    this.snapshot = VaultsSnapshot.empty,
    this.isReady = false,
    this.errorMessage,
    this.isReadOnly = false,
  });

  final VaultsSnapshot snapshot;
  final bool isReady;
  final String? errorMessage;
  final bool isReadOnly;

  List<VaultRegistration> get vaults => snapshot.vaults;

  VaultsState copyWith({
    VaultsSnapshot? snapshot,
    bool? isReady,
    String? errorMessage,
    bool clearError = false,
    bool? isReadOnly,
  }) {
    return VaultsState(
      snapshot: snapshot ?? this.snapshot,
      isReady: isReady ?? this.isReady,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
      isReadOnly: isReadOnly ?? this.isReadOnly,
    );
  }
}

final vaultsProvider = StateNotifierProvider<VaultsNotifier, VaultsState>(
  (ref) => VaultsNotifier(ref),
);

/// Owns vault registrations and workspace bindings.
///
/// Registering a vault only records its root; linking a workspace records
/// the vault id plus the project folder on both the binding and the
/// workspace itself, so the workspace keeps working when the vault is
/// re-pointed at another device path.
class VaultsNotifier extends StateNotifier<VaultsState> {
  VaultsNotifier(this._ref) : super(const VaultsState()) {
    whenReady = _load();
  }
  late final Future<void> whenReady;

  final Ref _ref;
  VaultStore? _store;
  static const VaultNotesService _notes = VaultNotesService();

  Future<void> _load() async {
    try {
      final store = await _ref.read(vaultStoreProvider.future);
      if (!mounted) return;
      _store = store;
      var snapshot = store.load();
      String? storageError;
      if (!store.isReadOnly &&
          snapshot.vaults.any((vault) => vault.isManaged)) {
        try {
          final root = await _ref.read(vaultStorageProvider).directory('vault');
          var rebased = snapshot;
          for (final vault in snapshot.vaults) {
            if (vault.isManaged && vault.rootPath != root) {
              rebased = rebased.upsertVault(vault.copyWith(rootPath: root));
            }
          }
          if (!identical(rebased, snapshot)) {
            if (store.save(rebased)) {
              snapshot = rebased;
            } else {
              storageError =
                  'Could not update the managed Vault location. Previous registrations are preserved.';
            }
          }
        } catch (_) {
          storageError =
              'Managed Vault storage is unavailable. Resolve the resource storage error and retry.';
        }
      }
      if (!mounted) return;
      state = VaultsState(
        snapshot: snapshot,
        isReady: true,
        isReadOnly: store.isReadOnly,
        errorMessage: store.isReadOnly
            ? 'Vaults were written by a newer version of InstaLLM and are '
                  'read-only in this build.'
            : storageError,
      );
    } catch (error) {
      state = state.copyWith(
        isReady: true,
        errorMessage: 'Could not load vaults: $error',
      );
    }
  }

  Future<bool> _persist([VaultsSnapshot? snapshot]) async {
    try {
      final store = _store;
      if (store == null || !mounted) return false;
      if (store.isReadOnly) {
        state = state.copyWith(
          errorMessage:
              'Vaults were written by a newer version and are '
              'read-only in this build.',
        );
        return false;
      }
      final saved = store.save(snapshot ?? state.snapshot);
      if (saved) {
        state = state.copyWith(
          snapshot: snapshot ?? state.snapshot,
          clearError: true,
        );
      }
      if (!saved) {
        state = state.copyWith(
          isReadOnly: store.isReadOnly,
          errorMessage:
              'Could not save vaults. Your previous registry is preserved.',
        );
      }
      return saved;
    } catch (error) {
      state = state.copyWith(errorMessage: 'Could not save vaults: $error');
      return false;
    }
  }

  Future<VaultRegistration?> registerVault(String name, String rootPath) async {
    await whenReady;
    if (!mounted || state.isReadOnly) return null;
    final vault = VaultRegistration.create(name: name, rootPath: rootPath);
    final snapshot = state.snapshot.upsertVault(vault);
    if (!await _persist(snapshot)) return null;
    return vault;
  }

  /// Explicit first use prepares the app-owned Vault. Existing external links
  /// and permissions remain untouched; no workspace is silently re-bound.
  Future<VaultRegistration?> ensureManagedVault() async {
    await whenReady;
    if (!state.isReady || state.isReadOnly) return null;
    try {
      final root = await _ref.read(vaultStorageProvider).directory('vault');
      VaultRegistration? vault;
      for (final existing in state.vaults) {
        if (existing.isManaged) {
          vault = existing.rootPath == root
              ? existing
              : existing.copyWith(rootPath: root);
          break;
        }
      }
      vault ??= VaultRegistration.create(
        name: 'InstaLLM',
        rootPath: root,
        isManaged: true,
      );
      final snapshot = state.snapshot.upsertVault(vault);
      if (!await _persist(snapshot) || !mounted) return null;
      return vault;
    } catch (_) {
      if (mounted) {
        state = state.copyWith(
          errorMessage:
              'Could not prepare the managed Vault. Resolve the resource storage error and retry.',
        );
      }
      return null;
    }
  }

  Future<void> removeVault(String vaultId) async {
    await whenReady;
    if (!mounted) return;
    final snapshot = state.snapshot.removeVault(vaultId);
    if (!await _persist(snapshot) || !mounted) return;
  }

  Future<bool> renameVault(String vaultId, String name) async {
    await whenReady;
    if (!mounted || state.isReadOnly || name.trim().isEmpty) return false;
    final vault = state.snapshot.vaultById(vaultId);
    if (vault == null) return false;
    return _persist(
      state.snapshot.upsertVault(vault.copyWith(name: name.trim())),
    );
  }

  /// Links [workspaceId] to [vaultId] at [projectPath], scaffolds the
  /// standard folders and mirrors the link onto the workspace entity.
  Future<List<String>> linkWorkspace({
    required String workspaceId,
    required String vaultId,
    required String projectPath,
    VaultPermissions permissions = VaultPermissions.defaults,
  }) async {
    await whenReady;
    if (!mounted) return const [];
    final vault = state.snapshot.vaultById(vaultId);
    if (vault == null) return const [];
    final binding = WorkspaceVaultBinding(
      workspaceId: workspaceId,
      vaultId: vaultId,
      projectPath: projectPath.trim(),
      permissions: permissions,
    );
    final snapshot = state.snapshot.upsertBinding(binding);
    if (!await _persist(snapshot) || !mounted) return const [];

    final workspaces = _ref.read(workspacesProvider);
    for (final workspace in workspaces.workspaces) {
      if (workspace.id == workspaceId) {
        await _ref
            .read(workspacesProvider.notifier)
            .updateWorkspace(
              workspace.copyWith(
                vaultId: vaultId,
                vaultProjectPath: projectPath.trim(),
              ),
            );
      }
    }

    try {
      return await _notes.ensureProjectStructure(
        VaultFolders.pathsFor(vault: vault, projectPath: projectPath.trim()),
        projectName: projectPath.trim().split('/').lastOrNull ?? 'Project',
      );
    } catch (error) {
      state = state.copyWith(
        errorMessage: 'Linked, but the folders could not be created: $error',
      );
      return const [];
    }
  }

  Future<void> unlinkWorkspace(String workspaceId) async {
    await whenReady;
    if (!mounted) return;
    final snapshot = state.snapshot.removeBinding(workspaceId);
    if (!await _persist(snapshot) || !mounted) return;
  }

  Future<void> setPermissions(
    String workspaceId,
    VaultPermissions permissions,
  ) async {
    await whenReady;
    if (!mounted) return;
    final binding = state.snapshot.bindingFor(workspaceId);
    if (binding == null) return;
    final snapshot = state.snapshot.upsertBinding(
      binding.copyWith(permissions: permissions),
    );
    if (!await _persist(snapshot) || !mounted) return;
  }

  /// Resolved paths for [workspaceId]'s vault link, or null when unlinked.
  VaultPaths? pathsFor(String workspaceId) {
    final binding = state.snapshot.bindingFor(workspaceId);
    if (binding == null) return null;
    final vault = state.snapshot.vaultById(binding.vaultId);
    if (vault == null) return null;
    return VaultFolders.pathsFor(
      vault: vault,
      projectPath: binding.projectPath,
    );
  }

  void clearError() {
    state = state.copyWith(clearError: true);
  }
}

extension on List<String> {
  String? get lastOrNull => isEmpty ? null : last;
}
