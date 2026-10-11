import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pocket_llm/features/group_chat/application/group_chat_controller.dart';
import 'package:pocket_llm/features/group_chat/data/group_chat_store.dart';
import 'package:pocket_llm/features/group_chat/presentation/group_chats_page.dart';

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
    tempDir = await Directory.systemTemp.createTemp('pocketllm_create_room');
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

  testWidgets('creating a room from the rooms page does not crash', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          groupChatStoreProvider.overrideWith(
            (ref) async => GroupChatStore(
              File(p.join(tempDir.path, 'group_chat', 'chats.json')),
            ),
          ),
        ],
        child: const MaterialApp(home: GroupChatsPage()),
      ),
    );

    // The seeded workspace makes the New room button appear.
    await pumpUntil(tester, () => find.text('New room').evaluate().isNotEmpty);
    expect(find.text('New room'), findsOneWidget);

    // The reported crash: rooms -> see more -> create room. The handler is
    // invoked directly because an overlay absorbs raw taps in tests.
    tester
        .widget<FloatingActionButton>(find.byType(FloatingActionButton))
        .onPressed!();
    await tester.pumpAndSettle();
    expect(find.text('New group chat'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Crash probe room');
    await tester.tap(find.text('Create'));
    await pumpUntil(
      tester,
      () => find.text('Crash probe room').evaluate().isNotEmpty,
    );
    expect(find.text('Crash probe room'), findsOneWidget);
    // Let the dialog's pop transition (and its tap-absorbing barrier)
    // fully leave before touching the list.
    await tester.pumpAndSettle();

    // Opening the fresh room must work too.
    await tester.tap(find.text('Crash probe room'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Message the room'), findsOneWidget);

    // The shared composer sends through the room turn loop.
    await tester.enterText(find.byType(TextField), 'hello room');
    await tester.tap(find.byTooltip('Send'));
    await pumpUntil(
      tester,
      () => find.text('hello room').evaluate().isNotEmpty,
    );
    expect(find.text('hello room'), findsOneWidget);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(GroupChatDetailPage)),
    );
    expect(
      container
          .read(groupChatsProvider)
          .snapshot
          .chats
          .any(
            (chat) =>
                chat.name == 'Crash probe room' && chat.directBotId == null,
          ),
      isTrue,
    );
  });
}
