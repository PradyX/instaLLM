import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pocket_llm/core/widgets/composer_model_pill.dart';
import 'package:pocket_llm/features/agents/application/agent_controller.dart';
import 'package:pocket_llm/features/bots/domain/built_in_bots.dart';
import 'package:pocket_llm/features/group_chat/application/group_chat_controller.dart';
import 'package:pocket_llm/features/group_chat/data/group_chat_store.dart';
import 'package:pocket_llm/features/group_chat/presentation/group_chats_page.dart';
import 'package:pocket_llm/features/model_selection/domain/llm_model.dart';

/// Two installed, tool-capable models: what a room can answer with.
const _alpha = LlmModel(
  id: 'm-alpha',
  name: 'Alpha',
  parameterSize: '1B',
  description: 'test model',
  capabilities: [ModelCapability.tools],
  isDownloaded: true,
);

const _beta = LlmModel(
  id: 'm-beta',
  name: 'Beta',
  parameterSize: '3B',
  description: 'test model',
  capabilities: [ModelCapability.tools],
  isDownloaded: true,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late ProviderContainer container;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('pocketllm_room_composer');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => tempDir.path,
        );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          (call) async => null,
        );
    container = ProviderContainer(
      overrides: [
        groupChatStoreProvider.overrideWith(
          (ref) async => GroupChatStore(
            File(p.join(tempDir.path, 'group_chat', 'chats.json')),
          ),
        ),
        installedAgentModelsProvider.overrideWithValue(const [_alpha, _beta]),
      ],
    );
    addTearDown(container.dispose);
    // The store is read off the event loop; wait for it before writing rooms
    // through the notifier.
    for (var attempt = 0; attempt < 50; attempt++) {
      if (container.read(groupChatsProvider).isReady) break;
      await Future<void>.delayed(Duration.zero);
    }
    expect(container.read(groupChatsProvider).isReady, isTrue);
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          null,
        );
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  /// Lets the app's own file work run, then draws a frame: the room writes
  /// through real documents and some of its widgets animate continuously, so
  /// waiting for the frame queue to empty would never return.
  Future<void> pumpRoom(
    WidgetTester tester,
    String chatId, {
    int frames = 40,
  }) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: GroupChatDetailPage(chatId: chatId)),
      ),
    );
    for (var attempt = 0; attempt < frames; attempt++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  /// Pumps the menu's open or close transition without settling the room.
  Future<void> pumpMenu(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  /// The pill's own label: the open menu can carry the same text.
  Finder pillLabel(String text) => find.descendant(
    of: find.byType(ComposerModelPill),
    matching: find.text(text),
  );

  testWidgets('a bot room switches its model from the composer', (
    tester,
  ) async {
    final notifier = container.read(groupChatsProvider.notifier);
    final room = await tester.runAsync(
      () => notifier.createChat(
        workspaceId: 'ws',
        name: 'Coder',
        memberBotIds: const [BuiltInBots.coderId],
        directBotId: BuiltInBots.coderId,
      ),
    );

    await pumpRoom(tester, room!.id);

    // The bot names no model, so the first tool-capable one is in use.
    expect(find.byType(ComposerModelPill), findsOneWidget);
    expect(pillLabel('Alpha · 1B'), findsOneWidget);

    await tester.tap(find.text('Alpha · 1B'));
    await pumpMenu(tester);
    await tester.tap(
      find.widgetWithText(CheckedPopupMenuItem<String>, 'Beta · 3B'),
    );
    await pumpRoom(tester, room.id, frames: 5);

    // The choice lands on the room, which is what the next answer reads.
    expect(
      container.read(groupChatsProvider).snapshot.chats.first.modelId,
      'm-beta',
    );
    expect(pillLabel('Beta · 3B'), findsOneWidget);
  });

  testWidgets('a group room keeps each bot on its own model', (tester) async {
    final notifier = container.read(groupChatsProvider.notifier);
    final room = await tester.runAsync(
      () => notifier.createChat(
        workspaceId: 'ws',
        name: 'Round table',
        memberBotIds: const [BuiltInBots.coderId, BuiltInBots.plannerId],
      ),
    );

    await pumpRoom(tester, room!.id);

    expect(find.text('Message the room (@name for a bot)...'), findsOneWidget);
    expect(find.byType(ComposerModelPill), findsNothing);
  });
}
