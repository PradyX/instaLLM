import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pocket_llm/core/widgets/composer_model_pill.dart';
import 'package:pocket_llm/features/bots/domain/built_in_bots.dart';
import 'package:pocket_llm/features/group_chat/application/group_chat_controller.dart';
import 'package:pocket_llm/features/group_chat/data/group_chat_store.dart';
import 'package:pocket_llm/features/group_chat/domain/group_chat.dart';
import 'package:pocket_llm/features/group_chat/presentation/group_chats_page.dart';
import 'package:pocket_llm/features/model_selection/domain/llm_model.dart';
import 'package:pocket_llm/features/model_selection/presentation/chat_models_provider.dart';

/// Installed chat models, none of which declares tool support: a room answers
/// on any installed model, so the list must not depend on that capability.
const _small = LlmModel(
  id: 'm-small',
  name: 'Small',
  parameterSize: '360M',
  description: 'test model',
  isDownloaded: true,
);

const _picked = LlmModel(
  id: 'm-picked',
  name: 'Picked',
  parameterSize: '1.1B',
  description: 'test model',
  isDownloaded: true,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late ProviderContainer container;

  /// [installed] and [selected] stand in for the app's model catalog: the room
  /// reads the same two providers home's composer does.
  ProviderContainer buildContainer({
    required List<LlmModel> installed,
    required LlmModel? selected,
  }) {
    final container = ProviderContainer(
      overrides: [
        groupChatStoreProvider.overrideWith(
          (ref) async => GroupChatStore(
            File(p.join(tempDir.path, 'group_chat', 'chats.json')),
          ),
        ),
        chatModelsProvider.overrideWithValue(installed),
        selectedChatModelProvider.overrideWithValue(selected),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  /// Waits for the store and opens one room. Real waits and real file work
  /// belong in [WidgetTester.runAsync]: a test body's own zone never fires the
  /// timers the app's loading path schedules.
  Future<GroupChat> openRoom(
    WidgetTester tester, {
    String name = 'Coder',
    List<String> memberBotIds = const [BuiltInBots.coderId],
    String? directBotId = BuiltInBots.coderId,
  }) async {
    final room = await tester.runAsync(() async {
      final notifier = container.read(groupChatsProvider.notifier);
      for (var attempt = 0; attempt < 50; attempt++) {
        if (container.read(groupChatsProvider).isReady) break;
        await Future<void>.delayed(Duration.zero);
      }
      expect(container.read(groupChatsProvider).isReady, isTrue);
      return notifier.createChat(
        workspaceId: 'ws',
        name: name,
        memberBotIds: memberBotIds,
        directBotId: directBotId,
      );
    });
    return room!;
  }

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

  /// What the room itself stored as its model, read from the loaded state.
  String? roomModel() =>
      container.read(groupChatsProvider).snapshot.chats.first.modelId;

  testWidgets('a bot room opens on the model the app is set to', (
    tester,
  ) async {
    container = buildContainer(
      installed: const [_small, _picked],
      selected: _picked,
    );
    final room = await openRoom(tester);

    await pumpRoom(tester, room.id);

    // Same model as home, and a model with no tool support still gets a pill.
    expect(find.byType(ComposerModelPill), findsOneWidget);
    expect(pillLabel('Picked · 1.1B'), findsOneWidget);
    expect(roomModel(), isNull);
  });

  testWidgets(
    'picking one stores it on the room, and handing it back clears it',
    (tester) async {
      container = buildContainer(
        installed: const [_small, _picked],
        selected: _picked,
      );
      final room = await openRoom(tester);

      await pumpRoom(tester, room.id);
      await tester.tap(pillLabel('Picked · 1.1B'));
      await pumpMenu(tester);
      await tester.tap(
        find.widgetWithText(CheckedPopupMenuItem<String>, 'Small · 360M'),
      );
      await pumpRoom(tester, room.id, frames: 5);

      expect(roomModel(), 'm-small');
      expect(pillLabel('Small · 360M'), findsOneWidget);

      // The bot editor's "Conversation model", in the composer: back to the
      // app's own model instead of a choice this room keeps forever.
      await tester.tap(pillLabel('Small · 360M'));
      await pumpMenu(tester);
      await tester.tap(
        find.widgetWithText(CheckedPopupMenuItem<String>, 'Conversation model'),
      );
      await pumpRoom(tester, room.id, frames: 5);

      expect(roomModel(), isNull);
      expect(pillLabel('Picked · 1.1B'), findsOneWidget);
    },
  );

  testWidgets('with nothing installed the room asks for a model', (
    tester,
  ) async {
    container = buildContainer(installed: const [], selected: null);
    final room = await openRoom(tester);

    await pumpRoom(tester, room.id);

    expect(find.text('Get a model'), findsOneWidget);
  });

  testWidgets('a group room keeps each bot on its own model', (tester) async {
    container = buildContainer(
      installed: const [_small, _picked],
      selected: _picked,
    );
    final room = await openRoom(
      tester,
      name: 'Round table',
      memberBotIds: const [BuiltInBots.coderId, BuiltInBots.plannerId],
      directBotId: null,
    );

    await pumpRoom(tester, room.id);

    expect(find.text('Message the room (@name for a bot)...'), findsOneWidget);
    expect(find.byType(ComposerModelPill), findsNothing);
  });
}
