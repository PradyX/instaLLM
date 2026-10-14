import 'dart:io';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:installm/features/group_chat/application/group_chat_controller.dart';
import 'package:installm/features/group_chat/data/group_chat_store.dart';
import 'package:installm/features/group_chat/domain/group_chat.dart';

class _FailingGroupStore extends GroupChatStore {
  _FailingGroupStore(super.file);
  bool failWrites = false;
  @override
  bool save(GroupChatsSnapshot snapshot) => !failWrites && super.save(snapshot);
}

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('installm_direct_chat');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  ProviderContainer buildContainer({GroupChatStore? store}) {
    final container = ProviderContainer(
      overrides: [
        groupChatStoreProvider.overrideWith(
          (ref) async =>
              store ??
              GroupChatStore(
                File(p.join(tempDir.path, 'group_chat', 'chats.json')),
              ),
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

  for (final clear in [false, true]) {
    group(clear ? 'clearChat' : 'removeChat', () {
      test(
        'deletes only the selected chat and its messages across restart',
        () async {
          final file = File(p.join(tempDir.path, 'group_chat', 'chats.json'));
          final store = GroupChatStore(file);
          final first = GroupChat.create(
            id: 'first',
            workspaceId: 'ws',
            name: 'First',
            directBotId: 'old-bot',
          );
          final second = GroupChat.create(
            id: 'second',
            workspaceId: 'ws',
            name: 'Second',
          );
          store.save(
            GroupChatsSnapshot(
              chats: [first, second],
              messages: {
                first.id: [
                  GroupMessage.user(chatId: first.id, text: 'Remove this'),
                ],
                second.id: [
                  GroupMessage.user(chatId: second.id, text: 'Keep this'),
                ],
              },
            ),
          );
          final container = buildContainer(store: store);
          final notifier = await loaded(container);
          expect(
            await (clear ? notifier.clearChat : notifier.removeChat)(first.id),
            isTrue,
          );
          final restored = GroupChatStore(file).load();
          expect(
            restored.chats.map((chat) => chat.id),
            clear ? [first.id, second.id] : [second.id],
          );
          if (clear) {
            final kept = container
                .read(groupChatsProvider)
                .snapshot
                .chats
                .first
                .toJson();
            expect(jsonDecode(file.readAsStringSync())['chats'].first, kept);
            expect(
              restored.chats.first
                  .copyWith(updatedAt: first.updatedAt)
                  .toJson(),
              first.toJson(),
            );
          }
          expect(restored.messagesFor(first.id), isEmpty);
          expect(restored.messagesFor(second.id).single.text, 'Keep this');
          expect(
            container
                .read(groupChatsProvider)
                .snapshot
                .chats
                .map((chat) => chat.id),
            clear ? [first.id, second.id] : [second.id],
          );
        },
      );

      test(
        'a failed deletion keeps the chat and messages visible and saved',
        () async {
          final file = File(p.join(tempDir.path, 'group_chat', 'chats.json'));
          final store = _FailingGroupStore(file);
          final chat = GroupChat.create(
            id: 'keep',
            workspaceId: 'ws',
            name: 'Keep',
          );
          store.save(
            GroupChatsSnapshot(
              chats: [chat],
              messages: {
                chat.id: [
                  GroupMessage.user(chatId: chat.id, text: 'Keep this'),
                ],
              },
            ),
          );
          final raw = file.readAsStringSync();
          final container = buildContainer(store: store);
          final notifier = await loaded(container);
          store.failWrites = true;
          expect(
            await (clear ? notifier.clearChat : notifier.removeChat)(chat.id),
            isFalse,
          );
          expect(
            container.read(groupChatsProvider).snapshot.chats.single.id,
            chat.id,
          );
          expect(
            container
                .read(groupChatsProvider)
                .snapshot
                .messagesFor(chat.id)
                .single
                .text,
            'Keep this',
          );
          expect(file.readAsStringSync(), raw);
          expect(container.read(groupChatsProvider).errorMessage, isNotNull);
          store.failWrites = false;
          expect(
            await (clear ? notifier.clearChat : notifier.removeChat)(chat.id),
            isTrue,
          );
        },
      );

      test('a newer room store cannot be deleted or downgraded', () async {
        final file = File(p.join(tempDir.path, 'group_chat', 'chats.json'));
        file.parent.createSync(recursive: true);
        const raw = '{"version":99,"chats":[{"id":"future"}],"messages":{}}';
        file.writeAsStringSync(raw);
        final notifier = await loaded(buildContainer());
        expect(
          await (clear ? notifier.clearChat : notifier.removeChat)('future'),
          isFalse,
        );
        expect(file.readAsStringSync(), raw);
      });
    });
  }

  group('directChatWith', () {
    test('creates one 1:1 room and reuses it', () async {
      final container = buildContainer();
      final notifier = await loaded(container);

      final first = await notifier.directChatWith(
        workspaceId: 'ws',
        botId: 'coder',
      );
      expect(first, isNotNull);
      expect(first!.isDirect, isTrue);
      expect(first.directBotId, 'coder');
      expect(first.memberBotIds, ['coder']);

      final second = await notifier.directChatWith(
        workspaceId: 'ws',
        botId: 'coder',
      );
      expect(second?.id, first.id);
      expect(
        container
            .read(groupChatsProvider)
            .snapshot
            .chats
            .where((chat) => chat.directBotId == 'coder')
            .length,
        1,
      );
    });

    test('keeps bots separate rooms apart', () async {
      final container = buildContainer();
      final notifier = await loaded(container);

      final coder = await notifier.directChatWith(
        workspaceId: 'ws',
        botId: 'coder',
      );
      final planner = await notifier.directChatWith(
        workspaceId: 'ws',
        botId: 'planner',
      );
      expect(coder?.id, isNot(planner?.id));
    });

    test('a task room stays a room', () async {
      final container = buildContainer();
      final notifier = await loaded(container);

      final room = await notifier.createChat(
        workspaceId: 'ws',
        name: 'PL-001 Build it',
        memberBotIds: const ['coder'],
      );
      expect(room?.isDirect, isFalse);
    });
  });

  group('GroupChat direct json', () {
    test('round-trips the direct bot', () {
      final chat = GroupChat.create(
        workspaceId: 'ws',
        name: 'Coder',
        memberBotIds: const ['coder'],
        directBotId: 'coder',
      );
      final decoded = GroupChat.fromJson(chat.toJson())!;
      expect(decoded.directBotId, 'coder');
      expect(decoded.isDirect, isTrue);
    });

    test('documents without the key still read as rooms', () {
      final chat = GroupChat.create(
        workspaceId: 'ws',
        name: 'Room',
        memberBotIds: const ['coder'],
      );
      final json = chat.toJson()..remove('directBotId');
      final decoded = GroupChat.fromJson(json)!;
      expect(decoded.directBotId, isNull);
      expect(decoded.isDirect, isFalse);
    });
  });

  group('roomNeedsUser', () {
    test('badges a room waiting on a pasted reply', () {
      final chat = GroupChat.create(workspaceId: 'ws', name: 'Room');
      final quiet = GroupChatsSnapshot(chats: [chat]);
      expect(roomNeedsUser(quiet, chat.id), isFalse);

      final waiting = GroupChatsSnapshot(
        chats: [chat],
        messages: {
          chat.id: [
            GroupMessage.bot(
              chatId: chat.id,
              botId: 'coder',
              botName: 'Coder',
              text: 'No model yet — paste my reply.',
              pendingPrompt: 'Answer as Coder.',
            ),
          ],
        },
      );
      expect(roomNeedsUser(waiting, chat.id), isTrue);
    });
  });
}
