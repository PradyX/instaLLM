import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:installm/features/vault/application/vault_browser_service.dart';
import 'package:installm/features/vault/application/vault_notes_service.dart';
import 'package:installm/features/vault/application/vaults_controller.dart';
import 'package:installm/features/vault/domain/vault_paths.dart';
import 'package:installm/features/vault/domain/vault_registration.dart';

final vaultBrowserServiceProvider = Provider<VaultBrowserService>(
  (ref) => const VaultBrowserService(),
);
final vaultBrowserProvider =
    StateNotifierProvider.autoDispose<
      VaultBrowserController,
      VaultBrowserState
    >(createVaultBrowserController);

VaultBrowserController createVaultBrowserController(Ref ref) =>
    VaultBrowserController(
      service: ref.watch(vaultBrowserServiceProvider),
      isRegistered: (vault) =>
          ref.read(vaultsProvider).snapshot.vaultById(vault.id)?.rootPath ==
          vault.rootPath,
    );

class VaultBrowserState {
  const VaultBrowserState({
    this.vault,
    this.folders = const {},
    this.loadingFolders = const {},
    this.expanded = const {},
    this.note,
    this.busy = false,
    this.query = '',
    this.searching = false,
    this.results,
    this.error,
  });
  final VaultRegistration? vault;
  final Map<String, VaultFileListing> folders;
  final Set<String> loadingFolders;
  final Set<String> expanded;
  final VaultNote? note;
  final bool busy;
  final String query;
  final bool searching;
  final VaultFileListing? results;
  final VaultNoteError? error;
  VaultBrowserState copyWith({
    Map<String, VaultFileListing>? folders,
    Set<String>? loadingFolders,
    Set<String>? expanded,
    VaultNote? note,
    bool clearNote = false,
    bool? busy,
    String? query,
    bool? searching,
    VaultFileListing? results,
    bool clearResults = false,
    VaultNoteError? error,
    bool clearError = false,
  }) => VaultBrowserState(
    vault: vault,
    folders: folders ?? this.folders,
    loadingFolders: loadingFolders ?? this.loadingFolders,
    expanded: expanded ?? this.expanded,
    note: clearNote ? null : note ?? this.note,
    busy: busy ?? this.busy,
    query: query ?? this.query,
    searching: searching ?? this.searching,
    results: clearResults ? null : results ?? this.results,
    error: clearError ? null : error ?? this.error,
  );
}

/// Owns selection and disk operations, including stale route/read rejection.
/// Manual note actions do not enable any bot permission or journal ownership.
class VaultBrowserController extends StateNotifier<VaultBrowserState> {
  VaultBrowserController({required this.service, required this.isRegistered})
    : super(const VaultBrowserState());
  final VaultBrowserService service;
  final bool Function(VaultRegistration vault) isRegistered;
  static const notes = VaultNotesService();
  static const maxNoteBytes = 512 * 1024;
  static const userPermissions = VaultPermissions(canDelete: true);
  int _vaultEpoch = 0;
  int _noteEpoch = 0;
  int _searchEpoch = 0;
  VaultPaths? get _paths => state.vault == null
      ? null
      : VaultPaths(vaultRoot: state.vault!.rootPath, projectPath: '');
  bool get _available => state.vault != null && isRegistered(state.vault!);

  Future<void> selectVault(VaultRegistration vault) async {
    if (!mounted || state.busy) return;
    _vaultEpoch++;
    _noteEpoch++;
    _searchEpoch++;
    state = VaultBrowserState(vault: vault);
    await loadFolder('.');
  }

  Future<void> loadFolder(String folder) async {
    final paths = _paths;
    if (paths == null || state.loadingFolders.contains(folder)) return;
    final epoch = _vaultEpoch;
    state = state.copyWith(loadingFolders: {...state.loadingFolders, folder});
    final (listing, error) = await service.list(paths, folder);
    if (!mounted || epoch != _vaultEpoch) return;
    state = state.copyWith(
      folders: listing == null ? null : {...state.folders, folder: listing},
      loadingFolders: {...state.loadingFolders}..remove(folder),
      error: error,
      clearError: error == null,
    );
  }

