import 'package:installm/features/documents/data/lexical_document_retriever.dart'
    show retrievalTokens;
import 'package:installm/features/documents/domain/document_retrieval.dart';

/// Local second pass over fused candidates (Road Map 3 Phase 3.4).
///
/// Fusion orders by rank; it never looks at the text again. The reranker does:
/// query-term coverage, exact-phrase overlap, heading agreement and a short
/// length preference, all from the query and the chunk text. Pure Dart, no
/// download, fully offline and deterministic, so the same candidates always
/// come back in the same order.
///
/// Scores are only comparable within one reranked query — like every other
/// retrieval score in this app, they are an ordering, not a quality
/// percentage.
abstract final class DocumentReranker {
  /// Weight of exact-phrase overlap relative to one covered term.
  static const double phraseWeight = 2;

  /// Weight of a heading that names a query term, relative to one covered term.
  static const double headingWeight = 1.5;

  /// Reorders [hits] for [query], best first.
  ///
  /// Hits keep their identity, matched terms and rank detail (extended with
  /// the rerank movement); only their order and score change. An empty query
  /// or an empty list returns the hits untouched.
  static List<DocumentSearchHit> rerank(
    String query,
    List<DocumentSearchHit> hits,
  ) {
    if (hits.length < 2) return hits;
    final terms = retrievalTokens(query).toSet();
    if (terms.isEmpty) return hits;

    final scored = <_ScoredHit>[];
    for (var index = 0; index < hits.length; index++) {
      final hit = hits[index];
      scored.add(
        _ScoredHit(
          hit: hit,
          score: _score(terms, query.toLowerCase(), hit),
          fusedRank: index,
        ),
      );
    }
    scored.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      if (byScore != 0) return byScore;
      // Ties keep the fused order: reranking refines, it does not shuffle.
      return a.fusedRank.compareTo(b.fusedRank);
    });

    return [
      for (var rank = 0; rank < scored.length; rank++)
        DocumentSearchHit(
          documentId: scored[rank].hit.documentId,
          documentName: scored[rank].hit.documentName,
          chunk: scored[rank].hit.chunk,
          score: scored[rank].score,
          matchedTerms: scored[rank].hit.matchedTerms,
          rankDetail:
              '${scored[rank].hit.rankDetail} · reranked #${rank + 1} '
              '(was #${scored[rank].fusedRank + 1})',
        ),
    ];
  }

  static double _score(
    Set<String> terms,
    String loweredQuery,
    DocumentSearchHit hit,
  ) {
    final text = hit.chunk.text.toLowerCase();
    final chunkTerms = retrievalTokens(hit.chunk.text).toSet();
    var score = 0.0;

    var covered = 0;
    for (final term in terms) {
      if (chunkTerms.contains(term)) covered++;
    }
    score += covered;

    // A chunk quoting the question back usually answers it: count whole
    // query phrases, longest first, without double-counting.
    var remaining = text;
    final phrases = _phrases(loweredQuery);
    for (final phrase in phrases) {
      if (phrase.contains(' ') && remaining.contains(phrase)) {
        score += phraseWeight;
        remaining = remaining.replaceFirst(phrase, ' ');
      }
    }

    final heading = hit.chunk.heading?.toLowerCase() ?? '';
    if (heading.isNotEmpty) {
      final headingTerms = retrievalTokens(heading).toSet();
      var headingHits = 0;
      for (final term in terms) {
        if (headingTerms.contains(term)) headingHits++;
      }
      score += headingHits * headingWeight;
    }

    // Shorter chunks that cover the same terms say more per line.
    if (score > 0 && chunkTerms.isNotEmpty) {
      score += covered / chunkTerms.length;
    }
    return score;
  }

  /// Candidate phrases of the query, longest first: the whole query when it
  /// holds several terms, then every adjacent pair.
  static List<String> _phrases(String loweredQuery) {
    final words = loweredQuery
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .toList(growable: false);
    if (words.length < 2) return const [];
    final phrases = <String>[words.join(' ')];
    for (var index = 0; index + 1 < words.length; index++) {
      phrases.add('${words[index]} ${words[index + 1]}');
    }
    return phrases;
  }
}

class _ScoredHit {
  const _ScoredHit({
    required this.hit,
    required this.score,
    required this.fusedRank,
  });

  final DocumentSearchHit hit;
  final double score;
  final int fusedRank;
}
