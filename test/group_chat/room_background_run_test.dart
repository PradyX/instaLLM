import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:installm/features/agents/application/agent_loop_service.dart';
import 'package:installm/features/agents/application/background_runs_controller.dart';
import 'package:installm/features/agents/data/background_run_store.dart';
import 'package:installm/features/agents/domain/background_run.dart';
import 'package:installm/features/bots/application/bots_controller.dart';
import 'package:installm/features/bots/data/bot_store.dart';
import 'package:installm/features/bots/domain/bot.dart';
import 'package:installm/features/group_chat/application/group_chat_controller.dart';
import 'package:installm/features/group_chat/data/group_chat_store.dart';
import 'package:installm/features/group_chat/domain/group_chat.dart';
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

const LlmModel _model = LlmModel(
  id: 'm',
  name: 'Local',
  parameterSize: '1B',
  description: 'test',
  isDownloaded: true,
  capabilities: [ModelCapability.tools],
);

/// One room, one bot, a scripted runtime and a notice sink that records.
class _Harness {
  _Harness({
    required this.root,
    required this.container,
    required this.runtime,
    required this.notices,
    required this.store,
    required this.roomId,
  });

  final Directory root;
  final ProviderContainer container;
  final ScriptedAgentRuntime runtime;

  /// What the app would have shown, in order.
  final List<(String, String)> notices;

  final BackgroundRunStore store;
  final String roomId;

  BackgroundRunsSnapshot get stored => store.load();

