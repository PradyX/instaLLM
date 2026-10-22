import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:installm/core/navigation/app_router.dart';
import 'package:installm/core/services/device_profile_service.dart';
import 'package:installm/core/services/hugging_face_avatar_service.dart';
import 'package:installm/core/services/hugging_face_repository_service.dart';
import 'package:installm/core/services/service_providers.dart';
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
  /// The model the detail pane shows. Null means the first model the list
  /// shows, which is also where a filter that hides the focused model lands.
  String? _focusedModelId;

  /// On a narrow window the pane replaces the list instead of sitting beside
  /// it, and this is what brings the list back.
  bool _narrowDetailOpen = false;

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

  /// Downloads a model, asking its repository first when the user presses
  /// Download: the card then offers that repository's quantizations as chips,
  /// and the filled chip is the file this button fetches.
  ///
  /// A model with nothing to choose between — no repository, a repository
  /// that cannot be read, or one carrying only this file — downloads exactly
  /// as it did before, so an offline device still works.
  Future<void> _handleDownload(LlmModel model) async {
    final controller = ref.read(modelSelectionControllerProvider.notifier);
    final choices = _quantizationChoices[model.id];

    if (choices != null) {
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

    if (_quantizationLoading.contains(model.id)) return;
    setState(() => _quantizationLoading.add(model.id));

    final loaded = await controller.loadQuantizationChoices(model);
    if (!mounted) return;

    if (loaded == null || loaded.variants.isEmpty) {
      setState(() => _quantizationLoading.remove(model.id));
      await controller.downloadModel(model);
      return;
    }

    setState(() {
      _quantizationLoading.remove(model.id);
      _quantizationChoices[model.id] = loaded;
      _selectedQuantization[model.id] =
          (loaded.variantFor(model) ?? loaded.variants.first).quantization;
    });
  }

  /// The quantizations of this model: its own file's until the repository is
  /// read, then every one the repository offers with its size. The filled
  /// segment is the file the download button fetches.
  Widget _buildQuantizationChoice(BuildContext context, LlmModel model) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final choices = _quantizationChoices[model.id];
    final ownQuantization = ModelFamilies.quantizationOf(model);

    if (choices == null) {
      if (ownQuantization == null) {
        return Text(
          'Read from the file once it is downloaded.',
          style: textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        );
      }
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          border: Border.all(color: colorScheme.outlineVariant),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          ownQuantization,
          style: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
        ),
      );
    }

    final selectedQuantization =
        _selectedQuantization[model.id] ?? ownQuantization;
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var index = 0; index < choices.variants.length; index++) ...[
            if (index > 0)
              VerticalDivider(
                width: 1,
                thickness: 1,
                color: colorScheme.outlineVariant,
              ),
            _buildQuantizationSegment(
              context,
              model,
              choices.variants[index],
              selected:
                  choices.variants[index].quantization == selectedQuantization,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildQuantizationSegment(
    BuildContext context,
    LlmModel model,
    HuggingFaceModelVariant variant, {
    required bool selected,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final size = variant.sizeBytes;

    return InkWell(
      onTap: () {
        setState(() => _selectedQuantization[model.id] = variant.quantization);
      },
      child: Container(
        color: selected
            ? colorScheme.primary.withValues(alpha: 0.14)
            : Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              variant.quantization,
              style: textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: selected
                    ? colorScheme.primary
                    : colorScheme.onSurfaceVariant,
              ),
            ),
            if (size != null)
              Text(
                _formatBytes(size),
                style: textTheme.labelSmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
      ),
    );
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

          return true;
        })
        .toList(growable: false);

    // The pane follows the list: when a filter hides the focused model it
    // moves to the first model that is still shown.
    LlmModel? focused;
    for (final model in filteredModels) {
      if (model.id == _focusedModelId) {
        focused = model;
        break;
      }
    }
    focused ??= filteredModels.isEmpty ? null : filteredModels.first;

    // One entry per family: the catalog lists `SmolLM2 360M` and `SmolLM2
    // 1.7B` as separate rows only because they are separate records, so the
    // list collapses everything a name shares and the pane exposes the
    // difference between the members instead.
    final families = ModelFamilies.group(filteredModels);

    // "Best fit" (sortFamiliesByFit below) orders families by how well their
    // best-fitting variant is expected to run here — the biggest comfortable
    // model first — using the device's memory budget; families whose weights
    // or budget cannot be estimated stay unranked and last.
    final deviceForFit = state.sortByFit
        ? ref.watch(deviceProfileProvider).valueOrNull
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

    ModelFamily? focusedFamily;
    if (focused != null) {
      for (final family in families) {
        if (family.variants.any((variant) => variant.model.id == focused!.id)) {
          focusedFamily = family;
          break;
        }
      }
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('Models'),
        actions: [
          TextButton.icon(
            onPressed: _showAddModelSheet,
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('Add model'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 760;
          final list = _buildListPane(
            context,
            state,
            families,
            focused,
            onOpen: (variant) {
              unawaited(_loadFitReport(variant.model));
              setState(() {
                _focusedModelId = variant.id;
                _narrowDetailOpen = !wide;
              });
            },
          );

          if (!wide) {
            if (_narrowDetailOpen && focused != null) {
              return _buildDetailPane(
                context,
                state,
                focused,
                family: focusedFamily,
                onBack: () => setState(() => _narrowDetailOpen = false),
              );
            }
            return Column(
              children: [
                _buildFilterBand(
                  context,
                  state,
                  wide: false,
                  visibleCapabilities: visibleCapabilities,
                  capabilityCounts: capabilityCounts,
                ),
                Expanded(child: list),
              ],
            );
          }

          return Column(
            children: [
              _buildFilterBand(
                context,
                state,
                wide: true,
                visibleCapabilities: visibleCapabilities,
                capabilityCounts: capabilityCounts,
              ),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(width: 300, child: list),
                    VerticalDivider(
                      width: 1,
                      thickness: 1,
                      color: colorScheme.outlineVariant.withValues(alpha: 0.6),
                    ),
                    Expanded(
                      child: focused == null
                          ? _buildEmptyFilterState(context, state)
                          : _buildDetailPane(
                              context,
                              state,
                              focused,
                              family: focusedFamily,
                            ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// What is on disk, the search and the filters, laid across the whole page
  /// so the chips have room for one line and the list and the focused model
  /// share the space below it.
  Widget _buildFilterBand(
    BuildContext context,
    ModelSelectionState state, {
    required bool wide,
    required List<ModelCapability> visibleCapabilities,
    required Map<ModelCapability, int> capabilityCounts,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final device = ref.watch(deviceProfileProvider).valueOrNull;
    final free = state.freeStorageBytes;
    final total = state.totalStorageBytes;
    final hasStorage = free != null && total != null && total > 0;
    final installedCount = state.models
        .where((model) => model.isDownloaded)
        .length;
    final usedRatio = hasStorage
        ? ((total - free) / total).clamp(0.0, 1.0)
        : 0.0;
    final hasFilters =
        state.selectedCapabilityFilters.isNotEmpty || !state.sortByFit;

    final summaryStyle = textTheme.bodySmall?.copyWith(
      color: colorScheme.onSurfaceVariant,
    );
    final summary = Text(
      hasStorage
          ? '$installedCount installed · ${_formatBytes(free)} free'
          : '$installedCount installed',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: summaryStyle,
    );
    final deviceLabel = device == null
        ? null
        : Text(
            _deviceLabel(device),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: wide ? TextAlign.end : TextAlign.start,
            style: summaryStyle,
          );

    final searchField = TextField(
      controller: _searchController,
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

    final chips = <Widget>[
      // Installed families always come first, so this chip shows a fixed
      // state rather than offering a switch: there is no off position.
      FilterChip(
        selected: true,
        showCheckmark: false,
        visualDensity: VisualDensity.compact,
        avatar: const Icon(Icons.download_done_rounded, size: 16),
        label: Text('Installed ($installedCount)'),
        onSelected: (_) {},
      ),
      FilterChip(
        selected: state.sortByFit,
        showCheckmark: false,
        visualDensity: VisualDensity.compact,
        avatar: const Icon(Icons.bolt_rounded, size: 16),
        label: const Text('Best fit'),
        onSelected: (selected) {
          ref
              .read(modelSelectionControllerProvider.notifier)
              .setSortByFit(selected);
        },
      ),
      ...visibleCapabilities.map(
        (capability) => FilterChip(
          selected: state.selectedCapabilityFilters.contains(capability),
          showCheckmark: false,
          visualDensity: VisualDensity.compact,
          avatar: Icon(_capabilityIcon(capability), size: 16),
          label: Text(
            '${capability.label} (${capabilityCounts[capability] ?? 0})',
          ),
          onSelected: (_) {
            ref
                .read(modelSelectionControllerProvider.notifier)
                .toggleCapabilityFilter(capability);
          },
        ),
      ),
    ];

    final filterRow = Row(
      children: [
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (var index = 0; index < chips.length; index++) ...[
                  if (index > 0) const SizedBox(width: 6),
                  chips[index],
                ],
              ],
            ),
          ),
        ),
        if (hasFilters) ...[
          const SizedBox(width: 4),
          TextButton(
            onPressed: () {
              ref
                  .read(modelSelectionControllerProvider.notifier)
                  .clearFilters();
            },
            style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
            child: const Text('Clear'),
          ),
        ],
      ],
    );

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.6),
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (wide)
            Row(
              children: [
                Flexible(child: summary),
                if (deviceLabel != null) ...[
                  const SizedBox(width: 16),
                  deviceLabel,
                ],
              ],
            )
          else ...[
            summary,
            ?deviceLabel,
          ],
          if (hasStorage) ...[
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: usedRatio,
              minHeight: 4,
              borderRadius: BorderRadius.circular(4),
              color: usedRatio >= 0.9
                  ? colorScheme.error
                  : usedRatio >= 0.7
                  ? Colors.amber.shade700
                  : colorScheme.primary,
              backgroundColor: colorScheme.surfaceContainerHighest,
            ),
          ],
          if (state.models.isNotEmpty) ...[
            const SizedBox(height: 12),
            if (wide)
              Row(
                children: [
                  SizedBox(width: 280, child: searchField),
                  const SizedBox(width: 12),
                  Expanded(child: filterRow),
                ],
              )
            else ...[
              searchField,
              const SizedBox(height: 8),
              filterRow,
            ],
          ],
        ],
      ),
    );
  }

  /// The left pane: one row per model family. Selecting a row focuses it
  /// rather than choosing it as the app's model; that is an explicit action in
  /// the detail pane.
  Widget _buildListPane(
    BuildContext context,
    ModelSelectionState state,
    List<ModelFamily> families,
    LlmModel? focused, {
    required ValueChanged<ModelVariant> onOpen,
  }) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 24),
      children: [
        if (families.isEmpty)
          _buildEmptyFilterState(context, state)
        else
          ...families.map(
            (family) => _buildFamilyRow(
              context,
              state,
              family,
              publisher: _familyPublishers[family.key],
              focused:
                  focused != null &&
                  family.variants.any(
                    (variant) => variant.model.id == focused.id,
                  ),
              onTap: () => onOpen(family.variants.first),
            ),
          ),
      ],
    );
  }

  Widget _buildFamilyRow(
    BuildContext context,
    ModelSelectionState state,
    ModelFamily family, {
    required String? publisher,
    required bool focused,
    required VoidCallback onTap,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isSelected = family.variants.any(
      (variant) => variant.model.id == state.selectedModelId,
    );
    final progressByModel = ref.watch(downloadProgressProvider);
    DownloadProgress? progress;
    for (final variant in family.variants) {
      final candidate = progressByModel[variant.model.id];
      if (candidate != null) {
        progress = candidate;
        break;
      }
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: focused
            ? colorScheme.primary.withValues(alpha: 0.12)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              children: [
                _buildFamilyMonogram(context, family, publisher),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        family.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: focused
                              ? colorScheme.primary
                              : colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        _familySubtitle(family, publisher),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.labelSmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (progress != null) ...[
                  const SizedBox(width: 8),
                  Text(
                    '${(progress.progress * 100).round()}%',
                    style: textTheme.labelSmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ] else if (isSelected) ...[
                  const SizedBox(width: 8),
                  Icon(
                    Icons.check_circle_rounded,
                    size: 16,
                    color: colorScheme.primary,
                  ),
                ] else if (family.hasInstalled) ...[
                  // Installed but not the model in use: a quiet check lets an
                  // installed family be seen without shouting over the one
                  // the chat is actually running.
                  const SizedBox(width: 8),
                  Icon(
                    Icons.check_circle_outline_rounded,
                    size: 16,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Name above, and below it the publisher the family's models come from —
  /// `4 variants · bartowski · ~1.1 GB` — where that is known, falling back to
  /// the approximate file size and then the parameter size. The quantization
  /// is deliberately absent from the list: each family's variants differ in
  /// size far more noticeably than in quantization, and the pane shows both
  /// when it matters.
  String _familySubtitle(ModelFamily family, String? publisher) {
    final best = family.variants.first;
    final exactBytes = best.fileSizeBytes;
    final sizeBytes = exactBytes ?? best.approximateFileSizeBytes;
    final parts = <String>[?publisher];
    if (family.variantCount > 1) parts.add('${family.variantCount} variants');
    if (sizeBytes != null) {
      parts.add(
        exactBytes == null
            ? '~${_formatBytes(sizeBytes)}'
            : _formatBytes(sizeBytes),
      );
    }
    if (parts.isEmpty) return best.parameterSize;
    return parts.join(' · ');
  }

  /// A small avatar per family: the publisher's own Hugging Face picture when
  /// one was fetched (so `bartowski` models carry bartowski's avatar, the way
  /// community lists show the author), otherwise a letter monogram whose hue
  /// varies by family so two rows never read as one.
  Widget _buildFamilyMonogram(
    BuildContext context,
    ModelFamily family,
    String? publisher,
  ) {
    final bytes = publisher == null ? null : _publisherAvatars[publisher];
    if (bytes != null) {
      return ClipOval(
        child: Image.memory(
          bytes,
          width: 32,
          height: 32,
          fit: BoxFit.cover,
          gaplessPlayback: true,
        ),
      );
    }
    final hue = (family.key.hashCode.abs() % 360).toDouble();
    final color = HSLColor.fromAHSL(1.0, hue, 0.3, 0.34).toColor();
    final initial = family.displayName.trim().isEmpty
        ? '?'
        : family.displayName.trim()[0].toUpperCase();
    return Container(
      width: 32,
      height: 32,
      alignment: Alignment.center,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
      child: Text(
        initial,
        style: TextStyle(
          color: Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  /// The right pane: everything about one model, including the quantization
  /// it will download and what it costs this device. When the pane shows a
  /// family rather than the only member of one, the family's variants are a
  /// ledger — one row per variant with its size, fit on this device, cost and
  /// action — and the focused member opens in place to carry its own
  /// quantization, fit meter and file facts.
  Widget _buildDetailPane(
    BuildContext context,
    ModelSelectionState state,
    LlmModel model, {
    required ModelFamily? family,
    VoidCallback? onBack,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isSelected = model.id == state.selectedModelId;
    final showVariants = family != null && family.variantCount > 1;

    // The pane is the details, so the estimate it shows is asked for on
    // arrival rather than after a tap.
    if (!_fitRequests.contains(model.id) &&
        !_fitReports.containsKey(model.id)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_loadFitReport(model));
      });
    }

    final identity = <String>[
      showVariants ? family.parameterRange : model.parameterSize,
      model.promptFormatId,
      model.isCustom ? 'Custom' : model.effectiveSource.label,
    ].join(' · ');

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 28),
      children: [
        if (onBack != null)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: onBack,
              icon: const Icon(Icons.arrow_back_rounded, size: 18),
              label: const Text('All models'),
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
              ),
            ),
          ),
        Text(
          showVariants ? family.displayName : model.name,
          style: textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w600,
            letterSpacing: -0.4,
          ),
        ),
        const SizedBox(height: 4),
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
        if (showVariants) ...[
          const SizedBox(height: 20),
          _buildVariantLedger(context, family),
        ],
        if (!showVariants) ...[
          const SizedBox(height: 20),
          _buildDetailSection(
            context,
            'Quantization',
            _buildQuantizationChoice(context, model),
          ),
          const SizedBox(height: 18),
          _buildDetailSection(
            context,
            'On this device',
            _buildFitMeter(context, model),
          ),
          const SizedBox(height: 18),
          _buildDetailSection(context, 'File', _buildFacts(context, model)),
        ],
        const SizedBox(height: 18),
        Divider(
          height: 1,
          color: colorScheme.outlineVariant.withValues(alpha: 0.6),
        ),
        const SizedBox(height: 14),
        _buildDetailActions(context, model, isSelected: isSelected),
      ],
    );
  }

  /// The family's variants as a ledger: a labelled column row per member —
  /// its size, how it fits this device, what it costs, and its action — with
  /// the focused member opening in place to show the quantization, the fit
  /// estimate and the file facts that belong to it. Picking a row switches
  /// the pane to that variant; nothing is downloaded or chosen for the app
  /// by doing so.
  Widget _buildVariantLedger(BuildContext context, ModelFamily family) {
    final colorScheme = Theme.of(context).colorScheme;
    final device = ref.watch(deviceProfileProvider).valueOrNull;

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

    const sizeColumnWidth = 56.0;
    const costColumnWidth = 104.0;
    const actionColumnWidth = 104.0;
    Widget columnHeader(
      String label, {
      Alignment alignment = Alignment.centerLeft,
    }) => Align(
      alignment: alignment,
      child: Text(
        label,
        style: Theme.of(
          context,
        ).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w700),
      ),
    );

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
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
            child: Row(
              children: [
                SizedBox(width: sizeColumnWidth, child: columnHeader('Size')),
                Expanded(child: columnHeader('Fit on this Mac')),
                SizedBox(
                  width: costColumnWidth,
                  child: columnHeader(
                    'Disk size',
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
              sizeWidth: sizeColumnWidth,
              costWidth: costColumnWidth,
              actionWidth: actionColumnWidth,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildVariantLedgerRow(
    BuildContext context,
    ModelFamily family,
    ModelVariant variant, {
    required GgufMetadata? kvCacheMetadata,
    required DeviceProfile? device,
    required bool selected,
    required double sizeWidth,
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

    final action = switch ((variant.model.isDownloaded, selected)) {
      (true, true) => Row(
        mainAxisAlignment: MainAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.check_circle_rounded,
            size: 16,
            color: colorScheme.primary,
          ),
          const SizedBox(width: 6),
          Text(
            'In use',
            style: textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: colorScheme.primary,
            ),
          ),
        ],
      ),
      (true, false) => FilledButton.tonal(
        onPressed: () => controller.selectModel(variant.model),
        style: FilledButton.styleFrom(
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.symmetric(horizontal: 12),
        ),
        child: const Text('Use'),
      ),
      _ => null,
    };

    final detail = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 10),
        _buildDetailSection(
          context,
          'Quantization',
          _buildQuantizationChoice(context, variant.model),
        ),
        const SizedBox(height: 12),
        _buildDetailSection(
          context,
          'On this device',
          _buildFitMeter(context, variant.model),
        ),
        const SizedBox(height: 12),
        _buildDetailSection(
          context,
          'File',
          _buildFacts(context, variant.model),
        ),
        const SizedBox(height: 12),
      ],
    );

    return Material(
      color: selected
          ? colorScheme.primary.withValues(alpha: 0.10)
          : Colors.transparent,
      child: InkWell(
        onTap: () {
          if (variant.model.id == _focusedModelId) return;
          unawaited(_loadFitReport(variant.model));
          setState(() => _focusedModelId = variant.model.id);
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              child: Row(
                children: [
                  SizedBox(
                    width: sizeWidth,
                    child: Text(
                      variant.parameterSize,
                      style: textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Expanded(
                    child: badgeColor == null
                        ? const SizedBox.shrink()
                        : Align(
                            alignment: Alignment.centerLeft,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: badgeColor.withValues(alpha: 0.85),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                rating!.label,
                                style: textTheme.labelSmall?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
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
                            ? 'Install to estimate'
                            : exactBytes == null
                            ? '~${_formatBytes(sizeBytes)}'
                            : _formatBytes(exactBytes),
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
                      child: action ?? const SizedBox.shrink(),
                    ),
                  ),
                ],
              ),
            ),
            if (selected)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: detail,
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
      ('Installed', model.isDownloaded ? 'Yes' : 'No'),
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

    return Wrap(
      spacing: 24,
      runSpacing: 14,
      children: [
        for (final (label, value) in facts)
          SizedBox(width: 220, child: _buildDetailRow(context, label, value)),
      ],
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

  /// `macOS · arm64 · 8 cores · 16 GB RAM` with graceful fallbacks.
  String _deviceLabel(DeviceProfile device) {
    final memoryBytes = device.totalMemoryBytes ?? device.availableMemoryBytes;
    final memory = memoryBytes == null || memoryBytes <= 0
        ? ''
        : ' · ${_formatBytes(memoryBytes)} RAM';
    return '${device.summaryLabel}$memory';
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
    final message = hasSearch && hasFilters
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
                'Try adjusting your search or removing filters to see more models.',
                style: textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
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
