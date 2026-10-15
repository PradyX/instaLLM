import 'package:installm/features/conversations/domain/context_policy.dart';
import 'package:installm/core/utils/llm_prompt_utils.dart';
import 'package:installm/features/tools/domain/tool_execution_result.dart';

/// Messages for the one follow-up turn after a tool ran.
///
/// The model sees the call it made and the result, then answers in prose. The
/// result is delivered as a user turn because the runtime's chat templates only
/// carry user and assistant roles; it is clearly labelled so a small model does
/// not read it as something the user typed.
///
/// [history] must be the same message list the first prompt was built from, so
/// the follow-up differs only by the tool exchange. The closing line asks for
/// no further tool call: this app runs one tool per user turn.
List<LlmPromptMessage> buildToolFollowUpMessages({
  required List<LlmPromptMessage> history,
  required String rawToolCall,
  required ToolExecutionResult result,
}) {
  return [
    ...history,
    LlmPromptMessage.assistant(rawToolCall),
    LlmPromptMessage.user(
      'The tool ran on this device. Its result follows.\n\n'
      '${result.toModelText()}\n\n'
      "Answer the user's original request using this result. Do not call "
      'another tool in this reply.',
    ),
  ];
}

/// Preserve the system prefix, latest request, tool exchange and answer
/// reservation. Older history is the only material dropped to fit the already
/// resolved input limit; null means even those essential parts do not fit.
BuiltLlmPrompt? buildBudgetedToolFollowUp({
  required List<LlmPromptMessage> history,
  required String rawToolCall,
  required ToolExecutionResult result,
  required String systemPrompt,
  required String promptFormatId,
  required int inputLimit,
  String assistantPrefill = '',
  List<String> retainedImagePaths = const [],
}) {
  for (var dropped = 0; dropped <= history.length; dropped++) {
    if (dropped > 0 && history.length - dropped < 1) break;
    final bundle = buildModelChatPrompt(
      buildToolFollowUpMessages(
        history: history.sublist(dropped),
        rawToolCall: rawToolCall,
        result: result,
      ),
      systemPrompt: systemPrompt,
      promptFormatId: promptFormatId,
      assistantPrefill: assistantPrefill,
    );
    final images = bundle.imagePaths.isEmpty
        ? retainedImagePaths
        : bundle.imagePaths;
    final cost =
        TokenEstimator.estimateText(bundle.prompt) +
        TokenEstimator.messageOverheadTokens +
        images.length * TokenEstimator.imageTokens;
    if (cost <= inputLimit) {
      return BuiltLlmPrompt(prompt: bundle.prompt, imagePaths: images);
    }
  }
  return null;
}
