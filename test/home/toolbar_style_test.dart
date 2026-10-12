import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pocket_llm/features/group_chat/application/active_room.dart';
import 'package:pocket_llm/features/group_chat/application/group_chat_controller.dart';
import 'package:pocket_llm/features/group_chat/data/group_chat_store.dart';
import 'package:pocket_llm/features/group_chat/domain/group_chat.dart';
import 'package:pocket_llm/features/home/presentation/home_page.dart';

/// The chat page's toolbar: what it looks like and how much room it leaves
/// itself. The buttons were filled grey squares, which read as pressed at rest
/// and competed with the composer; they are outlined accent icons now, with a
/// margin from each other and from the edge of the window.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late ProviderContainer container;

  /// The page with a room open, which is where the toolbar carries two actions
  /// — a room's settings and new chat — rather than one.
  Future<GroupChat> openRoom(WidgetTester tester) async {
    final notifier = container.read(groupChatsProvider.notifier);
    for (var attempt = 0; attempt < 50; attempt++) {
      if (container.read(groupChatsProvider).isReady) break;
      await Future<void>.delayed(Duration.zero);
    }
    return (await notifier.createChat(
      workspaceId: 'ws',
      name: 'Dev',
      memberBotIds: const [],
      directBotId: null,
    ))!;
  }

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('pocketllm_toolbar');
    // The app resolves its own folders and settings through platform channels,
    // so the temporary directory keeps this test off the real app folders.
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
      ],
    );
    addTearDown(container.dispose);
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

  /// Draws the chat page the way the app does, and steps its real file work:
  /// the page loads conversations and models while it is on screen.
  Future<void> pumpHome(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: HomePage()),
      ),
    );
    for (var attempt = 0; attempt < 30; attempt++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  testWidgets('an action carries no fill and takes the accent colour', (
    tester,
  ) async {
    await pumpHome(tester);

    final newChat = find.byTooltip('New chat');
    expect(newChat, findsOneWidget);

    // The tooltip lives inside the button, so the button is its ancestor.
    final button = tester.widget<IconButton>(
      find.ancestor(of: newChat, matching: find.byType(IconButton)),
    );
    final colorScheme = Theme.of(
      tester.element(find.byType(AppBar)),
    ).colorScheme;

    // Nothing behind the icon at rest: a filled square said "selected".
    expect(button.style?.backgroundColor?.resolve({}), Colors.transparent);
    // The accent colour, not a grey the user has to read as an icon.
    expect(button.style?.foregroundColor?.resolve({}), colorScheme.primary);
    // A button that cannot act yet fades rather than vanishing.
    expect(
      button.style?.foregroundColor?.resolve({WidgetState.disabled}),
      colorScheme.primary.withValues(alpha: 0.35),
    );
    // The new-chat action uses a simple plus glyph.
    expect((button.icon as Icon).icon, Icons.add);
  });

  testWidgets('the actions keep a margin from each other and the edge', (
    tester,
  ) async {
    final room = await tester.runAsync(() => openRoom(tester));
    container.read(activeRoomIdProvider.notifier).state = room!.id;
    await pumpHome(tester);

    expect(
      tester.widget<AppBar>(find.byType(AppBar)).actionsPadding,
      const EdgeInsets.only(right: 12),
    );

    final settings = tester.getRect(find.byTooltip('Settings'));
    final newChat = tester.getRect(find.byTooltip('New chat'));
    final windowWidth =
        tester.view.physicalSize.width / tester.view.devicePixelRatio;

    // The two actions are not one grey block: there is a gap between them, and
    // the last one does not run into the window's edge.
    expect(settings.right + 6, lessThanOrEqualTo(newChat.left));
    expect(windowWidth - newChat.right, greaterThanOrEqualTo(12));
  });
}
