import 'package:flutter_test/flutter_test.dart';
import 'package:installm/features/conversations/presentation/conversation_controller.dart';
import 'package:installm/features/home/presentation/home_controller.dart';
import 'package:installm/features/memory/application/memory_controller.dart';
import 'package:installm/features/memory/domain/memory_fact.dart';
import 'package:installm/features/model_selection/domain/llm_model.dart';
import 'package:installm/features/model_selection/presentation/model_selection_controller.dart';
import 'package:installm/features/workspaces/application/workspaces_controller.dart';
import 'package:installm/features/conversations/application/conversation_context_builder.dart';
import 'package:installm/features/conversations/domain/context_policy.dart';
import 'package:installm/features/conversations/domain/message.dart';
import 'package:installm/features/memory/domain/memory_prompt.dart';
import 'package:installm/core/utils/llm_structured_response.dart';

import 'memory_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MemoryTestHarness harness;
  setUp(
    () => harness = MemoryTestHarness(
      models: const [
        LlmModel(
          id: 'm1',
          name: 'One',
          parameterSize: '1B',
          description: 'test',
          isDownloaded: true,
        ),
        LlmModel(
          id: 'm2',
          name: 'Two',
          parameterSize: '1B',
          description: 'test',
          isDownloaded: true,
        ),
      ],
    ),
  );
  tearDown(() => harness.close());

  test(
    'ordinary requests and projection charge scoped facts without losing persona/reservation',
    () async {
      final container = harness.container();
      final home = await harness.home(container);
      await home.sendMessage(
        'remember in workspace: Project one uses Flutter.',
      );
      final memory = container.read(memoryProvider.notifier);
      await memory.remember(
        text: 'Project two secret.',
        scope: MemoryScope.workspace,
        ownerId: 'ws2',
      );
      await memory.remember(
        text: 'Expired.',
        scope: MemoryScope.workspace,
        ownerId: 'ws1',
        expiresAt: DateTime(2000),
      );
      await home.sendMessage('What should I use?');
      final prompt = harness.engine.prompts.single;
      expect(prompt, contains(defaultAssistantSystemPrompt));
      expect(prompt, contains('Project one uses Flutter.'));
      expect(prompt, isNot(contains('Project two secret.')));
      expect(prompt, isNot(contains('Expired.')));
      expect(prompt, contains('Saved memory'));
      final projection = container.read(homeContextProjectionProvider)!;
      expect(projection.fixedTokens, greaterThan(0));
      final usage = container.read(homeGenerationStatusProvider).contextUsage!;
      expect(harness.engine.reservations.single, usage.reservedOutputTokens);
      expect(usage.usedTokens, lessThanOrEqualTo(usage.limitTokens));
      expect(usage.reservedOutputTokens, greaterThanOrEqualTo(64));
      await container.read(workspacesProvider.notifier).setActive('ws2');
      (container.read(modelSelectionControllerProvider.notifier)
              as MemoryTestSelection)
          .choose('m2');
      await home.sendMessage('What about now?');
      // The same conversation stays bound to ws1 across workspace/model changes.
      expect(
        harness.engine.prompts.last,
        contains('Project one uses Flutter.'),
      );
      expect(
        harness.engine.prompts.last,
        isNot(contains('Project two secret.')),
      );
      expect(container.read(homeControllerProvider).last.modelId, 'm2');
      final id = container
          .read(conversationControllerProvider)
          .activeConversationId!;
      expect(harness.memoryStore.load(), isNotEmpty);
      expect(harness.memoryStore.conversationWorkspaces[id], 'ws1');
    },
  );

  test(
    'saved facts preserve the system prompt and output reservation through overflow',
    () {
      final system = withMemoryFacts(
        'Always answer clearly.',
        '- [workspace; inferred] Use Flutter.',
      );
      const policy = ContextPolicy(
        contextTokens: 512,
        reservedOutputTokens: 128,
      );
      for (final count in [1, 10, 100]) {
        final messages = [
          for (var i = 0; i < count; i++)
            Message.create(
              conversationId: 'c1',
              role: MessageRole.user,
              content: 'Question $i ${'padding ' * 10}',
            ),
        ];
        final assembly = const ConversationContextBuilder().build(
          messages: messages,
          systemPrompt: system,
          policy: policy,
        );
        expect(assembly.systemPrompt, system);
        expect(assembly.usage.reservedOutputTokens, 128);
        expect(
          assembly.usage.usedTokens,
          lessThanOrEqualTo(policy.usableInputTokens),
        );
        if (count > 10) expect(assembly.usage.droppedMessages, greaterThan(0));
        final projection = projectConversationContext(
          messages: messages,
          systemPrompt: system,
          policy: policy,
        );
        expect(projection.usage.usedTokens, assembly.usage.usedTokens);
        expect(projection.fixedTokens, TokenEstimator.estimateMessage(system));
      }
    },
  );
}
