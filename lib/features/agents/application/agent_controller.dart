import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pocket_llm/features/model_selection/domain/llm_model.dart';
import 'package:pocket_llm/features/model_selection/presentation/model_selection_controller.dart';

/// Models installed on this device — the only ones a bot turn can use.
///
/// Room turns filter this list by tool capability, because a turn is a
/// sequence of tool calls: a model whose chat template has no tool protocol
/// can never complete one. The capability comes from each file's own
/// template, not from its name.
final installedAgentModelsProvider = Provider<List<LlmModel>>((ref) {
  return [
    for (final model in ref.watch(modelSelectionControllerProvider).models)
      if (model.isDownloaded) model,
  ];
});

/// Installed models a bot turn can actually use.
List<LlmModel> agentRunnableModels(List<LlmModel> installed) => [
  for (final model in installed)
    if (model.supportsToolCalling) model,
];

/// Installed models that cannot call tools, so a turn can say why they are
/// not on offer instead of leaving an unexplained gap.
List<LlmModel> agentNonToolModels(List<LlmModel> installed) => [
  for (final model in installed)
    if (!model.supportsToolCalling) model,
];
