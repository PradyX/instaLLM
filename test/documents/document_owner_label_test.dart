import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_llm/features/documents/domain/document.dart';
import 'package:pocket_llm/features/documents/presentation/documents_page.dart';

void main() {
  IndexedDocument document({String? addedByConversationId}) => IndexedDocument(
    source: DocumentSource.fromFile(
      id: 'doc-1',
      path: '/tmp/notes.txt',
      name: 'notes.txt',
      sizeBytes: 120,
      modifiedAt: DateTime(2026, 3, 1),
      addedAt: DateTime(2026, 3, 2),
    ),
    chunks: const [],
    charCount: 120,
    indexedAt: DateTime(2026, 3, 2),
    contentHash: 'hash',
    addedByConversationId: addedByConversationId,
  );

  test('an unowned document says it stays until removed here', () {
    expect(
      documentOwnerLabel(
        document(),
        conversationTitles: const {},
        conversationsLoaded: true,
      ),
      'Added here · stays until you remove it',
    );
  });

  test('an unowned document is not blamed on a missing chat', () {
    // The owner is stored with the document, so an unloaded chat list cannot
    // make a library file look like it came from a chat.
    expect(
      documentOwnerLabel(
        document(),
        conversationTitles: const {},
        conversationsLoaded: false,
      ),
      'Added here · stays until you remove it',
    );
  });

  test('a chat-owned document names the chat that owns it', () {
    expect(
      documentOwnerLabel(
        document(addedByConversationId: 'chat-1'),
        conversationTitles: const {'chat-1': 'Android interview'},
        conversationsLoaded: true,
      ),
      'From chat "Android interview" · removed with that chat',
    );
  });

  test(
    'a dangling owner is offered for cleanup only once the list is known',
    () {
      expect(
        documentOwnerLabel(
          document(addedByConversationId: 'chat-1'),
          conversationTitles: const {},
          conversationsLoaded: true,
        ),
        'From a chat that no longer exists · remove it here',
      );

      expect(
        documentOwnerLabel(
          document(addedByConversationId: 'chat-1'),
          conversationTitles: const {},
          conversationsLoaded: false,
        ),
        'From a chat',
      );
    },
  );
}
