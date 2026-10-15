import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:installm/features/agents/application/agent_loop_service.dart';
import 'package:installm/features/agents/application/background_runs_controller.dart';
import 'package:installm/features/agents/application/run_checkpoint_session.dart';
import 'package:installm/features/agents/data/run_checkpoint_store.dart';
import 'package:installm/features/agents/domain/background_run.dart';
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

const LlmModel _model = LlmModel(
  id: 'm',
  name: 'Local',
  parameterSize: '1B',
  description: 'test',
  isDownloaded: true,
  capabilities: [ModelCapability.tools],
);

/// One room, one bot, a linked project folder and a scripted runtime.
class _Harness {
  _Harness({
    required this.root,
    required this.container,
    required this.runtime,
    required this.roomId,
    required this.project,
  });

  final Directory root;
  final ProviderContainer container;
  final ScriptedAgentRuntime runtime;
  final String roomId;
  final Directory project;

  GroupChatsNotifier get chats => container.read(groupChatsProvider.notifier);

  String get lastMessage =>
      container.read(groupChatsProvider).snapshot.messagesFor(roomId).last.text;

  Future<void> dispose() async {
    container.dispose();
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
    await Future<void>.delayed(const Duration(milliseconds: 50));
    root.deleteSync(recursive: true);
  }
}

Future<_Harness> _harness({
  required String name,
  List<String> script = const [],
  List<LlmModel> models = const [_model],
}) async {
  final root = Directory.systemTemp.createTempSync('room-review-$name-');
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
  final runtime = ScriptedAgentRuntime(script: script);
  final notices = <(String, String)>[];
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
        (ref) async =>
            RunCheckpointStore(File('${root.path}/agents/checkpoints.json')),
      ),
      backgroundRunNoticeProvider.overrideWithValue(
        (title, body) async => notices.add((title, body)),
      ),
      chatModelsProvider.overrideWithValue(models),
      selectedChatModelProvider.overrideWithValue(
        models.isEmpty ? null : models.first,
      ),
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

  await container.read(botsProvider.notifier).whenReady;
  container.read(groupChatsProvider);
  await pumpAgentUntil(() => container.read(groupChatsProvider).isReady);
  final room = (await container
      .read(groupChatsProvider.notifier)
      .createChat(workspaceId: 'w', name: 'Docs', memberBotIds: ['one']))!;
  await container.read(backgroundRunsProvider.notifier).whenReady;
  return _Harness(
    root: root,
    container: container,
    runtime: runtime,
    roomId: room.id,
    project: Directory('${root.path}/external/Project'),
  );
}

