import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;
import 'package:installm/core/navigation/app_router.dart';
import 'package:installm/core/widgets/name_prompt_dialog.dart';
import 'package:installm/features/group_chat/application/group_chat_controller.dart';
import 'package:installm/features/group_chat/data/group_chat_store.dart';
import 'package:installm/features/group_chat/presentation/room_chat_view.dart';
import 'package:installm/features/home/presentation/home_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Steps the tree by hand: the app does real file work on the event loop
  /// and some widgets animate continuously.
  Future<void> pumpUntil(WidgetTester tester, bool Function() done) async {
    for (var attempt = 0; attempt < 120 && !done(); attempt++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 25)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('installm_create_room');
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

  testWidgets('creating a room from the sidebar opens it on the chat page', (
    tester,
  ) async {
    // The rail is docked, so its sections and their create buttons are here.
    tester.view.physicalSize = const Size(1400, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    // The real app always has a router, and opening a chat navigates through
    // it, so the test gives the page one too.
    final router = GoRouter(
      routes: [
        GoRoute(
          path: AppRoutes.home,
          builder: (context, state) => const HomePage(),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          groupChatStoreProvider.overrideWith(
            (ref) async => GroupChatStore(
              File(p.join(tempDir.path, 'group_chat', 'chats.json')),
            ),
          ),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );

    // Rooms are created where they are listed, not on a page of their own.
    await pumpUntil(
      tester,
      () => find.byTooltip('New room').evaluate().isNotEmpty,
    ); // Invoked directly: the tooltip's own overlay can absorb a raw tap.
    tester
        .widget<IconButton>(
          find.ancestor(
            of: find.byTooltip('New room'),
            matching: find.byType(IconButton),
          ),
        )
        .onPressed!();
    await tester.pumpAndSettle();
    expect(find.text('New group chat'), findsOneWidget);

    // The dialog's own field: the rail above it has a search box too.
    await tester.enterText(
      find.descendant(
        of: find.byType(NamePromptDialog),
        matching: find.byType(TextField),
      ),
      'Crash probe room',
    );
    await tester.pump();
    await tester.tap(find.text('Create'));
    await pumpUntil(
      tester,
      () => find.byType(RoomChatView).evaluate().isNotEmpty,
    );
    await tester.pump(const Duration(milliseconds: 200));

    // A new room is open on the app's chat page, and it is in the store.
    expect(find.byType(RoomChatView), findsOneWidget);
    expect(find.textContaining('Message the room'), findsOneWidget);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(RoomChatView)),
    );
    expect(
      container
          .read(groupChatsProvider)
          .snapshot
          .chats
          .any((chat) => chat.name == 'Crash probe room'),
      isTrue,
    );
  });
}
