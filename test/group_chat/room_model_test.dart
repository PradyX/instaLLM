import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pocket_llm/features/bots/domain/bot.dart';
import 'package:pocket_llm/features/group_chat/application/group_chat_controller.dart';
import 'package:pocket_llm/features/group_chat/data/group_chat_store.dart';
import 'package:pocket_llm/features/group_chat/domain/group_chat.dart';
import 'package:pocket_llm/features/model_selection/domain/llm_model.dart';

/// An installed, tool-capable model, as `agentRunnableModels` would report
/// it to a room.
LlmModel _model(String id) => LlmModel(
  id: id,
  name: 'Model $id',
  parameterSize: '1B',
  description: 'test model',
  isDownloaded: true,
);

Bot _bot({String id = 'bot-1', String? modelId}) =>
    Bot.create(id: id, name: 'Bot', modelId: modelId);

GroupChat _room({String? modelId, String? directBotId = 'bot-1'}) =>
    GroupChat.create(
      workspaceId: 'ws',
      name: 'Room',
      directBotId: directBotId,
      modelId: modelId,
    );

void main() {
  group('roomAnswerModel', () {
    test("the room's own model wins over the bot's preference", () {
      final model = roomAnswerModel(
        chat: _room(modelId: 'm-room'),
        bot: _bot(modelId: 'm-bot'),
        runnable: [_model('m-bot'), _model('m-room')],
      );

      expect(model?.id, 'm-room');
    });

    test("falls back to the bot's preferred model", () {
      final model = roomAnswerModel(
        chat: _room(),
        bot: _bot(modelId: 'm-bot'),
        runnable: [_model('m-other'), _model('m-bot')],
      );

      expect(model?.id, 'm-bot');
    });

    test('a model that is no longer installed falls through', () {
      // The room names a model the user has since deleted: the bot's own
      // preference still answers rather than the room going silent.
      final model = roomAnswerModel(
        chat: _room(modelId: 'm-gone'),
        bot: _bot(modelId: 'm-bot'),
        runnable: [_model('m-bot')],
      );

      expect(model?.id, 'm-bot');

      final neither = roomAnswerModel(
        chat: _room(modelId: 'm-gone'),
        bot: _bot(modelId: 'm-also-gone'),
        runnable: [_model('m-first'), _model('m-second')],
      );

      expect(neither?.id, 'm-first');
    });

    test('with nothing runnable a room cannot answer', () {
      final model = roomAnswerModel(
        chat: _room(modelId: 'm-room'),
        bot: _bot(modelId: 'm-bot'),
        runnable: const [],
      );

      expect(model, isNull);
    });
  });

  group('a room remembers its model', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('pocketllm_room_model');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    File storeFile() => File(p.join(tempDir.path, 'group_chat', 'chats.json'));

    ProviderContainer buildContainer() {
      final container = ProviderContainer(
        overrides: [
          groupChatStoreProvider.overrideWith(
            (ref) async => GroupChatStore(storeFile()),
          ),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    Future<GroupChatsNotifier> loaded(ProviderContainer container) async {
      final notifier = container.read(groupChatsProvider.notifier);
      for (var attempt = 0; attempt < 50; attempt++) {
        if (container.read(groupChatsProvider).isReady) break;
        await Future<void>.delayed(Duration.zero);
      }
      expect(container.read(groupChatsProvider).isReady, isTrue);
      return notifier;
    }

    GroupChat firstChat(ProviderContainer container) =>
        container.read(groupChatsProvider).snapshot.chats.first;

    test('switching it survives a restart', () async {
      final container = buildContainer();
      final notifier = await loaded(container);
      final room = await notifier.createChat(
        workspaceId: 'ws',
        name: 'Coder',
        memberBotIds: const ['bot-1'],
        directBotId: 'bot-1',
      );

      await notifier.updateChat(room!.copyWith(modelId: 'm-picked'));

      // A second container reads the file again, as the next launch would.
      final reopened = buildContainer();
      await loaded(reopened);
      expect(firstChat(reopened).modelId, 'm-picked');
    });

    test('clearing it falls back to the bot again', () async {
      final container = buildContainer();
      final notifier = await loaded(container);
      final room = await notifier.createChat(
        workspaceId: 'ws',
        name: 'Coder',
        memberBotIds: const ['bot-1'],
        directBotId: 'bot-1',
      );
      await notifier.updateChat(room!.copyWith(modelId: 'm-picked'));

      await notifier.updateChat(
        notifier.state.snapshot.chats.first.copyWith(clearModel: true),
      );

      expect(firstChat(container).modelId, isNull);
    });

    test(
      'a document written before rooms had a model reads as no choice',
      () async {
        // Version 1 shipped without the key: the room keeps its messages and
        // simply follows the bot until the user picks something.
        await storeFile().parent.create(recursive: true);
        await storeFile().writeAsString('''
{
  "version": 1,
  "chats": [
    {
      "id": "groupchat-1",
      "workspaceId": "ws",
      "name": "Coder",
      "memberBotIds": ["bot-1"],
      "directBotId": "bot-1",
      "mode": "manual",
      "maxRounds": 10,
      "createdAt": "2026-10-12T12:00:00.000Z",
      "updatedAt": "2026-10-12T12:00:00.000Z"
    }
  ],
  "messages": {}
}
''');

        final container = buildContainer();
        await loaded(container);

        expect(firstChat(container).modelId, isNull);
        expect(firstChat(container).name, 'Coder');
      },
    );

    test('the room keeps every other setting it had', () {
      final room = _room(
        modelId: 'm-picked',
      ).copyWith(name: 'Renamed', maxRounds: 4);

      expect(room.modelId, 'm-picked');
      expect(room.name, 'Renamed');
      expect(room.maxRounds, 4);
      expect(room.directBotId, 'bot-1');
      expect(GroupChat.fromJson(room.toJson())?.modelId, 'm-picked');
    });
  });
}
