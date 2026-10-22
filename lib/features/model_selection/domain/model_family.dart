import 'package:installm/features/model_selection/domain/gguf_metadata.dart';
import 'package:installm/features/model_selection/domain/llm_model.dart';
import 'package:installm/features/model_selection/domain/model_compatibility.dart';

/// One downloadable file in a family: a parameter size, a quantization and the
/// catalog entry that carries it.
///
/// The catalog lists entries, not relationships: `SmolLM2 360M` and `SmolLM2
/// 1.7B` are separate records with no link between them, and the quantization
/// exists only inside the file name. This class recovers both so the page can
/// present a family and the choices inside it.
class ModelVariant {
  const ModelVariant({
    required this.model,
    required this.quantization,
    required this.quantizationIsRead,
    required this.parameterCount,
  });

  final LlmModel model;

  /// Read from the file's own GGUF metadata when it is installed, otherwise
  /// parsed from the file name. Null when neither carries one.
  final String? quantization;

  /// Whether [quantization] came from the GGUF file rather than its name.
  final bool quantizationIsRead;

  /// Parameters in billions; `360M` is 0.36. `double.infinity` when the
  /// parameter size is not a number this app recognises.
  final double parameterCount;

  String get id => model.id;
  String get parameterSize => model.parameterSize;
  bool get isInstalled => model.isDownloaded;

  /// `400 MB`-style size reported by the file's own metadata, when installed
  /// and parsed. Null before download, when nothing on disk knows the size.
  int? get fileSizeBytes => model.ggufMetadata?.fileSizeBytes;

  /// Roughly how large this variant's file is, before it is downloaded.
  ///
  /// llama.cpp stores about [`bitsPerWeight`] bits for every parameter plus a
  /// few percent of tensor and header overhead, so a declared parameter count
  /// and the quantization name are enough to say "about 1.1 GB". That is an
  /// estimate for choosing *between* variants; the exact size always comes
  /// from the installed file's own GGUF metadata when there is one.
  ///
  /// Null when the quantization is unknown or the parameter size is not a
  /// number this app recognises, so callers show nothing instead of a guess.
  ///
  /// Accuracy is around ±20%: the smallest models read low, because their
  /// embeddings and tokenizer are a larger share of the file than their
  /// parameter count alone suggests.
  int? get approximateFileSizeBytes {
    final quantization = this.quantization;
    final bits = quantization == null ? null : _bitsPerWeight[quantization];
    if (bits == null || !parameterCount.isFinite || parameterCount <= 0) {
      return null;
    }
    final weights = parameterCount * 1e9 * (bits / 8);
    return (weights * _ggufTensorOverhead).round();
  }

  /// `1.5B · Q4_K_M`, or just the size when no quantization is known.
  String get label =>
      quantization == null ? parameterSize : '$parameterSize · $quantization';

  /// Bits per parameter llama.cpp spends on the weights of each quantization,
  /// the k-quants being mixed precision and therefore not whole numbers.
  static const Map<String, double> _bitsPerWeight = {
    'F32': 32,
    'F16': 16,
    'BF16': 16,
    'Q8_0': 8.5,
    'Q6_K': 6.5625,
    'Q5_K_M': 5.5,
    'Q5_K_S': 5.5,
    'Q5_0': 5.5,
    'Q4_K_M': 4.85,
    'Q4_K_S': 4.6,
    'Q4_0': 4.5,
    'Q3_K_M': 3.5,
    'Q3_K_S': 3.4375,
    'Q2_K': 2.625,
    'Q2_K_S': 2.5625,
    'IQ4_XS': 4.25,
    'IQ3_XXS': 3.0625,
    'IQ3_S': 3.4375,
    'IQ3_M': 3.66,
    'IQ2_S': 2.5,
    'IQ2_M': 2.7,
    'IQ2_XXS': 2.0625,
  };

  /// Tensor, alignment and header bytes GGUF adds around the weights.
  static const double _ggufTensorOverhead = 1.08;
}

