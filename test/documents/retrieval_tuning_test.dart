import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:installm/features/documents/application/document_context_builder.dart';
import 'package:installm/features/documents/application/document_library.dart';
import 'package:installm/features/documents/data/document_extraction_service.dart';
import 'package:installm/features/documents/data/document_index_store.dart';
import 'package:installm/features/documents/data/hybrid_document_retriever.dart';
import 'package:installm/features/documents/domain/document.dart';
import 'package:installm/features/documents/domain/document_reranker.dart';
import 'package:installm/features/documents/domain/document_retrieval.dart';
import 'package:installm/features/documents/domain/document_vectors.dart';
import 'package:installm/features/documents/domain/knowledge_collection.dart';
import 'package:installm/features/documents/domain/retrieval_tuning.dart';

DocumentSource _source(String id, String name) => DocumentSource(
  id: id,
  path: '/tmp/$name',
  name: name,
  format: DocumentFormat.text,
  sizeBytes: 10,
  modifiedAt: DateTime(2026, 3, 1),
  addedAt: DateTime(2026, 3, 1),
);

IndexedDocument _document(
  String id,
  String name,
  List<String> texts, {
  String collectionId = defaultCollectionId,
  List<String?> headings = const [],
}) {
  return IndexedDocument(
    source: _source(id, name),
    collectionId: collectionId,
    chunks: [
      for (var index = 0; index < texts.length; index++)
        DocumentChunk(
          index: index,
          text: texts[index],
          startOffset: 0,
          endOffset: texts[index].length,
          heading: index < headings.length ? headings[index] : null,
        ),
    ],
    charCount: texts.fold(0, (sum, text) => sum + text.length),
    indexedAt: DateTime(2026, 3, 1),
    contentHash: 'hash-$id',
  );
}

DocumentVectors _vectors(Map<int, List<double>> byChunk) {
  final dimensions = byChunk.values.first.length;
  return DocumentVectors(
    dimensions: dimensions,
    chunkVectors: {
      for (final entry in byChunk.entries)
        entry.key: Float32List.fromList(entry.value),
    },
  );
}

