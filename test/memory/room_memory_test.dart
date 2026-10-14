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
import 'package:installm/features/home/presentation/home_controller.dart';
import 'package:installm/features/memory/application/memory_controller.dart';
import 'package:installm/features/memory/data/memory_store.dart';
import 'package:installm/features/memory/domain/memory_fact.dart';
import 'package:installm/features/model_selection/domain/gguf_metadata.dart';
import 'package:installm/features/model_selection/domain/llm_model.dart';
import 'package:installm/features/model_selection/presentation/chat_models_provider.dart';
import 'package:installm/features/tools/application/tool_registry.dart';
import 'package:installm/features/tools/application/tools_providers.dart';

import '../agents/scripted_agent_runtime.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late ScriptedAgentRuntime runtime;
  const model = LlmModel(
    id: 'local',
    name: 'Local',
    parameterSize: '1B',
    description: 'test',
    isDownloaded: true,
    ggufMetadata: GgufMetadata(
      architecture: 'llama',
      name: 'Local',
      version: 3,
      kvCount: 0,
      tensorCount: 0,
      fileSizeBytes: 1,
      parameterCount: 1,
      quantization: 'F16',
      chatTemplate: 'plain',
    ),
  );
  setUp(() {
    root = Directory.systemTemp.createTempSync('installm_room_memory_');
    runtime = ScriptedAgentRuntime(script: List.filled(10, 'Local answer.'));
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => root.path,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async => null,
    );
  });
  tearDown(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      null,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      null,
    );
    root.deleteSync(recursive: true);
  });

  Future<ProviderContainer> build({bool installed = true}) async {
    final bots = BotStore(File('${root.path}/bots.json'));
    bots.save(
      BotsSnapshot(
        customBots: [
          for (final scope in BotMemoryScope.values)
            Bot.create(
              id: scope.name,
              name: 'Bot ${scope.name}',
              soul: 'Be helpful.',
              memoryScope: scope,
            ),
        ],
      ),
    );
    final container = ProviderContainer(
      overrides: [
        botStoreProvider.overrideWith((ref) async => bots),
        groupChatStoreProvider.overrideWith(
          (ref) async => GroupChatStore(File('${root.path}/rooms.json')),
        ),
        memoryStoreProvider.overrideWith(
          (ref) async => MemoryStore(File('${root.path}/facts.json')),
        ),
        selectedContextWindowProvider.overrideWithValue(null),
        chatModelsProvider.overrideWithValue(installed ? [model] : []),
        selectedChatModelProvider.overrideWithValue(installed ? model : null),
        toolRegistryProvider.overrideWithValue(
          ToolRegistry(tools: [], platform: null),
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
    return container;
  }

  test(
    'persisted workspace facts reach the real room/agent prompt only in their scope',
    () async {
      final first = await build();
      final memory = first.read(memoryProvider.notifier);
      await memory.remember(
        text: 'Use Dart for this project.',
        scope: MemoryScope.workspace,
        ownerId: 'ws1',
      );
      await memory.remember(
        text: 'Other project secret.',
        scope: MemoryScope.workspace,
        ownerId: 'ws2',
      );
      await memory.remember(
        text: 'Prefer brief replies.',
        scope: MemoryScope.global,
        globalOptIn: true,
      );

      // A new provider container forces a reload from disk, then runs the real
      // room controller and agent loop. Only generation itself is scripted.
      final container = await build();
      final rooms = container.read(groupChatsProvider.notifier);
      for (final scope in BotMemoryScope.values) {
        final room = (await rooms.directChatWith(
          workspaceId: 'ws1',
          botId: scope.name,
        ))!;
        await container
            .read(memoryProvider.notifier)
            .remember(
              text: 'Private room fact ${scope.name}',
              ownerId: room.id,
            );
        await rooms.sendUserMessage(room.id, 'What should I use?');
        final prompt = runtime.prompts.last;
        expect(prompt, contains('Be helpful.'));
        expect(prompt, contains('What should I use?'));
        expect(prompt, isNot(contains('Other project secret.')));
        expect(
          prompt.contains('Use Dart for this project.'),
          scope.index >= BotMemoryScope.workspace.index,
        );
        expect(
          prompt.contains('Prefer brief replies.'),
          scope == BotMemoryScope.global,
        );
        expect(
          prompt.contains('Private room fact ${scope.name}'),
          scope != BotMemoryScope.none,
        );
        expect(
          container
              .read(groupChatsProvider)
              .snapshot
              .messagesFor(room.id)
              .last
              .text,
          'Local answer.',
        );
        if (scope == BotMemoryScope.workspace) {
          final systemEnd = prompt.indexOf('<|im_end|>');
          expect(
            prompt.indexOf('Use Dart for this project.'),
            lessThan(systemEnd),
          );
          expect(
            RegExp('Use Dart for this project.').allMatches(prompt),
            hasLength(1),
          );
        }
      }
      expect(
        runtime.requestedMaxTokens,
        everyElement(greaterThanOrEqualTo(64)),
      );
    },
  );

  test('pending prompt retains memory when no model is installed', () async {
    final container = await build(installed: false);
    await container
        .read(memoryProvider.notifier)
        .remember(
          text: 'Project fact',
          scope: MemoryScope.workspace,
          ownerId: 'ws1',
        );
    final rooms = container.read(groupChatsProvider.notifier);
    final room = (await rooms.directChatWith(
      workspaceId: 'ws1',
      botId: 'workspace',
    ))!;
    await rooms.sendUserMessage(room.id, 'Help me');
    expect(
      container
          .read(groupChatsProvider)
          .snapshot
          .messagesFor(room.id)
          .last
          .pendingPrompt,
      contains('Project fact'),
    );
    expect(runtime.prompts, isEmpty);
  });

  test('unavailable memory does not prevent a local bot answer', () async {
    final container = await build();
    // A directory where the JSON file should be forces a read failure.
    Directory('${root.path}/facts.json').createSync();
    final rooms = container.read(groupChatsProvider.notifier);
    final room = (await rooms.directChatWith(
      workspaceId: 'ws1',
      botId: 'workspace',
    ))!;
    await rooms.sendUserMessage(room.id, 'Help me');
    expect(
      container.read(memoryProvider).errorMessage,
      contains('Could not read'),
    );
    expect(
      container
          .read(groupChatsProvider)
          .snapshot
          .messagesFor(room.id)
          .last
          .text,
      'Local answer.',
    );
  });
}
