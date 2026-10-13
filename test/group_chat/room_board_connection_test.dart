import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:installm/features/bots/application/bots_controller.dart';
import 'package:installm/features/bots/domain/built_in_bots.dart';
import 'package:installm/features/bots/domain/bot.dart';
import 'package:installm/features/bots/data/bot_store.dart';
import 'package:installm/features/group_chat/application/group_chat_controller.dart';
import 'package:installm/features/group_chat/application/room_board_service.dart';
import 'package:installm/features/group_chat/data/group_chat_store.dart';
import 'package:installm/features/group_chat/domain/group_chat.dart';
import 'package:installm/features/kanban/application/board_task_operations.dart';
import 'package:installm/features/kanban/application/kanban_controller.dart';
import 'package:installm/features/kanban/data/task_repository.dart';
import 'package:installm/features/kanban/domain/task.dart';
import 'package:installm/features/home/presentation/home_controller.dart';
import 'package:installm/features/model_selection/presentation/chat_models_provider.dart';

final _workspace = StateProvider((_) => 'ws');

class _DelayedRepository implements TaskRepository {
  final firstLoad = Completer<List<ProjectTask>>();
  @override
  Future<List<ProjectTask>> load(String workspaceId) => firstLoad.future;
  @override
  Future<void> save(String workspaceId, List<ProjectTask> tasks) async {}
  @override
  Future<int?> nextNumber(String workspaceId) async => 1;
}

