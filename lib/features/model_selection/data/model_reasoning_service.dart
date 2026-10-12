import 'package:pocket_llm/core/services/model_storage_service.dart';
import 'package:pocket_llm/features/model_selection/data/gguf_reader.dart';
import 'package:pocket_llm/features/model_selection/domain/llm_model.dart';
import 'package:pocket_llm/features/model_selection/domain/model_reasoning.dart';

/// Answers what reasoning an installed model declares, once per model.
///
/// The answer lives in the model file's own chat template, so it is read the
/// same way the details page reads metadata — from the file, not from its name
/// — and remembered for the session: a GGUF does not change under the app, and
/// a composer asking on every rebuild must not re-read it every time. A file
/// that cannot be read reports no reasoning, which leaves the run exactly as it
/// was before the control existed.
class ModelReasoningService {
  ModelReasoningService({
    ModelStorageService? storageService,
    GgufReader reader = const GgufReader(),
  }) : _storageService = storageService ?? ModelStorageService(),
       _reader = reader;

  final ModelStorageService _storageService;
  final GgufReader _reader;
  final Map<String, ModelReasoning?> _byModelId = {};

  Future<ModelReasoning?> resolve(LlmModel model) async {
    if (_byModelId.containsKey(model.id)) return _byModelId[model.id];

    final reasoning = await _read(model);
    _byModelId[model.id] = reasoning;
    return reasoning;
  }

  Future<ModelReasoning?> _read(LlmModel model) async {
    // An imported model was read when it was registered; there is nothing
    // left to open.
    final knownTemplate = model.ggufMetadata?.chatTemplate;
    if (knownTemplate != null) return ModelReasoning.forTemplate(knownTemplate);

    try {
      final path = await _storageService.resolveModelPath(model);
      if (path == null || path.trim().isEmpty) return null;
      final metadata = await _reader.info(path);
      return ModelReasoning.forTemplate(metadata.chatTemplate);
    } catch (_) {
      return null;
    }
  }
}
