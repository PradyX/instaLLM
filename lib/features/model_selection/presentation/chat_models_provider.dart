import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:installm/features/model_selection/domain/llm_model.dart';
import 'package:installm/features/model_selection/presentation/model_selection_controller.dart';

/// The models a chat can answer with: installed, and not an embedding-only
/// model, smallest first.
///
/// Home's composer, a bot room's composer and the bot editor all read this one
/// list, so a model offered on one surface can no longer be missing on another,
/// and every menu is in the same order. It is a composer concern, not a
/// capability one: which models may *run tools* is decided per model, not by
/// hiding models from the user.
final chatModelsProvider = Provider<List<LlmModel>>((ref) {
  final models = ref.watch(modelSelectionControllerProvider).models;
  return [
    for (final model in models)
      if (model.isDownloaded && !model.isEmbeddingModel) model,
  ]..sort(compareModelsByParamSize);
});

/// The model a new answer uses: the app's selected model when it is still
/// installed, otherwise the smallest installed chat model.
///
/// Null only when nothing is installed, which is the one case where a composer
/// offers "Get a model" instead of a pill.
final selectedChatModelProvider = Provider<LlmModel?>((ref) {
  final models = ref.watch(chatModelsProvider);
  final selectedId = ref.watch(
    modelSelectionControllerProvider.select((state) => state.selectedModelId),
  );
  for (final model in models) {
    if (model.id == selectedId) return model;
  }
  return models.isEmpty ? null : models.first;
});

/// Smallest first: the smallest installed model is the one most devices can
/// run, so it is what an unpicked chat falls back to.
int compareModelsByParamSize(LlmModel a, LlmModel b) {
  final bySize = numericParameterSize(
    a.parameterSize,
  ).compareTo(numericParameterSize(b.parameterSize));
  if (bySize != 0) return bySize;
  return a.name.toLowerCase().compareTo(b.name.toLowerCase());
}

/// "1.4B" as 1.4e9, so sizes sort as sizes and not as text.
double numericParameterSize(String value) {
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
