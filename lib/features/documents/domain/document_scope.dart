import 'package:installm/features/documents/domain/knowledge_collection.dart';

/// Which knowledge collection one request may read from.
///
/// A collection is a group of local documents with its own index, and retrieval
/// reads one collection at a time so unrelated material cannot influence an
/// answer. That collection is the app-wide active one the user chose on the
/// Documents screen; this is the only place that decides what a request really
/// reads, so the chat can never silently search material the user did not
/// select.
///
/// The rule is deliberately forgiving about stale data: an active collection
/// that has since been removed falls back to one that still exists instead of
/// silently retrieving nothing.
class DocumentScope {
  const DocumentScope._(this.collectionId);

  /// Collection the request reads from.
  ///
  /// Never null: a store with no collections at all still resolves to the
  /// built-in default, so "reads nothing" cannot come from a missing id — only
  /// from a collection that holds no usable chunks.
  final String collectionId;

  /// Resolves the scope of a request against the collections that exist.
  ///
  /// [activeCollectionId] comes from the document library. It is absent on a
  /// store written before collections existed and normally points at a
  /// collection that is still there; when it does not, the first collection
  /// that exists is read instead, so an orphaned id cannot leave a chat with
  /// no documents at all.
  static DocumentScope resolve({
    required List<KnowledgeCollection> collections,
    required String activeCollectionId,
  }) {
    for (final collection in collections) {
      if (collection.id == activeCollectionId) {
        return DocumentScope._(collection.id);
      }
    }
    if (collections.isEmpty) {
      return DocumentScope._(KnowledgeCollection.defaultCollection().id);
    }
    return DocumentScope._(collections.first.id);
  }
}
