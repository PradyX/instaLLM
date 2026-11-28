import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:installm/core/services/hugging_face_model_capability_service.dart';
import 'package:installm/core/services/hugging_face_model_discovery_service.dart';
import 'package:installm/core/services/hugging_face_repository_service.dart';
import 'package:installm/core/services/local_notification_service.dart';
import 'package:installm/core/services/model_storage_service.dart';
import 'package:installm/core/services/storage_info_service.dart';
import 'package:installm/features/model_selection/data/gguf_reader.dart';
import 'package:installm/features/model_selection/data/model_import_service.dart';
import 'package:installm/features/model_selection/domain/gguf_metadata.dart';
import 'package:installm/features/model_selection/domain/llm_model.dart';
import 'package:installm/features/model_selection/domain/model_catalog_merge.dart';
import 'package:installm/features/model_selection/domain/model_import.dart';
import 'package:installm/features/model_selection/domain/model_install_state.dart';
import 'package:installm/features/model_selection/presentation/download_progress_provider.dart';
import 'package:installm/features/model_selection/presentation/model_selection_state.dart';
import 'package:installm/storage/secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'model_selection_controller.g.dart';

class _ModelDownloadAsset {
  final String url;
  final String fileName;

  const _ModelDownloadAsset({required this.url, required this.fileName});
}

/// The quantizations a model's own repository offers, together with the
/// repository needed to download one of them.
class ModelQuantizationChoices {
  const ModelQuantizationChoices({
    required this.repository,
    required this.variants,
  });

  final HuggingFaceRepository repository;

  /// Best for a device first, as the repository service orders them.
  final List<HuggingFaceModelVariant> variants;

  /// The variant that is [model]'s own file, when the repository lists it.
  HuggingFaceModelVariant? variantFor(LlmModel model) {
    for (final variant in variants) {
      if (variant.fileName == model.localFileName) return variant;
    }
    return null;
  }
}

@riverpod
class ModelSelectionController extends _$ModelSelectionController {
  static const _customModelsStorageKey = 'custom_models_v1';

  /// Where the model the user last chose is kept. The v1 suffix is the format
  /// of that stored id: changing it needs a migration, not a silent reset.
  static const selectedModelStorageKey = 'selected_model_id_v1';
  static const _downloadSafetyBytes = 128 * 1024 * 1024;

  late final ModelStorageService _storageService = ModelStorageService();
  late final StorageInfoService _storageInfoService = StorageInfoService();
  late final LocalNotificationService _notificationService =
      LocalNotificationService.instance;
  late final HuggingFaceModelCapabilityService _capabilityService =
      HuggingFaceModelCapabilityService();
  late final HuggingFaceModelDiscoveryService _discoveryService =
      HuggingFaceModelDiscoveryService();
  late final HuggingFaceRepositoryService _repositoryService =
      HuggingFaceRepositoryService();
  late final ModelImportService _importService = ModelImportService(
    storageService: _storageService,
  );
  final Map<String, CancelToken> _cancelTokens = {};

  /// The models the last Hugging Face page left in the list, in list order.
  ///
  /// The page's models are kept apart from [state] so a new page can be added
  /// without losing what is installed, and so a search can replace the list
  /// without touching the user's own records.
  List<LlmModel> _discoveredModels = const [];

  /// Where Hugging Face continues after the page on screen; null at the end.
  String? _nextDiscoveredCursor;

  /// The query the current [Hugging Face pages](_discoveredModels) answer.
  String _discoveredQuery = '';

  /// Collapses the keystrokes of a typed search into one request.
  Timer? _searchDebounce;

  /// Incremented for every catalog request so a slow answer that a newer one
  /// has overtaken is dropped instead of overwriting the list.
  int _catalogRequest = 0;

  DownloadProgressNotifier get _progress =>
      ref.read(downloadProgressProvider.notifier);

  @override
  ModelSelectionState build() {
    state = ModelSelectionState(
      models: const [],
      selectedModelId: null,
      isLoadingModels: true,
    );
    ref.onDispose(() => _searchDebounce?.cancel());
    unawaited(_init());
    return state;
  }

  /// Reads the installed models and the model the user last chose.
  ///
  /// Every step here touches the device, and a failure in any of them must
  /// cost the user nothing: the catalog stays the static one and the next
  /// launch tries again, while an error thrown out of here would become a
  /// provider error state that hides the selection on the next read.
  Future<void> _init() async {
    try {
      await _loadInitialState();
    } catch (error, stackTrace) {
      debugPrint('Model catalog load failed: $error\n$stackTrace');
    }
  }

