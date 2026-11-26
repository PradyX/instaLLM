import 'package:flutter_test/flutter_test.dart';
import 'package:installm/features/model_selection/domain/llm_model.dart';
import 'package:installm/features/model_selection/domain/model_family.dart';

/// Sizes measured by probing each release with a ranged request on
/// 2026-11-26 (the GGUF `content-length`), so the estimate the ledger shows can
/// be checked against the file that is really served.
const Map<String, int> _probedBytes = {
  'lfm2-350m': 229309376,
  'lfm2-1.2b': 730893248,
  'minicpm3-4b': 2469791584,
};

LlmModel _byId(String id) => LlmModel.availableModels.firstWhere(
  (model) => model.id == id,
  orElse: () => throw StateError('the catalog has no entry for $id'),
);

ModelVariant _variantOf(String id) {
  for (final family in ModelFamilies.group(LlmModel.availableModels)) {
    for (final variant in family.variants) {
      if (variant.id == id) return variant;
    }
  }
  throw StateError('no variant for $id');
}

void main() {
  test('Liquid AI LFM2 and MiniCPM3 are offered for download', () {
    for (final id in ['lfm2-350m', 'lfm2-1.2b', 'minicpm3-4b']) {
      final model = _byId(id);
      final url = model.downloadUrl;
      expect(url, isNotNull, reason: '$id must be downloadable');
      expect(url, startsWith('https://huggingface.co/'));
      expect(url, endsWith('.gguf'));
      expect(model.localFileName, isNotNull);
      expect(model.localFileName, endsWith('.gguf'));
      expect(model.description, isNotEmpty);
      // Neither model carries a catalog capability claim: LFM2 is text chat,
      // and MiniCPM3's file declares no tool or vision metadata. A badge here
      // would promise something the file cannot do.
      expect(model.capabilities, isEmpty, reason: id);
      expect(model.isEmbeddingModel, isFalse);
    }
  });

  test('each new entry downloads the file that was probed and run', () {
    // Pinned on purpose: the byte counts above are only meaningful for these
    // exact files, so changing a URL has to mean probing the new one.
    const probedUrls = {
      'lfm2-350m':
          'https://huggingface.co/LiquidAI/LFM2-350M-GGUF/resolve/main/LFM2-350M-Q4_K_M.gguf',
      'lfm2-1.2b':
          'https://huggingface.co/LiquidAI/LFM2-1.2B-GGUF/resolve/main/LFM2-1.2B-Q4_K_M.gguf',
      'minicpm3-4b':
          'https://huggingface.co/openbmb/MiniCPM3-4B-GGUF/resolve/main/minicpm3-4b-q4_k_m.gguf',
    };
    for (final entry in probedUrls.entries) {
      expect(_byId(entry.key).downloadUrl, entry.value, reason: entry.key);
    }
  });

  test('one family per parameter size: the two LFM2 sizes stay apart', () {
    // A family is a name at one size; only quantizations of that size belong
    // together. Merging sizes made a row promise a file it would not download.
    final families = ModelFamilies.group(LlmModel.availableModels);
    final lfm2 = families
        .where((family) => family.key.contains('lfm2'))
        .toList();
    expect(lfm2, hasLength(2), reason: '350M and 1.2B are different models');
    expect(lfm2.map((family) => family.parameterRange).toSet(), {
      '350M',
      '1.2B',
    });
    for (final family in lfm2) {
      expect(family.variants, hasLength(1));
      expect(family.variants.single.parameterSize, family.parameterRange);
    }

    final minicpm = families.where((family) => family.key.contains('minicpm'));
    expect(minicpm, hasLength(1));
  });

  test('each new entry shows a size before it is downloaded', () {
    for (final entry in _probedBytes.entries) {
      final variant = _variantOf(entry.key);
      expect(variant.quantization, 'Q4_K_M', reason: entry.key);
      final estimate = variant.approximateFileSizeBytes;
      expect(estimate, isNotNull, reason: '${entry.key} must show a size');
      // The estimate is documented as roughly ±20%; hold it to that, because
      // these three numbers were measured rather than guessed.
      expect(
        estimate,
        inInclusiveRange(entry.value * 0.8, entry.value * 1.2),
        reason: '${entry.key} estimate $estimate vs probed ${entry.value}',
      );
    }
  });

  test('a file whose quantization cannot be read shows no size', () {
    const unknown = LlmModel(
      id: 'unreadable-quant',
      name: 'Unknown',
      parameterSize: '1B',
      description: 'no quantization in the name',
      downloadUrl: 'https://huggingface.co/example/model.gguf',
      localFileName: 'model.gguf',
    );
    final families = ModelFamilies.group(const [unknown]);
    expect(families.single.variants.single.quantization, isNull);
    expect(families.single.variants.single.approximateFileSizeBytes, isNull);
  });

  test('every catalog entry is a distinct downloadable gguf', () {
    final ids = <String>{};
    for (final model in LlmModel.availableModels) {
      expect(ids.add(model.id), isTrue, reason: 'duplicate id ${model.id}');
      expect(model.name, isNotEmpty);
      expect(model.parameterSize, isNotEmpty);
      expect(model.description, isNotEmpty);
      final url = model.downloadUrl;
      expect(url, startsWith('https://'), reason: model.id);
      expect(url, endsWith('.gguf'), reason: model.id);
    }
  });
}