void main() {
  group('tuning storage', () {
    test('round-trips and clamps to its bounds', () {
      const tuning = RetrievalTuning(
        lexicalWeight: 2.5,
        vectorWeight: 0.5,
        rerankEnabled: true,
        fullDocumentContext: true,
      );
      final again = RetrievalTuning.fromJson(tuning.toJson());
      expect(again.lexicalWeight, 2.5);
      expect(again.vectorWeight, 0.5);
      expect(again.rerankEnabled, isTrue);
      expect(again.fullDocumentContext, isTrue);

      const wild = RetrievalTuning(lexicalWeight: -3, vectorWeight: 99);
      final tamed = RetrievalTuning.fromJson(wild.toJson());
      expect(tamed.lexicalWeight, RetrievalTuning.minWeight);
      expect(tamed.vectorWeight, RetrievalTuning.maxWeight);
    });

    test('missing or corrupt tuning answers untuned, never throwing', () {
      expect(
        RetrievalTuning.fromJson(null),
        isA<RetrievalTuning>().having(
          (tuning) => tuning.rerankEnabled,
          'rerankEnabled',
          isFalse,
        ),
      );
      expect(RetrievalTuning.fromJson('nope').lexicalWeight, 1);
      expect(
        RetrievalTuning.fromJson(const {'lexicalWeight': 'lots'}).lexicalWeight,
        1,
      );
      expect(
        RetrievalTuning.fromJson(const {'rerankEnabled': 'yes'}).rerankEnabled,
        isFalse,
      );
    });

    test('a collection stored before tuning existed parses untuned', () {
      final stored = KnowledgeCollection.create(name: 'Old').toJson()
        ..remove('retrieval');
      final collection = KnowledgeCollection.fromJson(stored)!;
      expect(collection.retrieval.lexicalWeight, 1);
      expect(collection.retrieval.vectorWeight, 1);
      expect(collection.retrieval.rerankEnabled, isFalse);
      expect(collection.retrieval.fullDocumentContext, isFalse);
    });

    test('a tuned collection round-trips through JSON', () {
      final collection = KnowledgeCollection.create(
        name: 'Tuned',
        retrieval: const RetrievalTuning(
          lexicalWeight: 0,
          vectorWeight: 3,
          rerankEnabled: true,
        ),
      );
      final again = KnowledgeCollection.fromJson(collection.toJson())!;
      expect(again.retrieval.lexicalWeight, 0);
      expect(again.retrieval.vectorWeight, 3);
      expect(again.retrieval.rerankEnabled, isTrue);
    });
  });

  group('reranker', () {
    DocumentSearchHit hit(String doc, String text, {String? heading}) {
      return DocumentSearchHit(
        documentId: doc,
        documentName: '$doc.md',
        chunk: DocumentChunk(
          index: 0,
          text: text,
          startOffset: 0,
          endOffset: text.length,
          heading: heading,
        ),
        score: 1,
        rankDetail: 'lexical #1',
      );
    }

    test('an exact answer outranks term stuffing, measurably', () {
      final stuffed = hit(
        'stuffed',
        'Tomato plants tomato plants. More about tomato plants and plants '
            'with tomatoes growing near other plants every season.',
      );
      final answer = hit(
        'answer',
        'How do I prune tomato plants in spring? Cut the suckers above the '
            'first flower.',
        heading: 'Tomato plants',
      );
      final reranked = DocumentReranker.rerank('how do I prune tomato plants', [
        stuffed,
        answer,
      ]);

      expect(reranked.map((entry) => entry.documentId), [
        'answer',
        'stuffed',
      ], reason: 'the rerank toggle changes the ranking on this fixture');
      expect(reranked.first.rankDetail, contains('reranked #1 (was #2)'));
      expect(reranked.last.rankDetail, contains('reranked #2 (was #1)'));
      // Identity survives the reorder: same chunks, same citations.
      expect(reranked.first.chunk.text, contains('suckers'));
      expect(reranked.first.documentName, 'answer.md');
    });

    test('is deterministic and leaves edge cases alone', () {
      final hits = [
        hit('a', 'Tomato plants need sun.'),
        hit('b', 'How do I prune tomato plants in spring?'),
      ];
      final first = DocumentReranker.rerank('prune tomato plants', hits);
      final second = DocumentReranker.rerank('prune tomato plants', hits);
      expect(
        first.map((entry) => entry.documentId),
        second.map((entry) => entry.documentId),
      );
      expect(DocumentReranker.rerank('', hits), hasLength(2));
      expect(DocumentReranker.rerank('tomato', const []), isEmpty);
      expect(
        DocumentReranker.rerank('tomato', [hits.first]).single.documentId,
        'a',
      );
    });
  });

  group('fusion weights', () {
    late HybridDocumentRetriever retriever;

    setUp(() {
      retriever = HybridDocumentRetriever();
      retriever.rebuild(
        [
          _document('doc-docker', 'docker.md', [
            'The docker engine keeps every image local.',
          ]),
          _document('doc-garden', 'garden.md', [
            'Tomatoes need sun and water.',
          ]),
        ],
        vectors: {
          // The garden chunk means what the tilted query asks; docker does not.
          'doc-docker': _vectors({
            0: [1.0, 0.0],
          }),
          'doc-garden': _vectors({
            0: [0.8, 0.6],
          }),
        },
      );
    });

    test('untuned fusion matches the pre-tuning ranking', () {
      final plain = retriever.search(
        'docker engine local images',
        queryVector: Float32List.fromList([0.8, 0.6]),
      );
      final tuned = retriever.search(
        'docker engine local images',
        queryVector: Float32List.fromList([0.8, 0.6]),
        tuning: const RetrievalTuning(),
      );
      expect(
        tuned.map((hit) => hit.documentId),
        plain.map((hit) => hit.documentId),
      );
      expect(tuned.first.rankDetail, contains('weights 1.0/1.0'));
    });

    test('zeroing a channel removes it from the ranking', () {
      const query = 'docker engine local images';
      final queryVector = Float32List.fromList([0.8, 0.6]);
      final vectorDecides = retriever.search(
        query,
        queryVector: queryVector,
        tuning: const RetrievalTuning(lexicalWeight: 0, vectorWeight: 1),
      );
      final lexicalDecides = retriever.search(
        query,
        queryVector: queryVector,
        tuning: const RetrievalTuning(lexicalWeight: 1, vectorWeight: 0),
      );
      // The query names docker in terms but points at the garden by meaning.
      expect(vectorDecides.first.documentId, 'doc-garden');
      expect(lexicalDecides.first.documentId, 'doc-docker');
      expect(vectorDecides.first.rankDetail, contains('vector #1'));
      expect(lexicalDecides.first.rankDetail, contains('lexical #1'));
    });
  });

  group('full-collection context', () {
    late List<IndexedDocument> documents;

    setUp(() {
      documents = [
        _document('doc-a', 'a.md', ['Alpha one.', 'Alpha two.']),
        _document('doc-b', 'b.md', ['Beta one.']),
      ];
    });

    DocumentContextBuilder builder() => const DocumentContextBuilder();

    test('a small tuned collection reads whole, in document order', () {
      final retriever = HybridDocumentRetriever()..rebuild(documents);
      final context = builder().build(
        retriever: retriever,
        query: 'unrelated question with no matching terms xyzzy',
        tokenBudget: 1000,
        tuning: const RetrievalTuning(fullDocumentContext: true),
        collectionDocuments: documents,
      );

      expect(context.hits.map((hit) => hit.chunk.text), [
        'Alpha one.',
        'Alpha two.',
        'Beta one.',
      ]);
      expect(
        context.hits.every(
          (hit) => hit.rankDetail == 'full collection · document order',
        ),
        isTrue,
      );
      expect(context.section, contains('[1] a.md'));
      expect(context.section, contains('[3] b.md'));
    });

    test('a starved budget falls back to ranking instead', () {
      final retriever = HybridDocumentRetriever()..rebuild(documents);
      final context = builder().build(
        retriever: retriever,
        query: 'Alpha',
        tokenBudget: 1,
        tuning: const RetrievalTuning(fullDocumentContext: true),
        collectionDocuments: documents,
      );

      expect(context.hits, isEmpty);
    });

    test('untuned collections still rank top-k', () {
      final retriever = HybridDocumentRetriever()..rebuild(documents);
      final context = builder().build(
        retriever: retriever,
        query: 'Beta one',
        tokenBudget: 1000,
        collectionDocuments: documents,
      );

      expect(context.hits.first.chunk.text, 'Beta one.');
      expect(context.hits.first.rankDetail, contains('lexical'));
    });
  });

  group('library tuning', () {
    late Directory tempDir;
    late DocumentLibrary library;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('installm_tuning_test');
      library = DocumentLibrary(
        extractor: DocumentExtractionService(),
        store: DocumentIndexStore(
          File(p.join(tempDir.path, 'index', 'index.json')),
        ),
      );
    });

    tearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    test('unknown collections refuse, changes persist and reload', () {
      expect(
        library.updateRetrievalTuning('col-missing', const RetrievalTuning()),
        isFalse,
      );

      const tuned = RetrievalTuning(rerankEnabled: true, vectorWeight: 3);
      expect(
        library.updateRetrievalTuning(KnowledgeCollection.defaultId, tuned),
        isTrue,
      );
      expect(
        library
            .collectionById(KnowledgeCollection.defaultId)!
            .retrieval
            .rerankEnabled,
        isTrue,
      );

      final reloaded = DocumentLibrary(
        extractor: DocumentExtractionService(),
        store: DocumentIndexStore(
          File(p.join(tempDir.path, 'index', 'index.json')),
        ),
      )..load();
      expect(
        reloaded
            .collectionById(KnowledgeCollection.defaultId)!
            .retrieval
            .vectorWeight,
        3,
      );
    });

    test(
      'rerank through the library reorders what chat would receive',
      () async {
        final first = File(p.join(tempDir.path, 'stuffed.txt'))
          ..writeAsStringSync(
            'Tomato plants tomato plants. More about tomato plants and plants '
            'with tomatoes growing near other plants every season.',
          );
        final second = File(p.join(tempDir.path, 'answer.txt'))
          ..writeAsStringSync(
            'How do I prune tomato plants in spring? Cut the suckers above the '
            'first flower.',
          );
        await library.addDocument(path: first.path);
        await library.addDocument(path: second.path);

        const query = 'how do I prune tomato plants';
        final ranked = library.search(query);
        expect(ranked.map((hit) => hit.documentName), contains('answer.txt'));

        expect(
          library.updateRetrievalTuning(
            KnowledgeCollection.defaultId,
            const RetrievalTuning(rerankEnabled: true),
          ),
          isTrue,
        );
        final reranked = library.search(query);
        expect(reranked.first.documentName, 'answer.txt');
        expect(reranked.first.rankDetail, contains('reranked'));
      },
    );
  });
}