  Future<void> _loadInitialState() async {
    // A record persisted by an older build carries a size estimated from its
    // file bytes, which hides a 0.5B model from the <1B filter. The file name
    // is on the record, so read the count from it again.
    final storedRecords = [
      for (final model in await _loadCustomModels()) _withSizeFromName(model),
    ];
    final cachedCatalog = await _discoveryService.readCachedCatalog();
    final storedSelectedId = await _readStoredSelectedModelId();

    _discoveredModels = cachedCatalog?.models ?? const [];
    _nextDiscoveredCursor = cachedCatalog?.nextCursor;
    _discoveredQuery = '';

    // A model file can outlive the entry that named it. The catalog is read
    // from the network now, so a file installed from a page that is no longer
    // shown would otherwise be invisible while still occupying disk. Adopting
    // it keeps it listed and keeps the user's model usable.
    final adoptedModels = await _adoptOrphanedModelFiles([
      ...storedRecords,
      ..._discoveredModels,
    ]);
    final customModels = [...storedRecords, ...adoptedModels];
    if (adoptedModels.isNotEmpty) {
      await _persistCustomModels(customModels);
    }

    final combinedModels = _mergeModelLists(
      discoveredModels: _discoveredModels,
      customModels: customModels,
    );

    // Each record is checked against storage before it is shown: a file removed
    // outside the app, or a record left by a build that registered a download
    // it never finished, must not be presented as a working install.
    final updatedModels = await Future.wait(
      combinedModels.map((model) async {
        final filePresent = await _isModelBundleDownloaded(model);
        return withVerifiedInstall(model, filePresent: filePresent);
      }),
    );
    final modelsWithCachedCapabilities = await _applyCachedCapabilities(
      updatedModels,
    );

    // The user's last choice wins over anything the app would pick itself,
    // as long as that model is still installed.
    String? newSelectedId = state.selectedModelId ?? storedSelectedId;
    if (newSelectedId != null &&
        !modelsWithCachedCapabilities.any(
          (m) => m.id == newSelectedId && m.isDownloaded,
        )) {
      newSelectedId = null;
    }
    if (newSelectedId == null) {
      try {
        newSelectedId = modelsWithCachedCapabilities
            .firstWhere((m) => m.isDownloaded)
            .id;
      } catch (_) {
        newSelectedId = null;
      }
    }

    state = state.copyWith(
      models: modelsWithCachedCapabilities,
      selectedModelId: newSelectedId,
      hasMoreModels: cachedCatalog?.hasMore ?? false,
      // With nothing cached the screen waits for the first page instead of
      // telling the user there are no models.
      isLoadingModels: cachedCatalog == null,
    );
    await _refreshStorageInfo();
    _refreshInBackground(
      () => _refreshModelCapabilities(modelsWithCachedCapabilities),
      'capability',
    );
    _refreshInBackground(_refreshDiscoveredModels, 'discovery');
  }

  /// A record with the parameter count read from the name it already carries.
  static LlmModel _withSizeFromName(LlmModel model) {
    final parsed =
        HuggingFaceModelDiscoveryService.parameterSizeIn(model.localFileName) ??
        HuggingFaceModelDiscoveryService.parameterSizeIn(model.downloadUrl);
    if (parsed == null || parsed == model.parameterSize) return model;
    return model.copyWith(parameterSize: parsed);
  }

  /// Starts a refresh the user is not waiting for.
  ///
  /// These read the network and the device's metadata cache, so they are an
  /// improvement rather than a requirement: a failure is logged and the
  /// catalog the app already has stands, instead of becoming an unhandled
  /// async error nothing can catch.
  void _refreshInBackground(Future<void> Function() refresh, String what) {
    unawaited(
      refresh().catchError((Object error, StackTrace stackTrace) {
        debugPrint('Model $what refresh failed: $error\n$stackTrace');
      }),
    );
  }

  /// Refreshes the first page of the catalog when the cached one has aged out.
  Future<void> _refreshDiscoveredModels() async {
    final isStale = await _discoveryService.isCacheStale();
    if (_discoveredModels.isNotEmpty && !isStale) {
      if (state.isLoadingModels) {
        state = state.copyWith(isLoadingModels: false);
      }
      return;
    }
    await _loadCatalogPage(query: '', cursor: null, replace: true);
  }

  /// Reads one page of the catalog and puts it on screen.
  ///
  /// [replace] reads a first page, for a refresh or a new search; otherwise
  /// [cursor] continues the page already on screen.
  Future<void> _loadCatalogPage({
    required String query,
    String? cursor,
    required bool replace,
  }) async {
    final request = ++_catalogRequest;
    state = state.copyWith(isLoadingModels: replace, isLoadingMore: !replace);

    final page = await _discoveryService.load(query: query, cursor: cursor);
    if (!ref.mounted || request != _catalogRequest) return;

    // An empty answer to the default list is a failed read, not an empty
    // Hugging Face: that list always has something. Keep what is on screen.
    if (replace && query.isEmpty && page.models.isEmpty) {
      state = state.copyWith(
        isLoadingModels: false,
        isLoadingMore: false,
        error: _discoveredModels.isEmpty
            ? 'Could not reach Hugging Face. Check the connection and retry.'
            : null,
      );
      return;
    }

    _discoveredModels = replace
        ? page.models
        : [..._discoveredModels, ...page.models];
    _nextDiscoveredCursor = page.nextCursor;
    _discoveredQuery = query;

    final merged = _mergeModelLists(
      discoveredModels: _discoveredModels,
      customModels: state.models.where((m) => m.isCustom).toList(),
    );
    final updatedModels = await Future.wait(
      merged.map((model) async {
        final filePresent = await _isModelBundleDownloaded(model);
        return withVerifiedInstall(model, filePresent: filePresent);
      }),
    );

    final withCapabilities = await _applyCachedCapabilities(updatedModels);
    if (!ref.mounted || request != _catalogRequest) return;

    state = state.copyWith(
      models: withCapabilities,
      selectedModelId: state.selectedModelId,
      hasMoreModels: page.hasMore,
      isLoadingModels: false,
      isLoadingMore: false,
    );
    _refreshInBackground(
      () => _refreshModelCapabilities(withCapabilities),
      'capability',
    );
  }

  /// Reads the page after the one on screen, for the list's Load more action.
  Future<void> loadMoreModels() async {
    if (state.isLoadingModels || state.isLoadingMore || !state.hasMoreModels) {
      return;
    }
    final cursor = _nextDiscoveredCursor;
    if (cursor == null) {
      state = state.copyWith(hasMoreModels: false);
      return;
    }
    await _loadCatalogPage(
      query: _discoveredQuery,
      cursor: cursor,
      replace: false,
    );
  }