/// Rough fit rating for a variant whose file was never downloaded.
///
/// The pane's own estimate needs the real file on disk; this one takes a
/// variant's declared parameter count and quantization — the same
/// approximately ±20% size estimate used to choose between variants — and
/// rates what it implies against the device's memory budget, so a family whose
/// members differ only in size can show *why* one is worth downloading
/// rather than another.
///
/// The KV cache comes from [kvCacheMetadata], which the caller sets to the
/// family's one installed member when there is one: sharing an architecture's
/// attention shapes is far more reliable than guessing here, and quantized
/// siblings share them.
///
/// Null when nothing is known about the variant's size or the device's memory.
ModelCompatibilityRating? variantFitRating(
  ModelVariant variant, {
  required GgufMetadata? kvCacheMetadata,
  required int contextTokens,
  int? totalMemoryBytes,
  int? availableMemoryBytes,
}) {
  final weights = variant.fileSizeBytes ?? variant.approximateFileSizeBytes;
  if (weights == null || weights <= 0) return null;
  final budget = ModelCompatibilityEstimator.memoryBudget(
    totalMemoryBytes: totalMemoryBytes,
    availableMemoryBytes: availableMemoryBytes,
  );
  if (budget == null || budget <= 0) return null;
  final overhead =
      ModelCompatibilityEstimator.runtimeOverheadBaseBytes +
      (weights * ModelCompatibilityEstimator.runtimeOverheadWeightsFraction)
          .round();
  final kvCache = kvCacheMetadata == null
      ? 0
      : ModelCompatibilityEstimator.kvCacheBytes(
          kvCacheMetadata,
          contextTokens,
        );
  return ModelCompatibilityEstimator.ratingFor(
    weights + overhead + kvCache,
    budget,
  );
}

/// How a family's best-fitting variant is expected to run, as an index into
/// [ModelCompatibilityRating]'s values (0 = recommended, -1 = unknown).
///
/// The list's "best fit" sort uses this: the largest model that is expected
/// to run comfortably stands first. Ratings come from the same estimate the
/// variant selector shows — the variant's estimated or on-disk size against
/// the device's memory budget — so this is a ranking aid, not a guarantee.
///
/// -1 when the variant sizes or the device budget answer nothing: a family
/// whose weights are unknown, or a device whose memory is unknown, cannot be
/// ranked against its neighbours.
int familyFitRank(
  ModelFamily family, {
  required int contextTokens,
  int? totalMemoryBytes,
  int? availableMemoryBytes,
}) {
  // Siblings share an architecture, so one member's GGUF metadata supplies
  // the KV-cache shape for the family's estimates — the same shortcut the
  // variant selector takes.
  GgufMetadata? kvCacheMetadata;
  for (final variant in family.variants) {
    final metadata = variant.model.ggufMetadata;
    if (metadata != null) {
      kvCacheMetadata = metadata;
      break;
    }
  }

  var best = -1;
  for (final variant in family.variants) {
    final rating = variantFitRating(
      variant,
      kvCacheMetadata: kvCacheMetadata,
      contextTokens: contextTokens,
      totalMemoryBytes: totalMemoryBytes,
      availableMemoryBytes: availableMemoryBytes,
    );
    if (rating == null) continue;
    if (rating.index == 0) return 0;
    if (rating.index > best) best = rating.index;
  }
  return best;
}

/// Sorts [families] so the families that are expected to run comfortably on
/// this device come first, the biggest of those first — "the best model that
/// still fits".
///
/// Ranks come from [familyFitRank], so a family whose weights or the device
/// budget cannot be estimated gets no rank, and no rank means *last*: an
/// unknown cost must never read as a good one. Families with the same rank
/// prefer the larger parameter count, because at the same expected fit the
/// bigger model is the more capable one; unranked families fall back to the
/// plain parameter-size order instead. With [installedFirst] the families the
/// user already has still jump ahead of everything ranked.
void sortFamiliesByFit(
  List<ModelFamily> families, {
  required int contextTokens,
  int? totalMemoryBytes,
  int? availableMemoryBytes,
  required bool installedFirst,
}) {
  final ranks = <String, int>{};
  for (final family in families) {
    ranks[family.key] = familyFitRank(
      family,
      contextTokens: contextTokens,
      totalMemoryBytes: totalMemoryBytes,
      availableMemoryBytes: availableMemoryBytes,
    );
  }

  // Unranked reads worst, above every known rating: the worst rating says
  // "this will not fit", which is more informative than "we cannot tell".
  int normalized(String key) {
    final rank = ranks[key];
    return rank == null || rank < 0
        ? ModelCompatibilityRating.values.length
        : rank;
  }

  String nameCompare(ModelFamily family) => family.displayName.toLowerCase();

  families.sort((a, b) {
    if (installedFirst) {
      final byInstalled = (b.hasInstalled ? 1 : 0).compareTo(
        a.hasInstalled ? 1 : 0,
      );
      if (byInstalled != 0) return byInstalled;
    }
    final byFit = normalized(a.key).compareTo(normalized(b.key));
    if (byFit != 0) return byFit;
    if ((ranks[a.key] ?? -1) >= 0) {
      final byBigger = b.lightest.parameterCount.compareTo(
        a.lightest.parameterCount,
      );
      if (byBigger != 0) return byBigger;
      return nameCompare(a).compareTo(nameCompare(b));
    }
    // Unranked: nobody knows the cost, so keep the parameter-size order.
    final bySize = a.lightest.parameterCount.compareTo(
      b.lightest.parameterCount,
    );
    if (bySize != 0) return bySize;
    return nameCompare(a).compareTo(nameCompare(b));
  });
}

