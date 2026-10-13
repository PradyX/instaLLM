import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:installm/core/navigation/app_shell.dart';
import 'package:installm/features/conversations/domain/conversation.dart';
import 'package:installm/features/conversations/presentation/conversation_controller.dart';

/// A chat with no messages, titled after its id so assertions read plainly.
ConversationSummary _chat(
  String id, {
  required int minutesAgo,
  bool pinned = false,
}) {
  final at = DateTime.utc(
    2026,
    10,
    12,
    12,
  ).subtract(Duration(minutes: minutesAgo));
  return ConversationSummary(
    conversation: Conversation(
      id: id,
      title: id,
      createdAt: at,
      updatedAt: at,
      isPinned: pinned,
    ),
    messageCount: 0,
    lastMessagePreview: '',
    lastMessageAt: null,
  );
}

/// Answers with a fixed list of chats: the real controller loads stored
/// conversations, which these checks do not care about.
class _FixedChats extends ConversationController {
  _FixedChats(this.summaries);

  final List<ConversationSummary> summaries;

  @override
  ConversationListState build() => ConversationListState(
    isInitialized: true,
    summaries: summaries,
    activeConversationId: summaries.first.conversation.id,
  );
}

/// The sidebar the app docks at desktop width, with a fixed chat list.
///
/// The cap is a rendering decision — pinned chats plus the five most recent,
/// the rest behind "See more" — so it is settled by looking at which rows the
/// sidebar draws, not only at the list the cap produces.
Future<void> _pumpSidebar(
  WidgetTester tester,
  List<ConversationSummary> chats,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        conversationControllerProvider.overrideWith(() => _FixedChats(chats)),
      ],
      child: const MaterialApp(
        home: Scaffold(
          body: AppShell(section: AppSection.chats, child: SizedBox.shrink()),
        ),
      ),
    ),
  );
  // The rail's other sections read the user's own stores on the event loop.
  for (var attempt = 0; attempt < 40; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    // The sidebar's bots and rooms come from the user's application-support
    // directory; a temporary one keeps these checks off the real stores.
    tempDir = await Directory.systemTemp.createTemp('installm_sidebar');
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

  testWidgets('shows pinned chats and the five newest others', (tester) async {
    // The shell docks its sidebar from 900px wide.
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await _pumpSidebar(tester, [
      _chat('Pinned old', minutesAgo: 600, pinned: true),
      _chat('Pinned new', minutesAgo: 5, pinned: true),
      for (var age = 1; age <= 8; age++) _chat('Chat $age', minutesAgo: age),
    ]);

    expect(find.text('Pinned old'), findsOneWidget);
    expect(find.text('Pinned new'), findsOneWidget);
    for (var age = 1; age <= 5; age++) {
      expect(find.text('Chat $age'), findsOneWidget);
    }
    for (var age = 6; age <= 8; age++) {
      expect(find.text('Chat $age'), findsNothing);
    }
  });

  testWidgets('a pin is listed in addition to the five newest chats', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await _pumpSidebar(tester, [
      _chat('Pinned', minutesAgo: 0, pinned: true),
      for (var age = 1; age <= 6; age++) _chat('Chat $age', minutesAgo: age),
    ]);

    expect(find.text('Pinned'), findsOneWidget);
    for (var age = 1; age <= 5; age++) {
      expect(find.text('Chat $age'), findsOneWidget);
    }
    expect(find.text('Chat 6'), findsNothing);
  });
}