/// One bot turn that writes the journal, so the room has a run to review.
List<String> _writingTurn(String facts) => [
  jsonEncode({
    'type': 'tool_call',
    'tool': 'vault_record_summary',
    'arguments': {'summary': facts},
  }),
  'Recorded it.',
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'a room reviews what its run wrote, then hands a finding to a bot',
    () async {
      final harness = await _harness(
        name: 'pass',
        script: [
          ..._writingTurn('First facts.'),
          // A second turn, so the reviewed run changed a file that existed.
          ..._writingTurn('Second facts.'),
          // The reviewer's answer, in the format the template asks for.
          'Looking at the change:\n'
              '1. [high] `bots/bot-one/summary.md` — The summary names no author\n'
              '   A reader cannot tell who recorded it.\n'
              '2. [note] — The order of the sections is unusual\n',
          'Added the author line.',
        ],
      );
      addTearDown(harness.dispose);

      await harness.chats.sendUserMessage(harness.roomId, '@One record facts.');
      final note = File('${harness.project.path}/bots/bot-one/summary.md');
      expect(
        note.existsSync(),
        isTrue,
        reason: 'the run wrote a file to review',
      );
      await harness.chats.sendUserMessage(
        harness.roomId,
        '@One record them again.',
      );

      await harness.chats.sendUserMessage(harness.roomId, '/review');

      // What the reviewer was given: the change itself, before and after.
      final prompt = harness.runtime.prompts.last;
      expect(prompt, contains('=== bots/bot-one/summary.md'));
      expect(prompt, contains('--- before ---'));
      expect(prompt, contains('--- after ---'));
      expect(prompt, contains('First facts.'));
      expect(prompt, contains('Second facts.'));
      expect(prompt, contains('[blocker], [high], [medium], [low] or [note]'));
      expect(
        prompt,
        contains('the latest run (run-'),
        reason: 'the reviewer is told which run it is reading',
      );

      expect(harness.lastMessage, contains('Review of the latest run (run-'));

      expect(
        harness.lastMessage,
        contains('1. [high] `bots/bot-one/summary.md`'),
      );
      expect(harness.lastMessage, contains('names no author'));
      expect(harness.lastMessage, contains('2. [note]'));
      expect(harness.lastMessage, contains('/review fix 1'));

      await harness.chats.sendUserMessage(harness.roomId, '/review list');
      expect(harness.lastMessage, contains('names no author'));

      await harness.chats.sendUserMessage(harness.roomId, '/review fix 1');
      final run = harness.container.read(backgroundRunsProvider).runs.single;
      expect(run.task, contains('Fix this review finding (High)'));
      expect(run.task, contains('bots/bot-one/summary.md'));
      expect(run.task, contains('A reader cannot tell who recorded it.'));
      await pumpAgentUntil(
        () => harness.container
            .read(backgroundRunsProvider)
            .runs
            .every((candidate) => !candidate.isRunning),
      );
      expect(
        harness.container.read(backgroundRunsProvider).runs.single.status,
        BackgroundRunStatus.done,
        reason: 'the fix is an ordinary run of this chat',
      );
      final started = harness.container
          .read(groupChatsProvider)
          .snapshot
          .messagesFor(harness.roomId)
          .map((message) => message.text)
          .any((text) => text.contains('Started ${run.id}'));
      expect(started, isTrue);

      // A finding number that is not in the listing is refused, not guessed.
      await harness.chats.sendUserMessage(harness.roomId, '/review fix 9');
      expect(harness.lastMessage, contains('2 findings'));
    },
  );

  test('a review of named files, and a room with nothing recorded', () async {
    final harness = await _harness(name: 'named', script: ['No findings']);
    addTearDown(harness.dispose);

    // Nothing has been written yet, so there is nothing to review.
    await harness.chats.sendUserMessage(harness.roomId, '/review');
    expect(harness.lastMessage, contains('nothing recorded to review'));

    final plan = File('${harness.project.path}/notes/plan.md');
    plan
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('Step one.\nStep two.\n');

    await harness.chats.sendUserMessage(
      harness.roomId,
      '/review notes/plan.md',
    );
    final prompt = harness.runtime.prompts.last;
    expect(prompt, contains('=== notes/plan.md ==='));
    expect(prompt, contains('Step two.'));
    expect(
      prompt,
      isNot(contains('--- before ---')),
      reason: 'a file the user names has no earlier version to show',
    );
    expect(harness.lastMessage, contains('Review of 1 named file(s)'));
    expect(harness.lastMessage, contains('No findings.'));

    // A named file that is not there is reported, not silently reviewed.
    await harness.chats.sendUserMessage(
      harness.roomId,
      '/review notes/gone.md',
    );
    expect(harness.lastMessage, contains('notes/gone.md'));
    expect(harness.lastMessage, contains('Nothing could be read'));
  });

  test('without an installed model nothing is reviewed', () async {
    final harness = await _harness(
      name: 'nomodel',
      script: ['No findings'],
      models: const [],
    );
    addTearDown(harness.dispose);

    File('${harness.project.path}/notes/plan.md')
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('Step one.\n');

    await harness.chats.sendUserMessage(
      harness.roomId,
      '/review notes/plan.md',
    );
    expect(harness.lastMessage, contains('No model is installed'));
    expect(
      harness.lastMessage,
      isNot(contains('No findings')),
      reason: 'nothing looked at the changes, so nothing may be claimed',
    );
    expect(harness.runtime.generateCalls, 0);
  });

  test(
    'a review left to the skill path keeps the review skill working',
    () async {
      final harness = await _harness(name: 'flags', script: ['No findings']);
      addTearDown(harness.dispose);

      // `/review --resource=…` belongs to the skill command, not this pass: it
      // must reach the skill path (here: no eligible review skill, so the room
      // says the skill cannot be used rather than starting a review).
      await harness.chats.sendUserMessage(
        harness.roomId,
        '/review --resource=template.md',
      );
      expect(harness.runtime.generateCalls, 0);
    },
  );
}
