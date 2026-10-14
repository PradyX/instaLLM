import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:installm/core/navigation/app_router.dart';
import 'package:installm/core/navigation/app_shell.dart';
import 'package:installm/features/vault/application/vault_browser_controller.dart';
import 'package:installm/features/vault/application/vault_browser_service.dart';
import 'package:installm/features/vault/application/vault_notes_service.dart';
import 'package:installm/features/vault/application/vaults_controller.dart';
import 'package:installm/features/workspaces/application/workspaces_controller.dart';
import 'package:installm/i18n/strings.g.dart';

typedef _VaultTreeRow = ({
  VaultFileEntry? entry,
  int depth,
  String? hint,
  bool loading,
});

/// Approved B: lazy folder tree beside a Markdown reader; narrow layouts show
/// one pane at a time. File IO, bounds and conditional mutations stay in services.
class VaultPage extends StatelessWidget {
  const VaultPage({super.key});

  @override
  Widget build(BuildContext context) => ProviderScope(
    overrides: [
      vaultBrowserProvider.overrideWith(createVaultBrowserController),
    ],
    child: const _VaultPageBody(),
  );
}

class _VaultPageBody extends ConsumerStatefulWidget {
  const _VaultPageBody();
  @override
  ConsumerState<_VaultPageBody> createState() => _VaultPageState();
}