/// A model family: one name shared by one or more variants.
class ModelFamily {
  const ModelFamily({
    required this.key,
    required this.displayName,
    required this.variants,
    required this.capabilities,
  });

  /// Stable grouping key (the name's tokens, normalized and sorted).
  final String key;

  /// The name to show; the most common spelling among the variants.
  final String displayName;

  /// Sorted smallest parameter count first, then best quantization first.
  final List<ModelVariant> variants;

  /// Union of the variants' capabilities, in enum order.
  final List<ModelCapability> capabilities;

  int get variantCount => variants.length;

  int get installedCount =>
      variants.where((variant) => variant.isInstalled).length;

  bool get hasInstalled => installedCount > 0;

  /// The lightest variant: the one most likely to run on a small device.
  ModelVariant get lightest => variants.first;

  /// `360M – 1.7B` when the family spans sizes, `1B` when it does not.
  String get parameterRange {
    final sizes = variants.map((variant) => variant.parameterSize).toList();
    final distinct = <String>[];
    for (final size in sizes) {
      if (!distinct.contains(size)) distinct.add(size);
    }
    if (distinct.length == 1) return distinct.first;
    return '${distinct.first} – ${distinct.last}';
  }
}

/// Groups catalog entries into families and reads their quantizations.
class ModelFamilies {
  const ModelFamilies._();

  /// Groups [models] by family name, dropping nothing.
  ///
  /// The name is compared as a set of normalized tokens, so the catalog's own
  /// inconsistent spellings of one family (`Qwen 2.5 Coder` and `Qwen Coder
  /// 2.5`) land in the same group. `IMat` names (importance-matrix
  /// quantization, a quantization method rather than a different model) drop
  /// the token, so `Qwen2 5B IMat` joins `Qwen2 5B` as more variants to pick
  /// between. Names that carry a training variant in parentheses
  /// (`DeepSeek Coder (Base)` versus `(Instruct)`) stay separate, because they
  /// are different models rather than different sizes of one.
  static List<ModelFamily> group(List<LlmModel> models) {
    final grouped = <String, List<ModelVariant>>{};
    final names = <String, List<String>>{};

    for (final model in models) {
      final key = familyKey(model.name);
      final quantization = quantizationOf(model);
      grouped
          .putIfAbsent(key, () => <ModelVariant>[])
          .add(
            ModelVariant(
              model: model,
              quantization: quantization,
              quantizationIsRead:
                  model.ggufMetadata?.quantization.trim().isNotEmpty ?? false,
              parameterCount: parameterCountOf(model.parameterSize),
            ),
          );
      names.putIfAbsent(key, () => <String>[]).add(_cleanName(model.name));
    }

    final families = <ModelFamily>[];
    for (final entry in grouped.entries) {
      final variants = entry.value..sort(_compareVariants);
      families.add(
        ModelFamily(
          key: entry.key,
          displayName: _mostCommonName(names[entry.key] ?? const []),
          variants: List.unmodifiable(variants),
          capabilities: _unionCapabilities(variants),
        ),
      );
    }
    families.sort((a, b) {
      final bySize = a.lightest.parameterCount.compareTo(
        b.lightest.parameterCount,
      );
      if (bySize != 0) return bySize;
      return a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
    });
    return families;
  }

  /// The grouping key for a model name.
  ///
  /// `imat`, a quantization-method marker, is dropped wherever it appears, so
  /// those files group with the plain spelling of their family.
  static String familyKey(String name) {
    final tokens = _tokens(name).where((token) => token != 'imat').toList()
      ..sort();
    return tokens.isEmpty ? _cleanName(name).toLowerCase() : tokens.join('|');
  }

  /// The quantization this model is stored or published as.
  ///
  /// The installed file's own GGUF metadata wins, because it is what the
  /// runtime loads; otherwise the file name is read, since a catalog entry
  /// that has not been downloaded has nothing else to go on.
  static String? quantizationOf(LlmModel model) {
    final fromMetadata = model.ggufMetadata?.quantization.trim();
    if (fromMetadata != null && fromMetadata.isNotEmpty) {
      final normalized = _normalizeQuantization(fromMetadata);
      if (normalized != null) return normalized;
    }
    for (final source in [model.localFileName, model.downloadUrl]) {
      final parsed = _quantizationFromText(source);
      if (parsed != null) return parsed;
    }
    return null;
  }