  /// Reads the first page again, for a retry or a manual refresh.
  Future<void> refreshCatalog() async {
    _searchDebounce?.cancel();
    await _loadCatalogPage(
      query: state.searchQuery.trim(),
      cursor: null,
      replace: true,
    );
  }

  /// Asks Hugging Face for [query] once the typing settles.
  ///
  /// The list is not just what the app knows: a model it has never seen is a
  /// search away, so this reads the matching repositories rather than only
  /// filtering the page already on screen.
  void searchCatalog(String query) {
    final trimmed = query.trim();
    _searchDebounce?.cancel();
    if (trimmed == _discoveredQuery) return;
    _searchDebounce = Timer(const Duration(milliseconds: 450), () {
      unawaited(_loadCatalogPage(query: trimmed, cursor: null, replace: true));
    });
  }

  /// Merges the discovered pages with the user's own records.
  List<LlmModel> _mergeModelLists({
    required List<LlmModel> discoveredModels,
    required List<LlmModel> customModels,
  }) {
    return mergeModelSources(
      catalogModels: const [],
      discoveredModels: discoveredModels,
      customModels: customModels,
    );
  }

  void selectModel(LlmModel model) {
    if (model.isDownloaded) {
      state = state.copyWith(selectedModelId: model.id);
      unawaited(_rememberSelectedModel(model.id));
    }
  }

