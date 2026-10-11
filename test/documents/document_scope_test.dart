import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_llm/features/conversations/domain/conversation.dart';
import 'package:pocket_llm/features/documents/domain/document_scope.dart';
import 'package:pocket_llm/features/documents/domain/knowledge_collection.dart';

void main() {
  KnowledgeCollection collection(String id, String name) {
    return KnowledgeCollection(
      id: id,
      name: name,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );
  }

  final collections = [
    collection(KnowledgeCollection.defaultId, 'General'),
    collection('col-work', 'Work'),
    collection('col-notes', 'Personal notes'),
  ];

  group('DocumentScope', () {
    test('reads the app-wide active collection', () {
      final scope = DocumentScope.resolve(
        collections: collections,
        activeCollectionId: 'col-work',
      );

      expect(scope.collectionId, 'col-work');
    });

    test('an unknown active collection falls back to one that exists', () {
      final scope = DocumentScope.resolve(
        collections: collections,
        activeCollectionId: 'col-deleted',
      );

      // The first collection is the built-in default here, which is what an
      // orphaned active id used to fall back to.
      expect(scope.collectionId, KnowledgeCollection.defaultId);
    });

    test('falls back to the first collection when the default is absent', () {
      final scope = DocumentScope.resolve(
        collections: [collections[1], collections[2]],
        activeCollectionId: 'col-deleted',
      );

      expect(scope.collectionId, 'col-work');
    });

    test('works before any index exists at all', () {
      final scope = DocumentScope.resolve(
        collections: const [],
        activeCollectionId: 'col-deleted',
      );

      expect(scope.collectionId, KnowledgeCollection.defaultId);
    });
  });

  group('Conversation document scope', () {
    // Store schema version 2 removed the per-conversation document scope, so
    // the model no longer carries one. A chat written before that still has to
    // load.
    final legacyJson = {
      'id': 'c-1',
      'title': 'Old chat',
      'createdAt': DateTime.utc(2026).toIso8601String(),
      'documentCollectionId': 'col-work',
      'documentsEnabled': false,
    };

    test('a chat stored with a document scope still loads', () {
      final conversation = Conversation.fromJson(legacyJson);

      expect(conversation.id, 'c-1');
      expect(conversation.title, 'Old chat');
    });

    test('the removed keys are not written back', () {
      final json = Conversation.fromJson(legacyJson).toJson();

      expect(json.containsKey('documentCollectionId'), isFalse);
      expect(json.containsKey('documentsEnabled'), isFalse);
    });

    test('malformed scope values cannot break the load', () {
      final conversation = Conversation.fromJson({
        ...legacyJson,
        'documentCollectionId': 42,
        'documentsEnabled': 'yes',
      });

      expect(conversation.title, 'Old chat');
    });
  });
}
