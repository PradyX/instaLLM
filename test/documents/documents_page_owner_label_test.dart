import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pocket_llm/features/conversations/domain/conversation.dart';
import 'package:pocket_llm/features/conversations/presentation/conversation_controller.dart';
import 'package:pocket_llm/features/documents/application/document_library.dart';
import 'package:pocket_llm/features/documents/application/documents_controller.dart';
import 'package:pocket_llm/features/documents/data/document_extraction_service.dart';
import 'package:pocket_llm/features/documents/data/document_index_store.dart';
import 'package:pocket_llm/features/documents/presentation/documents_page.dart';

/// The chat list the page reads for names, without the store behind it: these
/// tests are about what a document row says, not about loading chats.
class _StubChats extends ConversationController {
  _StubChats(this._initial);

  final ConversationListState _initial;

  @override
  ConversationListState build() => _initial;
}

/// The Documents screen on its own, to check what a row says about a file's
/// owner. A library file and a chat-owned file look identical otherwise, which
/// is how a screen with no conversations still shows documents and reads as
/// leftover state.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late DocumentLibrary library;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('pocketllm_docs_page');
    library = DocumentLibrary(
      extractor: DocumentExtractionService(),
      store: DocumentIndexStore(
        File(p.join(tempDir.path, 'documents', 'index.json')),
      ),
    );
    library.load();
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  ConversationSummary summary(String id, String title) => ConversationSummary(
    conversation: Conversation.create(id: id, title: title),
    messageCount: 0,
    lastMessagePreview: '',
    lastMessageAt: DateTime(2026, 3, 1),
  );

  ProviderContainer containerWith(ConversationListState chats) {
    final container = ProviderContainer(
      overrides: [
        // These tests are about documents, not models: saying the catalog is
        // empty keeps the model screen and its platform storage out of the way.
        documentModelsProvider.overrideWithValue(const []),
        documentLibraryProvider.overrideWith((ref) async => library),
        conversationControllerProvider.overrideWith(() => _StubChats(chats)),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  /// Indexes a file, optionally as the document a chat brought in. The read and
  /// write happen in the real async zone: under a widget test's faked clock,
  /// awaited file work never finishes.
  Future<void> index(
    WidgetTester tester,
    String name, {
    String? forConversation,
  }) async {
    await tester.runAsync(() async {
      final file = File(p.join(tempDir.path, name));
      await file.writeAsString('notes about docker and styling');
      await library.addDocument(
        path: file.path,
        addedByConversationId: forConversation,
      );
    });
  }

  Future<void> pumpPage(
    WidgetTester tester,
    ProviderContainer container,
  ) async {
    // A viewport tall enough for the whole list keeps every row in the tree
    // instead of testing only what fits on a phone.
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: DocumentsPage()),
      ),
    );
    // A bounded number of frames, not pumpAndSettle: the loading screen is a
    // spinner, and settling on a spinner never returns.
    for (var frame = 0; frame < 30; frame++) {
      await tester.pump(const Duration(milliseconds: 20));
      if (container.read(documentsProvider).isReady) break;
    }
    expect(container.read(documentsProvider).isReady, isTrue);
    for (var frame = 0; frame < 5; frame++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  testWidgets('rows say which chat owns a file and which files have no chat', (
    tester,
  ) async {
    await index(tester, 'from-a-chat.txt', forConversation: 'chat-1');
    await index(tester, 'from-this-screen.txt');
    final container = containerWith(
      ConversationListState(
        isInitialized: true,
        summaries: [summary('chat-1', 'Android interview')],
      ),
    );

    await pumpPage(tester, container);

    expect(
      find.text('From chat "Android interview" · removed with that chat'),
      findsOneWidget,
    );
    expect(find.text('Added here · stays until you remove it'), findsOneWidget);
  });

  testWidgets('a file whose chat is gone is offered for cleanup', (
    tester,
  ) async {
    // A chat deleted by an older build leaves the index entry behind, so the
    // screen has to name that state instead of quietly showing an orphan.
    await index(tester, 'orphan.txt', forConversation: 'chat-that-was-deleted');
    final container = containerWith(
      const ConversationListState(isInitialized: true),
    );

    await pumpPage(tester, container);

    expect(
      find.text('From a chat that no longer exists · remove it here'),
      findsOneWidget,
    );
  });
}
