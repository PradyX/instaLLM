import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:installm/core/navigation/app_router.dart';
import 'package:installm/core/navigation/app_shell.dart';
import 'package:installm/core/navigation/navigation_panel_widgets.dart';
import 'package:installm/core/widgets/name_prompt_dialog.dart';
import 'package:installm/features/bots/domain/built_in_bots.dart';
import 'package:installm/features/bots/domain/bot.dart';
import 'package:installm/features/bots/data/bot_store.dart';
import 'package:installm/features/bots/application/bots_controller.dart';
import 'package:installm/features/bots/presentation/bot_editor_page.dart';
import 'package:installm/features/bots/presentation/create_bot_dialog.dart';
import 'package:installm/features/conversations/data/conversation_store.dart';
import 'package:installm/features/conversations/domain/conversation.dart';
import 'package:installm/features/conversations/presentation/conversation_controller.dart';
import 'package:installm/features/group_chat/application/active_room.dart';
import 'package:installm/features/group_chat/application/group_chat_controller.dart';
import 'package:installm/features/group_chat/data/group_chat_store.dart';
import 'package:installm/features/group_chat/domain/group_chat.dart';
import 'package:installm/features/group_chat/presentation/room_chat_view.dart';
import 'package:installm/features/group_chat/presentation/room_mention_composer.dart';
import 'package:installm/features/home/presentation/home_page.dart';
import 'package:installm/features/kanban/presentation/kanban_page.dart';
import 'package:installm/features/kanban/application/kanban_controller.dart';
import 'package:installm/features/settings/presentation/settings_page.dart';
import 'package:installm/features/workspaces/data/workspace_store.dart';
import 'package:installm/features/workspaces/domain/workspace.dart';
import 'package:installm/features/workspaces/application/workspaces_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late ConversationStore conversations;
  late ProviderContainer container;
  late GoRouter router;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('responsive_navigation');
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
    conversations = ConversationStore(
      rootDirectory: Directory('${directory.path}/conversations'),
    );
    BotStore(File('${directory.path}/bots/bots.json')).save(
      BotsSnapshot(
        customBots: [
          for (final template in BuiltInBots.all())
            Bot.fromJson(template.toJson())!,
        ],
      ),
    );
    for (final (id, title) in [('a', 'Chat A'), ('b', 'Chat B')]) {
      await conversations.createConversation(
        Conversation.create(id: id, title: title),
      );
    }
    WorkspaceStore(File('${directory.path}/workspaces/workspaces.json')).save(
      WorkspacesSnapshot(
        workspaces: [Workspace.create(id: 'ws', name: 'My workspace')],
        activeWorkspaceId: 'ws',
      ),
    );
    GroupChatStore(File('${directory.path}/group_chat/chats.json')).save(
      GroupChatsSnapshot(
        chats: [
          GroupChat.create(
            id: 'dev',
            workspaceId: 'ws',
            name: 'Dev',
            memberBotIds: [BuiltInBots.researcherId, BuiltInBots.plannerId],
          ),
        ],
      ),
    );
    container = ProviderContainer(
      overrides: [conversationStoreProvider.overrideWithValue(conversations)],
    );
    router = GoRouter(
      routes: [
        GoRoute(path: AppRoutes.home, builder: (_, _) => const HomePage()),
        GoRoute(path: AppRoutes.kanban, builder: (_, _) => const KanbanPage()),
        GoRoute(
          path: AppRoutes.settings,
          builder: (_, _) => const SettingsPage(),
        ),
        for (final route in [
          AppRoutes.conversations,
          AppRoutes.modelSelection,
          AppRoutes.workspaces,
          AppRoutes.benchmark,
          AppRoutes.about,
        ])
          GoRoute(
            path: route,
            builder: (_, _) =>
                Scaffold(appBar: AppBar(title: Text('Destination $route'))),
          ),
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

  Future<void> pumpUntil(WidgetTester tester, bool Function() done) async {
    for (var attempt = 0; attempt < 100 && !done(); attempt++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(done(), isTrue);
  }

  Future<void> pumpHome(
    WidgetTester tester, {
    double width = 390,
    double scale = 1,
  }) async {
    tester.view.physicalSize = Size(width, 1100);
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
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
        ),
      ),
    );
    await pumpUntil(
      tester,
      () =>
          container.read(conversationControllerProvider).isInitialized &&
          container.read(groupChatsProvider).isReady &&
          container.read(workspacesProvider).isReady,
    );
    await tester.pump(const Duration(milliseconds: 200));
  }

  ScaffoldState homeScaffold(WidgetTester tester) =>
      tester.state<ScaffoldState>(
        find
            .descendant(
              of: find.byType(HomePage),
              matching: find.byType(Scaffold),
            )
            .first,
      );
  Finder panelText(String text) => find.descendant(
    of: find.byType(AppNavigationPanel),
    matching: find.byWidgetPredicate(
      (widget) => widget is Text && widget.data == text,
    ),
  );
  Finder searchField() => find.descendant(
    of: find.byType(AppNavigationPanel),
    matching: find.byType(TextField),
  );
  Finder newChatButton() => find.descendant(
    of: find.byType(AppNavigationPanel),
    matching: find.byTooltip('New chat'),
  );

  Future<void> openDrawer(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Menu'));
    await tester.pumpAndSettle();
    expect(find.byType(AppNavigationPanel), findsOneWidget);
  }

  Future<void> tapPanel(WidgetTester tester, String text) async {
    final target = panelText(text);
    await tester.ensureVisible(target);
    await tester.tap(target);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('an empty registry offers creation without listing templates', (
    tester,
  ) async {
    BotStore(File('${directory.path}/bots/bots.json')).save(BotsSnapshot.empty);
    await pumpHome(tester, width: 1400);
    await pumpUntil(tester, () => container.read(botsProvider).isReady);
    expect(panelText('Researcher'), findsNothing);
    expect(panelText('Planner'), findsNothing);
    expect(panelText('Coder'), findsNothing);
    expect(panelText('Tester'), findsNothing);
    expect(panelText('No bots yet. Use + to create your own.'), findsOneWidget);
    expect(find.byTooltip('New bot'), findsOneWidget);
  });

  testWidgets(
    'creating from a template is optional and keeps the chosen name',
    (tester) async {
      BotStore(
        File('${directory.path}/bots/bots.json'),
      ).save(BotsSnapshot.empty);
      await pumpHome(tester);
      await openDrawer(tester);
      await tester.ensureVisible(find.byTooltip('New bot'));
      await tester.tap(find.byTooltip('New bot'));
      await tester.pumpAndSettle();
      expect(find.text('Blank bot'), findsOneWidget);
      await tester.enterText(
        find.descendant(
          of: find.byType(CreateBotDialog),
          matching: find.byType(TextField),
        ),
        'My planning bot',
      );
      await tester.tap(find.byType(DropdownButtonFormField<String?>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Planner').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Create'));
      await pumpUntil(
        tester,
        () => find.byType(BotEditorPage).evaluate().isNotEmpty,
      );
      final bot = container.read(botsProvider).bots.single;
      expect(bot.name, 'My planning bot');
      expect(bot.id, isNot(BuiltInBots.plannerId));
      expect(bot.isBuiltIn, isFalse);
      expect(bot.soul, BuiltInBots.byId(BuiltInBots.plannerId)!.soul);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('old default-bot chats stay readable without activating a bot', (
    tester,
  ) async {
    BotStore(File('${directory.path}/bots/bots.json')).save(BotsSnapshot.empty);
    final store = GroupChatStore(
      File('${directory.path}/group_chat/chats.json'),
    );
    final chat = GroupChat.create(
      id: 'old',
      workspaceId: 'ws',
      name: 'Earlier Coder',
      directBotId: BuiltInBots.coderId,
      memberBotIds: [BuiltInBots.coderId],
    );
    final message = GroupMessage.bot(
      chatId: chat.id,
      botId: BuiltInBots.coderId,
      botName: 'Coder then',
      text: 'Keep this history.',
    );
    final emptyChat = GroupChat.create(
      id: 'empty-old',
      workspaceId: 'ws',
      name: 'Empty old chat',
      directBotId: BuiltInBots.testerId,
      memberBotIds: [BuiltInBots.testerId],
    );
    store.save(
      store
          .load()
          .upsertChat(chat)
          .upsertChat(emptyChat)
          .appendMessage(message),
    );
    final raw = File(store.filePath).readAsStringSync();
    await pumpHome(tester, width: 1400);
    await pumpUntil(tester, () => container.read(botsProvider).isReady);
    expect(find.byKey(ValueKey('bot-${BuiltInBots.coderId}')), findsNothing);
    expect(find.byKey(const ValueKey('room-old')), findsOneWidget);
    await tapPanel(tester, 'Earlier Coder');
    expect(find.text('Keep this history.'), findsOneWidget);
    expect(
      find.text('This bot is no longer active. Its chat history is preserved.'),
      findsOneWidget,
    );
    expect(find.byType(RoomMentionComposer), findsNothing);
    await tester.runAsync(
      () => container
          .read(groupChatsProvider.notifier)
          .sendUserMessage(chat.id, 'Do not append'),
    );
    expect(File(store.filePath).readAsStringSync(), raw);
    await tapPanel(tester, 'Empty old chat');
    expect(find.text('No messages in this saved chat.'), findsOneWidget);
    expect(find.textContaining('answers directly'), findsNothing);
    expect(find.byType(RoomMentionComposer), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'group history cannot record a pending answer from a removed bot',
    (tester) async {
      BotStore(
        File('${directory.path}/bots/bots.json'),
      ).save(BotsSnapshot.empty);
      final store = GroupChatStore(
        File('${directory.path}/group_chat/chats.json'),
      );
      final pending = GroupMessage.bot(
        chatId: 'dev',
        botId: BuiltInBots.researcherId,
        botName: 'Researcher',
        text: 'Earlier pending turn',
        pendingPrompt: 'Stored prompt',
      );
      store.save(store.load().appendMessage(pending));
      final raw = File(store.filePath).readAsStringSync();
      await pumpHome(tester, width: 1400);
      await tapPanel(tester, 'Dev');
      expect(find.text('Earlier pending turn'), findsOneWidget);
      expect(find.text('Record reply'), findsNothing);
      await tester.runAsync(
        () => container
            .read(groupChatsProvider.notifier)
            .answerPending('dev', pending.id, 'Cannot submit'),
      );
      expect(File(store.filePath).readAsStringSync(), raw);
    },
  );

  testWidgets(
    'delete confirms, preserves the chat and removes the active bot',
    (tester) async {
      await pumpHome(tester, width: 1400);
      await tapPanel(tester, 'Planner');
      final chatId = container.read(activeRoomIdProvider)!;
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit bot'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Delete bot'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(
        container.read(botsProvider).botById(BuiltInBots.plannerId),
        isNotNull,
      );
      await tester.tap(find.byTooltip('Delete bot'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete bot'));
      await pumpUntil(
        tester,
        () =>
            container.read(botsProvider).botById(BuiltInBots.plannerId) == null,
      );
      await tester.pumpAndSettle();
      expect(find.byType(BotEditorPage), findsNothing);
      expect(
        container
            .read(groupChatsProvider)
            .snapshot
            .chats
            .any((chat) => chat.id == chatId),
        isTrue,
      );
      expect(find.byKey(ValueKey('room-$chatId')), findsOneWidget);
      expect(
        BotStore(
          File('${directory.path}/bots/bots.json'),
        ).load().allBots.any((bot) => bot.id == BuiltInBots.plannerId),
        isFalse,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'the drawer presents the same header, controls and rows as the wide rail',
    (tester) async {
      await pumpHome(tester, width: 1400);
      final railLabels = tester
          .widgetList<Text>(
            find.descendant(
              of: find.byType(AppNavigationPanel),
              matching: find.byType(Text),
            ),
          )
          .map((widget) => widget.data)
          .toList();
      expect(
        railLabels,
        containsAll([
          'InstaLLM',
          'My workspace',
          'Models',
          'Benchmark',
          'Settings',
          'CHATS',
          'BOTS',
          'ROOMS',
          'Dev',
          'Chat A',
          'Chat B',
          'Board',
        ]),
      );
      expect(
        railLabels,
        containsAllInOrder([
          'My workspace',
          'Models',
          'Benchmark',
          'Settings',
          'Search chats',
        ]),
      );
      expect(panelText('MORE'), findsNothing);
      expect(newChatButton(), findsOneWidget);
      expect(
        tester.getCenter(searchField()).dy,
        closeTo(tester.getCenter(newChatButton()).dy, 1),
      );
      expect(find.byTooltip('New bot'), findsOneWidget);
      expect(find.byTooltip('New room'), findsOneWidget);
      final shortcuts = find.byType(NavigationShortcutTile);
      expect(shortcuts, findsNWidgets(3));
      final tiles = shortcuts
          .evaluate()
          .map((element) => tester.getCenter(find.byWidget(element.widget)))
          .toList();
      expect(tiles.map((point) => point.dy).toSet(), hasLength(1));
      expect(
        tester.getSize(find.byType(AppNavigationPanel)).width,
        AppShell.railWidth,
      );
      expect(find.byTooltip('Menu'), findsNothing);

      tester.view.physicalSize = const Size(899, 1100);
      await tester.pumpAndSettle();
      expect(find.byType(AppNavigationPanel), findsNothing);
      await openDrawer(tester);
      final drawerLabels = tester
          .widgetList<Text>(
            find.descendant(
              of: find.byType(AppNavigationPanel),
              matching: find.byType(Text),
            ),
          )
          .map((widget) => widget.data)
          .toList();
      expect(drawerLabels, railLabels);
      expect(
        tester.getCenter(searchField()).dy,
        closeTo(tester.getCenter(newChatButton()).dy, 1),
      );
      expect(
        tester.getSize(find.byType(AppNavigationPanel)).width,
        AppShell.railWidth,
      );
      expect(find.byType(DrawerHeader), findsNothing);
    },
  );

  testWidgets(
    'search and its visible text survive closing, reopening and resizing',
    (tester) async {
      await pumpHome(tester);
      await openDrawer(tester);
      await tester.enterText(searchField(), 'Chat B');
      await tester.pump();
      expect(panelText('Chat A'), findsNothing);
      expect(panelText('Chat B'), findsOneWidget);
      homeScaffold(tester).closeDrawer();
      await tester.pumpAndSettle();
      await openDrawer(tester);
      expect(
        tester.widget<TextField>(searchField()).controller!.text,
        'Chat B',
      );
      tester.view.physicalSize = const Size(1400, 1100);
      await tester.pumpAndSettle();
      expect(find.byType(AppNavigationPanel), findsOneWidget);
      expect(
        tester.widget<TextField>(searchField()).controller!.text,
        'Chat B',
      );
      expect(panelText('Chat A'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('workspace header saves its choice and filters room rows', (
    tester,
  ) async {
    await pumpHome(tester, width: 1400);
    final workspaces = container.read(workspacesProvider.notifier);
    await tester.runAsync(() async {
      await workspaces.createWorkspace('Second workspace');
      final id = container.read(workspacesProvider).active!.id;
      await container
          .read(groupChatsProvider.notifier)
          .createChat(workspaceId: id, name: 'Second room');
      await workspaces.setActive('ws');
    });
    await tester.pump();
    expect(panelText('Dev'), findsOneWidget);
    expect(panelText('Second room'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('workspace-picker')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Second workspace'));
    await tester.pumpAndSettle();
    final secondId = container.read(workspacesProvider).active!.id;
    await pumpUntil(
      tester,
      () =>
          WorkspaceStore(
            File('${directory.path}/workspaces/workspaces.json'),
          ).load().activeWorkspaceId ==
          secondId,
    );
    expect(panelText('Second workspace'), findsOneWidget);
    expect(panelText('Second room'), findsOneWidget);
    expect(panelText('Dev'), findsNothing);
  });

  testWidgets('selected compact rows follow conversations, bots and rooms', (
    tester,
  ) async {
    await pumpHome(tester, width: 1400);
    await tapPanel(tester, 'Chat A');
    await pumpUntil(
      tester,
      () =>
          container.read(conversationControllerProvider).activeConversationId ==
          'a',
    );
    expect(
      tester
          .widget<NavigationChatTile>(
            find.byKey(const ValueKey('conversation-a')),
          )
          .selected,
      isTrue,
    );
    expect(
      tester
          .widget<NavigationChatTile>(
            find.byKey(const ValueKey('conversation-b')),
          )
          .selected,
      isFalse,
    );
    expect(
      find.descendant(
        of: find.byType(AppNavigationPanel),
        matching: find.text('No messages yet'),
      ),
      findsNothing,
    );
    await tapPanel(tester, 'Planner');
    await pumpUntil(
      tester,
      () =>
          container.read(activeRoomProvider)?.directBotId ==
          BuiltInBots.plannerId,
    );
    expect(
      tester
          .widget<NavigationChatTile>(
            find.byKey(ValueKey('bot-${BuiltInBots.plannerId}')),
          )
          .selected,
      isTrue,
    );
    expect(
      tester
          .widget<NavigationChatTile>(
            find.byKey(const ValueKey('conversation-a')),
          )
          .selected,
      isFalse,
    );
    await tapPanel(tester, 'Dev');
    expect(
      tester
          .widget<NavigationChatTile>(find.byKey(const ValueKey('room-dev')))
          .selected,
      isTrue,
    );
    expect(
      tester
          .widget<NavigationChatTile>(
            find.byKey(ValueKey('bot-${BuiltInBots.plannerId}')),
          )
          .selected,
      isFalse,
    );
  });

  testWidgets(
    'rooms retain the hamburger and selecting a conversation closes the drawer',
    (tester) async {
      container.read(activeRoomIdProvider.notifier).state = 'dev';
      await pumpHome(tester);
      expect(find.byType(RoomChatView), findsOneWidget);
      await openDrawer(tester);
      await tapPanel(tester, 'Chat A');
      await pumpUntil(
        tester,
        () =>
            container
                .read(conversationControllerProvider)
                .activeConversationId ==
            'a',
      );
      expect(container.read(activeRoomIdProvider), isNull);
      expect(homeScaffold(tester).isDrawerOpen, isFalse);
      expect(find.byType(RoomChatView), findsNothing);
    },
  );

  testWidgets('new chat exits a room, clears search and closes the drawer', (
    tester,
  ) async {
    container.read(activeRoomIdProvider.notifier).state = 'dev';
    await pumpHome(tester);
    await openDrawer(tester);
    await tester.enterText(searchField(), 'Chat B');
    await tester.ensureVisible(newChatButton());
    await tester.tap(newChatButton());
    await tester.pump(const Duration(milliseconds: 400));
    await pumpUntil(
      tester,
      () =>
          container.read(conversationControllerProvider).summaries.length == 3,
    );
    expect(container.read(activeRoomIdProvider), isNull);
    expect(container.read(conversationControllerProvider).searchQuery, isEmpty);
    expect(homeScaffold(tester).isDrawerOpen, isFalse);
    expect(find.byType(RoomChatView), findsNothing);
  });

  testWidgets('selecting a bot opens its direct chat and closes the drawer', (
    tester,
  ) async {
    await pumpHome(tester);
    await openDrawer(tester);
    await tapPanel(tester, 'Planner');
    await pumpUntil(
      tester,
      () =>
          container.read(activeRoomProvider)?.directBotId ==
          BuiltInBots.plannerId,
    );
    expect(homeScaffold(tester).isDrawerOpen, isFalse);
    expect(find.byType(RoomChatView), findsOneWidget);
    expect(find.byTooltip('Menu'), findsOneWidget);
  });

  testWidgets('room creation in the drawer saves and opens the room', (
    tester,
  ) async {
    await pumpHome(tester);
    await openDrawer(tester);
    await tester.ensureVisible(find.byTooltip('New room'));
    await tester.tap(find.byTooltip('New room'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.descendant(
        of: find.byType(NamePromptDialog),
        matching: find.byType(TextField),
      ),
      'Mobile room',
    );
    await tester.tap(find.text('Create'));
    await pumpUntil(
      tester,
      () => container.read(activeRoomProvider)?.name == 'Mobile room',
    );
    await tester.pump(const Duration(milliseconds: 400));
    expect(homeScaffold(tester).isDrawerOpen, isFalse);
    expect(find.byType(RoomChatView), findsOneWidget);
  });

  testWidgets('bot creation in the drawer closes it and opens the editor', (
    tester,
  ) async {
    await pumpHome(tester);
    final scaffold = homeScaffold(tester);
    await openDrawer(tester);
    await tester.ensureVisible(find.byTooltip('New bot'));
    await tester.tap(find.byTooltip('New bot'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.descendant(
        of: find.byType(CreateBotDialog),
        matching: find.byType(TextField),
      ),
      'Mobile bot',
    );
    await tester.pump();
    await tester.tap(find.text('Create'));
    await pumpUntil(
      tester,
      () => find.byType(BotEditorPage).evaluate().isNotEmpty,
    );
    expect(scaffold.isDrawerOpen, isFalse);
    expect(find.text('Edit Mobile bot'), findsOneWidget);
  });

  for (final (label, route) in [
    ('See all', AppRoutes.conversations),
    ('Models', AppRoutes.modelSelection),
    ('Benchmark', AppRoutes.benchmark),
    ('Manage workspaces', AppRoutes.workspaces),
  ]) {
    testWidgets('$label closes the drawer and navigates to its page', (
      tester,
    ) async {
      await pumpHome(tester);
      final scaffold = homeScaffold(tester);
      await openDrawer(tester);
      if (label == 'Manage workspaces') {
        await tester.tap(find.byKey(const ValueKey('workspace-picker')));
        await tester.pumpAndSettle();
        await tester.tap(find.text(label));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
      } else {
        await tapPanel(tester, label);
      }
      await pumpUntil(
        tester,
        () => find.text('Destination $route').evaluate().isNotEmpty,
      );
      expect(find.text('Destination $route'), findsOneWidget);
      expect(scaffold.isDrawerOpen, isFalse);
    });
  }

  testWidgets('the board uses the same mobile drawer and can open a room', (
    tester,
  ) async {
    await pumpHome(tester);
    await openDrawer(tester);
    await tapPanel(tester, 'Board');
    await pumpUntil(
      tester,
      () => find.byType(KanbanPage).evaluate().isNotEmpty,
    );
    await pumpUntil(tester, () => container.read(kanbanProvider).isReady);
    await tester.pumpAndSettle();
    expect(find.byType(KanbanPage), findsOneWidget);
    await openDrawer(tester);
    await tapPanel(tester, 'Dev');
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(HomePage), findsOneWidget);
    expect(container.read(activeRoomIdProvider), 'dev');
    expect(find.byType(RoomChatView), findsOneWidget);
    expect(find.byType(AppNavigationPanel), findsNothing);
  });

  testWidgets(
    'Settings keeps About after Benchmark moves to the navigation panel',
    (tester) async {
      await pumpHome(tester);
      await openDrawer(tester);
      await tapPanel(tester, 'Settings');
      await pumpUntil(
        tester,
        () => find.byType(SettingsPage).evaluate().isNotEmpty,
      );
      expect(find.byType(SettingsPage), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('About'),
        400,
        scrollable: find
            .descendant(
              of: find.byType(SettingsPage),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(find.text('Benchmark'), findsNothing);
      await tester.tap(find.text('About'));
      await tester.pump();
      await tester.pumpAndSettle();
      expect(find.text('Destination ${AppRoutes.about}'), findsOneWidget);
    },
  );

  testWidgets(
    'a narrow drawer scrolls with large text and the keyboard visible',
    (tester) async {
      tester.view.physicalSize = const Size(390, 600);
      tester.view.devicePixelRatio = 1;
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(tester.view.reset);
      final scaffold = GlobalKey<ScaffoldState>();
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            ),
            home: Scaffold(
              key: scaffold,
              drawer: const AppNavigationDrawer(section: AppSection.chats),
              body: const SizedBox(),
            ),
          ),
        ),
      );
      scaffold.currentState!.openDrawer();
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        panelText('Settings'),
        200,
        scrollable: find
            .descendant(
              of: find.byType(AppNavigationPanel),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pumpAndSettle();
      expect(
        tester.getRect(panelText('Settings')).bottom,
        lessThanOrEqualTo(300),
      );
      await tester.scrollUntilVisible(
        searchField(),
        200,
        scrollable: find
            .descendant(
              of: find.byType(AppNavigationPanel),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(
        tester.getCenter(searchField()).dy,
        closeTo(tester.getCenter(newChatButton()).dy, 1),
      );
      expect(tester.takeException(), isNull);
    },
  );
}