class _FailingRepository implements TaskRepository {
  _FailingRepository(this.delegate);
  final TaskRepository delegate;
  var failWrites = true;
  @override
  Future<List<ProjectTask>> load(String workspaceId) =>
      delegate.load(workspaceId);
  @override
  Future<int?> nextNumber(String workspaceId) =>
      delegate.nextNumber(workspaceId);
  @override
  Future<void> save(String workspaceId, List<ProjectTask> tasks) async {
    if (failWrites) throw const FileSystemException('Disk is unavailable');
    await delegate.save(workspaceId, tasks);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late LocalTaskRepository repository;
  late GroupChatStore rooms;
  late ProviderContainer container;

  ProviderContainer makeContainer({TaskRepository? boardRepository}) =>
      ProviderContainer(
        overrides: [
          selectedContextWindowProvider.overrideWithValue(null),
          chatModelsProvider.overrideWithValue(const []),
          selectedChatModelProvider.overrideWithValue(null),
          activeWorkspaceIdProvider.overrideWith(
            (ref) => ref.watch(_workspace),
          ),
          taskRepositoryProvider(
            'ws',
          ).overrideWith((_) async => boardRepository ?? repository),
          taskRepositoryProvider('other').overrideWith((_) async => repository),
          groupChatStoreProvider.overrideWith((_) async => rooms),
        ],
      );

  Future<void> waitReady(ProviderContainer target) async {
    target.read(groupChatsProvider);
    target.read(botsProvider);
    target.read(kanbanProvider);
    for (var i = 0; i < 100; i++) {
      if (target.read(groupChatsProvider).isReady &&
          target.read(botsProvider).isReady &&
          target.read(kanbanProvider).isReady) {
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    fail('Providers did not load');
  }

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('room_board');
    BotStore(File('${directory.path}/bots/bots.json')).save(
      BotsSnapshot(
        customBots: [
          for (final template in BuiltInBots.all())
            Bot.fromJson(template.toJson())!,
        ],
      ),
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => directory.path,
        );
    repository = LocalTaskRepository(Directory('${directory.path}/tasks'));
    rooms = GroupChatStore(File('${directory.path}/rooms.json'));
    container = makeContainer();
    await waitReady(container);
  });
  tearDown(() async {
    container.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    await directory.delete(recursive: true);
  });

  Future<GroupChat> room({
    String workspaceId = 'ws',
    String name = 'Dev',
  }) async => (await container
      .read(groupChatsProvider.notifier)
      .createChat(workspaceId: workspaceId, name: name))!;

  test(
    'message task links survive capped history and restart, and Board reopens that room',
    () async {
      final chat = await room();
      final messages = List.generate(
        310,
        (i) => GroupMessage.user(chatId: chat.id, text: 'Message $i'),
      );
      final task = await container
          .read(roomBoardServiceProvider)
          .createFromMessage(chat, messages.first);
      expect(task.relatedMessages, [messages.first.id]);
      expect(task.relatedRoomIds, [chat.id]);
      rooms.save(
        GroupChatsSnapshot(chats: [chat], messages: {chat.id: messages}),
      );
      container.dispose();
      container = makeContainer();
      await waitReady(container);
      expect(
        container.read(groupChatsProvider).snapshot.messagesFor(chat.id),
        hasLength(300),
      );
      final reopened = await container
          .read(groupChatsProvider.notifier)
          .discussTaskInRoom(task);
      expect(reopened, chat.id);
      expect(container.read(groupChatsProvider).snapshot.chats, hasLength(1));
      expect(container.read(kanbanProvider).byId[task.id]!.relatedRoomIds, [
        chat.id,
      ]);
    },
  );

  test(
    'Board creates one saved discussion for concurrent clicks and reuses it without another inference turn',
    () async {
      final task = await container
          .read(kanbanProvider.notifier)
          .createTask(title: 'Ship this');
      expect(
        task,
        isNotNull,
        reason: container.read(kanbanProvider).errorMessage,
      );
      await container
          .read(kanbanProvider.notifier)
          .assignTask(task!.id, BuiltInBots.coderId);
      final notifier = container.read(groupChatsProvider.notifier);
      final opened = await Future.wait([
        notifier.discussTaskInRoom(task),
        notifier.discussTaskInRoom(task),
      ]);
      expect(opened.first, isNotNull);
      expect(opened.last, opened.first);
      final chat = container.read(groupChatsProvider).snapshot.chats.single;
      expect(chat.memberBotIds, [BuiltInBots.coderId]);
      expect(
        container.read(groupChatsProvider).snapshot.messagesFor(chat.id),
        hasLength(1),
      );
      expect(container.read(groupChatsProvider).runningChatIds, isEmpty);
      expect(
        await notifier.discussTaskInRoom(task),
        chat.id,
      ); // stale task instance
      expect(
        container.read(groupChatsProvider).snapshot.messagesFor(chat.id),
        hasLength(1),
      );
      await notifier.removeChat(chat.id);
      final replacement = await notifier.discussTaskInRoom(task);
      expect(replacement, isNot(chat.id));
      expect(
        (await repository.load('ws')).single.relatedRoomIds,
        contains(replacement),
      );
    },
  );

  test(
    'legacy message links are promoted instead of creating a duplicate room',
    () async {
      final chat = await room();
      final message = GroupMessage.user(chatId: chat.id, text: 'Legacy work');
      rooms.save(
        GroupChatsSnapshot(
          chats: [chat],
          messages: {
            chat.id: [message],
          },
        ),
      );
      container.dispose();
      final task = await createBoardTask(
        repository: repository,
        workspaceId: 'ws',
        title: 'Legacy',
        relatedMessages: [message.id],
      );
      container = makeContainer();
      await waitReady(container);
      expect(
        await container
            .read(groupChatsProvider.notifier)
            .discussTaskInRoom(task),
        chat.id,
      );
      expect((await repository.load('ws')).single.relatedRoomIds, [chat.id]);
    },
  );

  test(
    'room status and Board comments share latest saved tasks; concurrent creates retain unique ids',
    () async {
      final chat = await room();
      final task = await container
          .read(kanbanProvider.notifier)
          .createTask(title: 'Shared work');
      expect(
        task,
        isNotNull,
        reason: container.read(kanbanProvider).errorMessage,
      );
      final service = container.read(roomBoardServiceProvider);
      await service.linkTask(chat, task!.id);
      await Future.wait([
        service.moveTask(chat, task.id, TaskStatus.done),
        container
            .read(kanbanProvider.notifier)
            .addComment(task.id, 'user', 'Keep this comment'),
      ]);
      final saved = (await repository.load('ws')).single;
      expect(saved.status, TaskStatus.done);
      expect(saved.relatedRoomIds, [chat.id]);
      expect(
        saved.comments.map((comment) => comment.text),
        contains('Keep this comment'),
      );
      await container
          .read(kanbanProvider.notifier)
          .moveTask(task.id, TaskStatus.review);
      expect((await repository.load('ws')).single.completedAt, isNull);
      final created = await Future.wait([
        createBoardTask(
          repository: repository,
          workspaceId: 'ws',
          title: 'First',
        ),
        createBoardTask(
          repository: repository,
          workspaceId: 'ws',
          title: 'Second',
        ),
      ]);
      expect(created.map((task) => task.id).toSet(), hasLength(2));
      expect(await repository.load('ws'), hasLength(3));
    },
  );

  test(
    'a room in another workspace updates its own task, preserving the active Board',
    () async {
      final active = await container
          .read(kanbanProvider.notifier)
          .createTask(title: 'Active work');
      expect(
        active,
        isNotNull,
        reason: container.read(kanbanProvider).errorMessage,
      );
      await container
          .read(kanbanProvider.notifier)
          .assignTask(active!.id, BuiltInBots.coderId);
      final other = await createBoardTask(
        repository: repository,
        workspaceId: 'other',
        title: 'Other work',
      );
      final chat = await room(workspaceId: 'other');
      await container.read(roomBoardServiceProvider).linkTask(chat, other.id);
      await container
          .read(roomBoardServiceProvider)
          .moveTask(chat, other.id, TaskStatus.done);
      expect(
        container.read(kanbanProvider).byId[active.id]!.status,
        TaskStatus.todo,
      );
      expect((await repository.load('other')).single.status, TaskStatus.done);
      final promptRoom = await container
          .read(groupChatsProvider.notifier)
          .createChat(
            workspaceId: 'other',
            name: 'Other bot',
            memberBotIds: [BuiltInBots.coderId],
            directBotId: BuiltInBots.coderId,
          );
      await container
          .read(roomBoardServiceProvider)
          .linkTask(promptRoom!, other.id);
      await container
          .read(groupChatsProvider.notifier)
          .sendUserMessage(promptRoom.id, 'Hello');
      final prompt = container
          .read(groupChatsProvider)
          .snapshot
          .messagesFor(promptRoom.id)
          .last
          .pendingPrompt!;
      expect(prompt, isNot(contains('Active work')));
      expect(prompt, contains('PL-001 [done] Other work'));
    },
  );

  test(
    'failed status writes keep the saved Board unchanged and the next attempt can succeed',
    () async {
      final chat = await room();
      final task = await container
          .read(roomBoardServiceProvider)
          .createFromMessage(
            chat,
            GroupMessage.user(chatId: chat.id, text: 'Save safely'),
          );
      container.dispose();
      final failing = _FailingRepository(repository);
      container = makeContainer(boardRepository: failing);
      await waitReady(container);
      await expectLater(
        container
            .read(roomBoardServiceProvider)
            .moveTask(chat, task.id, TaskStatus.done),
        throwsA(isA<FileSystemException>()),
      );
      expect(
        container.read(kanbanProvider).byId[task.id]!.status,
        TaskStatus.todo,
      );
      expect((await repository.load('ws')).single.status, TaskStatus.todo);
      failing.failWrites = false;
      await container
          .read(roomBoardServiceProvider)
          .moveTask(chat, task.id, TaskStatus.done);
      expect(
        container.read(kanbanProvider).byId[task.id]!.status,
        TaskStatus.done,
      );
    },
  );

  test(
    'a late load from the old workspace cannot replace the new Board',
    () async {
      final slow = _DelayedRepository();
      final second = await createBoardTask(
        repository: repository,
        workspaceId: 'other',
        title: 'New workspace',
      );
      final target = ProviderContainer(
        overrides: [
          activeWorkspaceIdProvider.overrideWith(
            (ref) => ref.watch(_workspace),
          ),
          taskRepositoryProvider('ws').overrideWith((_) async => slow),
          taskRepositoryProvider('other').overrideWith((_) async => repository),
        ],
      );
      addTearDown(target.dispose);
      target.read(kanbanProvider);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      target.read(_workspace.notifier).state = 'other';
      for (var i = 0; i < 50 && !target.read(kanbanProvider).isReady; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      slow.firstLoad.complete([
        ProjectTask.create(
          id: 'PL-001',
          workspaceId: 'ws',
          title: 'Old workspace',
        ),
      ]);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(target.read(kanbanProvider).tasks.single.title, second.title);
    },
  );
}