  /// Parameters in billions from a size label such as `1.5B`, `360M` or `7B`.
  static double parameterCountOf(String parameterSize) {
    final match = RegExp(
      r'^([0-9]*\.?[0-9]+)\s*([KMBT]?)$',
    ).firstMatch(parameterSize.trim().toUpperCase());
    if (match == null) return double.infinity;
    final number = double.tryParse(match.group(1) ?? '');
    if (number == null) return double.infinity;
    return switch (match.group(2) ?? '') {
      'K' => number / 1e6,
      'M' => number / 1e3,
      'B' => number,
      'T' => number * 1e3,
      _ => number / 1e9,
    };
  }

  /// Quantization labels the runtime knows, best quality first.
  static const List<String> knownQuantizations = [
    'F32',
    'F16',
    'BF16',
    'Q8_0',
    'Q6_K',
    'Q5_K_M',
    'Q5_K_S',
    'Q5_0',
    'Q4_K_M',
    'Q4_K_S',
    'Q4_0',
    'Q3_K_M',
    'Q3_K_S',
    'Q2_K',
    'Q2_K_S',
    'IQ4_XS',
    'IQ3_XXS',
    'IQ2_XXS',
  ];

  static int _quantizationRank(String quantization) {
    final index = knownQuantizations.indexOf(quantization);
    if (index >= 0) return index;
    // Unknown labels sort after every known one rather than disappearing.
    return knownQuantizations.length;
  }

  static int _compareVariants(ModelVariant a, ModelVariant b) {
    final bySize = a.parameterCount.compareTo(b.parameterCount);
    if (bySize != 0) return bySize;
    final aQuant = a.quantization;
    final bQuant = b.quantization;
    if (aQuant != null && bQuant != null) {
      final byQuality = _quantizationRank(
        aQuant,
      ).compareTo(_quantizationRank(bQuant));
      if (byQuality != 0) return byQuality;
    } else if (aQuant == null && bQuant != null) {
      return 1;
    } else if (aQuant != null) {
      return -1;
    }
    return a.model.id.compareTo(b.model.id);
  }

  static List<ModelCapability> _unionCapabilities(List<ModelVariant> variants) {
    final found = <ModelCapability>{};
    for (final variant in variants) {
      found.addAll(variant.model.capabilities);
    }
    return ModelCapability.values.where(found.contains).toList(growable: false);
  }

  /// `Qwen 3 (Thinking)` for the family row; the parenthetical is dropped when
  /// the same family also has a plain spelling, so the heading stays short.
  static String _mostCommonName(List<String> names) {
    if (names.isEmpty) return '';
    final counts = <String, int>{};
    for (final name in names) {
      counts[name] = (counts[name] ?? 0) + 1;
    }
    final ranked = counts.entries.toList()
      ..sort((a, b) {
        final byCount = b.value.compareTo(a.value);
        if (byCount != 0) return byCount;
        return a.key.length.compareTo(b.key.length);
      });
    return ranked.first.key;
  }

  static String _cleanName(String name) => name.trim();

  /// Letters, digits and inner dots: `2.5` stays one token, `Q4_K_M` in a name
  /// does not leak into the family key because names here are model names.
  static Iterable<String> _tokens(String name) sync* {
    for (final raw in name.toLowerCase().split(RegExp(r'[^a-z0-9.]+'))) {
      final token = raw.replaceAll(RegExp(r'^\.+|\.+$'), '');
      if (token.isNotEmpty) yield token;
    }
  }

  /// Finds a quantization label inside a file name or URL.
  static String? _quantizationFromText(String? text) {
    if (text == null || text.trim().isEmpty) return null;
    final decoded = Uri.decodeFull(text);
    final file = decoded.split('/').last;
    for (final match in RegExp(
      r'(?:^|[^a-z0-9])((?:iq|q)[0-9]+(?:_[a-z0-9]+)*|f16|f32|bf16)',
      caseSensitive: false,
    ).allMatches(file)) {
      final normalized = _normalizeQuantization(match.group(1) ?? '');
      if (normalized != null) return normalized;
    }
    return null;
  }

  /// `q4_k_m` to `Q4_K_M`, and `F16` left as it is. Returns null for anything
  /// that is not a quantization label, so `qwen2` never reads as `Q2`.
  static String? _normalizeQuantization(String value) {
    final upper = value.trim().toUpperCase();
    if (upper.isEmpty) return null;
    if (knownQuantizations.contains(upper)) return upper;
    final match = RegExp(
      r'^(IQ|Q|F|BF)([0-9]+)(?:_([A-Z0-9]+(?:_[A-Z0-9]+)*))?$',
    ).firstMatch(upper);
    if (match == null) return null;
    return upper;
  }
}
