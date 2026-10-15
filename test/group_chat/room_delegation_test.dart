import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:installm/features/agents/application/agent_loop_service.dart';
import 'package:installm/features/bots/application/bots_controller.dart';
import 'package:installm/features/bots/data/bot_store.dart';
import 'package:installm/features/bots/domain/bot.dart';
import 'package:installm/features/group_chat/application/group_chat_controller.dart';
import 'package:installm/features/group_chat/data/group_chat_store.dart';
import 'package:installm/features/model_selection/domain/llm_model.dart';
import 'package:installm/features/model_selection/presentation/chat_models_provider.dart';
import 'package:installm/features/skills/application/skills_controller.dart';
import 'package:installm/features/skills/data/skill_store.dart';
import 'package:installm/features/tools/application/tool_registry.dart';
import 'package:installm/features/tools/application/tools_providers.dart';
import 'package:installm/features/tools/domain/tool_definition.dart';
import 'package:installm/features/vault/application/vaults_controller.dart';
import 'package:installm/features/vault/data/vault_store.dart';

import '../agents/scripted_agent_runtime.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'a room bot delegates one task and gets back only the other bot’s answer',
    () async {
      final root = Directory.systemTemp.createTempSync('room-delegation-');
      addTearDown(() => root.deleteSync(recursive: true));
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (_) async => root.path,
      );
      messenger.setMockMethodCallHandler(
        const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
        (_) async => null,
      );
      addTearDown(() {
        messenger.setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
        messenger.setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          null,
        );
      });

      final bots = BotStore(File('${root.path}/bots.json'));
      bots.save(
        BotsSnapshot(
          customBots: [
            Bot.create(
              id: 'one',
              name: 'One',
              soul: 'PARENT SOUL: split the work and answer briefly.',
            ),
            Bot.create(
              id: 'two',
              name: 'Research bot',
              soul: 'CHILD SOUL: read notes and report exactly what they say.',
            ),
          ],
        ),
      );
      final vaults = VaultStore(File('${root.path}/registry.json'));
      vaults.save(VaultsSnapshot(vaults: const [], bindings: const []));
      const roomQuestion = 'Please look into the widget documentation.';
      final runtime = ScriptedAgentRuntime(
        script: [
          jsonEncode({
            'type': 'tool_call',
            'tool': 'delegate_task',
            'arguments': {
              'bot': 'Research bot',
              'task': 'Which note lists the widgets?',
            },
          }),
          'The widgets are documented in notes/a.md.',
          'The research bot found the widgets in notes/a.md.',
        ],
      );
      const model = LlmModel(
        id: 'm',
        name: 'Local',
        parameterSize: '1B',
        description: 'test',
        isDownloaded: true,
        capabilities: [ModelCapability.tools],
      );
      final container = ProviderContainer(
        overrides: [
          skillStoreProvider.overrideWith(
            (ref) async => SkillStore(File('${root.path}/skills.json')),
          ),
          botStoreProvider.overrideWith((ref) async => bots),
          groupChatStoreProvider.overrideWith(
            (ref) async => GroupChatStore(File('${root.path}/rooms.json')),
          ),
          vaultStoreProvider.overrideWith((ref) async => vaults),
          chatModelsProvider.overrideWithValue([model]),
          selectedChatModelProvider.overrideWithValue(model),
          toolRegistryProvider.overrideWithValue(
            ToolRegistry(tools: [], platform: ToolPlatform.linux),
          ),
          agentLoopServiceProvider.overrideWithValue(
            AgentLoopService(
              runtime: runtime,
              resolveModelPath: (_) async => '/test.gguf',
              isFileReady: (_) async => true,
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      await container.read(botsProvider.notifier).whenReady;
      container.read(groupChatsProvider);
      await pumpAgentUntil(() => container.read(groupChatsProvider).isReady);
      final controller = container.read(groupChatsProvider.notifier);
      final room = (await controller.createChat(
        workspaceId: 'w',
        name: 'Docs',
        memberBotIds: ['one', 'two'],
      ))!;

      // A plain mention routes to One, which delegates and then answers.
      await controller.sendUserMessage(room.id, '@One $roomQuestion');

      expect(
        runtime.generateCalls,
        3,
        reason: 'the parent, the child, then the parent again',
      );
      final parentPrompt = runtime.prompts.first;
      final childPrompt = runtime.prompts[1];
      expect(parentPrompt, contains('PARENT SOUL'));
      expect(parentPrompt, contains('delegate_task'));
      expect(parentPrompt, contains('Research bot'));

      expect(childPrompt, contains('CHILD SOUL'));
      expect(childPrompt, contains('Which note lists the widgets?'));
      expect(
        childPrompt,
        isNot(contains('PARENT SOUL')),
        reason: 'the child is told its own soul, not the asking bot’s',
      );
      expect(
        childPrompt,
        isNot(contains(roomQuestion)),
        reason: 'the room’s conversation is never part of a delegation',
      );
      expect(
        childPrompt,
        isNot(contains('delegate_task')),
        reason: 'a delegated run cannot delegate again',
      );

      // What the asking bot is handed back is the child’s answer, and nothing
      // of the child's own prompt or context.
      final followUp = runtime.prompts[2];
      expect(followUp, contains('delegate_task'));
      expect(followUp, contains('Answer from Research bot'));
      expect(followUp, contains('The widgets are documented in notes/a.md.'));
      expect(
        followUp,
        isNot(contains('CHILD SOUL')),
        reason: 'the child’s prompt and context stay inside the delegation',
      );

      final messages = container
          .read(groupChatsProvider)
          .snapshot
          .messagesFor(room.id);
      expect(
        messages.last.text,
        'The research bot found the widgets in notes/a.md.',
      );
    },
  );

  test(
    'a delegation with nobody to ask says so, and the bot still answers',
    () async {
      final root = Directory.systemTemp.createTempSync('room-delegation-solo-');
      addTearDown(() => root.deleteSync(recursive: true));
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (_) async => root.path,
      );
      messenger.setMockMethodCallHandler(
        const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
        (_) async => null,
      );
      addTearDown(() {
        messenger.setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
        messenger.setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          null,
        );
      });

      final bots = BotStore(File('${root.path}/bots.json'));
      bots.save(
        BotsSnapshot(
          customBots: [
            Bot.create(id: 'one', name: 'One', soul: 'Answer briefly.'),
          ],
        ),
      );
      final vaults = VaultStore(File('${root.path}/registry.json'));
      vaults.save(VaultsSnapshot(vaults: const [], bindings: const []));
      final runtime = ScriptedAgentRuntime(script: ['Answered on my own.']);
      const model = LlmModel(
        id: 'm',
        name: 'Local',
        parameterSize: '1B',
        description: 'test',
        isDownloaded: true,
        capabilities: [ModelCapability.tools],
      );
      final container = ProviderContainer(
        overrides: [
          skillStoreProvider.overrideWith(
            (ref) async => SkillStore(File('${root.path}/skills.json')),
          ),
          botStoreProvider.overrideWith((ref) async => bots),
          groupChatStoreProvider.overrideWith(
            (ref) async => GroupChatStore(File('${root.path}/rooms.json')),
          ),
          vaultStoreProvider.overrideWith((ref) async => vaults),
          chatModelsProvider.overrideWithValue([model]),
          selectedChatModelProvider.overrideWithValue(model),
          toolRegistryProvider.overrideWithValue(
            ToolRegistry(tools: [], platform: ToolPlatform.linux),
          ),
          agentLoopServiceProvider.overrideWithValue(
            AgentLoopService(
              runtime: runtime,
              resolveModelPath: (_) async => '/test.gguf',
              isFileReady: (_) async => true,
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      await container.read(botsProvider.notifier).whenReady;
      container.read(groupChatsProvider);
      await pumpAgentUntil(() => container.read(groupChatsProvider).isReady);
      final controller = container.read(groupChatsProvider.notifier);
      final room = (await controller.createChat(
        workspaceId: 'w',
        name: 'Solo',
        memberBotIds: ['one'],
      ))!;

      await controller.sendUserMessage(room.id, '@One answer this.');

      expect(
        runtime.prompts.single,
        isNot(contains('delegate_task')),
        reason: 'with one member there is nobody to delegate to',
      );
      expect(
        container
            .read(groupChatsProvider)
            .snapshot
            .messagesFor(room.id)
            .last
            .text,
        'Answered on my own.',
      );
    },
  );
}
