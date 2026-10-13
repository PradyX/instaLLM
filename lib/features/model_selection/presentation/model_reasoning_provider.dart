import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:installm/core/services/service_providers.dart';
import 'package:installm/features/model_selection/domain/model_reasoning.dart';
import 'package:installm/features/model_selection/presentation/model_selection_controller.dart';

/// The reasoning the installed model [modelId] declares, or null when its own
/// chat template declares none.
///
/// Read from the model file, so it costs one header read per model per session
/// and is cached by [ModelReasoningService] after that. A caller that gets null
/// shows no control at all: the choice is the model's to offer.
final modelReasoningProvider = FutureProvider.family<ModelReasoning?, String>((
  ref,
  modelId,
) async {
  final models = ref.watch(modelSelectionControllerProvider).models;
  for (final model in models) {
    if (model.id != modelId) continue;
    if (!model.isDownloaded) return null;
    return ref.watch(modelReasoningServiceProvider).resolve(model);
  }
  return null;
});