  GroupChatsNotifier get chats => container.read(groupChatsProvider.notifier);

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

List<ToolEntry> _toolEntries(List<String> tools, {required bool ran}) => [
  for (final name in tools)
    ToolEntry(
      definition: ToolDefinition(
        name: name,
        description: 'Test tool $name.',
        parameters: const [
          ToolParameter(
            name: 'text',
            type: ToolParameterType.string,
            description: 'Text.',
            required: false,
          ),
        ],
        risk: ToolRiskLevel.sensitive,
      ),
      handler: (arguments) async {
        ran = true;
        return '$name ran';
      },
    ),
];

Future<_Harness> _harness({
  required String name,
  List<String> script = const [],
  bool holdAtEnd = false,
  List<LlmModel> models = const [_model],
  ToolRegistry? registry,
  Future<void> Function(String title, String body)? notice,

  /// Room lines written before the app opens, so a turn can be given the long
  /// history a real room has.
  List<String> roomLines = const [],

  /// Whether the runtime claims to be mid-answer already.
  bool runtimeBusy = false,
}) async {
  final root = Directory.systemTemp.createTempSync('runs-$name-');
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
        Bot.create(id: 'one', name: 'One', soul: 'Do the task briefly.'),
      ],
    ),
  );
  final vaults = VaultStore(File('${root.path}/registry.json'));
  vaults.save(const VaultsSnapshot(vaults: [], bindings: []));
  final runtime = ScriptedAgentRuntime(script: script)
    ..holdAtEnd = holdAtEnd
    ..isGenerating = runtimeBusy;
  final notices = <(String, String)>[];
  final store = BackgroundRunStore(File('${root.path}/agents/runs.json'));
  final rooms = GroupChatStore(File('${root.path}/rooms.json'));
  if (roomLines.isNotEmpty) {
    final chat = GroupChat.create(
      id: 'dev',
      workspaceId: 'w',
      name: 'Docs',
      memberBotIds: const ['one'],
    );
    rooms.save(
      GroupChatsSnapshot(
        chats: [chat],
        messages: {
          chat.id: [
            for (final line in roomLines)
              GroupMessage.user(chatId: chat.id, text: line),
          ],
        },
      ),
    );
  }
  final container = ProviderContainer(
    overrides: [
      skillStoreProvider.overrideWith(
        (ref) async => SkillStore(File('${root.path}/skills.json')),
      ),
      botStoreProvider.overrideWith((ref) async => bots),
      groupChatStoreProvider.overrideWith((ref) async => rooms),
      vaultStoreProvider.overrideWith((ref) async => vaults),
      backgroundRunStoreProvider.overrideWith((ref) async => store),
      backgroundRunNoticeProvider.overrideWithValue(
        notice ?? (title, body) async => notices.add((title, body)),
      ),
      chatModelsProvider.overrideWithValue(models),
      selectedChatModelProvider.overrideWithValue(
        models.isEmpty ? null : models.first,
      ),
      toolRegistryProvider.overrideWithValue(
        registry ?? ToolRegistry(tools: [], platform: ToolPlatform.linux),
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
  final room = roomLines.isEmpty
      ? (await container
            .read(groupChatsProvider.notifier)
            .createChat(workspaceId: 'w', name: 'Docs', memberBotIds: ['one']))!
      : container.read(groupChatsProvider).snapshot.chats.single;
  // The supervisor is read once so its store load runs before the first start.
  await container.read(backgroundRunsProvider.notifier).whenReady;
  return _Harness(
    root: root,
    container: container,
    runtime: runtime,
    notices: notices,
    store: store,
    roomId: room.id,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a background run finishes, is recorded and notifies once', () async {
    final harness = await _harness(
      name: 'done',
      script: ['The board is up to date.'],
    );
    addTearDown(harness.dispose);

    await harness.chats.sendUserMessage(
      harness.roomId,
      '/background check the board',
    );
    await pumpAgentUntil(
      () => harness.stored.runs.every((run) => !run.isRunning),
    );

    final run = harness.stored.runs.single;
    expect(run.status, BackgroundRunStatus.done);
    expect(run.botName, 'One');
    expect(run.chatName, 'Docs');
    expect(run.task, 'check the board');
    expect(run.notified, isTrue);
    expect(harness.notices, hasLength(1));
    expect(harness.notices.single.$1, 'One · Docs');
    expect(harness.notices.single.$2, 'The board is up to date.');

    final messages = harness.container
        .read(groupChatsProvider)
        .snapshot
        .messagesFor(harness.roomId);
    expect(
      messages.any((message) => message.text.contains('Started run-')),
      isTrue,
    );
    expect(messages.last.text, 'The board is up to date.');
  });

  test(
    'a run that needs an answer says so instead of finishing quietly',
    () async {
      // No installed model: the room answers with a prompt for the user to paste,
      // which is exactly the "needs you" case.
      final harness = await _harness(name: 'needs', models: const []);
      addTearDown(harness.dispose);

      await harness.chats.sendUserMessage(
        harness.roomId,
        '/background draft a plan',
      );
      await pumpAgentUntil(
        () => harness.stored.runs.every((run) => !run.isRunning),
      );

      final run = harness.stored.runs.single;
      expect(run.status, BackgroundRunStatus.needsInput);
      expect(run.notified, isTrue);
      expect(harness.notices.single.$2, contains('waiting for your answer'));
    },
  );

  test('/background stop cancels the run and says what it kept', () async {
    final harness = await _harness(
      name: 'stop',
      script: ['This will not finish.'],
      holdAtEnd: true,
    );
    addTearDown(harness.dispose);

    await harness.chats.sendUserMessage(
      harness.roomId,
      '/background count slowly',
    );
    await pumpAgentUntil(() => harness.stored.runs.single.isRunning);
    expect(harness.runtime.cancelled, isFalse);

    await harness.chats.sendUserMessage(harness.roomId, '/background stop');
    await pumpAgentUntil(
      () => harness.stored.runs.every((run) => !run.isRunning),
    );

    final run = harness.stored.runs.single;
    expect(harness.runtime.cancelled, isTrue);
    expect(run.status, BackgroundRunStatus.stopped);
    expect(run.notified, isTrue);
    expect(harness.notices.single.$2, contains('stopped this run'));
    final messages = harness.container
        .read(groupChatsProvider)
        .snapshot
        .messagesFor(harness.roomId);
    expect(
      messages.any((message) => message.text.contains('Stopping run')),
      isTrue,
    );
  });

  test(
    'a second run in one chat is refused while the first is going',
    () async {
      final harness = await _harness(
        name: 'busy',
        script: ['Waiting.'],
        holdAtEnd: true,
      );
      addTearDown(harness.dispose);

      await harness.chats.sendUserMessage(harness.roomId, '/background first');
      await pumpAgentUntil(() => harness.stored.runs.single.isRunning);

      await harness.chats.sendUserMessage(harness.roomId, '/background second');
      expect(
        harness.container.read(backgroundRunsProvider).errorMessage,
        contains('already has a run going'),
      );
      expect(harness.stored.runs, hasLength(1));

      await harness.chats.sendUserMessage(harness.roomId, '/background stop');
      await pumpAgentUntil(
        () => harness.stored.runs.every((run) => !run.isRunning),
      );
    },
  );

  test(
    'a room whose history is longer than the goal limit still runs',
    () async {
      // The room's goal is the conversation itself. It is longer than the limit
      // that exists for a goal the user typed, and refusing it would refuse the
      // room — which is what happened before this was separated out.
      final harness = await _harness(
        name: 'longgoal',
        script: ['Nothing to do.'],
        roomLines: [
          for (var index = 0; index < 120; index++)
            'Planner: line $index of the discussion we had about the release.',
        ],
      );
      addTearDown(harness.dispose);

      await harness.chats.sendUserMessage(
        harness.roomId,
        '/background tidy up',
      );
      await pumpAgentUntil(
        () => harness.stored.runs.every((run) => !run.isRunning),
      );

      final run = harness.stored.runs.single;
      expect(run.status, BackgroundRunStatus.done, reason: run.notice);
      expect(harness.runtime.generateCalls, greaterThan(0));
    },
  );

  test(
    'a turn that could not run is reported as failed, not as needing you',
    () async {
      // A room turn that threw leaves a “paste my reply” prompt behind, so the
      // room does need the user — but the reason is a failure and the run has to
      // say so.
      final harness = await _harness(name: 'broken', runtimeBusy: true);
      addTearDown(harness.dispose);

      await harness.chats.sendUserMessage(
        harness.roomId,
        '/background check the board',
      );
      await pumpAgentUntil(
        () => harness.stored.runs.every((run) => !run.isRunning),
      );

      final run = harness.stored.runs.single;
      expect(run.status, BackgroundRunStatus.failed);
      expect(run.notice, contains('I could not run just now'));
      expect(harness.notices.single.$2, contains('I could not run just now'));
    },
  );

  test('/background list shows the runs and how each one ended', () async {
    final harness = await _harness(name: 'list', script: ['Nothing to do.']);
    addTearDown(harness.dispose);

    await harness.chats.sendUserMessage(harness.roomId, '/background tidy up');
    await pumpAgentUntil(
      () => harness.stored.runs.every((run) => !run.isRunning),
    );
    await harness.chats.sendUserMessage(harness.roomId, '/background list');

    final listing = harness.container
        .read(groupChatsProvider)
        .snapshot
        .messagesFor(harness.roomId)
        .last
        .text;
    expect(listing, contains('Runs started here'));
    expect(listing, contains('Finished'));
    expect(listing, contains('tidy up'));
    expect(listing, contains(harness.stored.runs.single.id));
  });

  test(
    'a supervised run cannot run a tool the permission gate refuses',
    () async {
      var ran = false;
      final registry = ToolRegistry(
        tools: _toolEntries(['act'], ran: ran),
        platform: ToolPlatform.linux,
        // The same gate the app uses until the user answers: refuse.
        permissionGate: const DenySensitiveTools(),
      );
      final harness = await _harness(
        name: 'gate',
        registry: registry,
        script: [
          jsonEncode({
            'type': 'tool_call',
            'tool': 'act',
            'arguments': {'text': 'do it'},
          }),
          'I could not do that.',
        ],
      );
      addTearDown(harness.dispose);

      await harness.chats.sendUserMessage(
        harness.roomId,
        '/background act now',
      );
      await pumpAgentUntil(
        () => harness.stored.runs.every((run) => !run.isRunning),
      );

      expect(ran, isFalse, reason: 'the gate refused, so nothing ran');
      expect(
        harness.runtime.prompts.last,
        contains('Status: denied'),
        reason: 'the run was told the call was refused',
      );
      expect(harness.stored.runs.single.status, BackgroundRunStatus.done);
    },
  );

  test('a run left behind by a closed app is not reported as running', () async {
    final root = Directory.systemTemp.createTempSync('runs-restart-');
    addTearDown(() => root.deleteSync(recursive: true));
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => root.path,
    );
    addTearDown(() {
      messenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        null,
      );
    });

    final store = BackgroundRunStore(File('${root.path}/agents/runs.json'));
    store.save(
      BackgroundRunsSnapshot(
        runs: [
          BackgroundRun(
            id: 'run-old',
            chatId: 'room-1',
            chatName: 'Docs',
            botId: 'one',
            botName: 'One',
            task: 'Count slowly',
            startedAt: DateTime(2026, 10, 15, 12),
          ),
        ],
      ),
    );
    final notices = <(String, String)>[];
    final container = ProviderContainer(
      overrides: [
        backgroundRunStoreProvider.overrideWith((ref) async => store),
        backgroundRunNoticeProvider.overrideWithValue(
          (title, body) async => notices.add((title, body)),
        ),
      ],
    );
    addTearDown(container.dispose);

    await container.read(backgroundRunsProvider.notifier).whenReady;

    final run = container.read(backgroundRunsProvider).runs.single;
    expect(run.status, BackgroundRunStatus.failed);
    expect(run.body, contains('app closed'));
    expect(store.load().runs.single.status, BackgroundRunStatus.failed);
    expect(
      notices,
      isEmpty,
      reason:
          'the user was there when the app closed; a notice now would be noise',
    );
  });
}