class _VaultPageState extends ConsumerState<_VaultPageBody> {
  final _draft = TextEditingController();
  final _query = TextEditingController();
  Timer? _searchTimer;
  bool _editing = false;
  bool _initializing = true;
  bool _permitPop = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(_initialize);
  }

  @override
  void dispose() {
    _searchTimer?.cancel();
    _draft.dispose();
    _query.dispose();
    super.dispose();
  }

  VaultBrowserController get _browser =>
      ref.read(vaultBrowserProvider.notifier);

  Future<void> _initialize() async {
    final registry = ref.read(vaultsProvider.notifier);
    await registry.whenReady;
    if (!mounted) return;
    await registry.ensureManagedVault();
    if (!mounted) return;
    await _chooseVault();
    if (mounted) setState(() => _initializing = false);
  }

  Future<void> _chooseVault() async {
    final registry = ref.read(vaultsProvider);
    if (registry.vaults.isEmpty) return;
    final current = ref.read(vaultBrowserProvider).vault;
    final workspaceId = ref.read(workspacesProvider).active?.id;
    final bound = workspaceId == null
        ? null
        : registry.snapshot.bindingFor(workspaceId)?.vaultId;
    final vault =
        registry.snapshot.vaultById(current?.id ?? bound ?? '') ??
        registry.vaults.where((v) => v.isManaged).firstOrNull ??
        registry.vaults.first;
    _query.clear();
    _searchTimer?.cancel();
    await _browser.selectVault(vault);
  }

  bool get _dirty =>
      _editing && _draft.text != ref.read(vaultBrowserProvider).note?.content;
  Future<bool> _leaveEditor() async {
    FocusScope.of(context).unfocus();
    if (_dirty) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(t.vault.discardTitle),
          content: Text(t.vault.discardDescription),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(t.vault.cancel),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(t.vault.discard),
            ),
          ],
        ),
      );
      if (discard != true || !mounted) return false;
    }
    if (mounted) setState(() => _editing = false);
    return mounted;
  }

  Future<void> _open(VaultFileEntry entry) async {
    if (entry.isDirectory) {
      await _browser.toggleFolder(entry.path);
      return;
    }
    if (await _leaveEditor()) await _browser.openNote(entry.path);
  }

  Future<void> _manage() async {
    if (!await _leaveEditor()) return;
    if (!mounted) return;
    await context.push(AppRoutes.vaultManage);
    if (mounted) await _chooseVault();
  }

  Future<void> _refresh() async {
    if (!await _leaveEditor()) return;
    _query.clear();
    _searchTimer?.cancel();
    await _browser.refresh();
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    final saved = await _browser.save(_draft.text);
    if (!mounted || !saved) return;
    setState(() => _editing = false);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(t.vault.saved)));
  }

  Future<void> _delete() async {
    final note = ref.read(vaultBrowserProvider).note;
    if (note == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t.vault.deleteTitle),
        content: Text(t.vault.deleteDescription(name: note.relativePath)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(t.vault.cancel),
          ),
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: Text(t.vault.delete),
          ),
        ],
      ),
    );
    if (!mounted || confirm != true) return;
    if (await _browser.delete() && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(t.vault.deleted)));
    }
  }

  void _search(String value) {
    _searchTimer?.cancel();
    _searchTimer = Timer(const Duration(milliseconds: 300), () {
      if (mounted) _browser.search(value);
    });
  }

  String _error(VaultNoteError error) => switch (error) {
    VaultNoteError.conflict => t.vault.conflict,
    VaultNoteError.denied => t.vault.denied,
    VaultNoteError.outsideProject => t.vault.unsafePath,
    VaultNoteError.notFound => t.vault.missing,
    VaultNoteError.tooLarge => t.vault.tooLarge,
    VaultNoteError.io => t.vault.unavailable,
  };

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(vaultBrowserProvider);
    final registry = ref.watch(vaultsProvider);
    final wideShell =
        MediaQuery.sizeOf(context).width >= AppShell.wideBreakpoint;
    final colors = Theme.of(context).colorScheme;
    return ShellNavigationGuard(
      canLeave: () async =>
          !ref.read(vaultBrowserProvider).busy && await _leaveEditor(),
      child: AppShell(
        section: AppSection.vault,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final split =
                constraints.maxWidth >= 700 &&
                MediaQuery.textScalerOf(context).scale(14) < 23;
            final reader = state.note != null || state.busy;
            return PopScope(
              canPop:
                  _permitPop || (!_dirty && !state.busy && (split || !reader)),
              onPopInvokedWithResult: (didPop, _) async {
                if (didPop || state.busy || !await _leaveEditor()) return;
                if (!split && reader) {
                  _browser.closeNote();
                  return;
                }
                if (!mounted) return;
                setState(() => _permitPop = true);
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) Navigator.of(context).maybePop();
                });
              },
              child: Scaffold(
                key: const ValueKey('vault-page-scaffold'),
                appBar: AppBar(
                  title: Text(t.vault.title),
                  automaticallyImplyLeading: false,
                  leading: wideShell
                      ? null
                      : Builder(
                          builder: (context) => IconButton(
                            tooltip: t.vault.menu,
                            icon: const Icon(Icons.menu_rounded),
                            onPressed: () => Scaffold.of(context).openDrawer(),
                          ),
                        ),
                  actions: [
                    IconButton(
                      tooltip: t.vault.refresh,
                      onPressed: state.busy || _initializing ? null : _refresh,
                      icon: const Icon(Icons.refresh_rounded),
                    ),
                  ],
                ),
                drawer: wideShell
                    ? null
                    : const AppNavigationDrawer(section: AppSection.vault),
                body: _fitBody(
                  context,
                  Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                        child: LayoutBuilder(
                          builder: (context, header) => Wrap(
                            alignment: WrapAlignment.spaceBetween,
                            spacing: 8,
                            runSpacing: 4,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              SizedBox(
                                width: math.min(220, header.maxWidth),
                                child: PopupMenuButton<String>(
                                  tooltip: t.vault.title,
                                  enabled: !state.busy && !_initializing,
                                  onSelected: (id) async {
                                    if (!await _leaveEditor()) return;
                                    final vault = registry.snapshot.vaultById(
                                      id,
                                    );
                                    if (vault != null) {
                                      _query.clear();
                                      _searchTimer?.cancel();
                                      await _browser.selectVault(vault);
                                    }
                                  },
                                  itemBuilder: (_) => [
                                    for (final vault in registry.vaults)
                                      PopupMenuItem(
                                        value: vault.id,
                                        child: Text(vault.name),
                                      ),
                                  ],
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 8,
                                    ),
                                    child: Row(
                                      children: [
                                        Flexible(
                                          child: Text(
                                            registry.snapshot
                                                    .vaultById(
                                                      state.vault?.id ?? '',
                                                    )
                                                    ?.name ??
                                                t.vault.title,
                                            overflow: TextOverflow.ellipsis,
                                            maxLines: 1,
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                        const Icon(
                                          Icons.expand_more_rounded,
                                          size: 18,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              TextButton(
                                onPressed: state.busy ? null : _manage,
                                child: Text(t.vault.manage),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (state.error != null || registry.errorMessage != null)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              state.error == null
                                  ? registry.errorMessage!
                                  : _error(state.error!),
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: colors.error),
                            ),
                          ),
                        ),
                      Expanded(
                        child: _initializing
                            ? const Center(child: CircularProgressIndicator())
                            : state.vault == null
                            ? Center(child: Text(t.vault.emptyVault))
                            : split
                            ? Row(
                                children: [
                                  SizedBox(width: 220, child: _tree(state)),
                                  VerticalDivider(
                                    width: 1,
                                    thickness: 1,
                                    color: colors.outlineVariant,
                                  ),
                                  Expanded(
                                    child: _reader(state, narrow: false),
                                  ),
                                ],
                              )
                            : reader
                            ? _reader(state, narrow: true)
                            : _tree(state),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _fitBody(BuildContext context, Widget child) => LayoutBuilder(
    builder: (context, constraints) {
      if (constraints.maxHeight >= 400) return child;
      return SingleChildScrollView(
        child: SizedBox(
          height: 500 * MediaQuery.textScalerOf(context).scale(14) / 14,
          child: child,
        ),
      );
    },
  );

  Widget _tree(VaultBrowserState state) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: TextField(
          key: const ValueKey('vault-search'),
          controller: _query,
          onChanged: _search,
          decoration: InputDecoration(
            hintText: t.vault.search,
            prefixIcon: const Icon(Icons.search_rounded, size: 18),
            isDense: true,
            filled: true,
            fillColor: Theme.of(context).colorScheme.surfaceContainerLow,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide.none,
            ),
          ),
        ),
      ),
      Expanded(
        child: state.searching
            ? const Center(child: CircularProgressIndicator())
            : state.query.isNotEmpty
            ? _entries(state, state.results, searching: true)
            : _entries(state, state.folders['.']),
      ),
    ],
  );

  Widget _entries(
    VaultBrowserState state,
    VaultFileListing? listing, {
    bool searching = false,
  }) {
    if (listing == null) {
      return state.loadingFolders.contains('.')
          ? const Center(child: CircularProgressIndicator())
          : const SizedBox.shrink();
    }
    if (listing.entries.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          searching ? t.vault.noResults : t.vault.emptyFolder,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      );
    }
    final rows = <_VaultTreeRow>[];
    void append(VaultFileListing listing, int depth) {
      for (final entry in listing.entries) {
        rows.add((entry: entry, depth: depth, hint: null, loading: false));
        if (!entry.isDirectory || !state.expanded.contains(entry.path)) {
          continue;
        }
        if (state.loadingFolders.contains(entry.path)) {
          rows.add((entry: null, depth: depth + 1, hint: null, loading: true));
        }
        final children = state.folders[entry.path];
        if (children == null) continue;
        if (children.entries.isEmpty) {
          rows.add((
            entry: null,
            depth: depth + 1,
            hint: t.vault.emptyFolder,
            loading: false,
          ));
        }
        append(children, depth + 1);
      }
      if (listing.truncated) {
        rows.add((
          entry: null,
          depth: depth,
          hint: t.vault.limit,
          loading: false,
        ));
      }
    }

    append(listing, 0);
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
      itemCount: rows.length,
      itemBuilder: (context, index) {
        final row = rows[index];
        if (row.entry != null) {
          return _entry(state, row.entry!, row.depth, searching: searching);
        }
        return Padding(
          padding: EdgeInsets.fromLTRB(
            8 + math.min(row.depth, 4) * 12.0,
            8,
            8,
            8,
          ),
          child: row.loading
              ? const LinearProgressIndicator()
              : Text(row.hint!, style: Theme.of(context).textTheme.bodySmall),
        );
      },
    );
  }

  Widget _entry(
    VaultBrowserState state,
    VaultFileEntry entry,
    int depth, {
    bool searching = false,
  }) {
    final expanded = state.expanded.contains(entry.path);
    return Padding(
      padding: EdgeInsets.only(left: math.min(depth, 4) * 12.0),
      child: ListTile(
        key: ValueKey('vault-entry-${entry.path}'),
        dense: true,
        visualDensity: VisualDensity.compact,
        contentPadding: const EdgeInsets.symmetric(horizontal: 8),
        minLeadingWidth: 18,
        horizontalTitleGap: 8,
        selected: state.note?.relativePath == entry.path,
        selectedTileColor: Theme.of(
          context,
        ).colorScheme.primary.withValues(alpha: 0.08),
        leading: Icon(
          entry.isDirectory
              ? expanded
                    ? Icons.folder_open_outlined
                    : Icons.folder_outlined
              : Icons.description_outlined,
          size: 18,
        ),
        title: Tooltip(
          message: entry.path,
          child: Text(entry.name, maxLines: 2, overflow: TextOverflow.ellipsis),
        ),
        subtitle: searching
            ? Text(entry.path, maxLines: 2, overflow: TextOverflow.ellipsis)
            : null,
        trailing: entry.isDirectory
            ? Icon(expanded ? Icons.expand_more : Icons.chevron_right, size: 16)
            : null,
        onTap: state.busy ? null : () => _open(entry),
      ),
    );
  }

  Widget _reader(VaultBrowserState state, {required bool narrow}) {
    if (state.busy && state.note == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final note = state.note;
    if (note == null) return Center(child: Text(t.vault.selectNote));
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (narrow)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: state.busy
                    ? null
                    : () async {
                        if (await _leaveEditor()) _browser.closeNote();
                      },
                icon: const Icon(Icons.arrow_back_rounded, size: 18),
                label: Text(t.vault.backToFiles),
              ),
            ),
          Text(
            note.relativePath,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            alignment: WrapAlignment.end,
            children: _editing
                ? [
                    TextButton(
                      onPressed: state.busy ? null : _leaveEditor,
                      child: Text(t.vault.cancel),
                    ),
                    FilledButton(
                      onPressed: state.busy ? null : _save,
                      child: Text(t.vault.save),
                    ),
                  ]
                : [
                    TextButton.icon(
                      onPressed: state.busy
                          ? null
                          : () {
                              _draft.text = note.content;
                              setState(() => _editing = true);
                            },
                      icon: const Icon(Icons.edit_outlined, size: 16),
                      label: Text(t.vault.edit),
                    ),
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        foregroundColor: Theme.of(context).colorScheme.error,
                      ),
                      onPressed: state.busy ? null : _delete,
                      icon: const Icon(Icons.delete_outline, size: 16),
                      label: Text(t.vault.delete),
                    ),
                  ],
          ),
          if (state.busy) const LinearProgressIndicator(),
          const SizedBox(height: 8),
          Expanded(
            child: _editing
                ? TextField(
                    key: const ValueKey('vault-note-editor'),
                    controller: _draft,
                    enabled: !state.busy,
                    expands: true,
                    minLines: null,
                    maxLines: null,
                    textAlignVertical: TextAlignVertical.top,
                    keyboardType: TextInputType.multiline,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(border: InputBorder.none),
                  )
                : SingleChildScrollView(
                    child: MarkdownBody(
                      data: note.content,
                      selectable: true,
                      sizedImageBuilder: (image) => Text(
                        t.vault.image(label: image.alt ?? image.title ?? ''),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
