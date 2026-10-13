import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:installm/features/conversations/data/conversation_store.dart';
import 'package:installm/features/conversations/domain/message.dart';
import 'package:installm/features/conversations/presentation/conversation_controller.dart';
import 'package:installm/features/documents/application/document_library.dart';
import 'package:installm/features/documents/application/documents_controller.dart';
import 'package:installm/features/documents/data/document_extraction_service.dart';
import 'package:installm/features/documents/data/document_index_store.dart';

void main() {
  // The controller's startup path reads the stores through platform plugins.
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late ProviderContainer container;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('installm_lifecycle_test');
    // Deleting a conversation also removes the attachments its messages
    // carried, which resolves the app's own directory through the platform
    // channel; pointing that at the temporary directory keeps the test off the
    // real app folders.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => tempDir.path,
        );
    container = ProviderContainer(
      overrides: [
        conversationStoreProvider.overrideWithValue(
          ConversationStore(rootDirectory: tempDir),
        ),
        // These tests are about documents, not models: saying the catalog is
        // empty keeps the model screen (and its platform storage) out of the
        // way of deleting a chat.
        documentModelsProvider.overrideWithValue(const []),
        // The document index the chat adds to, kept in the same temporary
        // directory instead of the app's own.
        documentLibraryProvider.overrideWith(
          (ref) async => DocumentLibrary(
            extractor: DocumentExtractionService(),
            store: DocumentIndexStore(
              File(p.join(tempDir.path, 'documents', 'index.json')),
            ),
          )..load(),
        ),
      ],
    );
  });

  File documentIndexFile() =>
      File(p.join(tempDir.path, 'documents', 'index.json'));

  Future<File> writeDocument(String name, String content) async {
    final file = File(p.join(tempDir.path, name));
    await file.writeAsString(content);
    return file;
  }

  /// Reads the documents provider until the index has been opened.
  Future<DocumentsNotifier> startDocuments() async {
    final notifier = container.read(documentsProvider.notifier);
    for (var attempt = 0; attempt < 100; attempt++) {
      if (container.read(documentsProvider).isReady) return notifier;
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    fail('DocumentsNotifier did not finish opening the index');
  }

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    container.dispose();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  /// Reads the controller until its asynchronous startup has finished.
  ///
  /// The controller is auto-disposed, so it also needs a listener for that
  /// startup to run to completion.
  Future<ConversationListState> start() async {
    final subscription = container.listen(
      conversationControllerProvider,
      (previous, next) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);

    for (var attempt = 0; attempt < 200; attempt++) {
      final state = container.read(conversationControllerProvider);
      if (state.isInitialized) return state;
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    fail('ConversationController did not finish initializing');
  }

  Message message(String conversationId, MessageRole role, String content) {
    return Message.create(
      conversationId: conversationId,
      role: role,
      content: content,
    );
  }

  test('the list entry follows the messages that were saved', () async {
    await start();
    final controller = container.read(conversationControllerProvider.notifier);
    final conversation = await controller.createConversation(id: 'c-1');

    await controller.saveConversationMessages(conversation.id, [
      message(conversation.id, MessageRole.user, 'hey'),
      message(
        conversation.id,
        MessageRole.assistant,
        'I can perform: calculator, date and chat history searches',
      ),
    ]);

    final afterSend = container
        .read(conversationControllerProvider)
        .summaries
        .single;
    expect(afterSend.messageCount, 2);
    expect(afterSend.lastMessagePreview, contains('I can perform'));

    // Saving an empty list is the store's clear path; the entry must not keep
    // describing messages that are no longer there.
    await controller.saveConversationMessages(conversation.id, const []);

    final afterClear = container
        .read(conversationControllerProvider)
        .summaries
        .single;
    expect(afterClear.messageCount, 0);
    expect(afterClear.lastMessagePreview, isEmpty);
    expect(afterClear.lastMessageAt, isNull);
  });

  test(
    'deleting the active conversation opens the most recent one left',
    () async {
      await start();
      final controller = container.read(
        conversationControllerProvider.notifier,
      );
      await controller.createConversation(id: 'c-1');
      final active = await controller.createConversation(id: 'c-2');
      await controller.saveConversationMessages(active.id, [
        message(active.id, MessageRole.user, 'second chat'),
      ]);

      await controller.deleteConversation(active.id);

      final state = container.read(conversationControllerProvider);
      expect(state.summaries, hasLength(1));
      expect(state.summaries.single.conversation.id, 'c-1');
      expect(state.activeConversationId, 'c-1');
      expect(state.activeConversation?.id, 'c-1');
    },
  );

  test('deleting a chat forgets the documents that chat added', () async {
    await start();
    final controller = container.read(conversationControllerProvider.notifier);
    final doomed = await controller.createConversation(id: 'c-1');
    await controller.createConversation(id: 'c-2');

    final shared = await writeDocument(
      'shared.txt',
      'Docker images stay local.',
    );
    final fromTheChat = await writeDocument(
      'from-the-chat.txt',
      'Notes about styling buttons.',
    );

    final documents = await startDocuments();
    // Indexed from the Documents screen: no chat owns it.
    await documents.addDocument(shared.path);
    await documents.addDocument(
      fromTheChat.path,
      addedByConversationId: doomed.id,
    );
    expect(container.read(documentsProvider).documents, hasLength(2));

    final forgotten = await controller.deleteConversation(doomed.id);

    expect(forgotten, 1);
    expect(
      container
          .read(documentsProvider)
          .documents
          .map((document) => document.source.name),
      ['shared.txt'],
    );
    // The original file is never touched, only the index entry goes.
    expect(await fromTheChat.exists(), isTrue);

    // And it stays forgotten across a reload of the index file.
    final reloaded = DocumentLibrary(
      extractor: DocumentExtractionService(),
      store: DocumentIndexStore(documentIndexFile()),
    )..load();
    expect(reloaded.documents.map((document) => document.source.name), [
      'shared.txt',
    ]);
  });

  test('deleting a chat without documents reports nothing forgotten', () async {
    await start();
    final controller = container.read(conversationControllerProvider.notifier);
    final conversation = await controller.createConversation(id: 'c-1');

    expect(await controller.deleteConversation(conversation.id), 0);
  });

  test('deleting the last conversation leaves nothing active', () async {
    await start();
    final controller = container.read(conversationControllerProvider.notifier);
    final only = await controller.createConversation(id: 'c-1');
    await controller.saveConversationMessages(only.id, [
      message(only.id, MessageRole.user, 'hey'),
    ]);

    await controller.deleteConversation(only.id);

    final state = container.read(conversationControllerProvider);
    expect(state.summaries, isEmpty);
    expect(state.activeConversationId, isNull);
    expect(state.activeConversation, isNull);
    expect(
      await container.read(conversationRepositoryProvider).loadMessages('c-1'),
      isEmpty,
    );
  });
}