  Future<void> toggleFolder(String folder) async {
    if (state.expanded.contains(folder)) {
      state = state.copyWith(expanded: {...state.expanded}..remove(folder));
    } else {
      state = state.copyWith(expanded: {...state.expanded, folder});
      if (!state.folders.containsKey(folder)) await loadFolder(folder);
    }
  }

  Future<void> search(String query) async {
    final epoch = ++_searchEpoch;
    final paths = _paths;
    state = state.copyWith(
      query: query.trim(),
      searching: query.trim().isNotEmpty,
      clearResults: true,
    );
    if (paths == null || query.trim().isEmpty || !_available) {
      state = state.copyWith(searching: false);
      return;
    }
    final (results, error) = await service.search(
      paths,
      query.trim(),
      cancelled: () => !mounted || epoch != _searchEpoch || !_available,
    );
    if (!mounted || epoch != _searchEpoch) return;
    state = state.copyWith(
      results: results,
      searching: false,
      error: error,
      clearError: error == null,
    );
  }

  Future<void> openNote(String path) async {
    if (state.busy || !path.toLowerCase().endsWith('.md')) return;
    final paths = _paths;
    if (paths == null || !_available) {
      state = state.copyWith(error: VaultNoteError.denied);
      return;
    }
    final epoch = ++_noteEpoch;
    final vaultEpoch = _vaultEpoch;
    state = state.copyWith(busy: true, clearNote: true, clearError: true);
    final (note, error) = await notes.readNote(
      paths: paths,
      permissions: userPermissions,
      relativePath: path,
      maxBytes: maxNoteBytes,
    );
    if (!mounted || epoch != _noteEpoch || vaultEpoch != _vaultEpoch) return;
    state = state.copyWith(
      note: note,
      busy: false,
      error: error,
      clearError: error == null,
    );
  }

  void closeNote() {
    if (state.busy) return;
    _noteEpoch++;
    state = state.copyWith(clearNote: true, clearError: true);
  }

  Future<bool> save(String content) async {
    if (utf8.encode(content).length > maxNoteBytes) {
      state = state.copyWith(error: VaultNoteError.tooLarge);
      return false;
    }
    return _mutate(content: content);
  }

  Future<bool> delete() => _mutate();

  Future<bool> _mutate({String? content}) async {
    final baseline = state.note;
    final paths = _paths;
    if (state.busy || baseline == null || paths == null || !_available) {
      state = state.copyWith(error: VaultNoteError.denied);
      return false;
    }
    state = state.copyWith(busy: true, clearError: true);
    final error = content == null
        ? await notes.deleteNote(
            paths: paths,
            permissions: userPermissions,
            relativePath: baseline.relativePath,
            expectedModified: baseline.modified,
            expectedContent: baseline.content,
          )
        : await notes.writeNote(
            paths: paths,
            permissions: userPermissions,
            relativePath: baseline.relativePath,
            content: content,
            expectedModified: baseline.modified,
            expectedContent: baseline.content,
          );
    if (!mounted) return error == null;
    if (error != null) {
      state = state.copyWith(busy: false, error: error);
      return false;
    }
    if (content == null) {
      state = state.copyWith(
        busy: false,
        clearNote: true,
        folders: {
          for (final entry in state.folders.entries)
            entry.key: VaultFileListing(
              entry.value.entries
                  .where((file) => file.path != baseline.relativePath)
                  .toList(),
              truncated: entry.value.truncated,
            ),
        },
        results: state.results == null
            ? null
            : VaultFileListing(
                state.results!.entries
                    .where((file) => file.path != baseline.relativePath)
                    .toList(),
                truncated: state.results!.truncated,
              ),
      );
    } else {
      final (updated, readError) = await notes.readNote(
        paths: paths,
        permissions: userPermissions,
        relativePath: baseline.relativePath,
        maxBytes: maxNoteBytes,
      );
      if (!mounted) return true;
      state = state.copyWith(
        note: updated,
        busy: false,
        error: readError,
        clearError: readError == null,
      );
      return readError == null;
    }
    return true;
  }

  Future<void> refresh() async {
    if (state.busy || state.vault == null) return;
    final selected = state.note?.relativePath;
    final vault = state.vault!;
    await selectVault(vault);
    if (selected != null) await openNote(selected);
  }
}
