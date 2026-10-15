import 'package:installm/features/conversations/domain/context_policy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:installm/core/utils/llm_prompt_utils.dart';
import 'package:installm/features/tools/application/tool_follow_up_prompt.dart';
import 'package:installm/features/tools/domain/tool_execution_result.dart';

void main() {
  const callJson =
      '{"type": "tool_call", "tool": "calculator", '
      '"arguments": {"expression": "2 + 2"}}';

  group('buildToolFollowUpMessages', () {
    test('keeps the history and adds the call and its result', () {
      final history = [const LlmPromptMessage.user('What is 2 + 2?')];

      final messages = buildToolFollowUpMessages(
        history: history,
        rawToolCall: callJson,
        result: const ToolExecutionResult(
          toolName: 'calculator',
          status: ToolExecutionStatus.success,
          output: '2 + 2 = 4',
        ),
      );

      expect(messages, hasLength(3));
      expect(messages[0].isUser, isTrue);
      expect(messages[0].text, 'What is 2 + 2?');
      expect(messages[1].isUser, isFalse);
      expect(messages[1].text, callJson);
      expect(messages[2].isUser, isTrue);
      expect(messages[2].text, contains('Tool: calculator'));
      expect(messages[2].text, contains('Status: success'));
      expect(messages[2].text, contains('Result: 2 + 2 = 4'));
      expect(
        messages[2].text,
        contains('Do not call another tool in this reply.'),
      );
    });

    test('carries a failure result so the model can explain it', () {
      final messages = buildToolFollowUpMessages(
        history: const [],
        rawToolCall: callJson,
        result: const ToolExecutionResult(
          toolName: 'calculator',
          status: ToolExecutionStatus.timedOut,
          output: 'calculator did not finish and was stopped.',
        ),
      );

      expect(messages, hasLength(2));
      expect(messages.last.text, contains('Status: timedOut'));
      expect(messages.last.text, contains('did not finish'));
    });
  });
  test(
    'budgeted resource follow-up preserves system/latest request and output reservation',
    () {
      const reserved = 256;
      const window = 1024;
      const system = 'Preserve this system instruction.';
      final result = buildBudgetedToolFollowUp(
        history: [
          for (var i = 0; i < 20; i++)
            LlmPromptMessage.user('Old turn $i ${'padding ' * 100}'),
          const LlmPromptMessage.user('Important latest question'),
        ],
        rawToolCall: callJson,
        result: ToolExecutionResult(
          toolName: 'skill_read_resource',
          status: ToolExecutionStatus.success,
          output: 'Reference facts. ' * 40,
        ),
        systemPrompt: system,
        promptFormatId: 'chatml',
        inputLimit: window - reserved,
      )!;
      expect(result.prompt, contains(system));
      expect(result.prompt, contains('Important latest question'));
      expect(result.prompt, contains('Reference facts.'));
      expect(result.prompt, isNot(contains('Old turn 0')));
      expect(
        TokenEstimator.estimateText(result.prompt) +
            TokenEstimator.messageOverheadTokens +
            reserved,
        lessThanOrEqualTo(window),
      );
    },
  );
  test(
    'oversized essential tool exchange refuses inference instead of dropping system or result',
    () {
      final result = buildBudgetedToolFollowUp(
        history: const [LlmPromptMessage.user('Question')],
        rawToolCall: callJson,
        result: ToolExecutionResult(
          toolName: 'skill_read_resource',
          status: ToolExecutionStatus.success,
          output: 'Facts ' * 2000,
        ),
        systemPrompt: 'Always preserve me.',
        promptFormatId: 'chatml',
        inputLimit: 256,
      );
      expect(result, isNull);
    },
  );
}
