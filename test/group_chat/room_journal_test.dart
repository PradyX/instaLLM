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
import 'package:installm/features/tools/application/tools_providers.dart';
import 'package:installm/features/tools/application/tool_registry.dart';
import 'package:installm/features/tools/domain/tool_definition.dart';
import 'package:installm/features/vault/application/vaults_controller.dart';
import 'package:installm/features/vault/data/vault_store.dart';
import 'package:installm/features/vault/data/journal_checkpoint_store.dart';
import 'package:installm/features/vault/domain/vault_registration.dart';
import '../agents/scripted_agent_runtime.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'room controller advertises and executes its bot journal through the real agent loop',
    () async {
      final root = Directory.systemTemp.createTempSync('room-journal-');
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
              soul: 'Summarize project facts.',
            ),
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
            'arguments': {'summary': 'Use Dart for this project.'},
          }),
          'Recorded the project summary.',
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
          botStoreProvider.overrideWith((ref) async => bots),
          groupChatStoreProvider.overrideWith(
            (ref) async => GroupChatStore(File('${root.path}/rooms.json')),
          ),
          vaultStoreProvider.overrideWith((ref) async => vaults),
          journalCheckpointStoreProvider.overrideWith(
            (ref) async =>
                JournalCheckpointStore(File('${root.path}/checkpoints.json')),
          ),
          chatModelsProvider.overrideWithValue([model]),
          selectedChatModelProvider.overrideWithValue(model),
          toolRegistryProvider.overrideWithValue(
            ToolRegistry(tools: [], platform: ToolPlatform.macOS),
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
      final room = (await controller.directChatWith(
        workspaceId: 'w',
        botId: 'one',
      ))!;
      await controller.sendUserMessage(
        room.id,
        'Record a concise summary in your journal.',
      );
      final note = File(
        '${root.path}/external/Project/bots/bot-one/summary.md',
      );
      expect(await note.readAsString(), 'Use Dart for this project.\n');
      expect(runtime.prompts.first, contains('vault_record_summary'));
      expect(runtime.prompts.first, contains('vault_write_note'));
      expect(
        container
            .read(groupChatsProvider)
            .snapshot
            .messagesFor(room.id)
            .last
            .text,
        'Recorded the project summary.',
      );
      expect(runtime.loadedModelPaths, hasLength(1));
    },
  );
}
