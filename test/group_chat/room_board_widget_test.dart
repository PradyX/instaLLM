import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:installm/core/navigation/app_router.dart';
import 'package:installm/features/group_chat/application/active_room.dart';
import 'package:installm/features/group_chat/application/group_chat_controller.dart';
import 'package:installm/features/group_chat/data/group_chat_store.dart';
import 'package:installm/features/group_chat/domain/group_chat.dart';
import 'package:installm/features/group_chat/presentation/room_chat_view.dart';
import 'package:installm/features/group_chat/presentation/room_tasks_panel.dart';
import 'package:installm/features/home/presentation/home_page.dart';
import 'package:installm/features/kanban/application/kanban_controller.dart';
import 'package:installm/features/kanban/data/task_repository.dart';
import 'package:installm/features/kanban/domain/task.dart';
import 'package:installm/features/kanban/presentation/kanban_page.dart';
import 'package:installm/features/workspaces/application/workspaces_controller.dart';
import 'package:installm/features/workspaces/data/workspace_store.dart';
import 'package:installm/features/workspaces/domain/workspace.dart';

void main() {
  late Directory directory;
  late ProviderContainer container;
  late GoRouter router;
  late GroupChat room;
  late GroupMessage message;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('room_board_widget');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => directory.path,
        );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          (_) async => null,
        );
    room = GroupChat.create(id: 'dev', workspaceId: 'ws', name: 'Dev');
    message = GroupMessage.user(chatId: room.id, text: 'Track implementation');
    final rooms = GroupChatStore(File('${directory.path}/rooms.json'));
    rooms.save(
      GroupChatsSnapshot(
        chats: [room],
        messages: {
          room.id: [message],
        },
      ),
    );
    final workspaces = WorkspaceStore(
      File('${directory.path}/workspaces.json'),
    );
    workspaces.save(
      WorkspacesSnapshot(
        workspaces: [Workspace.create(id: 'ws', name: 'Workspace')],
        activeWorkspaceId: 'ws',
      ),
    );
    final repository = LocalTaskRepository(
      Directory('${directory.path}/tasks'),
    );
    await repository.save('ws', [
      ProjectTask.create(
        id: 'PL-001',
        workspaceId: 'ws',
        title: 'Existing board task',
      ),
    ]);
    container = ProviderContainer(
      overrides: [
        groupChatStoreProvider.overrideWith((_) async => rooms),
        workspaceStoreProvider.overrideWith((_) async => workspaces),
        taskRepositoryProvider('ws').overrideWith((_) async => repository),
      ],
    );
    container.read(activeRoomIdProvider.notifier).state = room.id;
    router = GoRouter(
      routes: [
        GoRoute(path: AppRoutes.home, builder: (_, _) => const HomePage()),
        GoRoute(path: AppRoutes.kanban, builder: (_, _) => const KanbanPage()),
      ],
    );
  });

  tearDown(() async {
    router.dispose();
    container.dispose();
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
    await directory.delete(recursive: true);
  });

  Future<void> until(WidgetTester tester, bool Function() done) async {
    for (var i = 0; i < 120 && !done(); i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(done(), isTrue);
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> pump(
    WidgetTester tester, {
    bool narrow = false,
    bool settings = false,
  }) async {
    await tester.runAsync(() async {
      container.read(groupChatsProvider);
      container.read(workspacesProvider);
      container.read(kanbanProvider);
      for (var i = 0; i < 100; i++) {
        if (container.read(groupChatsProvider).isReady &&
            container.read(workspacesProvider).isReady &&
            container.read(kanbanProvider).isReady) {
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
    });
    tester.view.physicalSize = narrow
        ? const Size(390, 1000)
        : const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          routerConfig: router,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(narrow ? 2 : 1)),
            child: child!,
          ),
        ),
      ),
    );
    await until(
      tester,
      () =>
          container.read(kanbanProvider).isReady &&
          container.read(groupChatsProvider).isReady &&
          find.byTooltip('Settings').evaluate().isNotEmpty,
    );
    if (settings) {
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
    }
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  testWidgets('a missing bot assignee remains visible and can be cleared', (
    tester,
  ) async {
    await pump(tester);
    await tester.runAsync(
      () => container
          .read(kanbanProvider.notifier)
          .assignTask('PL-001', 'removed-bot'),
    );
    await tester.tap(find.byTooltip('Open board'));
    await until(tester, () => find.byType(KanbanPage).evaluate().isNotEmpty);
    await tester.tap(find.text('Existing board task'));
    await tester.pumpAndSettle();
    expect(find.text('Unavailable bot'), findsOneWidget);
    expect(
      container.read(kanbanProvider).byId['PL-001']!.assignedBotId,
      'removed-bot',
    );
    await tester.tap(find.byType(DropdownButtonFormField<String?>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Unassigned').last);
    await until(
      tester,
      () =>
          container.read(kanbanProvider).byId['PL-001']!.assignedBotId == null,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'link an existing task, change status from the room, then Board reopens that same room',
    (tester) async {
      await pump(tester);
      await tester.tap(find.byTooltip('Link task'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Existing board task'));
      await until(
        tester,
        () =>
            container
                .read(kanbanProvider)
                .byId['PL-001']
                ?.relatedRoomIds
                .contains('dev') ==
            true,
      );
      await tester.tap(find.byKey(const ValueKey('room-task-status-PL-001')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('Done').last);
      await until(
        tester,
        () =>
            container.read(kanbanProvider).byId['PL-001']?.status ==
            TaskStatus.done,
      );
      expect(find.text('Done'), findsOneWidget);
      await tester.tap(find.byTooltip('Open board'));
      await until(tester, () => find.byType(KanbanPage).evaluate().isNotEmpty);
      // Done is the last column; scroll it into view using the board's horizontal list.
      await tester.scrollUntilVisible(
        find.text('Existing board task'),
        600,
        scrollable: find
            .byWidgetPredicate(
              (widget) =>
                  widget is Scrollable &&
                  widget.axisDirection == AxisDirection.right,
            )
            .last,
      );
      await tester.tap(find.text('Existing board task'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Linked rooms'), findsOneWidget);
      await tester.ensureVisible(find.text('Open room'));
      await tester.pump();
      await tester.tap(find.text('Open room'));
      await until(tester, () => find.byType(HomePage).evaluate().isNotEmpty);
      expect(container.read(activeRoomIdProvider), 'dev');
      expect(container.read(groupChatsProvider).snapshot.chats, hasLength(1));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'creating a task from a message immediately adds its durable room link',
    (tester) async {
      await pump(tester);
      await tester.tap(find.text('Create task'));
      await until(
        tester,
        () => container.read(kanbanProvider).tasks.length == 2,
      );
      final created = container.read(kanbanProvider).tasks.last;
      expect(created.relatedRoomIds, ['dev']);
      expect(created.relatedMessages, [message.id]);
      expect(find.text('PL-002 · Track implementation'), findsOneWidget);
    },
  );

  testWidgets('room task controls fit a narrow window at double text size', (
    tester,
  ) async {
    await pump(tester, narrow: true);
    await tester.tap(find.byTooltip('Link task'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Existing board task'));
    await until(
      tester,
      () =>
          container
              .read(kanbanProvider)
              .byId['PL-001']
              ?.relatedRoomIds
              .contains('dev') ==
          true,
    );
    expect(find.byTooltip('Change task status'), findsOneWidget);
    final error = tester.takeException();
    expect(error, isNull);
  });

  testWidgets(
    'direct bot tasks live in settings and still link and open the board',
    (tester) async {
      room = room.copyWith(directBotId: 'former', memberBotIds: ['former']);
      GroupChatStore(File('${directory.path}/rooms.json')).save(
        GroupChatsSnapshot(
          chats: [room],
          messages: {
            room.id: [message],
          },
        ),
      );
      await pump(tester);
      expect(find.byType(RoomTasksPanel), findsNothing);
      expect(
        find
            .byTooltip('New chat')
            .evaluate()
            .where(
              (element) =>
                  element.findAncestorWidgetOfExactType<AppBar>() != null,
            ),
        isEmpty,
      );
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(RoomSettingsSheet),
          matching: find.byType(RoomTasksPanel),
        ),
        findsOneWidget,
      );
      await tester.tap(find.byTooltip('Link task'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Existing board task'));
      await until(
        tester,
        () => container
            .read(kanbanProvider)
            .byId['PL-001']!
            .relatedRoomIds
            .contains(room.id),
      );
      expect(find.text('Open board'), findsNothing);
      await tester.tap(find.text('Linked tasks'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open board'));
      await until(tester, () => find.byType(KanbanPage).evaluate().isNotEmpty);
      expect(find.byType(RoomSettingsSheet), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