  /// The model the user last chose, so the app opens on their choice rather
  /// than on whichever model happens to come first in the catalog.
  Future<String?> _readStoredSelectedModelId() async {
    try {
      return await SecureStorage.instance.readPrimitive(
        selectedModelStorageKey,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _rememberSelectedModel(String? modelId) async {
    if (modelId == null || modelId.isEmpty) return;
    try {
      await SecureStorage.instance.writePrimitive(
        key: selectedModelStorageKey,
        value: modelId,
      );
    } catch (_) {
      // Failing to remember the choice must not fail the selection itself.
    }
  }

  void toggleCapabilityFilter(ModelCapability capability) {
    final updatedFilters = Set<ModelCapability>.from(
      state.selectedCapabilityFilters,
    );

    if (!updatedFilters.add(capability)) {
      updatedFilters.remove(capability);
    }

    state = state.copyWith(selectedCapabilityFilters: updatedFilters);
  }

  void clearCapabilityFilters() {
    if (state.selectedCapabilityFilters.isEmpty) return;
    state = state.copyWith(selectedCapabilityFilters: <ModelCapability>{});
  }

  void setSortByFit(bool enabled) {
    if (state.sortByFit == enabled) return;
    state = state.copyWith(sortByFit: enabled);
  }

  void clearFilters() {
    if (state.selectedCapabilityFilters.isEmpty && state.sortByFit) return;

    state = state.copyWith(
      selectedCapabilityFilters: <ModelCapability>{},
      sortByFit: true,
    );
  }

  void setSearchQuery(String query) {
    if (state.searchQuery == query) return;
    state = state.copyWith(searchQuery: query);
    searchCatalog(query);
  }

  void clearSearch() {
    if (state.searchQuery.isEmpty) return;
    state = state.copyWith(searchQuery: '');
    searchCatalog('');
  }

  Future<void> downloadModel(LlmModel model) async {
    // A repository's published template is what makes an arbitrary GGUF
    // answer as an instruction model when the file carries none of its own.
    model = await _withRepositoryChatTemplate(model);
    final assets = _downloadAssetsForModel(model);
    if (assets.isEmpty) return;

    if (!_progress.isDownloading(model.id)) {
      _progress.start(model.id);
    }

    final cancelToken = CancelToken();
    _cancelTokens[model.id] = cancelToken;

    try {
      final storageInfo = await _refreshStorageInfo();
      final remoteSizes = await Future.wait(
        assets.map(
          (asset) => _storageService.getRemoteFileSize(
            asset.url,
            cancelToken: cancelToken,
          ),
        ),
      );
      // Bytes actually received, so a resumed download reports where it really
      // is: a chunked download reserves the whole file up front, and counting
      // that reservation made the bar jump past 100% and stay there.
      final existingSizes = await Future.wait(
        assets.map(
          (asset) => _storageService.getDownloadedBytes(asset.fileName),
        ),
      );

      final totalRemoteBytes = remoteSizes.whereType<int>().fold<int>(
        0,
        (sum, size) => sum + size,
      );
      final remainingBytes = List.generate(assets.length, (index) {
        final remoteSize = remoteSizes[index];
        if (remoteSize == null) return 0;
        final existingSize = existingSizes[index];
        return remoteSize > existingSize ? remoteSize - existingSize : 0;
      }).fold<int>(0, (sum, size) => sum + size);

      if (storageInfo != null && remainingBytes > 0) {
        final requiredBytes = remainingBytes + _downloadSafetyBytes;
        if (storageInfo.freeBytes < requiredBytes) {
          _cancelTokens.remove(model.id);
          _progress.clear(model.id);
          state = state.copyWith(
            error:
                'Not enough free storage for ${model.name}. '
                'Need ${_formatBytes(requiredBytes)} (including safety buffer), '
                'free ${_formatBytes(storageInfo.freeBytes)}.',
          );
          return;
        }
      }

      var completedBytes = List.generate(assets.length, (index) {
        final remoteSize = remoteSizes[index];
        final existingSize = existingSizes[index];
        if (remoteSize == null) return 0;
        return existingSize > remoteSize ? remoteSize : existingSize;
      }).fold<int>(0, (sum, size) => sum + size);

      if (completedBytes > 0) {
        _progress.report(
          model.id,
          received: completedBytes,
          total: totalRemoteBytes > 0 ? totalRemoteBytes : completedBytes,
        );
      }

      for (var index = 0; index < assets.length; index++) {
        final asset = assets[index];
        final knownRemoteSize = remoteSizes[index];
        final currentLocalSize = await _storageService.getLocalFileSize(
          asset.fileName,
        );
        final isAlreadyComplete =
            knownRemoteSize != null &&
            currentLocalSize >= knownRemoteSize &&
            await _storageService.isModelDownloaded(asset.fileName);
        if (isAlreadyComplete) {
          continue;
        }

        final completedBeforeAsset = completedBytes;
        await _storageService.downloadModel(
          asset.url,
          asset.fileName,
          cancelToken: cancelToken,
          onProgress: (received, total) {
            final resolvedTotal = totalRemoteBytes > 0
                ? totalRemoteBytes
                : completedBeforeAsset + total;
            final resolvedReceived = completedBeforeAsset + received;
            final safeTotal = resolvedTotal > 0
                ? resolvedTotal
                : resolvedReceived;
            _progress.report(
              model.id,
              received: resolvedReceived,
              total: safeTotal,
            );
          },
        );

        completedBytes +=
            knownRemoteSize ??
            await _storageService.getLocalFileSize(asset.fileName);
      }

      _cancelTokens.remove(model.id);
      _progress.clear(model.id);

      final isDownloaded = await _isModelBundleDownloaded(model);
      final updatedModels = state.models
          .map(
            (m) => m.id == model.id
                ? withVerifiedInstall(m, filePresent: isDownloaded)
                : m,
          )
          .toList();

      final hadSelection = state.selectedModelId != null;
      state = state.copyWith(
        models: updatedModels,
        selectedModelId:
            state.selectedModelId ?? (isDownloaded ? model.id : null),
      );
      // The notice is owed as soon as the files are here. The bookkeeping
      // below (remembering the selection, writing model records, reading
      // storage figures) can fail, and a failure there must not swallow the
      // one thing the user was waiting for.
      try {
        await _notificationService.showModelDownloadComplete(model.name);
      } catch (_) {
        // Notification failures should not affect download success.
      }
      if (!hadSelection) {
        unawaited(_rememberSelectedModel(state.selectedModelId));
      }
      await _persistCustomModels(updatedModels);
      await _refreshStorageInfo();
    } catch (e) {
      _cancelTokens.remove(model.id);

      _progress.clear(model.id);

      if (e is DioException && CancelToken.isCancel(e)) {
        // A paused download keeps its bytes and its resume metadata on disk.
        // Dropping the progress entry is what hands the card back to a resume
        // button: a card pinned to a download that is no longer running would
        // offer pause and no way back.
        return;
      }

      state = state.copyWith(
        error: 'Failed to download ${model.name}: ${_friendlyDownloadError(e)}',
      );
    }
  }

  void pauseDownload(String modelId) {
    _cancelTokens[modelId]?.cancel();
    _cancelTokens.remove(modelId);
  }

  void clearError() {
    state = state.copyWith(error: null);
  }

  Future<void> addCustomModel({
    required String downloadUrl,
    required String name,
    required String parameterSize,
    String? description,
    List<ModelCapability> capabilities = const [],
  }) async {
    final normalizedUrl = downloadUrl.trim();
    final uri = Uri.tryParse(normalizedUrl);
    final normalizedName = name.trim();
    final normalizedSize = parameterSize.trim().toUpperCase();

    if (normalizedUrl.isEmpty ||
        uri == null ||
        !uri.hasAbsolutePath ||
        !(uri.scheme == 'http' || uri.scheme == 'https')) {
      state = state.copyWith(
        error: 'Please provide a valid direct model link (http/https).',
      );
      return;
    }

    if (!uri.path.toLowerCase().endsWith('.gguf')) {
      state = state.copyWith(
        error:
            'This app supports GGUF only. Please provide a direct .gguf file URL.',
      );
      return;
    }

    if (normalizedName.isEmpty) {
      state = state.copyWith(error: 'Model name is required.');
      return;
    }

    if (!_isValidParameterSize(normalizedSize)) {
      state = state.copyWith(
        error: 'Parameter size is required (format: 1.5B, 800M, 360M).',
      );
      return;
    }

    final localFileName = _deriveLocalFileName(uri);
    if (state.models.any(
      (m) =>
          m.downloadUrl == normalizedUrl ||
          (m.localFileName != null && m.localFileName == localFileName),
    )) {
      state = state.copyWith(error: 'This model link is already in your list.');
      return;
    }

    final resolvedDescription = (description ?? '').trim().isNotEmpty
        ? description!.trim()
        : 'User-added model from custom download link.';
    final id =
        'custom-${_slugify(normalizedName)}-${DateTime.now().millisecondsSinceEpoch}';

    final isDownloaded = await _storageService.isModelDownloaded(localFileName);
    final model = LlmModel(
      id: id,
      name: normalizedName,
      parameterSize: normalizedSize,
      description: resolvedDescription,
      capabilities: capabilities,
      downloadUrl: normalizedUrl,
      localFileName: localFileName,
      isDownloaded: isDownloaded,
      isCustom: true,
    );

    final updatedModels = [...state.models, model];
    state = state.copyWith(models: updatedModels, error: null);
    await _persistCustomModels(updatedModels);
    if (_capabilityService.canResolveFromUrl(model.downloadUrl)) {
      _refreshInBackground(
        () => _refreshModelCapabilities([model]),
        'capability',
      );
    }
  }

  Future<void> deleteModel(LlmModel model) async {
    // Imported models cannot be re-downloaded, so remove them from the
    // catalog entirely. External files are never touched on disk.
    if (model.modelSource == ModelSource.imported) {
      try {
        if (!model.isExternal) {
          final managedFiles = [
            model.localFileName,
            model.mmprojLocalFileName,
          ].whereType<String>();
          for (final fileName in managedFiles) {
            if (fileName.trim().isEmpty) continue;
            await _storageService.deleteModel(fileName);
          }
        }
        await _removeModelFromList(model);
      } catch (e) {
        state = state.copyWith(
          error: 'Failed to remove ${model.name}: ${_friendlyDownloadError(e)}',
        );
      }
      return;
    }

    final assets = _downloadAssetsForModel(model);
    if (assets.isEmpty) return;

    try {
      await Future.wait(
        assets.map((asset) => _storageService.deleteModel(asset.fileName)),
      );

      final updatedModels = state.models
          .map(
            (m) => m.id == model.id
                ? m.copyWith(isDownloaded: false, fileMissing: false)
                : m,
          )
          .toList();

      String? newSelectedId = state.selectedModelId;
      if (newSelectedId == model.id) {
        newSelectedId = null;
        try {
          newSelectedId = updatedModels.firstWhere((m) => m.isDownloaded).id;
        } catch (_) {
          newSelectedId = null;
        }
      }

      state = state.copyWith(
        models: updatedModels,
        selectedModelId: newSelectedId,
      );
      await _persistCustomModels(updatedModels);
      await _refreshStorageInfo();
    } catch (e) {
      state = state.copyWith(
        error: 'Failed to delete ${model.name}: ${_friendlyDownloadError(e)}',
      );
    }
  }

  Future<void> refreshStorageInfo() async {
    await _refreshStorageInfo();
  }

  Future<void> _removeModelFromList(LlmModel model) async {
    final updatedModels = state.models.where((m) => m.id != model.id).toList();

    String? newSelectedId = state.selectedModelId;
    if (newSelectedId == model.id) {
      newSelectedId = null;
      try {
        newSelectedId = updatedModels.firstWhere((m) => m.isDownloaded).id;
      } catch (_) {
        newSelectedId = null;
      }
    }

    state = state.copyWith(
      models: updatedModels,
      selectedModelId: newSelectedId,
    );
    await _persistCustomModels(updatedModels);
    await _refreshStorageInfo();
  }

  /// Opens the file picker and parses a local GGUF file for import.
  ///
  /// Returns null when the user cancels; validation failures are surfaced
  /// through [state.error].
  Future<PendingModelImport?> pickModelForImport({
    ImportedFile? projector,
  }) async {
    try {
      return await _importService.pickModelFile(projector: projector);
    } on GgufFormatException catch (error) {
      state = state.copyWith(error: error.message);
      return null;
    } catch (error) {
      state = state.copyWith(error: 'Could not read the selected file: $error');
      return null;
    }
  }

  /// Opens the file picker for a vision-projector (mmproj) file.
  Future<ImportedFile?> pickProjectorFileForImport() async {
    try {
      return await _importService.pickProjectorFile();
    } catch (error) {
      state = state.copyWith(
        error: 'Could not read the projector file: $error',
      );
      return null;
    }
  }

  /// Checks a parsed import against the models already installed.
  Future<ImportDuplicateInfo?> findImportDuplicate(
    PendingModelImport pending,
  ) async {
    return _importService.findDuplicate(
      pending,
      installed: [
        for (final model in state.models)
          if (model.modelSource == ModelSource.imported)
            LocalModelRecord(
              managedFileName: model.localFileName,
              externalPath: model.externalPath,
            ),
      ],
    );
  }

  /// Copies a parsed GGUF into app storage or references it in place, then
  /// registers it in the catalog.
  Future<LlmModel> importLocalModel({
    required PendingModelImport pending,
    required bool copyToApp,
    void Function(int copiedBytes, int totalBytes)? onProgress,
    Future<void> Function()? shouldCancel,
  }) async {
    final CompletedModelImport completed;
    if (copyToApp) {
      completed = await _importService.copyIntoManagedStorage(
        pending,
        onProgress: onProgress,
        shouldCancel: shouldCancel,
      );
    } else {
      completed = _importService.referenceInPlace(pending);
    }

    final model = _modelFromImport(completed);
    final updatedModels = [...state.models, model];
    final hadSelection = state.selectedModelId != null;
    state = state.copyWith(
      models: updatedModels,
      error: null,
      selectedModelId: state.selectedModelId ?? model.id,
    );
    if (!hadSelection) {
      unawaited(_rememberSelectedModel(state.selectedModelId));
    }
    await _persistCustomModels(updatedModels);
    await _refreshStorageInfo();
    return model;
  }

  LlmModel _modelFromImport(CompletedModelImport completed) {
    final metadata = completed.metadata;
    final hasProjector =
        completed.projectorManagedFileName != null ||
        completed.projectorExternalPath != null;
    final architecture = metadata.architecture;
    final quantization = metadata.quantization;
    return LlmModel(
      id:
          'imported-${_slugify(completed.name)}-'
          '${DateTime.now().millisecondsSinceEpoch}',
      name: completed.name,
      parameterSize: completed.parameterSize,
      description:
          'Imported local GGUF'
          '${architecture.isEmpty ? '' : ' • $architecture'}'
          ' • $quantization',
      capabilities: [if (hasProjector) ModelCapability.vision],
      localFileName: completed.managedFileName,
      mmprojLocalFileName: completed.projectorManagedFileName,
      externalPath: completed.externalPath,
      externalMmprojPath: completed.projectorExternalPath,
      promptFormatId:
          HuggingFaceModelDiscoveryService.promptFormatForArchitecture(
            architecture,
          ),
      isDownloaded: true,
      isCustom: true,
      modelSource: ModelSource.imported,
      ggufMetadata: metadata,
    );
  }

  /// The quantizations the repository behind [model] offers.
  ///
  /// Null when there is nothing to choose between — the model has no
  /// repository, the repository cannot be read, or it carries only this one
  /// file. The caller then downloads the catalog file as it always has, so a
  /// device that is offline is not blocked by a lookup it never needed.
  Future<ModelQuantizationChoices?> loadQuantizationChoices(
    LlmModel model,
  ) async {
    final url = model.downloadUrl;
    final fileName = model.localFileName;
    if (url == null || fileName == null) return null;

    final repoId = HuggingFaceRepositoryService.parseRepositoryInput(url);
    if (repoId == null) return null;

    try {
      final repository = await _repositoryService.fetchRepository(repoId);
      final files = HuggingFaceRepositoryService.quantizationFilesFor(
        repository.files,
        fileName: fileName,
      );
      if (files.length < 2) return null;

      // Variants are built from every file so a vision projector still pairs
      // with the quantization chosen, then narrowed to this model's files.
      final paths = {for (final file in files) file.path};
      final variants = HuggingFaceRepositoryService.variantsFromFiles(
        repository.files,
      ).where((variant) => paths.contains(variant.filePath)).toList();
      if (variants.length < 2) return null;

      return ModelQuantizationChoices(
        repository: repository,
        variants: List.unmodifiable(variants),
      );
    } on HuggingFaceRepositoryException {
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Downloads [variant] of [model]. The model's own file goes through the
  /// normal pipeline; another quantization is registered the way a file added
  /// from the Hugging Face dialog is, then downloaded the same way.
  Future<void> downloadQuantization({
    required LlmModel model,
    required ModelQuantizationChoices choices,
    required HuggingFaceModelVariant variant,
  }) async {
    // Case-insensitive: a repository often spells the file differently from
    // the catalog (`jinen-v2-small-Q4_K_M.gguf` against
    // `jinen-v2-small-q4_k_m.gguf`). Comparing exactly registered a second
    // model entry for the same file, so the download ran under an id the open
    // card never watched: no progress and a Download button that looked dead.
    final localFileName = model.localFileName;
    if (localFileName != null &&
        variant.fileName.toLowerCase() == localFileName.toLowerCase()) {
      await downloadModel(model);
      return;
    }
    await addModelFromHuggingFaceRepo(
      repository: choices.repository,
      variant: variant,
    );
  }

  /// Whether a repository variant is already present in app storage.
  Future<bool> isHfVariantInstalled(HuggingFaceModelVariant variant) {
    return _storageService.isModelDownloaded(variant.fileName);
  }

  /// Registers a Hugging Face repository variant and starts its resumable
  /// download (skipped when the file already exists).
  Future<void> addModelFromHuggingFaceRepo({
    required HuggingFaceRepository repository,
    required HuggingFaceModelVariant variant,
  }) async {
    var model = HuggingFaceRepositoryService.modelForVariant(
      repository: repository,
      variant: variant,
    );

    // A GGUF does not always embed its chat template, while the repository
    // still publishes one. Reading it now is what lets the app chat with an
    // instruction model instead of mistaking it for a base completion model.
    if (model.repositoryChatTemplate == null) {
      final template = await _repositoryChatTemplateFor(repository.repoId);
      if (template != null) {
        model = model.copyWith(repositoryChatTemplate: template);
      }
    }

    final existingIndex = state.models.indexWhere((m) => m.id == model.id);
    if (existingIndex >= 0) {
      final existing = state.models[existingIndex];
      if (existing.isDownloaded) {
        state = state.copyWith(
          error: '${model.name} is already installed on this device.',
        );
        return;
      }
      unawaited(downloadModel(existing));
      return;
    }

    final isDownloaded = await _isModelBundleDownloaded(model);
    final registered = withVerifiedInstall(model, filePresent: isDownloaded);
    final updatedModels = [...state.models, registered];
    final hadSelection = state.selectedModelId != null;
    state = state.copyWith(
      models: updatedModels,
      error: null,
      selectedModelId:
          state.selectedModelId ?? (isDownloaded ? model.id : null),
    );
    if (!hadSelection) {
      unawaited(_rememberSelectedModel(state.selectedModelId));
    }
    await _persistCustomModels(updatedModels);
    if (!isDownloaded) {
      unawaited(downloadModel(registered));
    }
  }

  /// Chat template a repository publishes, read at most once per repository.
  final Map<String, String?> _repositoryTemplates = {};

  Future<String?> _repositoryChatTemplateFor(String repoId) async {
    if (_repositoryTemplates.containsKey(repoId)) {
      return _repositoryTemplates[repoId];
    }
    String? template;
    try {
      template = await _repositoryService.fetchChatTemplate(repoId);
    } catch (_) {
      // A repository without a readable config leaves the file to decide.
      template = null;
    }
    _repositoryTemplates[repoId] = template;
    return template;
  }

  /// [model] with its repository's chat template attached, when it has none.
  ///
  /// Discovery builds records from Hugging Face metadata, which never carries
  /// a template; without this an arbitrary instruction model would be treated
  /// as a base completion model. The record on screen is updated too, so the
  /// template is still there after the download finishes.
  Future<LlmModel> _withRepositoryChatTemplate(LlmModel model) async {
    if (model.repositoryChatTemplate != null) return model;
    final downloadUrl = model.downloadUrl;
    if (downloadUrl == null) return model;
    final repoId = HuggingFaceRepositoryService.parseRepositoryInput(
      downloadUrl,
    );
    if (repoId == null) return model;

    final template = await _repositoryChatTemplateFor(repoId);
    if (template == null) return model;

    final updated = model.copyWith(repositoryChatTemplate: template);
    if (ref.mounted) {
      state = state.copyWith(
        models: [
          for (final existing in state.models)
            existing.id == model.id ? updated : existing,
        ],
      );
    }
    return updated;
  }

  Future<List<LlmModel>> _applyCachedCapabilities(List<LlmModel> models) async {
    final cachedCapabilities = await _capabilityService.readCachedCapabilities(
      models,
    );
    if (cachedCapabilities.isEmpty) return models;
    return _mergeCapabilitiesIntoModels(models, cachedCapabilities);
  }

  Future<void> _refreshModelCapabilities(List<LlmModel> models) async {
    final resolvedCapabilities = await _capabilityService.refreshCapabilities(
      models,
    );
    // The scan can outlive the screen that started it.
    if (!ref.mounted || resolvedCapabilities.isEmpty) return;

    final updatedModels = _mergeCapabilitiesIntoModels(
      state.models,
      resolvedCapabilities,
    );
    if (_sameModelCapabilities(state.models, updatedModels)) return;

    state = state.copyWith(models: updatedModels);
    await _persistCustomModels(updatedModels);
  }

  /// Records for model files already in the app's model directory that no
  /// record names.
  ///
  /// Only headers are read, so this costs a few kilobytes per file and never
  /// loads weights. Projectors, embedding files and speech models are not chat
  /// models and are left where they are.
  Future<List<LlmModel>> _adoptOrphanedModelFiles(
    Iterable<LlmModel> known,
  ) async {
    try {
      final directory = Directory(await _storageService.getModelDir());
      if (!await directory.exists()) return const [];

      final knownFiles = <String>{
        for (final model in known)
          if (model.localFileName?.trim().toLowerCase() case final name?
              when name.isNotEmpty)
            name,
      };

      final adopted = <LlmModel>[];
      await for (final entity in directory.list(followLinks: false)) {
        if (entity is! File) continue;
        final fileName = p.basename(entity.path);
        final lower = fileName.toLowerCase();
        if (!lower.endsWith('.gguf') || lower.contains('mmproj')) continue;
        if (!knownFiles.add(lower)) continue;

        final GgufMetadata metadata;
        try {
          metadata = await const GgufReader().info(entity.path);
        } catch (_) {
          continue;
        }
        final architecture = metadata.architecture.trim().toLowerCase();
        if (LlmModel.embeddingArchitectures.contains(architecture)) continue;
        if (architecture == 'whisper') continue;

        final described = <String>[
          if (architecture.isNotEmpty) architecture,
          if (metadata.quantization.trim().isNotEmpty)
            metadata.quantization.trim(),
        ];
        final declaredName = metadata.name.trim();
        adopted.add(
          LlmModel(
            id: 'local-${_slugify(fileName)}',
            name: declaredName.isEmpty
                ? p.basenameWithoutExtension(fileName)
                : declaredName,
            parameterSize: metadata.parameterCount > 0
                ? metadata.parameterSizeLabel
                : 'Unknown',
            description:
                'Already on this device'
                '${described.isEmpty ? '' : ' • ${described.join(' • ')}'}',
            capabilities: [
              if (metadata.hasVisionEncoder) ModelCapability.vision,
            ],
            localFileName: fileName,
            promptFormatId:
                HuggingFaceModelDiscoveryService.promptFormatForArchitecture(
                  architecture,
                ),
            isDownloaded: true,
            isCustom: true,
            modelSource: ModelSource.imported,
            ggufMetadata: metadata,
          ),
        );
      }
      return adopted;
    } catch (_) {
      return const [];
    }
  }

  Future<List<LlmModel>> _loadCustomModels() async {
    try {
      final data = await SecureStorage.instance.read(_customModelsStorageKey);
      final raw = data?['models'];
      if (raw is! List) return const [];

      final models = <LlmModel>[];
      for (final entry in raw) {
        if (entry is! Map) continue;
        final model = LlmModel.fromJson(Map<String, dynamic>.from(entry));
        if (model.modelSource == ModelSource.imported) {
          final hasManagedFile =
              model.localFileName != null &&
              model.localFileName!.trim().isNotEmpty;
          if (!model.isExternal && !hasManagedFile) continue;
          models.add(model.copyWith(isCustom: true));
          continue;
        }
        if (model.downloadUrl == null ||
            model.downloadUrl!.trim().isEmpty ||
            model.localFileName == null ||
            model.localFileName!.trim().isEmpty) {
          continue;
        }
        models.add(model.copyWith(isCustom: true));
      }
      return models;
    } catch (_) {
      return const [];
    }
  }

  /// Keeps the user's own records and the models installed on this device.
  ///
  /// An installed model is stored even when discovery found it. Discovery's
  /// pages are network state: the page a model came from is replaced on the
  /// next search or refresh, and an installed file with no record would drop
  /// out of the library while still being on disk.
  Future<void> _persistCustomModels(List<LlmModel> models) async {
    final encoded = models
        .where((m) => m.isCustom || (m.isDownloaded && !m.isExternal))
        .map((m) => m.toJson())
        .toList();
    await SecureStorage.instance.write(
      key: _customModelsStorageKey,
      value: {'models': encoded},
    );
  }

  List<LlmModel> _mergeCapabilitiesIntoModels(
    List<LlmModel> models,
    Map<String, List<ModelCapability>> capabilitiesByModelId,
  ) {
    return models
        .map((model) {
          final incomingCapabilities = capabilitiesByModelId[model.id];
          if (incomingCapabilities == null) return model;

          final mergedCapabilities = _mergeCapabilities(
            model.capabilities,
            incomingCapabilities,
          );
          if (_sameCapabilities(model.capabilities, mergedCapabilities)) {
            return model;
          }

          return model.copyWith(capabilities: mergedCapabilities);
        })
        .toList(growable: false);
  }

  List<ModelCapability> _mergeCapabilities(
    List<ModelCapability> current,
    List<ModelCapability> incoming,
  ) {
    final merged = <ModelCapability>{...current, ...incoming};
    return ModelCapability.values
        .where(merged.contains)
        .toList(growable: false);
  }

  bool _sameModelCapabilities(List<LlmModel> current, List<LlmModel> updated) {
    if (current.length != updated.length) return false;

    for (var index = 0; index < current.length; index++) {
      if (!_sameCapabilities(
        current[index].capabilities,
        updated[index].capabilities,
      )) {
        return false;
      }
    }

    return true;
  }

  bool _sameCapabilities(
    List<ModelCapability> first,
    List<ModelCapability> second,
  ) {
    if (first.length != second.length) return false;
    for (var index = 0; index < first.length; index++) {
      if (first[index] != second[index]) return false;
    }
    return true;
  }

  List<_ModelDownloadAsset> _downloadAssetsForModel(LlmModel model) {
    final assets = <_ModelDownloadAsset>[];
    if (model.downloadUrl != null &&
        model.downloadUrl!.trim().isNotEmpty &&
        model.localFileName != null &&
        model.localFileName!.trim().isNotEmpty) {
      assets.add(
        _ModelDownloadAsset(
          url: model.downloadUrl!.trim(),
          fileName: model.localFileName!.trim(),
        ),
      );
    }
    if (model.supportsVision &&
        model.mmprojDownloadUrl != null &&
        model.mmprojDownloadUrl!.trim().isNotEmpty &&
        model.mmprojLocalFileName != null &&
        model.mmprojLocalFileName!.trim().isNotEmpty) {
      assets.add(
        _ModelDownloadAsset(
          url: model.mmprojDownloadUrl!.trim(),
          fileName: model.mmprojLocalFileName!.trim(),
        ),
      );
    }
    return assets;
  }

  Future<bool> _isModelBundleDownloaded(LlmModel model) async {
    if (model.isExternal) {
      return _storageService.isModelPathDownloaded(model.externalPath);
    }

    if (model.modelSource == ModelSource.imported) {
      final localFileName = model.localFileName;
      if (localFileName == null || localFileName.trim().isEmpty) {
        return false;
      }
      if (!await _storageService.isModelDownloaded(localFileName)) {
        return false;
      }
      final mmproj = model.mmprojLocalFileName;
      if (mmproj != null && mmproj.trim().isNotEmpty) {
        return _storageService.isModelDownloaded(mmproj);
      }
      return true;
    }

    final assets = _downloadAssetsForModel(model);
    if (assets.isEmpty) return false;

    for (final asset in assets) {
      if (!await _storageService.isModelDownloaded(asset.fileName)) {
        return false;
      }
    }
    return true;
  }

  String _friendlyDownloadError(Object error) {
    if (error is DioException) {
      final code = error.response?.statusCode;
      if (code == 401 || code == 403) {
        return 'HTTP $code from host. Link may be private or blocked. Use a public direct .gguf URL.';
      }
      if (code == 404) {
        return 'Model file not found (404). Verify the URL and filename.';
      }
      if (code != null) {
        return 'Network request failed (HTTP $code).';
      }
      if (error.type == DioExceptionType.connectionTimeout ||
          error.type == DioExceptionType.receiveTimeout ||
          error.type == DioExceptionType.sendTimeout) {
        return 'Connection timed out. Check network and retry.';
      }
      return error.message ?? 'Unexpected network error.';
    }
    // A corrupt transfer reports itself this way, and its sentence is already
    // the one the user needs to read.
    if (error is StateError) return error.message;
    return error.toString();
  }

  String _deriveLocalFileName(Uri uri) {
    final lastSegment = uri.pathSegments.isNotEmpty
        ? uri.pathSegments.last
        : '';
    final fileName = lastSegment.isEmpty
        ? 'custom-${DateTime.now().millisecondsSinceEpoch}.gguf'
        : lastSegment;
    return fileName.toLowerCase().endsWith('.gguf')
        ? fileName
        : '$fileName.gguf';
  }

  String _slugify(String text) {
    final slug = text
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    return slug.isEmpty ? 'model' : slug;
  }

  bool _isValidParameterSize(String value) {
    return RegExp(r'^[0-9]*\.?[0-9]+\s*[KMBT]$').hasMatch(value);
  }

  Future<StorageInfo?> _refreshStorageInfo() async {
    final info = await _storageInfoService.getStorageInfo();
    state = state.copyWith(
      freeStorageBytes: info?.freeBytes,
      totalStorageBytes: info?.totalBytes,
    );
    return info;
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
}
