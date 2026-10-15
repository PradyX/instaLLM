/// Per-collection retrieval tuning (Road Map 3 Phase 3.4, retrieval tuning).
///
/// How a knowledge collection answers: the balance between its lexical and
/// vector channels, whether a local re-score runs over the fused candidates,
/// and whether a small collection is sent whole instead of top-k.
///
/// Every field has the value that reproduces the untuned behaviour, so a
/// collection stored before tuning existed answers exactly as it always has:
/// equal fusion weights, no rerank, ranked top-k context.
class RetrievalTuning {
  const RetrievalTuning({
    this.lexicalWeight = 1,
    this.vectorWeight = 1,
    this.rerankEnabled = false,
    this.fullDocumentContext = false,
  });

  /// Weight of the lexical channel in reciprocal-rank fusion.
  ///
  /// Zero removes the channel from the fused ranking; equal weights reproduce
  /// the untuned fusion.
  final double lexicalWeight;

  /// Weight of the vector channel in reciprocal-rank fusion.
  final double vectorWeight;

  /// Whether fused candidates pass through the local reranker before the
  /// prompt sees them. Pure Dart, no download, deterministic.
  final bool rerankEnabled;

  /// Whether a small collection is sent whole (every chunk in document order)
  /// instead of the top-k ranked hits. Collections past
  /// [RetrievalTuningLimits.maxFullContextChunks] chunks always rank.
  final bool fullDocumentContext;

  /// Bounds for the weights a user can set.
  static const double minWeight = 0;
  static const double maxWeight = 4;

  RetrievalTuning copyWith({
    double? lexicalWeight,
    double? vectorWeight,
    bool? rerankEnabled,
    bool? fullDocumentContext,
  }) {
    return RetrievalTuning(
      lexicalWeight: lexicalWeight ?? this.lexicalWeight,
      vectorWeight: vectorWeight ?? this.vectorWeight,
      rerankEnabled: rerankEnabled ?? this.rerankEnabled,
      fullDocumentContext: fullDocumentContext ?? this.fullDocumentContext,
    );
  }

  /// Weights clamped to their bounds; switches kept as set.
  RetrievalTuning normalized() {
    return RetrievalTuning(
      lexicalWeight: lexicalWeight.clamp(minWeight, maxWeight),
      vectorWeight: vectorWeight.clamp(minWeight, maxWeight),
      rerankEnabled: rerankEnabled,
      fullDocumentContext: fullDocumentContext,
    );
  }

  Map<String, dynamic> toJson() => {
    'lexicalWeight': lexicalWeight,
    'vectorWeight': vectorWeight,
    'rerankEnabled': rerankEnabled,
    'fullDocumentContext': fullDocumentContext,
  };

  /// Parses stored tuning, or the untuned default when [raw] is missing,
  /// corrupt, or from before tuning existed — never null, never throwing.
  static RetrievalTuning fromJson(Object? raw) {
    if (raw is! Map) return const RetrievalTuning();
    final map = Map<String, dynamic>.from(raw);
    // A stored weight of the wrong type is corrupt data, not a crash: fall
    // back to the untuned default the same way a missing key does.
    final lexical = map['lexicalWeight'];
    final vector = map['vectorWeight'];
    return RetrievalTuning(
      lexicalWeight: lexical is num
          ? lexical.toDouble()
          : const RetrievalTuning().lexicalWeight,
      vectorWeight: vector is num
          ? vector.toDouble()
          : const RetrievalTuning().vectorWeight,
      rerankEnabled: map['rerankEnabled'] == true,
      fullDocumentContext: map['fullDocumentContext'] == true,
    ).normalized();
  }
}

/// Bounds that keep one full-context prompt honest.
abstract final class RetrievalTuningLimits {
  /// Collections with more chunks than this always rank rather than sending
  /// everything, however the switch is set.
  static const int maxFullContextChunks = 200;
}
