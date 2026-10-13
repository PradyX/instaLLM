import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:installm/features/conversations/data/conversation_store.dart';
import 'package:installm/features/conversations/domain/conversation.dart';
import 'package:installm/features/conversations/presentation/conversation_controller.dart';
import 'package:installm/features/conversations/presentation/conversations_page.dart';
import 'package:installm/i18n/strings.g.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Pumps frames until [done] holds, letting real file work finish between
  /// them. The app keeps its work on the real event loop and some of its
  /// widgets animate continuously, so the tree is stepped by hand.
  Future<void> pumpUntil(WidgetTester tester, bool Function() done) async {
    for (var attempt = 0; attempt < 80 && !done(); attempt++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 25)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  late Directory tempDir;
  late ConversationStore store;

  /// The conversation titles the on-disk index still lists, read straight from
  /// the file the store wrote.
  List<String> storedTitles() {
    final index = File(p.join(tempDir.path, 'index.json'));
    if (!index.existsSync()) return const [];
    final decoded = jsonDecode(index.readAsStringSync()) as Map;
    final summaries = decoded['conversations'] as List? ?? const [];
    return summaries
        .map((summary) => (summary as Map)['title'] as String? ?? '')
        .toList();
  }

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('installm_delete_flow');
    // The app resolves its own folder through a platform channel, so the
    // temporary directory keeps this test off the real app folders.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => tempDir.path,
        );
    // Settings and personas live in secure storage; the app reads them while it
    // starts, so the channel answers an empty store instead of failing.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          (call) async => null,
        );
    store = ConversationStore(rootDirectory: tempDir);
    // A chat an earlier clear emptied: it still has its title and no messages.
    await store.createConversation(
      Conversation.create(id: 'c-1', title: 'hey'),
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

  testWidgets(
    'an empty conversation can be deleted from the conversations list',
    (tester) async {
      // The homepage no longer carries a delete action (Option A keeps the
      // toolbar to menu · model pill · context · new chat), so deletion is
      // verified where it lives now: the conversations list.
      await tester.pumpWidget(
        TranslationProvider(
          child: ProviderScope(
            overrides: [conversationStoreProvider.overrideWithValue(store)],
            child: const MaterialApp(home: ConversationsPage()),
          ),
        ),
      );
      await pumpUntil(tester, () => find.text('hey').evaluate().isNotEmpty);
      expect(find.text('hey'), findsWidgets);
      expect(storedTitles(), ['hey']);

      await tester.tap(find.byTooltip('Conversation actions'));
      await tester.pumpAndSettle(const Duration(milliseconds: 200));
      await tester.tap(find.text('Delete'));
      await pumpUntil(
        tester,
        () => find.text('Delete conversation?').evaluate().isNotEmpty,
      );
      expect(find.text('Delete conversation?'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await pumpUntil(tester, () => find.text('hey').evaluate().isEmpty);

      // The conversation is gone from the screen and from what was written to
      // disk.
      expect(find.text('hey'), findsNothing);
      expect(storedTitles(), isEmpty);
      expect(File(p.join(tempDir.path, 'c-1.json')).existsSync(), isFalse);
    },
  );
}
