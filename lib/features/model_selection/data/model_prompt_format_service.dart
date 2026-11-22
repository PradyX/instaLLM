import 'package:installm/core/services/model_storage_service.dart';
import 'package:installm/core/utils/llm_prompt_utils.dart';
import 'package:installm/features/model_selection/data/gguf_reader.dart';
import 'package:installm/features/model_selection/domain/llm_model.dart';

/// How a model's own file says a conversation should be written.
class ModelPromptFormat {
  /// The format [buildModelChatPrompt] builds.
  final String promptFormatId;

  /// Whether the file declares an instruction template at all.
  ///
  /// A base completion model declares none: it was trained to continue text,
  /// not to follow instructions, so a chat prompt produces babble whatever the
  /// app writes into it.
  final bool isInstruct;

  const ModelPromptFormat._({
    required this.promptFormatId,
    required this.isInstruct,
  });

  const ModelPromptFormat.instruct(String id)
    : this._(promptFormatId: id, isInstruct: true);

  const ModelPromptFormat.base()
    : this._(promptFormatId: 'chatml', isInstruct: false);

  /// What a file declaring [template] can be chatted with.
  ///
  /// `null` is the one answer that cannot be formatted around: no instruction
  /// template means the file is a base completion model.
  factory ModelPromptFormat.fromTemplate(String? template) {
    final detected = promptFormatFromTemplate(template);
    return detected == null
        ? const ModelPromptFormat.base()
        : ModelPromptFormat.instruct(detected);
  }

  @override
  bool operator ==(Object other) =>
      other is ModelPromptFormat &&
      other.promptFormatId == promptFormatId &&
      other.isInstruct == isInstruct;

  @override
  int get hashCode => Object.hash(promptFormatId, isInstruct);

  @override
  String toString() => isInstruct
      ? 'ModelPromptFormat($promptFormatId)'
      : 'ModelPromptFormat.base';
}

/// Reads the prompt format from an installed model's own chat template.
///
/// The format is a property of the file — an imported repository brings its own
/// template, and two files from one repository can differ — so it is read the
/// same way the details page reads metadata, and remembered for the session: a
/// GGUF does not change under the app, and every turn must not re-open it.
class ModelPromptFormatService {
  ModelPromptFormatService({
    ModelStorageService? storageService,
    GgufReader reader = const GgufReader(),
  }) : _storageService = storageService ?? ModelStorageService(),
       _reader = reader;

  final ModelStorageService _storageService;
  final GgufReader _reader;
  final Map<String, ModelPromptFormat> _byModelId = {};

  Future<ModelPromptFormat> resolve(LlmModel model) async {
    final cached = _byModelId[model.id];
    if (cached != null) return cached;

    final resolved = await _read(model);
    _byModelId[model.id] = resolved;
    return resolved;
  }

  Future<ModelPromptFormat> _read(LlmModel model) async {
    // Registered imports and models whose details were opened carry the
    // template already; there is nothing left to open.
    final knownTemplate = model.ggufMetadata?.chatTemplate;
    if (knownTemplate != null) return _fromTemplate(knownTemplate);

    try {
      final path = await _storageService.resolveModelPath(model);
      if (path != null && path.trim().isNotEmpty) {
        final info = await _reader.info(path);
        if (info.chatTemplate != null) return _fromTemplate(info.chatTemplate);
        // The file embeds nothing, but the repository it came from may still
        // declare the template it was converted with.
        if (model.repositoryChatTemplate != null) {
          return _fromTemplate(model.repositoryChatTemplate);
        }
        return const ModelPromptFormat.base();
      }
    } catch (_) {
      // An unreadable file keeps the recorded format rather than declaring the
      // model a base one: a read failure is not evidence about the model.
    }

    if (model.repositoryChatTemplate != null) {
      return _fromTemplate(model.repositoryChatTemplate);
    }
    return ModelPromptFormat.instruct(model.promptFormatId);
  }

  ModelPromptFormat _fromTemplate(String? template) =>
      ModelPromptFormat.fromTemplate(template);
}
