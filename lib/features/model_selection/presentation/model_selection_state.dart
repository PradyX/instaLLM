import 'package:installm/features/model_selection/domain/llm_model.dart';

/// The model list, as the selection screen keeps it.
///
/// Live download progress is not here on purpose: see
/// `download_progress_provider.dart` for why it has its own provider.
class ModelSelectionState {
  static const _unset = Object();

  final List<LlmModel> models;
  final String? selectedModelId;
  final Set<ModelCapability> selectedCapabilityFilters;

  /// Whether installed families are pulled to the top of the list before the
  /// rest. On by default: the models you already have are the ones you will
  /// act on first, and the chip turns this off when the raw catalog matters.
  final bool prioritizeDownloadedModels;

  /// Whether families sort by how well their best-fitting variant is expected
  /// to run on this device, the biggest comfortable model first, instead of by
  /// parameter size. On by default, together with the installed ordering: the
  /// list should start with what runs here.
  final bool sortByFit;
  final String searchQuery;
  final String? error;
  final int? freeStorageBytes;
  final int? totalStorageBytes;

  ModelSelectionState({
    required this.models,
    this.selectedModelId,
    this.selectedCapabilityFilters = const {},
    this.prioritizeDownloadedModels = true,
    this.sortByFit = true,
    this.searchQuery = '',
    this.error,
    this.freeStorageBytes,
    this.totalStorageBytes,
  });

  LlmModel? get selectedModel {
    if (selectedModelId == null) return null;
    try {
      return models.firstWhere((m) => m.id == selectedModelId);
    } catch (_) {
      return null;
    }
  }

  ModelSelectionState copyWith({
    List<LlmModel>? models,
    Object? selectedModelId = _unset,
    Set<ModelCapability>? selectedCapabilityFilters,
    bool? prioritizeDownloadedModels,
    bool? sortByFit,
    String? searchQuery,
    Object? error = _unset,
    Object? freeStorageBytes = _unset,
    Object? totalStorageBytes = _unset,
  }) {
    return ModelSelectionState(
      models: models ?? this.models,
      selectedModelId: selectedModelId == _unset
          ? this.selectedModelId
          : selectedModelId as String?,
      selectedCapabilityFilters:
          selectedCapabilityFilters ?? this.selectedCapabilityFilters,
      prioritizeDownloadedModels:
          prioritizeDownloadedModels ?? this.prioritizeDownloadedModels,
      sortByFit: sortByFit ?? this.sortByFit,
      searchQuery: searchQuery ?? this.searchQuery,
      error: error == _unset ? this.error : error as String?,
      freeStorageBytes: freeStorageBytes == _unset
          ? this.freeStorageBytes
          : freeStorageBytes as int?,
      totalStorageBytes: totalStorageBytes == _unset
          ? this.totalStorageBytes
          : totalStorageBytes as int?,
    );
  }
}
