import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:installm/core/inference/inference_engine.dart';
import 'package:installm/core/services/service_providers.dart';
import 'package:installm/core/utils/llm_prompt_utils.dart';
import 'package:installm/features/model_selection/presentation/chat_models_provider.dart';

/// A spoken turn that cannot continue, in words the Companion page can show.
class CompanionTurnException implements Exception {
  const CompanionTurnException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Turns what was heard into an answer.
///
/// Behind an interface so the page can be tested without loading a GGUF model,
/// in the same way the voice loop's own turn runner is.
abstract class CompanionTurnRunner {
  /// Answers [transcript], or returns null when there is nothing worth saying.
  Future<String?> answer(String transcript);

  /// Stops an answer that is still being written.
  void interrupt();
}

/// Answers on the local engine, without writing to any conversation.
///
/// The Companion is ephemeral on purpose: the prompt is built here from the one
/// transcript, the reply is returned to the page, and neither is stored, so a
/// spoken exchange leaves no message in Chats and nothing on disk. The model
/// itself is the one chosen by the pill on the page, so the Companion can run
/// on a different model from the open chat.
class LocalCompanionTurnRunner implements CompanionTurnRunner {
  LocalCompanionTurnRunner(this.ref);

  final Ref ref;

  /// Room for the transcript plus the reply. A spoken turn is short, so this
  /// keeps the load cheap and does not reserve a whole chat window.
  static const int contextTokens = 2048;

  static const int maxReplyTokens = 220;

  static const String systemPrompt =
      'You are a friendly voice companion. Answer in one or two short spoken '
      'sentences, in plain everyday words. Do not use lists, headings, '
      'markdown, emoji or code blocks, because your answer is read aloud.';

  @override
  void interrupt() {
    final engine = ref.read(inferenceEngineProvider);
    if (engine.isGenerating) engine.cancel();
  }

  @override
  Future<String?> answer(String transcript) async {
    final model = ref.read(selectedChatModelProvider);
    if (model == null) {
      throw const CompanionTurnException(
        'Choose a model with the pill at the top of this page, then speak '
        'again.',
      );
    }

    final storage = ref.read(modelStorageServiceProvider);
    final modelPath = await storage.resolveModelPath(model);
    if (!await storage.isModelPathDownloaded(modelPath)) {
      throw CompanionTurnException(
        '${model.name} is not downloaded on this device any more.',
      );
    }

    final engine = ref.read(inferenceEngineProvider);
    if (engine.isGenerating) {
      throw const CompanionTurnException(
        'The model is still answering something else. Try again once it has '
        'finished.',
      );
    }

    await engine.ensureModelLoaded(
      InferenceLoadRequest(
        modelPath: modelPath!,
        contextTokens: contextTokens,
        batchTokens: contextTokens,
        temperature: 0.7,
        topP: 0.9,
        topK: 40,
      ),
    );

    final prompt = buildModelChatPrompt(
      [LlmPromptMessage.user(transcript)],
      systemPrompt: systemPrompt,
      promptFormatId: model.promptFormatId,
    );
    final stopToken = modelStopToken(model.promptFormatId);
    final buffer = StringBuffer();

    await for (final token in engine.generateResponse(
      prompt.prompt,
      maxTokens: maxReplyTokens,
    )) {
      final clean = token.replaceAll(stopToken, '');
      if (clean.isNotEmpty) buffer.write(clean);
    }

    final reply = buildFinalResponseText(buffer.toString()).trim();
    if (reply.isEmpty || reply == 'No response generated.') return null;
    return _forSpeaking(reply);
  }

  /// The reply as a voice should hear it: no code fences, no markup marks, and
  /// whitespace collapsed so the synthesizer does not read a pause per line.
  static String _forSpeaking(String text) {
    return text
        .replaceAll(RegExp(r'```[\s\S]*?```'), ' ')
        .replaceAll(RegExp(r'[#*_>`]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}

final companionTurnRunnerProvider = Provider<CompanionTurnRunner>(
  (ref) => LocalCompanionTurnRunner(ref),
);
