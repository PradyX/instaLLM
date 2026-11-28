import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:installm/core/navigation/app_router.dart';
import 'package:installm/core/services/device_profile_service.dart';
import 'package:installm/core/services/hugging_face_avatar_service.dart';
import 'package:installm/core/services/hugging_face_repository_service.dart';
import 'package:installm/core/services/service_providers.dart';
import 'package:installm/features/model_selection/data/gguf_reader.dart';
import 'package:installm/features/model_selection/data/model_compatibility_service.dart';
import 'package:installm/features/model_selection/domain/gguf_metadata.dart';
import 'package:installm/features/model_selection/domain/llm_model.dart';
import 'package:installm/features/model_selection/domain/model_compatibility.dart';
import 'package:installm/features/model_selection/domain/model_family.dart';
import 'package:installm/features/model_selection/presentation/download_progress_provider.dart';
import 'package:installm/features/model_selection/presentation/hugging_face_repository_dialog.dart';
import 'package:installm/features/model_selection/presentation/model_import_dialog.dart';
import 'package:installm/features/model_selection/presentation/model_selection_controller.dart';
import 'package:installm/features/model_selection/presentation/model_selection_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Choices offered when the user taps "Add Model".
enum _AddModelAction { importFile, huggingFaceRepo, directUrl }

/// Apple's desktops are the only platform that says "unified" about its RAM.
bool get _isAppleDesktop => defaultTargetPlatform == TargetPlatform.macOS;

/// The parameter-size buckets the filter rail offers. Sizes are compared in
/// billions of parameters, the same number the families sort by.
enum _SizeBucket {
  under1('<1B'),
  upTo3('1–3B'),
  upTo8('3–8B'),
  over8('8B+');

  const _SizeBucket(this.label);

  final String label;

  bool contains(double parameters) => switch (this) {
    _SizeBucket.under1 => parameters < 1,
    _SizeBucket.upTo3 => parameters >= 1 && parameters < 3,
    _SizeBucket.upTo8 => parameters >= 3 && parameters < 8,
    _SizeBucket.over8 => parameters >= 8,
  };
}

/// `4096` as `4K`, `32768` as `32K`, `5500` as `5.4K`; smaller values as is.
String _formatContext(int tokens) {
  if (tokens < 1024) return '$tokens';
  final thousands = tokens / 1024;
  final text = thousands == thousands.roundToDouble()
      ? thousands.toStringAsFixed(0)
      : thousands.toStringAsFixed(1);
  return '${text}K';
}

String _formatBytes(int bytes) {
  if (bytes <= 0) return '0 B';
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
}

class ModelSelectionPage extends ConsumerStatefulWidget {
  const ModelSelectionPage({super.key});

  @override
  ConsumerState<ModelSelectionPage> createState() => _ModelSelectionPageState();
}

class _ModelSelectionPageState extends ConsumerState<ModelSelectionPage> {
  /// The variant the family ledger highlights, set when a row is opened.
  String? _focusedModelId;

  /// The family whose row has unfolded into its details, if any. One at a
  /// time: an open row is the list's focus, and two open rows would make the
  /// catalog twice as long as what it is showing.
  String? _expandedFamilyKey;

  /// The parameter-size bucket the list is narrowed to, if any.
  _SizeBucket? _sizeBucket;

  /// Whether the list hides models whose file is not expected to run here.
  /// Off by default: a catalog that hides entries before the user asks is a
  /// worse first impression than one that shows what will not fit.
  bool _onlyWhatFits = false;

  final TextEditingController _searchController = TextEditingController();

  /// Memory estimates per model id, computed when a card is expanded.
  final Map<String, ModelFitReport?> _fitReports = <String, ModelFitReport?>{};
  final Set<String> _fitRequests = <String>{};

  /// Quantizations each model's repository offers, read the first time its
  /// download button is pressed. Absent until then: a card only knows its own
  /// file, and asking huggingface.co about every model on the page would be a
  /// request the user never asked for.
  final Map<String, ModelQuantizationChoices> _quantizationChoices = {};
  final Set<String> _quantizationLoading = <String>{};
  final Map<String, String> _selectedQuantization = <String, String>{};

  /// GGUF metadata of installed models whose own record carries none: the
  /// built-in catalog stores no snapshot, so the file's header is read once
  /// per model and kept here. A null value means "asked, unreadable".
  final Map<String, GgufMetadata?> _liveGgufMetadata = {};
  final Set<String> _ggufMetadataRequests = {};

  /// Context window per Hugging Face repository, read for models that are not
  /// on disk. Null means "asked, unavailable"; absent means "never asked".
  final Map<String, int?> _remoteContextByRepo = {};
  final Set<String> _remoteContextRequests = {};
  final HuggingFaceRepositoryService _repositoryService =
      HuggingFaceRepositoryService();

  /// Publisher avatars per family, fetched once per distinct publisher and
  /// kept in memory for the page's life. Absent means "never asked"; a null
  /// means "asked, none found or unreachable", which is also final for the
  /// page's life. Absent entirely when the family has no Hugging Face link.
  final Map<String, String> _familyPublishers = {};
  final Map<String, Uint8List?> _publisherAvatars = {};
  final Set<String> _avatarRequests = <String>{};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(modelSelectionControllerProvider.notifier).refreshStorageInfo();
      _searchController.text = ref
          .read(modelSelectionControllerProvider)
          .searchQuery;
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Asks for one publisher's avatar image, fresh for this session. The
  /// service itself caches on disk, so only a publisher's very first row
  /// reaches the network this launch.
  Future<void> _loadPublisherAvatar(String publisher) async {
    if (_avatarRequests.contains(publisher) ||
        _publisherAvatars.containsKey(publisher)) {
      return;
    }
    setState(() => _avatarRequests.add(publisher));
    Uint8List? bytes;
    try {
      bytes = await ref
          .read(huggingFaceAvatarServiceProvider)
          .avatarForPublisher(publisher);
    } catch (_) {
      bytes = null;
    }
    if (!mounted) return;
    setState(() {
      _publisherAvatars[publisher] = bytes;
      _avatarRequests.remove(publisher);
    });
  }

  /// Estimates a model's memory use once, the first time its details open.
  /// Reads an installed model's GGUF metadata from its file when the model
  /// record has none. Header only: the weights are never touched.
  Future<void> _loadGgufMetadata(LlmModel model) async {
    if (!model.isDownloaded) return;
    if (_liveGgufMetadata.containsKey(model.id) ||
        !_ggufMetadataRequests.add(model.id)) {
      return;
    }
    try {
      final path = await ref
          .read(modelStorageServiceProvider)
          .resolveModelPath(model);
      if (path == null || path.trim().isEmpty) {
        throw const GgufFormatException('Model file location is unknown.');
      }
      final metadata = await const GgufReader().info(path);
      if (!mounted) return;
      setState(() => _liveGgufMetadata[model.id] = metadata);
    } catch (_) {
      if (!mounted) return;
      setState(() => _liveGgufMetadata[model.id] = null);
    } finally {
      _ggufMetadataRequests.remove(model.id);
    }
  }

  /// Reads the context window a repository's GGUF files declare, so a model
  /// that is not downloaded can still show what it provides. Only public
  /// metadata is asked for, and the answer is kept per repository.
  Future<void> _loadRemoteContext(String repoId) async {
    if (_remoteContextByRepo.containsKey(repoId) ||
        !_remoteContextRequests.add(repoId)) {
      return;
    }
    try {
      final context = await _repositoryService.fetchContextLength(repoId);
      if (!mounted) return;
      setState(() => _remoteContextByRepo[repoId] = context);
    } finally {
      _remoteContextRequests.remove(repoId);
    }
  }

  Future<void> _loadFitReport(LlmModel model) async {
    if (_fitRequests.contains(model.id) || _fitReports.containsKey(model.id)) {
      return;
    }
    setState(() => _fitRequests.add(model.id));
    try {
      final device = await ref.read(deviceProfileProvider.future);
      final report = await ref
          .read(modelCompatibilityServiceProvider)
          .evaluate(model, device: device);
      if (!mounted) return;
      setState(() {
        _fitReports[model.id] = report;
        _fitRequests.remove(model.id);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _fitReports[model.id] = null;
        _fitRequests.remove(model.id);
      });
    }
  }

  /// Reads a repository's quantizations so the chips exist for the next press.
  ///
  /// The first press of Download no longer waits on this: a repository it
  /// cannot read simply leaves the model's own file as the only choice.
  Future<void> _loadQuantizationChoices(LlmModel model) async {
    if (_quantizationChoices.containsKey(model.id) ||
        _quantizationLoading.contains(model.id)) {
      return;
    }
    setState(() => _quantizationLoading.add(model.id));
    final loaded = await ref
        .read(modelSelectionControllerProvider.notifier)
        .loadQuantizationChoices(model);
    if (!mounted) return;
    setState(() {
      _quantizationLoading.remove(model.id);
      if (loaded == null || loaded.variants.isEmpty) return;
      _quantizationChoices[model.id] = loaded;
      _selectedQuantization[model.id] =
          (loaded.variantFor(model) ?? loaded.variants.first).quantization;
    });
  }

