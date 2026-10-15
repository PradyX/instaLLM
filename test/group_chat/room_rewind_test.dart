import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:installm/features/agents/application/agent_loop_service.dart';
import 'package:installm/features/agents/application/run_checkpoint_session.dart';
import 'package:installm/features/agents/data/run_checkpoint_store.dart';
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
import 'package:installm/features/vault/data/journal_checkpoint_store.dart';
import 'package:installm/features/vault/data/vault_store.dart';
import 'package:installm/features/vault/domain/vault_registration.dart';

import '../agents/scripted_agent_runtime.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'a room bot writes notes, and /rewind puts them back or removes them',
    () async {
      final root = Directory.systemTemp.createTempSync('room-rewind-');
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
            Bot.create(id: 'one', name: 'One', soul: 'Record project facts.'),
          ],
        ),
      );
      final vaults = VaultStore(File('${root.path}/registry.json'));
      vaults.save(
        VaultsSnapshot(
          vaults: [
            VaultRegistration.create(
              id: 'v',
              name: 'Notes',
              rootPath: '${root.path}/external',
            ),
          ],
          bindings: const [
            WorkspaceVaultBinding(
              workspaceId: 'w',
              vaultId: 'v',
              projectPath: 'Project',
            ),
          ],
        ),
      );
      final runtime = ScriptedAgentRuntime(
        script: [
          jsonEncode({
            'type': 'tool_call',
            'tool': 'vault_record_summary',
            'arguments': {'summary': 'First facts.'},
          }),
          'Recorded the first summary.',
          jsonEncode({
            'type': 'tool_call',
            'tool': 'vault_record_summary',
            'arguments': {'summary': 'Second facts.'},
          }),
          'Recorded the second summary.',
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
      final checkpointStore = RunCheckpointStore(
        File('${root.path}/agents/checkpoints.json'),
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
          journalCheckpointStoreProvider.overrideWith(
            (ref) async =>
                JournalCheckpointStore(File('${root.path}/checkpoints.json')),
          ),
          runCheckpointStoreProvider.overrideWith(
            (ref) async => checkpointStore,
          ),
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
        memberBotIds: ['one'],
      ))!;
      final summary = File(
        '${root.path}/external/Project/bots/bot-one/summary.md',
      );

      await controller.sendUserMessage(
        room.id,
        '@One record the project facts.',
      );
      expect(await summary.readAsString(), 'First facts.\n');

      await controller.sendUserMessage(
        room.id,
        '@One record them again, differently.',
      );
      expect(await summary.readAsString(), 'Second facts.\n');

      final runs = checkpointStore.load().forContext('room:${room.id}');
      expect(runs, hasLength(2), reason: 'each bot turn that wrote is a run');
      final first = runs.last;
      final second = runs.first;
      expect(second.entries.single.relativePath, 'bots/bot-one/summary.md');
      expect(second.entries.single.beforeContent, 'First facts.\n');

      String lastMessageText() => container
          .read(groupChatsProvider)
          .snapshot
          .messagesFor(room.id)
          .last
          .text;

      await controller.sendUserMessage(room.id, '/rewind');
      expect(lastMessageText(), contains(second.id));
      expect(lastMessageText(), contains(first.id));
      expect(lastMessageText(), contains('bots/bot-one/summary.md'));

      await controller.sendUserMessage(room.id, '/rewind last');
      expect(lastMessageText(), contains('Rewind put back 1 file'));
      expect(await summary.readAsString(), 'First facts.\n');

      await controller.sendUserMessage(room.id, '/rewind ${first.id}');
      expect(lastMessageText(), contains('removed'));
      expect(summary.existsSync(), isFalse);

      // The listing still names what is left, and an unknown id says so.
      await controller.sendUserMessage(room.id, '/rewind run-nope');
      expect(lastMessageText(), contains('run-nope'));
      expect(lastMessageText(), contains('Agent runs that wrote files here'));
    },
  );

  test(
    'a file the user edited after the run is kept, with the reason',
    () async {
      final root = Directory.systemTemp.createTempSync('room-rewind-edit-');
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
            Bot.create(id: 'one', name: 'One', soul: 'Record project facts.'),
          ],
        ),
      );
      final vaults = VaultStore(File('${root.path}/registry.json'));
      vaults.save(
        VaultsSnapshot(
          vaults: [
            VaultRegistration.create(
              id: 'v',
              name: 'Notes',
              rootPath: '${root.path}/external',
            ),
          ],
          bindings: const [
            WorkspaceVaultBinding(
              workspaceId: 'w',
              vaultId: 'v',
              projectPath: 'Project',
            ),
          ],
        ),
      );
      final runtime = ScriptedAgentRuntime(
        script: [
          jsonEncode({
            'type': 'tool_call',
            'tool': 'vault_record_summary',
            'arguments': {'summary': 'First facts.'},
          }),
          'Done.',
          jsonEncode({
            'type': 'tool_call',
            'tool': 'vault_record_summary',
            'arguments': {'summary': 'Second facts.'},
          }),
          'Done again.',
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
      final checkpointStore = RunCheckpointStore(
        File('${root.path}/agents/checkpoints.json'),
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
          journalCheckpointStoreProvider.overrideWith(
            (ref) async =>
                JournalCheckpointStore(File('${root.path}/checkpoints.json')),
          ),
          runCheckpointStoreProvider.overrideWith(
            (ref) async => checkpointStore,
          ),
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
        memberBotIds: ['one'],
      ))!;
      final summary = File(
        '${root.path}/external/Project/bots/bot-one/summary.md',
      );

      await controller.sendUserMessage(
        room.id,
        '@One record the project facts.',
      );
      await controller.sendUserMessage(room.id, '@One record them again.');
      // The user edits the note afterwards.
      summary.writeAsStringSync('The user rewrote this.\n');

      await controller.sendUserMessage(room.id, '/rewind last');

      final answer = container
          .read(groupChatsProvider)
          .snapshot
          .messagesFor(room.id)
          .last
          .text;
      expect(answer, contains('changed after this run wrote it'));
      expect(await summary.readAsString(), 'The user rewrote this.\n');
    },
  );
}