  /// Downloads a model; the filled chip is the file this button fetches.
  ///
  /// Pressing Download always starts a download. Asking the repository for its
  /// other quantizations used to happen first and then stop, which showed a
  /// spinner and nothing else: the chips it revealed render above the button,
  /// so the press looked like it did nothing at all. The chips still arrive, in
  /// the Quantization section, while the file the user asked for is already
  /// coming down.
  Future<void> _handleDownload(LlmModel model) async {
    final controller = ref.read(modelSelectionControllerProvider.notifier);
    final choices = _quantizationChoices[model.id];

    if (choices != null && choices.variants.isNotEmpty) {
      final selected = _selectedQuantization[model.id];
      final variant = choices.variants.firstWhere(
        (candidate) => candidate.quantization == selected,
        orElse: () => choices.variantFor(model) ?? choices.variants.first,
      );
      await controller.downloadQuantization(
        model: model,
        choices: choices,
        variant: variant,
      );
      return;
    }

    unawaited(_loadQuantizationChoices(model));
    await controller.downloadModel(model);
  }

  /// Label describing the estimate (or why there is none yet).
  String _fitLabel(LlmModel model) {
    if (_fitRequests.contains(model.id)) return 'Estimating...';
    final report = _fitReports[model.id];
    if (report == null && !_fitReports.containsKey(model.id)) {
      return 'Estimating...';
    }
    if (report == null) return 'Could not estimate';

    final estimate = report.estimate;
    if (estimate == null) {
      if (!report.hasLocalFile) return 'Install to estimate';
      return 'Metadata unavailable';
    }
    final rating = estimate.rating;
    final required = ModelMemoryEstimate.formatBytes(estimate.requiredBytes);
    final budget = estimate.budgetBytes;
    if (rating == null || budget == null) {
      return 'Needs about $required · device memory unknown';
    }
    return '${rating.label} · needs about $required of '
        '${ModelMemoryEstimate.formatBytes(budget)}';
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(modelSelectionControllerProvider);
    // Embedding models turn text into vectors, not conversation; the chat
    // runtime cannot use them, so they do not appear here.
    final selectableModels = state.models
        .where((model) => !model.isEmbeddingModel)
        .toList(growable: false);
    // What is already on disk always leads the list; that is not a filter the
    // page offers to switch off.
    final sortedModels = [...selectableModels]
      ..sort(_compareModelsPrioritizingInstalled);
    final capabilityCounts = _buildCapabilityCounts(selectableModels);
    final visibleCapabilities = ModelCapability.values
        .where((capability) => (capabilityCounts[capability] ?? 0) > 0)
        .toList(growable: false);
    final filteredModels = sortedModels
        .where((model) {
          if (state.selectedCapabilityFilters.isNotEmpty &&
              !state.selectedCapabilityFilters.every(
                model.capabilities.contains,
              )) {
            return false;
          }

          if (state.searchQuery.trim().isNotEmpty) {
            final q = state.searchQuery.trim().toLowerCase();
            final nameMatch = model.name.toLowerCase().contains(q);
            final descMatch = model.description.toLowerCase().contains(q);
            if (!nameMatch && !descMatch) return false;
          }

          final bucket = _sizeBucket;
          if (bucket != null &&
              !bucket.contains(
                ModelFamilies.parameterCountOf(model.parameterSize),
              )) {
            return false;
          }

          return true;
        })
        .toList(growable: false);

    // One entry per family: a name at one parameter size. Quantizations of
    // that size share the family; a different size is a different model.
    final families = ModelFamilies.group(filteredModels);

    // "Best fit" (sortFamiliesByFit below) orders families by how well their
    // best-fitting variant is expected to run here — the biggest comfortable
    // model first — using the device's memory budget; families whose weights
    // or budget cannot be estimated stay unranked and last.
    final deviceForFit = state.sortByFit
        ? ref.watch(deviceProfileProvider).value
        : null;
    if (state.sortByFit) {
      sortFamiliesByFit(
        families,
        contextTokens: ModelCompatibilityService.defaultContextTokens,
        totalMemoryBytes: deviceForFit?.totalMemoryBytes,
        availableMemoryBytes: deviceForFit?.availableMemoryBytes,
        installedFirst: true,
      );
    } else {
      families.sort((a, b) {
        final byInstalled = (b.hasInstalled ? 1 : 0).compareTo(
          a.hasInstalled ? 1 : 0,
        );
        if (byInstalled != 0) return byInstalled;
        final bySize = a.lightest.parameterCount.compareTo(
          b.lightest.parameterCount,
        );
        if (bySize != 0) return bySize;
        return a.displayName.toLowerCase().compareTo(
          b.displayName.toLowerCase(),
        );
      });
    }

    // Only what fits: the same estimate the rows show, applied as a filter.
    if (_onlyWhatFits) {
      final fitDevice = ref.watch(deviceProfileProvider).value;
      families.removeWhere(
        (family) =>
            familyFitRank(
              family,
              contextTokens: ModelCompatibilityService.defaultContextTokens,
              totalMemoryBytes: fitDevice?.totalMemoryBytes,
              availableMemoryBytes: fitDevice?.availableMemoryBytes,
            ) !=
            0,
      );
    }

    // A family's avatar and sub-line label prefer the model's own creator
    // (Qwen, not the community account that quantized it): this is also the
    // page's only automatic network habit. Only the very first time a name
    // is seen does one request leave the app, and the service keeps every
    // answer on disk after that.
    for (final family in families) {
      final publisher =
          HuggingFaceAvatarService.creatorOrgFor(family.displayName) ??
          HuggingFaceAvatarService.publisherFromUrl(
            family.variants
                .firstWhere(
                  (variant) => variant.model.downloadUrl != null,
                  orElse: () => family.variants.first,
                )
                .model
                .downloadUrl,
          );
      if (publisher == null) continue;
      _familyPublishers[family.key] = publisher;
      if (!_publisherAvatars.containsKey(publisher) &&
          !_avatarRequests.contains(publisher)) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) unawaited(_loadPublisherAvatar(publisher));
        });
      }
    }

    final colorScheme = Theme.of(context).colorScheme;

    // Listen for errors and show SnackBar
    ref.listen(modelSelectionControllerProvider.select((s) => s.error), (
      previous,
      next,
    ) {
      if (next != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(next),
            backgroundColor: colorScheme.error,
            behavior: SnackBarBehavior.floating,
            action: SnackBarAction(
              label: 'Dismiss',
              textColor: colorScheme.onError,
              onPressed: () {
                ref
                    .read(modelSelectionControllerProvider.notifier)
                    .clearError();
              },
            ),
          ),
        );
        ref.read(modelSelectionControllerProvider.notifier).clearError();
      }
    });

    final installedFamilies = families
        .where((family) => family.hasInstalled)
        .toList(growable: false);
    final catalogFamilies = families
        .where((family) => !family.hasInstalled)
        .toList(growable: false);

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 760;

          final list = _buildListPane(
            context,
            state,
            installed: installedFamilies,
            catalog: catalogFamilies,
            wide: wide,
          );

          if (!wide) {
            return SafeArea(
              bottom: false,
              child: Column(
                children: [
                  _buildPhoneHeader(context, state),
                  _buildPhoneFilters(
                    context,
                    state,
                    visibleCapabilities: visibleCapabilities,
                    capabilityCounts: capabilityCounts,
                  ),
                  Expanded(child: list),
                  _buildStorageFooter(context, state),
                ],
              ),
            );
          }

          return Column(
            children: [
              _buildToolbar(
                context,
                state,
                modelCount: selectableModels.length,
                installedCount: installedFamilies.length,
              ),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildFilterRail(
                      context,
                      state,
                      visibleCapabilities: visibleCapabilities,
                      capabilityCounts: capabilityCounts,
                    ),
                    Expanded(child: list),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// The desktop toolbar: the catalog's name and counts, then the search, the
  /// sort control and the one action that adds a model.
  Widget _buildToolbar(
    BuildContext context,
    ModelSelectionState state, {
    required int modelCount,
    required int installedCount,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 10, 24, 10),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.7),
          ),
        ),
      ),
      child: Row(
        children: [
          Text(
            'Models',
            style: textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w600,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            '$modelCount models · $installedCount installed',
            style: textTheme.labelSmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const Spacer(),
          SizedBox(width: 250, child: _buildSearchField(context, state)),
          const SizedBox(width: 10),
          _buildSortButton(context, state, iconOnly: false),
          const SizedBox(width: 10),
          FilledButton.icon(
            onPressed: _showAddModelSheet,
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('Add model'),
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 40),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(9),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// The phone's title row. The search lives in its own row below it, so this
  /// one only carries the way back, the page name and the add action.
  ///
  /// The page builds its own headers instead of an [AppBar], so it has to
  /// offer the back control an [AppBar] would: Models is pushed from chat and
  /// settings, and on a narrow screen this row is the only way out.
  Widget _buildPhoneHeader(BuildContext context, ModelSelectionState state) {
    final textTheme = Theme.of(context).textTheme;
    final canGoBack = ModalRoute.of(context)?.canPop ?? false;
    return Padding(
      padding: EdgeInsets.fromLTRB(canGoBack ? 4 : 16, 4, 8, 4),
      child: Row(
        children: [
          if (canGoBack)
            IconButton(
              onPressed: () => Navigator.maybePop(context),
              icon: const Icon(Icons.arrow_back_rounded, size: 22),
              tooltip: 'Back',
            ),
          Text(
            'Models',
            style: textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w600,
              letterSpacing: -0.3,
            ),
          ),
          const Spacer(),
          IconButton(
            onPressed: _showAddModelSheet,
            icon: const Icon(Icons.add_rounded, size: 22),
            tooltip: 'Add model',
          ),
        ],
      ),
    );
  }

  Widget _buildSearchField(BuildContext context, ModelSelectionState state) {
    final colorScheme = Theme.of(context).colorScheme;
    return TextField(
      controller: _searchController,
      style: Theme.of(context).textTheme.bodyMedium,
      decoration: InputDecoration(
        hintText: 'Search models',
        prefixIcon: const Icon(Icons.search_rounded, size: 20),
        suffixIcon: state.searchQuery.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.clear_rounded, size: 18),
                tooltip: 'Clear search',
                onPressed: () {
                  _searchController.clear();
                  ref
                      .read(modelSelectionControllerProvider.notifier)
                      .clearSearch();
                  FocusScope.of(context).unfocus();
                },
              )
            : null,
        filled: true,
        fillColor: colorScheme.surfaceContainerHigh,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(9),
          borderSide: BorderSide.none,
        ),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(vertical: 12),
      ),
      onChanged: (value) {
        ref
            .read(modelSelectionControllerProvider.notifier)
            .setSearchQuery(value);
      },
    );
  }

  /// The ordering control. On a phone the label has no room, so the same menu
  /// opens from an icon beside the search field.
  Widget _buildSortButton(
    BuildContext context,
    ModelSelectionState state, {
    required bool iconOnly,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final label = state.sortByFit ? 'Sort: Best fit' : 'Sort: Smallest';

    return PopupMenuButton<bool>(
      tooltip: 'Sort models',
      initialValue: state.sortByFit,
      onSelected: (value) => ref
          .read(modelSelectionControllerProvider.notifier)
          .setSortByFit(value),
      itemBuilder: (context) => const [
        PopupMenuItem(value: true, child: Text('Best fit for this device')),
        PopupMenuItem(value: false, child: Text('Smallest first')),
      ],
      child: Container(
        width: iconOnly ? 40 : null,
        height: 40,
        alignment: Alignment.center,
        padding: iconOnly ? null : const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          border: Border.all(color: colorScheme.outlineVariant),
          borderRadius: BorderRadius.circular(9),
        ),
        child: iconOnly
            ? Icon(Icons.tune_rounded, size: 18, color: colorScheme.onSurface)
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: textTheme.labelLarge?.copyWith(
                      color: colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(
                    Icons.expand_more_rounded,
                    size: 18,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
      ),
    );
  }

  /// The phone's filter block: search with the sort icon, one scrollable
  /// capability track, one parameter control, and the device switch.
  Widget _buildPhoneFilters(
    BuildContext context,
    ModelSelectionState state, {
    required List<ModelCapability> visibleCapabilities,
    required Map<ModelCapability, int> capabilityCounts,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final device = ref.watch(deviceProfileProvider).value;
    final deviceMemory =
        device?.totalMemoryBytes ?? device?.availableMemoryBytes;

    final segments = <Widget>[
      _buildSegment(
        context,
        label: 'Best fit',
        width: 92,
        selected: state.sortByFit && state.selectedCapabilityFilters.isEmpty,
        onTap: () {
          ref.read(modelSelectionControllerProvider.notifier).clearFilters();
          ref
              .read(modelSelectionControllerProvider.notifier)
              .setSortByFit(true);
        },
      ),
      for (final capability in visibleCapabilities)
        _buildSegment(
          context,
          label: capability.label,
          width: 92,
          selected: state.selectedCapabilityFilters.contains(capability),
          onTap: () => ref
              .read(modelSelectionControllerProvider.notifier)
              .toggleCapabilityFilter(capability),
        ),
    ];

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.6),
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: _buildSearchField(context, state)),
              const SizedBox(width: 8),
              _buildSortButton(context, state, iconOnly: true),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            height: 34,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(17),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(mainAxisSize: MainAxisSize.min, children: segments),
            ),
          ),
          const SizedBox(height: 6),
          Container(
            height: 34,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(17),
            ),
            child: Row(
              children: [
                for (final bucket in _SizeBucket.values)
                  Expanded(
                    child: _buildSegment(
                      context,
                      label: bucket.label,
                      selected: _sizeBucket == bucket,
                      onTap: () => setState(
                        () =>
                            _sizeBucket = _sizeBucket == bucket ? null : bucket,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(
              children: [
                Text(
                  'Only what fits here',
                  style: textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurface,
                  ),
                ),
                const SizedBox(width: 8),
                _buildFitsSwitch(
                  context,
                  value: _onlyWhatFits,
                  onChanged: (value) => setState(() => _onlyWhatFits = value),
                ),
                const Spacer(),
                if (deviceMemory != null)
                  Text(
                    _formatBytes(deviceMemory),
                    style: textTheme.labelSmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// The "only what fits" toggle, drawn here rather than taken from Material:
  /// a switch scaled down to fit a 12px label row blurs its own track and
  /// thumb, and its off state reads as a stray grey pill. This one is a 44×26
  /// pill that goes to the accent colour when on.
  Widget _buildFitsSwitch(
    BuildContext context, {
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    const height = 24.0;
    const inset = 3.0;
    const thumb = height - inset * 2;

    return Semantics(
      toggled: value,
      label: 'Only what fits here',
      child: GestureDetector(
        onTap: () => onChanged(!value),
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          width: 42,
          height: height,
          padding: const EdgeInsets.all(inset),
          decoration: BoxDecoration(
            color: value
                ? colorScheme.primary
                : colorScheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(height / 2),
            border: Border.all(
              color: value ? colorScheme.primary : colorScheme.outlineVariant,
            ),
          ),
          child: AnimatedAlign(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOut,
            alignment: value ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              width: thumb,
              height: thumb,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: value ? colorScheme.onPrimary : colorScheme.surface,
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x1A000000),
                    blurRadius: 2,
                    offset: Offset(0, 1),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSegment(
    BuildContext context, {
    required String label,
    required bool selected,
    required VoidCallback onTap,
    double? width,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    // The chosen segment is a pill *inside* the track, not a slice of it: a
    // full-height slice rounds its own corners against the track's, which
    // leaves grey wedges that read as square cuts at the ends of the rail.
    return InkWell(
      onTap: onTap,
      // The theme's highlight is a cream wash: on a segment it painted a
      // full-height square slab over the rail's rounded end, which is what
      // read as a cut corner. The selected pill is the only selection cue the
      // rail needs, so the wash is kept transparent.
      highlightColor: Colors.transparent,
      hoverColor: colorScheme.outlineVariant.withValues(alpha: 0.18),
      focusColor: colorScheme.outlineVariant.withValues(alpha: 0.22),
      borderRadius: BorderRadius.circular(17),
      child: SizedBox(
        width: width,
        height: 34,
        child: Center(
          child: Container(
            height: 28,
            margin: const EdgeInsets.symmetric(horizontal: 4),
            padding: const EdgeInsets.symmetric(horizontal: 10),
            alignment: Alignment.center,
            decoration: selected
                ? BoxDecoration(
                    color: colorScheme.surface,
                    // Half the pill's height, so it reads as a rounded slot in
                    // the rail rather than a box with softened corners.
                    borderRadius: BorderRadius.circular(14),
                  )
                : null,
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: textTheme.labelMedium?.copyWith(
                fontSize: 12,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                color: selected
                    ? colorScheme.primary
                    : colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The desktop rail: tasks, parameter sizes, the device switch and the disk
  /// meter, all visible at once so nothing hides behind a "more" control.
  Widget _buildFilterRail(
    BuildContext context,
    ModelSelectionState state, {
    required List<ModelCapability> visibleCapabilities,
    required Map<ModelCapability, int> capabilityCounts,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final device = ref.watch(deviceProfileProvider).value;
    final deviceMemory =
        device?.totalMemoryBytes ?? device?.availableMemoryBytes;
    final free = state.freeStorageBytes;
    final total = state.totalStorageBytes;

    return Container(
      width: 264,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        border: Border(
          right: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.7),
          ),
        ),
      ),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
        children: [
          Text(
            'FILTERS',
            style: textTheme.labelSmall?.copyWith(
              letterSpacing: 0.8,
              fontWeight: FontWeight.w700,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'Task',
            style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          _buildRailRow(
            context,
            label: 'All models',
            icon: Icons.apps_rounded,
            selected: state.selectedCapabilityFilters.isEmpty,
            onTap: () => ref
                .read(modelSelectionControllerProvider.notifier)
                .clearFilters(),
          ),
          for (final capability in visibleCapabilities)
            _buildRailRow(
              context,
              label: capability.label,
              icon: _capabilityIcon(capability),
              count: capabilityCounts[capability],
              selected: state.selectedCapabilityFilters.contains(capability),
              onTap: () => ref
                  .read(modelSelectionControllerProvider.notifier)
                  .toggleCapabilityFilter(capability),
            ),
          const SizedBox(height: 16),
          Divider(height: 1, color: colorScheme.outlineVariant),
          const SizedBox(height: 16),
          Text(
            'Parameters',
            style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final bucket in _SizeBucket.values)
                _buildSizePill(
                  context,
                  label: bucket.label,
                  selected: _sizeBucket == bucket,
                  onTap: () => setState(
                    () => _sizeBucket = _sizeBucket == bucket ? null : bucket,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Divider(height: 1, color: colorScheme.outlineVariant),
          const SizedBox(height: 16),
          Text(
            // The wide layout's filter column is the same panel on a desktop and
            // a tablet; naming a Mac there told an Android tablet it was one.
            _isAppleDesktop ? 'This Mac' : 'This device',
            style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
          ),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Only what fits here',
                  style: textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurface,
                  ),
                ),
              ),
              _buildFitsSwitch(
                context,
                value: _onlyWhatFits,
                onChanged: (value) => setState(() => _onlyWhatFits = value),
              ),
            ],
          ),
          if (deviceMemory != null) ...[
            const SizedBox(height: 4),
            Text(
              '${_formatBytes(deviceMemory)} '
              '${_isAppleDesktop ? 'unified memory' : 'memory'}',
              style: textTheme.labelSmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: 22),
          Text(
            'DISK',
            style: textTheme.labelSmall?.copyWith(
              letterSpacing: 0.8,
              fontWeight: FontWeight.w700,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          _buildStorageBar(context, state),
          const SizedBox(height: 8),
          Text(
            free == null || total == null
                ? 'Storage unknown'
                : '${_formatBytes(free)} free of ${_formatBytes(total)}',
            style: textTheme.labelSmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => _showStorageSheet(context, state),
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
              ),
              child: const Text('Manage'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRailRow(
    BuildContext context, {
    required String label,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
    int? count,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Material(
      color: selected
          ? colorScheme.primary.withValues(alpha: 0.12)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            children: [
              Icon(
                icon,
                size: 15,
                color: selected
                    ? colorScheme.primary
                    : colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.bodySmall?.copyWith(
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    color: selected
                        ? colorScheme.primary
                        : colorScheme.onSurface,
                  ),
                ),
              ),
              if (count != null)
                Text(
                  '$count',
                  style: textTheme.labelSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSizePill(
    BuildContext context, {
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Material(
      color: selected ? colorScheme.primary : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            border: Border.all(
              color: selected
                  ? colorScheme.primary
                  : colorScheme.outlineVariant,
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            label,
            style: textTheme.labelMedium?.copyWith(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: selected ? colorScheme.onPrimary : colorScheme.onSurface,
            ),
          ),
        ),
      ),
    );
  }

  /// The disk meter both layouts show: the same widget the app already used,
  /// kept with its thresholds so a nearly full disk still reads as a warning.
  Widget _buildStorageBar(BuildContext context, ModelSelectionState state) {
    final colorScheme = Theme.of(context).colorScheme;
    final free = state.freeStorageBytes;
    final total = state.totalStorageBytes;
    if (free == null || total == null || total <= 0) {
      return const SizedBox.shrink();
    }
    final usedRatio = ((total - free) / total).clamp(0.0, 1.0);
    return LinearProgressIndicator(
      value: usedRatio,
      minHeight: 4,
      borderRadius: BorderRadius.circular(4),
      color: usedRatio >= 0.9
          ? colorScheme.error
          : usedRatio >= 0.7
          ? Colors.amber.shade700
          : colorScheme.primary,
      backgroundColor: colorScheme.surfaceContainerHighest,
    );
  }

  /// The phone's bottom bar: the disk meter, then what is left and the way to
  /// manage it. No divider above it — the meter itself is the edge.
  Widget _buildStorageFooter(BuildContext context, ModelSelectionState state) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final free = state.freeStorageBytes;
    final total = state.totalStorageBytes;
    if (free == null || total == null || total <= 0) {
      return const SizedBox.shrink();
    }

    return Container(
      color: colorScheme.surface,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
      child: Column(
        children: [
          _buildStorageBar(context, state),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  '${_formatBytes(free)} free of ${_formatBytes(total)}',
                  style: textTheme.labelSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              TextButton(
                onPressed: () => _showStorageSheet(context, state),
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                  minimumSize: const Size(0, 32),
                ),
                child: const Text('Manage'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// What the disk holds: the installed models and what each one costs. The
  /// sheet is read-only — deleting stays where it was, on the model's page.
  void _showStorageSheet(BuildContext context, ModelSelectionState state) {
    final installed = state.models
        .where((model) => model.isDownloaded)
        .toList(growable: false);
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Storage',
                style: textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                state.freeStorageBytes == null ||
                        state.totalStorageBytes == null
                    ? '${installed.length} models installed'
                    : '${installed.length} models installed · '
                          '${_formatBytes(state.freeStorageBytes!)} free of '
                          '${_formatBytes(state.totalStorageBytes!)}',
                style: textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              if (installed.isEmpty)
                Text(
                  'No models are installed yet.',
                  style: textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                )
              else
                for (final model in installed)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 7),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            model.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: textTheme.bodyMedium,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          switch (model.ggufMetadata?.fileSizeBytes) {
                            final bytes? => _formatBytes(bytes),
                            _ => model.parameterSize,
                          },
                          style: textTheme.labelSmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
            ],
          ),
        ),
      ),
    );
  }

  /// The catalog list: what is installed first, then the rest, one flat row
  /// per model. A row opens the model's own page; the button at its right is
  /// whatever applies to that model right now.
  Widget _buildListPane(
    BuildContext context,
    ModelSelectionState state, {
    required List<ModelFamily> installed,
    required List<ModelFamily> catalog,
    required bool wide,
  }) {
    if (installed.isEmpty && catalog.isEmpty) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          if (state.isLoadingModels)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else
            _buildEmptyFilterState(context, state),
        ],
      );
    }

    return ListView(
      padding: EdgeInsets.only(bottom: wide ? 16 : 8),
      children: [
        if (state.isLoadingModels)
          const Padding(
            padding: EdgeInsets.fromLTRB(12, 6, 12, 0),
            child: LinearProgressIndicator(minHeight: 2),
          ),
        if (installed.isNotEmpty) ...[
          _buildSectionHeader(
            context,
            'INSTALLED',
            wide: wide,
            trailing: installed.length > 1
                ? '${installed.length} installed'
                : null,
          ),
          for (final family in installed)
            _buildFamilyRow(context, state, family, wide: wide),
        ],
        if (catalog.isNotEmpty) ...[
          _buildSectionHeader(
            context,
            'CATALOG',
            wide: wide,
            trailing: '${catalog.length} more',
          ),
          for (final family in catalog)
            _buildFamilyRow(context, state, family, wide: wide),
        ],
        if (state.hasMoreModels)
          Padding(
            padding: EdgeInsets.fromLTRB(wide ? 24 : 12, 10, wide ? 24 : 12, 4),
            child: SizedBox(
              width: double.infinity,
              height: 42,
              child: FilledButton.tonal(
                onPressed: state.isLoadingMore
                    ? null
                    : () => ref
                          .read(modelSelectionControllerProvider.notifier)
                          .loadMoreModels(),
                child: state.isLoadingMore
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Load more models'),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildSectionHeader(
    BuildContext context,
    String title, {
    String? trailing,
    bool wide = true,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(wide ? 24 : 12, 14, wide ? 24 : 12, 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: textTheme.labelSmall?.copyWith(
                letterSpacing: 0.8,
                fontWeight: FontWeight.w700,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          if (trailing != null)
            Text(
              trailing,
              style: textTheme.labelSmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFamilyRow(
    BuildContext context,
    ModelSelectionState state,
    ModelFamily family, {
    required bool wide,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final publisher = _familyPublishers[family.key];
    // The installed member is the one this row acts on once it is on disk.
    final variant = family.variants.firstWhere(
      (candidate) => candidate.model.isDownloaded,
      orElse: () => family.variants.first,
    );
    final model = variant.model;
    final inUse = model.id == state.selectedModelId;
    final expanded = _expandedFamilyKey == family.key;
    // An installed row's job is to become the app's model, so a tap anywhere on
    // it selects; a catalog row has nothing to select yet, so a tap unfolds it.
    // A record whose file went missing is the exception: its tap must reach the
    // card that offers the download that repairs it.
    final selectsOnTap = family.hasInstalled && !model.fileMissing;
    // The publisher reads as a fact about the file, so it sits in the meta
    // line; the title is then the repository name alone, which is what the
    // catalog row is actually pointing at.
    final repository = _repositoryLabel(model);
    final title = repository?.repo ?? family.displayName;
    final device = ref.watch(deviceProfileProvider).value;

    final sizeBytes = variant.fileSizeBytes ?? variant.approximateFileSizeBytes;
    final contextTokens = model.ggufMetadata?.contextLength;
    final meta = <String>[
      ?repository?.publisher,
      variant.parameterSize,
      if (sizeBytes != null) _formatBytes(sizeBytes),
      ?variant.quantization,
      if (contextTokens != null) '${_formatContext(contextTokens)} context',
    ].join(' · ');
    final fit = _rowFitLabel(context, variant, device);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          // The model the chat is running is the list's selected item, so its
          // row carries the selection rather than only its icon.
          color: inUse
              ? colorScheme.primary.withValues(alpha: 0.07)
              : Colors.transparent,
          child: InkWell(
            onTap: selectsOnTap
                ? () => ref
                      .read(modelSelectionControllerProvider.notifier)
                      .selectModel(model)
                : () => _toggleFamilyDetails(family, model),
            child: Container(
              padding: EdgeInsets.symmetric(
                horizontal: wide ? 24 : 12,
                vertical: wide ? 12 : 9,
              ),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: colorScheme.outlineVariant.withValues(alpha: 0.55),
                  ),
                ),
              ),
              child: Row(
                children: [
                  _buildFamilyMonogram(
                    context,
                    family,
                    publisher,
                    size: wide ? 38 : 34,
                  ),
                  SizedBox(width: wide ? 14 : 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: _monoTitle(context, wide: wide),
                              ),
                            ),

                            if (family.hasMissingFile) ...[
                              const SizedBox(width: 6),
                              Tooltip(
                                message: 'File missing — download again',
                                child: Icon(
                                  Icons.report_gmailerrorred_rounded,
                                  size: 15,
                                  color: colorScheme.error,
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          meta,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.labelSmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                        if (fit != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            fit.text,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: textTheme.labelSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: fit.color,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  SizedBox(width: wide ? 12 : 6),
                  _buildRowAction(context, model, inUse: inUse),
                  _buildExpandButton(
                    context,
                    expanded: expanded,
                    onTap: () => _toggleFamilyDetails(family, model),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (expanded)
          _buildExpandedCard(context, state, model, family: family, wide: wide),
      ],
    );
  }

  /// Opens a row's details under it, or folds them away. The list stays where
  /// it is, so comparing a model against its neighbours costs no navigation.
  void _toggleFamilyDetails(ModelFamily family, LlmModel model) {
    unawaited(_loadFitReport(model));
    unawaited(_loadGgufMetadata(model));
    setState(() {
      _focusedModelId = model.id;
      _expandedFamilyKey = _expandedFamilyKey == family.key ? null : family.key;
    });
  }

  /// The chevron that unfolds a row. It sits beside the action so the two
  /// read as a pair: what this row does, and what else there is to know.
  Widget _buildExpandButton(
    BuildContext context, {
    required bool expanded,
    required VoidCallback onTap,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return IconButton(
      onPressed: onTap,
      tooltip: expanded ? 'Hide details' : 'Show details',
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 34, height: 40),
      iconSize: 22,
      color: colorScheme.primary,
      icon: Icon(
        expanded
            ? Icons.keyboard_arrow_up_rounded
            : Icons.keyboard_arrow_down_rounded,
      ),
    );
  }

  /// Everything about one model, unfolded under its row: the identity line,
  /// the description, the family's variant ledger, the estimate for this
  /// device, the file's facts and its actions. A family is always a ledger —
  /// one row per variant with its context, size, fit on this device and
  /// action, whether it holds one variant or several — and a row opens in
  /// place to carry its own quantization, fit meter and file facts.
  Widget _buildExpandedCard(
    BuildContext context,
    ModelSelectionState state,
    LlmModel model, {
    required ModelFamily family,
    required bool wide,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isSelected = model.id == state.selectedModelId;

    // The card is the details, so the estimate it shows is asked for on
    // arrival rather than after a tap.
    if (!_fitRequests.contains(model.id) &&
        !_fitReports.containsKey(model.id)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_loadFitReport(model));
      });
    }

    final identity = <String>[
      family.parameterRange,
      model.promptFormatId,
      model.isCustom ? 'Custom' : model.effectiveSource.label,
    ].join(' · ');

    final progress = ref.watch(
      downloadProgressProvider.select((all) => all[model.id]),
    );

    return Padding(
      // The details hang under the row's text column, not out at the avatar,
      // and stand clear of the row's own last line.
      padding: EdgeInsets.fromLTRB(wide ? 76 : 60, 12, wide ? 24 : 16, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            identity,
            style: textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            model.description,
            style: textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          if (model.isCustom) ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: colorScheme.tertiaryContainer,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'Custom',
                  style: textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: colorScheme.onTertiaryContainer,
                  ),
                ),
              ),
            ),
          ],
          if (model.capabilities.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: model.capabilities
                  .map(
                    (capability) => _buildCapabilityBadge(
                      context,
                      capability,
                      isSelected: false,
                    ),
                  )
                  .toList(growable: false),
            ),
          ],
          // The ledger is where a variant is downloaded, so it is always here
          // for a model that is not; a choice between variants keeps it too.
          if (family.variantCount > 1 || !model.isDownloaded) ...[
            const SizedBox(height: 18),
            _buildVariantLedger(
              context,
              family,
              selectedModelId: state.selectedModelId,
            ),
          ],
          // Before the download the row's own fit line is the estimate, so
          // "install to estimate" and an empty file table would only repeat
          // what the row already says.
          if (model.isDownloaded) ...[
            const SizedBox(height: 18),
            _buildDetailSection(
              context,
              'On this device',
              _buildFitMeter(context, model),
            ),
            const SizedBox(height: 16),
            _buildDetailSection(context, 'File', _buildFacts(context, model)),
          ],
          // A file that is here has actions of its own; a file that is coming
          // down keeps its progress and pause. A catalog row with nothing in
          // flight is downloaded from the ledger above it.
          if (model.isDownloaded || progress != null) ...[
            const SizedBox(height: 14),
            Divider(
              height: 1,
              color: colorScheme.outlineVariant.withValues(alpha: 0.6),
            ),
            const SizedBox(height: 12),
            if (model.fileMissing) ...[
              _buildMissingFileNotice(context, model),
              const SizedBox(height: 12),
            ],
            _buildDetailActions(context, model, isSelected: isSelected),
          ],
        ],
      ),
    );
  }

  /// `Qwen/Qwen3-0.6B`: the publisher who owns a catalog entry and the
  /// repository Hugging Face lists it under. Null for a model added by direct
  /// URL, whose own name then stands in.
  ({String? publisher, String repo})? _repositoryLabel(LlmModel model) {
    final url = model.downloadUrl;
    if (url == null || url.trim().isEmpty) return null;
    final repository = HuggingFaceRepositoryService.parseRepositoryInput(url);
    final trimmed = repository?.trim() ?? '';
    if (trimmed.isEmpty) return null;
    final slash = trimmed.indexOf('/');
    if (slash <= 0 || slash == trimmed.length - 1) {
      return (publisher: null, repo: trimmed);
    }
    return (
      publisher: trimmed.substring(0, slash),
      repo: trimmed.substring(slash + 1),
    );
  }

  TextStyle? _monoTitle(BuildContext context, {required bool wide}) {
    return Theme.of(context).textTheme.bodyMedium?.copyWith(
      fontFamily: 'monospace',
      fontFamilyFallback: const ['Menlo', 'Roboto Mono', 'Courier New'],
      fontWeight: FontWeight.w600,
      fontSize: wide ? 14 : 13,
      color: Theme.of(context).colorScheme.onSurface,
    );
  }

  /// How well the row's own file is expected to run here, with the share of
  /// the device's memory budget it would take. Null when neither the file size
  /// nor the device's memory is known, so the row stays quiet instead of
  /// guessing.
  ({String text, Color color})? _rowFitLabel(
    BuildContext context,
    ModelVariant variant,
    DeviceProfile? device,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final rating = variantFitRating(
      variant,
      kvCacheMetadata: variant.model.ggufMetadata,
      contextTokens: ModelCompatibilityService.defaultContextTokens,
      totalMemoryBytes: device?.totalMemoryBytes,
      availableMemoryBytes: device?.availableMemoryBytes,
    );
    if (rating == null) return null;
    final color = switch (rating) {
      ModelCompatibilityRating.recommended ||
      ModelCompatibilityRating.shouldRun => colorScheme.primary,
      ModelCompatibilityRating.mayBeSlow => Colors.amber.shade700,
      ModelCompatibilityRating.memoryRisk ||
      ModelCompatibilityRating.notRecommended => colorScheme.error,
    };
    final bytes = variant.fileSizeBytes ?? variant.approximateFileSizeBytes;
    final budget = ModelCompatibilityEstimator.memoryBudget(
      totalMemoryBytes: device?.totalMemoryBytes,
      availableMemoryBytes: device?.availableMemoryBytes,
    );
    final text = bytes != null && budget != null
        ? '${rating.label} · ${(bytes / budget).toStringAsFixed(1)} of '
              '${_formatBytes(budget)}'
        : rating.label;
    return (text: text, color: color);
  }

  /// The row's action: progress while a file is coming down, the model's own
  /// page action once it is here, and the download that starts it otherwise.
  Widget _buildRowAction(
    BuildContext context,
    LlmModel model, {
    required bool inUse,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Consumer(
      builder: (context, ref, _) {
        final progress = ref.watch(
          downloadProgressProvider.select((all) => all[model.id]),
        );
        if (progress != null) {
          return Text(
            '${(progress.progress * 100).round()}%',
            style: textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurfaceVariant,
            ),
          );
        }

        final controller = ref.read(modelSelectionControllerProvider.notifier);
        // The model in use states that on the right, where the action is: an
        // "Open" button there would be a no-op beside a row that already says
        // what the chat is running.
        if (inUse) {
          return Tooltip(
            message: 'In use',
            child: SizedBox(
              width: 40,
              height: 40,
              child: Icon(
                Icons.check_circle_rounded,
                size: 20,
                color: colorScheme.primary,
              ),
            ),
          );
        }

        // A row action is a quiet accent glyph, not a boxed button: every row
        // carries one, and a label on all of them turns a list of names into a
        // list of buttons. The tooltip keeps the verb for the pointer and for
        // screen readers.
        //
        // An installed model offers the same circle the in-use one fills: the
        // column then reads as one choice among the models on disk, rather
        // than as a row of arrows pointing somewhere else.
        return IconButton(
          onPressed: model.isDownloaded
              ? () => controller.selectModel(model)
              : () => _handleDownload(model),
          tooltip: model.isDownloaded ? 'Use this model' : 'Download',
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints.tightFor(width: 36, height: 40),
          iconSize: model.isDownloaded ? 21 : 22,
          color: colorScheme.primary,
          icon: Icon(
            model.isDownloaded
                ? Icons.radio_button_unchecked_rounded
                : Icons.download_rounded,
          ),
        );
      },
    );
  }

  /// A circular avatar per family: the publisher's own Hugging Face picture
  /// when one was fetched, otherwise a letter monogram in the same circle, so
  /// the two states share one footprint.
  Widget _buildFamilyMonogram(
    BuildContext context,
    ModelFamily family,
    String? publisher, {
    int size = 32,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final bytes = publisher == null ? null : _publisherAvatars[publisher];
    if (bytes != null) {
      return ClipOval(
        child: Image.memory(
          bytes,
          width: size.toDouble(),
          height: size.toDouble(),
          fit: BoxFit.cover,
          gaplessPlayback: true,
        ),
      );
    }
    final initial = family.displayName.trim().isEmpty
        ? '?'
        : family.displayName.trim()[0].toUpperCase();
    return Container(
      width: size.toDouble(),
      height: size.toDouble(),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: colorScheme.surfaceContainerHigh,
      ),
      child: Text(
        initial,
        style: TextStyle(
          color: colorScheme.onSurface,
          fontSize: size * 0.4,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  /// Says plainly that a record's file is gone, so the Download button under it
  /// is understood as a repair rather than a first install.
  Widget _buildMissingFileNotice(BuildContext context, LlmModel model) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: colorScheme.errorContainer.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.report_gmailerrorred_rounded,
            size: 20,
            color: colorScheme.error,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              "This model's file is missing from this device. Download it "
              'again to chat with it — nothing else about the model was lost.',
              style: textTheme.bodyMedium?.copyWith(
                color: colorScheme.onErrorContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// The family's variants as a ledger: a labelled column row per member —
  /// its size, how it fits this device, what it costs, and its action — with
  /// the focused member opening in place to show the quantization, the fit
  /// estimate and the file facts that belong to it. Picking a row switches
  /// the pane to that variant; nothing is downloaded or chosen for the app
  /// by doing so.
  Widget _buildVariantLedger(
    BuildContext context,
    ModelFamily family, {
    required String? selectedModelId,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final device = ref.watch(deviceProfileProvider).value;

    // Siblings share an architecture, so one member's GGUF metadata supplies
    // the KV-cache shape for every member's rough `fit` estimate.
    GgufMetadata? kvCacheMetadata;
    for (final variant in family.variants) {
      final metadata = variant.model.ggufMetadata;
      if (metadata != null) {
        kvCacheMetadata = metadata;
        break;
      }
    }

    Widget columnHeader(
      String label, {
      Alignment alignment = Alignment.centerLeft,
    }) => Align(
      alignment: alignment,
      child: Text(
        label,
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(
          context,
        ).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w700),
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        // A narrow pane cannot hold every column; the context pair is the one
        // that can stand down without taking the row's actions with it.
        final showContext = constraints.maxWidth >= 560;
        // A phone-width ledger has no room for a heading that wraps to five
        // lines, and a fixed 104 px Action column only ever holds "Use". The
        // fit badge is the widest thing a row shows, so the fixed columns give
        // way to it instead of squeezing the one column that carries meaning.
        final compact = constraints.maxWidth < 460;
        // Quantization names are short but wide in the mono face: `Q4_K_M`
        // must not wrap inside its own column.
        final sizeColumnWidth = compact ? 74.0 : 96.0;
        const contextColumnWidth = 96.0;
        final costColumnWidth = compact ? 76.0 : 104.0;
        final actionColumnWidth = compact ? 76.0 : 104.0;

        return Container(
          decoration: BoxDecoration(
            border: Border.all(color: colorScheme.outlineVariant),
            borderRadius: BorderRadius.circular(10),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                child: Row(
                  children: [
                    SizedBox(
                      width: sizeColumnWidth,
                      child: columnHeader('Quant'),
                    ),
                    Expanded(
                      child: columnHeader(
                        compact ? 'Fit' : 'Fit on this device',
                      ),
                    ),
                    if (showContext)
                      SizedBox(
                        width: contextColumnWidth,
                        child: columnHeader(
                          'Context',
                          alignment: Alignment.centerRight,
                        ),
                      ),
                    SizedBox(
                      width: costColumnWidth,
                      child: columnHeader(
                        'Size',
                        alignment: Alignment.centerRight,
                      ),
                    ),
                    SizedBox(
                      width: actionColumnWidth,
                      child: columnHeader(
                        'Action',
                        alignment: Alignment.centerRight,
                      ),
                    ),
                  ],
                ),
              ),
              for (var index = 0; index < family.variants.length; index++) ...[
                Divider(
                  height: 1,
                  thickness: 1,
                  color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                ),
                _buildVariantLedgerRow(
                  context,
                  family,
                  family.variants[index],
                  kvCacheMetadata: kvCacheMetadata,
                  device: device,
                  selected: family.variants[index].model.id == _focusedModelId,
                  inUse: family.variants[index].model.id == selectedModelId,
                  sizeWidth: sizeColumnWidth,
                  compact: compact,
                  showContext: showContext,
                  contextWidth: contextColumnWidth,
                  costWidth: costColumnWidth,
                  actionWidth: actionColumnWidth,
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildVariantLedgerRow(
    BuildContext context,
    ModelFamily family,
    ModelVariant variant, {
    required GgufMetadata? kvCacheMetadata,
    required DeviceProfile? device,
    required bool selected,
    required bool inUse,
    required double sizeWidth,
    required bool compact,
    required bool showContext,
    required double contextWidth,
    required double costWidth,
    required double actionWidth,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final controller = ref.read(modelSelectionControllerProvider.notifier);
    final rating = variantFitRating(
      variant,
      kvCacheMetadata: kvCacheMetadata,
      contextTokens: ModelCompatibilityService.defaultContextTokens,
      totalMemoryBytes: device?.totalMemoryBytes,
      availableMemoryBytes: device?.availableMemoryBytes,
    );
    final badgeColor = switch (rating) {
      ModelCompatibilityRating.recommended => colorScheme.primary,
      ModelCompatibilityRating.shouldRun => colorScheme.tertiary,
      ModelCompatibilityRating.mayBeSlow => Colors.amber.shade700,
      ModelCompatibilityRating.memoryRisk ||
      ModelCompatibilityRating.notRecommended => colorScheme.error,
      null => null,
    };
    final exactBytes = variant.fileSizeBytes;
    final sizeBytes = exactBytes ?? variant.approximateFileSizeBytes;

    // The pair the Context column shows: what the file declares, and how much
    // of it the device's memory budget can hold beside the weights. A catalog
    // record carries no snapshot, so an installed file is read on demand.
    final metadata =
        variant.model.ggufMetadata ?? _liveGgufMetadata[variant.model.id];
    if (metadata == null &&
        variant.model.isDownloaded &&
        !_liveGgufMetadata.containsKey(variant.model.id)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_loadGgufMetadata(variant.model));
      });
    }
    // A model that is not on disk still declares its window in the
    // repository's own GGUF metadata, which is public and can be shown
    // before the download.
    final repoId = switch (variant.model.downloadUrl) {
      final url? => HuggingFaceRepositoryService.parseRepositoryInput(url),
      _ => null,
    };
    final needsRemoteContext =
        metadata?.contextLength == null &&
        repoId != null &&
        !_remoteContextByRepo.containsKey(repoId);
    if (needsRemoteContext) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_loadRemoteContext(repoId));
      });
    }
    final remoteContext = repoId == null ? null : _remoteContextByRepo[repoId];
    final contextFromRemote =
        metadata?.contextLength == null && remoteContext != null;
    final providedContext = metadata?.contextLength ?? remoteContext;
    int? runnableContext;
    if (metadata != null) {
      runnableContext = ModelCompatibilityEstimator.maxContextTokens(
        metadata: metadata,
        weightsBytes: sizeBytes ?? 0,
        totalMemoryBytes: device?.totalMemoryBytes,
        availableMemoryBytes: device?.availableMemoryBytes,
      );
      if (runnableContext != null &&
          providedContext != null &&
          providedContext > 0 &&
          runnableContext > providedContext) {
        runnableContext = providedContext;
      }
    }
    final hasContext = providedContext != null && providedContext > 0;
    final contextLabel = !hasContext
        ? '—'
        : runnableContext == null || runnableContext <= 0
        ? '${_formatContext(providedContext)} / —'
        : '${_formatContext(providedContext)} / '
              '${_formatContext(runnableContext)}';
    final contextTooltip = !hasContext
        ? 'Context is read from the GGUF file once the model is installed.'
        : runnableContext == null || runnableContext <= 0
        ? 'The model provides ${_formatContext(providedContext)} context'
              '${contextFromRemote ? ', read from Hugging Face' : ''}; this '
              'device cannot estimate how much of it fits.'
        : 'The model provides ${_formatContext(providedContext)} context; about '
              '${_formatContext(runnableContext)} fit this device.';

    // The ledger's action column is that variant's own control: a download for
    // a file that is not here, the circle the rows use once it is, a live
    // percentage while it arrives, and the filled check for the model in use.
    final progress = ref.watch(
      downloadProgressProvider.select((all) => all[variant.model.id]),
    );
    final Widget action;
    if (progress != null) {
      action = Text(
        '${(progress.progress * 100).round()}%',
        style: textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w600,
          color: colorScheme.onSurfaceVariant,
        ),
      );
    } else if (!variant.model.isDownloaded) {
      action = IconButton(
        onPressed: () => _handleDownload(variant.model),
        tooltip: variant.quantization == null
            ? 'Download'
            : 'Download ${variant.quantization}',
        visualDensity: VisualDensity.compact,
        iconSize: 20,
        color: colorScheme.primary,
        icon: const Icon(Icons.download_rounded),
      );
    } else if (inUse) {
      action = Icon(
        Icons.check_circle_rounded,
        size: 20,
        color: colorScheme.primary,
      );
    } else {
      action = IconButton(
        onPressed: () => controller.selectModel(variant.model),
        tooltip: 'Use this model',
        visualDensity: VisualDensity.compact,
        iconSize: 20,
        color: colorScheme.primary,
        icon: const Icon(Icons.radio_button_unchecked_rounded),
      );
    }

    return Material(
      color: selected
          ? colorScheme.primary.withValues(alpha: 0.10)
          : Colors.transparent,
      child: InkWell(
        onTap: () {
          unawaited(_loadFitReport(variant.model));
          // The row is the model: tapping an installed variant makes it the
          // app's model, the same as its circle.
          controller.selectModel(variant.model);
          setState(() => _focusedModelId = variant.model.id);
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(
                children: [
                  SizedBox(
                    width: sizeWidth,
                    child: Text(
                      variant.quantization ?? variant.parameterSize,
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.labelLarge?.copyWith(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Expanded(
                    // An empty cell reads as a layout fault; a dash says the
                    // estimate is missing and why, like the Context column.
                    child: badgeColor == null
                        ? Tooltip(
                            message: device == null
                                ? 'Reading this device\'s memory…'
                                : 'Fit is not known for this file',
                            child: Text(
                              '—',
                              style: textTheme.labelSmall?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          )
                        : Align(
                            alignment: Alignment.centerLeft,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: badgeColor.withValues(alpha: 0.85),
                                borderRadius: BorderRadius.circular(5),
                              ),
                              // A phone's fit column is about eighty pixels
                              // wide, so it gets one short word rather than
                              // "Recommended" cut down to "Reco…".
                              child: Text(
                                compact
                                    ? switch (rating!) {
                                        ModelCompatibilityRating.recommended =>
                                          'Fits',
                                        ModelCompatibilityRating.shouldRun =>
                                          'OK',
                                        ModelCompatibilityRating.mayBeSlow =>
                                          'Slow',
                                        ModelCompatibilityRating.memoryRisk =>
                                          'Risk',
                                        ModelCompatibilityRating
                                            .notRecommended =>
                                          'No',
                                      }
                                    : rating!.label,
                                maxLines: 1,
                                softWrap: false,
                                overflow: TextOverflow.ellipsis,
                                style: textTheme.labelSmall?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                  ),
                  if (showContext)
                    SizedBox(
                      width: contextWidth,
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: Tooltip(
                          message: contextTooltip,
                          child: Text(
                            contextLabel,
                            maxLines: 1,
                            softWrap: false,
                            overflow: TextOverflow.ellipsis,
                            style: textTheme.labelSmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                    ),
                  SizedBox(
                    width: costWidth,
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        sizeBytes == null
                            ? (compact ? '—' : 'Install to estimate')
                            : exactBytes == null
                            ? '~${_formatBytes(sizeBytes)}'
                            : _formatBytes(exactBytes),
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.labelSmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: actionWidth,
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: action,
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailSection(BuildContext context, String label, Widget child) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        child,
      ],
    );
  }

  /// How much memory this model would take, as a bar against the device's own
  /// budget, with the existing wording underneath.
  Widget _buildFitMeter(BuildContext context, LlmModel model) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final estimate = _fitReports[model.id]?.estimate;
    final ratio = estimate?.headroomRatio;
    final color = switch (estimate?.rating) {
      ModelCompatibilityRating.recommended => colorScheme.primary,
      ModelCompatibilityRating.shouldRun => colorScheme.tertiary,
      ModelCompatibilityRating.mayBeSlow => Colors.amber.shade700,
      ModelCompatibilityRating.memoryRisk ||
      ModelCompatibilityRating.notRecommended => colorScheme.error,
      null => colorScheme.primary,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (ratio != null) ...[
          LinearProgressIndicator(
            value: ratio.clamp(0.0, 1.0),
            minHeight: 6,
            borderRadius: BorderRadius.circular(4),
            color: color,
            backgroundColor: colorScheme.surfaceContainerHighest,
          ),
          const SizedBox(height: 8),
        ],
        Text(
          _fitLabel(model),
          style: textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _buildFacts(BuildContext context, LlmModel model) {
    final facts = <(String, String)>[
      ('Kind', model.isCustom ? 'Custom' : 'Built-in'),
      ('Source', model.effectiveSource.label),
      ('Prompt format', model.promptFormatId),
      (
        'Vision projector',
        model.mmprojLocalFileName ??
            (model.mmprojDownloadUrl != null
                ? 'Downloads with the model'
                : 'None'),
      ),
      (
        'Installed',
        model.isDownloaded
            ? 'Yes'
            : model.fileMissing
            ? 'File missing'
            : 'No',
      ),
      (
        'Capabilities',
        model.capabilities.isEmpty
            ? 'None'
            : model.capabilities
                  .map((capability) => capability.label)
                  .join(', '),
      ),
      if (model.localFileName != null) ('Local file', model.localFileName!),
      if (model.isExternal) ('External file', model.externalPath ?? 'Unknown'),
      if (model.downloadUrl != null) ('Download URL', model.downloadUrl!),
      ('ID', model.id),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = 20.0;
        // Low enough that a window of about 400 dp holds two columns, high
        // enough that a phone's own width stays one readable column.
        const minimumCell = 170.0;
        final available = constraints.maxWidth;

        // The cells share the width they are given instead of sitting at a
        // fixed 220 dp. A pane between about 460 and 700 dp fitted one cell per
        // line and left half of every line empty, which is what made this
        // section twice as tall as the room it had.
        if (!available.isFinite) {
          return Wrap(
            spacing: 24,
            runSpacing: 12,
            children: [
              for (final (label, value) in facts)
                SizedBox(
                  width: 220,
                  child: _buildDetailRow(context, label, value),
                ),
            ],
          );
        }

        final columns = ((available + spacing) / (minimumCell + spacing))
            .floor()
            .clamp(1, 3)
            .toInt();
        final cellWidth = (available - spacing * (columns - 1)) / columns;

        return Wrap(
          spacing: spacing,
          runSpacing: 12,
          children: [
            for (final (label, value) in facts)
              SizedBox(
                width: cellWidth,
                child: _buildDetailRow(context, label, value),
              ),
          ],
        );
      },
    );
  }

  Widget _buildDetailActions(
    BuildContext context,
    LlmModel model, {
    required bool isSelected,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final controller = ref.read(modelSelectionControllerProvider.notifier);
    final progress = ref.watch(
      downloadProgressProvider.select((all) => all[model.id]),
    );
    final loading = _quantizationLoading.contains(model.id);
    final quantization =
        _selectedQuantization[model.id] ?? ModelFamilies.quantizationOf(model);

    if (model.isDownloaded) {
      return Wrap(
        spacing: 12,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (isSelected)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.check_circle_rounded,
                  size: 18,
                  color: colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  'In use',
                  style: textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: colorScheme.primary,
                  ),
                ),
              ],
            )
          else
            FilledButton.tonal(
              onPressed: () => controller.selectModel(model),
              child: const Text('Use this model'),
            ),
          OutlinedButton.icon(
            onPressed: () => context.push(AppRoutes.modelDetailsFor(model.id)),
            icon: const Icon(Icons.science_outlined, size: 18),
            label: const Text('GGUF metadata'),
          ),
          TextButton(
            onPressed: () => _showDeleteConfirmation(context, model),
            style: TextButton.styleFrom(foregroundColor: colorScheme.error),
            child: Text(model.isExternal ? 'Remove' : 'Delete'),
          ),
        ],
      );
    }

    if (progress != null) {
      return Row(
        children: [
          Expanded(
            child: _ModelDownloadBar(modelId: model.id, isSelected: false),
          ),
          const SizedBox(width: 12),
          IconButton(
            onPressed: () => controller.pauseDownload(model.id),
            icon: const Icon(Icons.pause_circle_outline_rounded),
            tooltip: 'Pause download',
            color: colorScheme.primary,
          ),
        ],
      );
    }

    return FilledButton.icon(
      onPressed: loading ? null : () => _handleDownload(model),
      icon: loading
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.download_rounded, size: 18),
      label: Text(quantization == null ? 'Download' : 'Download $quantization'),
    );
  }

  Widget _buildEmptyFilterState(
    BuildContext context,
    ModelSelectionState state,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final hasSearch = state.searchQuery.trim().isNotEmpty;
    final hasFilters =
        state.selectedCapabilityFilters.isNotEmpty || !state.sortByFit;
    // Nothing searched and nothing filtered means the catalog itself is empty:
    // either it has not been read yet or the last read failed.
    final isEmptyCatalog = !hasSearch && !hasFilters;
    final message = isEmptyCatalog
        ? 'No models yet.'
        : hasSearch && hasFilters
        ? 'No models match the search query and selected filters.'
        : hasSearch
        ? 'No models match your search.'
        : 'No models match the selected filters.';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Card(
        color: colorScheme.surfaceContainerLow,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                message,
                style: textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                isEmptyCatalog
                    ? 'The list is read from Hugging Face, not compiled into '
                          'the app. Connect to the internet and load it again.'
                    : 'Try adjusting your search or removing filters to see '
                          'more models.',
                style: textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              if (isEmptyCatalog) ...[
                const SizedBox(height: 12),
                FilledButton.tonal(
                  onPressed: () => ref
                      .read(modelSelectionControllerProvider.notifier)
                      .refreshCatalog(),
                  child: const Text('Load models'),
                ),
              ],
              if (hasSearch || hasFilters) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (hasSearch)
                      FilledButton.tonal(
                        onPressed: () {
                          _searchController.clear();
                          ref
                              .read(modelSelectionControllerProvider.notifier)
                              .clearSearch();
                        },
                        child: const Text('Clear Search'),
                      ),
                    if (hasFilters)
                      FilledButton.tonal(
                        onPressed: () {
                          ref
                              .read(modelSelectionControllerProvider.notifier)
                              .clearFilters();
                        },
                        child: const Text('Clear Filters'),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Map<ModelCapability, int> _buildCapabilityCounts(List<LlmModel> models) {
    final counts = <ModelCapability, int>{};
    for (final capability in ModelCapability.values) {
      counts[capability] = 0;
    }

    for (final model in models) {
      for (final capability in model.capabilities) {
        counts[capability] = (counts[capability] ?? 0) + 1;
      }
    }

    return counts;
  }

  int _compareModelsByParamSize(LlmModel a, LlmModel b) {
    final aSize = _toNumericParameterSize(a.parameterSize);
    final bSize = _toNumericParameterSize(b.parameterSize);

    final bySize = aSize.compareTo(bSize);
    if (bySize != 0) return bySize;
    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  }

  int _compareModelsPrioritizingInstalled(LlmModel a, LlmModel b) {
    final byDownloaded = (b.isDownloaded ? 1 : 0).compareTo(
      a.isDownloaded ? 1 : 0,
    );
    if (byDownloaded != 0) return byDownloaded;
    return _compareModelsByParamSize(a, b);
  }

  double _toNumericParameterSize(String value) {
    final raw = value.trim().toUpperCase();
    final match = RegExp(r'^([0-9]*\.?[0-9]+)\s*([KMBT]?)$').firstMatch(raw);
    if (match == null) return double.infinity;

    final number = double.tryParse(match.group(1) ?? '');
    if (number == null) return double.infinity;
    final unit = match.group(2) ?? '';
    return switch (unit) {
      'K' => number * 1e3,
      'M' => number * 1e6,
      'B' => number * 1e9,
      'T' => number * 1e12,
      _ => number,
    };
  }

  Widget _buildDetailRow(BuildContext context, String label, String value) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: textTheme.labelSmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          SelectableText(
            value,
            style: textTheme.bodySmall?.copyWith(color: colorScheme.onSurface),
          ),
        ],
      ),
    );
  }

  Widget _buildCapabilityBadge(
    BuildContext context,
    ModelCapability capability, {
    required bool isSelected,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final backgroundColor = isSelected
        ? colorScheme.primary.withValues(alpha: 0.14)
        : colorScheme.primaryContainer.withValues(alpha: 0.55);
    final foregroundColor = isSelected
        ? colorScheme.primary
        : colorScheme.onPrimaryContainer;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_capabilityIcon(capability), size: 16, color: foregroundColor),
          const SizedBox(width: 6),
          Text(
            capability.label.toLowerCase(),
            style: textTheme.labelMedium?.copyWith(
              color: foregroundColor,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  IconData _capabilityIcon(ModelCapability capability) {
    return switch (capability) {
      ModelCapability.vision => Icons.visibility_rounded,
      ModelCapability.audio => Icons.graphic_eq_rounded,
      ModelCapability.tools => Icons.build_rounded,
      ModelCapability.thinking => Icons.psychology_rounded,
      ModelCapability.coding => Icons.code_rounded,
      ModelCapability.embedding => Icons.hub_rounded,
    };
  }

  /// Bottom sheet with the three ways a model can enter the app: a local
  /// GGUF import, a Hugging Face repository or a direct download link.
  Future<void> _showAddModelSheet() async {
    final action = await showModalBottomSheet<_AddModelAction>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Add a model',
                  style: Theme.of(sheetContext).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.folder_open_rounded),
              title: const Text('Import GGUF from this device'),
              subtitle: const Text(
                'Read metadata, then copy it in or keep it where it is',
              ),
              onTap: () =>
                  Navigator.of(sheetContext).pop(_AddModelAction.importFile),
            ),
            ListTile(
              leading: const Icon(Icons.travel_explore_rounded),
              title: const Text('Browse a Hugging Face repository'),
              subtitle: const Text('author/repository or huggingface.co link'),
              onTap: () => Navigator.of(
                sheetContext,
              ).pop(_AddModelAction.huggingFaceRepo),
            ),
            ListTile(
              leading: const Icon(Icons.link_rounded),
              title: const Text('Add a direct download link'),
              subtitle: const Text('Any direct .gguf URL'),
              onTap: () =>
                  Navigator.of(sheetContext).pop(_AddModelAction.directUrl),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (!mounted || action == null) return;
    final controller = ref.read(modelSelectionControllerProvider.notifier);
    switch (action) {
      case _AddModelAction.importFile:
        await showImportLocalModelDialog(context, controller);
      case _AddModelAction.huggingFaceRepo:
        await showHuggingFaceRepositoryDialog(context, controller);
      case _AddModelAction.directUrl:
        await _showAddModelDialog(context);
    }
  }

  Future<void> _showAddModelDialog(BuildContext context) async {
    String downloadUrl = '';
    String name = '';
    String parameterSize = '';
    String description = '';
    final selectedCapabilities = <ModelCapability>{};
    String? urlError;
    String? nameError;
    String? sizeError;

    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Add Model'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      autofocus: true,
                      decoration: InputDecoration(
                        labelText: 'Model link *',
                        hintText: 'https://.../model.gguf',
                        errorText: urlError,
                        border: const OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.url,
                      textInputAction: TextInputAction.next,
                      onChanged: (value) {
                        downloadUrl = value.trim();
                        if (urlError != null) {
                          setDialogState(() => urlError = null);
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      decoration: InputDecoration(
                        labelText: 'Name *',
                        errorText: nameError,
                        border: const OutlineInputBorder(),
                      ),
                      textInputAction: TextInputAction.next,
                      onChanged: (value) {
                        name = value;
                        if (nameError != null) {
                          setDialogState(() => nameError = null);
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      decoration: InputDecoration(
                        labelText: 'Parameter size *',
                        hintText: 'e.g. 1.5B or 800M',
                        errorText: sizeError,
                        border: const OutlineInputBorder(),
                      ),
                      textInputAction: TextInputAction.next,
                      onChanged: (value) {
                        parameterSize = value;
                        if (sizeError != null) {
                          setDialogState(() => sizeError = null);
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      decoration: const InputDecoration(
                        labelText: 'Description (optional)',
                        border: OutlineInputBorder(),
                      ),
                      minLines: 2,
                      maxLines: 4,
                      onChanged: (value) => description = value,
                    ),
                    const SizedBox(height: 16),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Capabilities (optional)',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Choose one or more chips. If this is a Hugging Face model, the app will also try to infer matching capabilities automatically.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: ModelCapability.values
                            .map(
                              (capability) => FilterChip(
                                selected: selectedCapabilities.contains(
                                  capability,
                                ),
                                showCheckmark: false,
                                avatar: Icon(
                                  _capabilityIcon(capability),
                                  size: 18,
                                ),
                                label: Text(capability.label),
                                onSelected: (selected) {
                                  setDialogState(() {
                                    if (selected) {
                                      selectedCapabilities.add(capability);
                                    } else {
                                      selectedCapabilities.remove(capability);
                                    }
                                  });
                                },
                              ),
                            )
                            .toList(growable: false),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () async {
                    final normalizedName = name.trim();
                    final normalizedSize = parameterSize.trim().toUpperCase();
                    var hasError = false;

                    if (!_isValidUrl(downloadUrl)) {
                      setDialogState(() {
                        urlError = 'Enter a valid http/https URL.';
                      });
                      hasError = true;
                    }
                    if (normalizedName.isEmpty) {
                      setDialogState(() {
                        nameError = 'Name is required.';
                      });
                      hasError = true;
                    }
                    if (!_isValidParameterSize(normalizedSize)) {
                      setDialogState(() {
                        sizeError = 'Use format like 1.5B, 800M, 360M.';
                      });
                      hasError = true;
                    }
                    if (hasError) return;

                    Navigator.pop(context);
                    await ref
                        .read(modelSelectionControllerProvider.notifier)
                        .addCustomModel(
                          downloadUrl: downloadUrl,
                          name: normalizedName,
                          parameterSize: normalizedSize,
                          description: description,
                          capabilities: selectedCapabilities.toList(),
                        );
                  },
                  child: const Text('Add'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  bool _isValidUrl(String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null) return false;
    if (!(uri.scheme == 'http' || uri.scheme == 'https')) return false;
    return uri.host.isNotEmpty;
  }

  bool _isValidParameterSize(String value) {
    return RegExp(
      r'^[0-9]*\.?[0-9]+\s*[KMBT]$',
    ).hasMatch(value.trim().toUpperCase());
  }

  void _showDeleteConfirmation(BuildContext context, LlmModel model) {
    final message = model.isExternal
        ? 'Remove ${model.name} from InstaLLM? The original file at '
              '${model.externalPath} stays on your device.'
        : model.modelSource == ModelSource.imported
        ? 'Remove ${model.name}? The imported copy stored by InstaLLM will '
              'be deleted to free up storage space.'
        : 'Are you sure you want to delete ${model.name}? This will free up '
              'storage space.';
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(model.isExternal ? 'Remove Model?' : 'Delete Model?'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              ref
                  .read(modelSelectionControllerProvider.notifier)
                  .deleteModel(model);
            },
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}

/// The download bar of one model card.
///
/// Only this subtree watches [downloadProgressProvider]: a progress report a few
/// times a second rebuilt the whole list when the state carried it, and the
/// download's own stream is delivered on the same isolate. See the provider for
/// the measured cost of that.
class _ModelDownloadBar extends ConsumerWidget {
  const _ModelDownloadBar({required this.modelId, required this.isSelected});

  final String modelId;
  final bool isSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = ref.watch(
      downloadProgressProvider.select((all) => all[modelId]),
    );
    if (progress == null) return const SizedBox.shrink();

    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        LinearProgressIndicator(
          value: progress.progress,
          backgroundColor: colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(4),
        ),
        const SizedBox(height: 4),
        Text(
          '${_formatBytes(progress.received)} / ${_formatBytes(progress.total)}',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: isSelected
                ? colorScheme.onPrimaryContainer.withValues(alpha: 0.7)
                : colorScheme.onSurfaceVariant,
            fontSize: 10,
          ),
        ),
      ],
    );
  }
}
