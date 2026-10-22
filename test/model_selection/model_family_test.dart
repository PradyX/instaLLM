import 'package:flutter_test/flutter_test.dart';
import 'package:installm/features/model_selection/domain/gguf_metadata.dart';
import 'package:installm/features/model_selection/domain/llm_model.dart';
import 'package:installm/features/model_selection/domain/model_compatibility.dart';
import 'package:installm/features/model_selection/domain/model_family.dart';

/// The catalog is the data this grouping exists for, so the records below use
/// its real file names and sizes rather than invented ones.
LlmModel _catalogModel(
  String id,
  String name,
  String parameterSize, {
  String? localFileName,
  String? downloadUrl,
  List<ModelCapability> capabilities = const [],
  bool isDownloaded = false,
  GgufMetadata? ggufMetadata,
}) {
  return LlmModel(
    id: id,
    name: name,
    parameterSize: parameterSize,
    description: 'Description for $name',
    capabilities: capabilities,
    localFileName: localFileName,
    downloadUrl: downloadUrl,
    isDownloaded: isDownloaded,
    ggufMetadata: ggufMetadata,
  );
}

GgufMetadata _metadata({
  required String quantization,
  int fileSizeBytes = 486 * 1024 * 1024,
  String architecture = 'qwen3',
}) {
  return GgufMetadata(
    architecture: architecture,
    name: 'test.gguf',
    version: 3,
    kvCount: 20,
    tensorCount: 200,
    fileSizeBytes: fileSizeBytes,
    parameterCount: 596049920,
    quantization: quantization,
  );
}

void main() {
  group('quantizationOf', () {
    test('reads the quantization out of a catalog file name', () {
      final model = _catalogModel(
        'smollm2-360m',
        'SmolLM2',
        '360M',
        localFileName: 'smollm2-360m-instruct-q4_k_m.gguf',
      );
      expect(ModelFamilies.quantizationOf(model), 'Q4_K_M');
    });

    test('reads it out of the URL when there is no local file name', () {
      final model = _catalogModel(
        'llama-3.2-1b',
        'Llama 3.2',
        '1B',
        downloadUrl:
            'https://huggingface.co/bartowski/Llama-3.2-1B-Instruct-GGUF/'
            'resolve/main/Llama-3.2-1B-Instruct-Q8_0.gguf',
      );
      expect(ModelFamilies.quantizationOf(model), 'Q8_0');
    });

    test('a model name is never mistaken for a quantization', () {
      final model = _catalogModel(
        'qwen-2.5-0.5b',
        'Qwen 2.5',
        '0.5B',
        localFileName: 'qwen2.5-0.5b-instruct',
      );
      expect(ModelFamilies.quantizationOf(model), isNull);
    });

    test('the installed file wins over its own name', () {
      final model = _catalogModel(
        'qwen-3-0.6b',
        'Qwen 3 (Thinking)',
        '0.6B',
        localFileName: 'qwen3-0.6b-q4_k_m.gguf',
        isDownloaded: true,
        ggufMetadata: _metadata(quantization: 'Q8_0'),
      );
      final variant = ModelFamilies.group([model]).single.variants.single;

      expect(variant.quantization, 'Q8_0');
      expect(variant.quantizationIsRead, isTrue);
    });

    test('a variant with no quantization keeps its size as its label', () {
      final model = _catalogModel(
        'imported',
        'Imported',
        '3B',
        localFileName: 'mystery.gguf',
      );
      final variant = ModelFamilies.group([model]).single.variants.single;

      expect(variant.quantization, isNull);
      expect(variant.label, '3B');
    });
  });

  group('familyKey', () {
    test('the catalog\'s two spellings of one family land together', () {
      expect(
        ModelFamilies.familyKey('Qwen 2.5 Coder'),
        ModelFamilies.familyKey('Qwen Coder 2.5'),
      );
    });

    test('case and spacing do not separate a family', () {
      expect(
        ModelFamilies.familyKey('  smolLM2 '),
        ModelFamilies.familyKey('SmolLM2'),
      );
    });

    test('different training variants stay separate', () {
      expect(
        ModelFamilies.familyKey('DeepSeek Coder (Base)'),
        isNot(ModelFamilies.familyKey('DeepSeek Coder (Instruct)')),
      );
      expect(
        ModelFamilies.familyKey('DeepSeek R1 Distill Qwen'),
        isNot(ModelFamilies.familyKey('DeepSeek R1 ReDistill Qwen')),
      );
    });

    test('IMat repackages group with the plain spelling of their family', () {
      expect(
        ModelFamilies.familyKey('Qwen2 0.5B IMat'),
        ModelFamilies.familyKey('Qwen2 0.5B'),
      );
      expect(
        ModelFamilies.familyKey('Qwen2 0.5B Instruct IMAT'),
        ModelFamilies.familyKey('Qwen2 0.5B Instruct'),
      );

      final merged = ModelFamilies.group([
        _catalogModel('qwen2-base', 'Qwen2 0.5B', '0.5B'),
        _catalogModel('qwen2-imat', 'Qwen2 0.5B IMat', '0.5B'),
        _catalogModel('qwen2-instruct', 'Qwen2 0.5B Instruct', '0.5B'),
      ]);
      expect(merged, hasLength(2));
      final base = merged.singleWhere(
        (family) => !family.displayName.contains('Instruct'),
      );
      expect(base.displayName, 'Qwen2 0.5B');
      expect(base.variantCount, 2);
      // A training variant still keeps its own row.
      final instruct = merged.singleWhere(
        (family) => family.displayName.contains('Instruct'),
      );
      expect(instruct.variantCount, 1);
    });
  });

  group('parameterCountOf', () {
    test('reads sizes the catalog uses', () {
      expect(ModelFamilies.parameterCountOf('360M'), closeTo(0.36, 1e-9));
      expect(ModelFamilies.parameterCountOf('1.5B'), 1.5);
      expect(ModelFamilies.parameterCountOf('7B'), 7);
      expect(ModelFamilies.parameterCountOf('33M'), closeTo(0.033, 1e-9));
    });

    test('an unrecognised size sorts last instead of throwing', () {
      expect(ModelFamilies.parameterCountOf('Unknown'), double.infinity);
      expect(ModelFamilies.parameterCountOf(''), double.infinity);
    });
  });

  group('approximateFileSizeBytes', () {
    ModelVariant variant(
      String parameterSize, {
      String? localFileName,
      GgufMetadata? ggufMetadata,
    }) {
      final models = ModelFamilies.group([
        _catalogModel(
          'subject',
          'Subject',
          parameterSize,
          localFileName: localFileName,
          ggufMetadata: ggufMetadata,
        ),
      ]);
      return models.single.variants.single;
    }

    test('lands near the real file of a known catalog entry', () {
      // SmolLM2 1.7B Q4_K_M is 1.06 GB on the hub; the estimate has to be
      // close enough to choose between variants with it.
      final size = variant(
        '1.7B',
        localFileName: 'smollm2-1.7b-instruct-q4_k_m.gguf',
      ).approximateFileSizeBytes;

      expect(size, isNotNull);
      expect(size!, inInclusiveRange(950 * 1000 * 1000, 1250 * 1000 * 1000));
    });

    test('a heavier quantization estimates a larger file', () {
      final q4 = variant(
        '7B',
        localFileName: 'example-7b-q4_k_m.gguf',
      ).approximateFileSizeBytes!;
      final q8 = variant(
        '7B',
        localFileName: 'example-7b-q8_0.gguf',
      ).approximateFileSizeBytes!;

      expect(q8, greaterThan(q4));
    });

    test('grows with the parameter count', () {
      final small = variant(
        '1.5B',
        localFileName: 'example-1.5b-q4_k_m.gguf',
      ).approximateFileSizeBytes!;
      final large = variant(
        '7B',
        localFileName: 'example-7b-q4_k_m.gguf',
      ).approximateFileSizeBytes!;

      expect(large, greaterThan(small));
    });

    test('claims nothing without a quantization or a readable size', () {
      expect(
        variant(
          '4B',
          localFileName: 'example-4b-mystery.gguf',
        ).approximateFileSizeBytes,
        isNull,
      );
      expect(
        variant(
          'Unknown',
          localFileName: 'example-q4_k_m.gguf',
        ).approximateFileSizeBytes,
        isNull,
      );
    });

    test('the installed file still wins over the estimate', () {
      final installed = variant(
        '1.7B',
        localFileName: 'smollm2-1.7b-instruct-q4_k_m.gguf',
        ggufMetadata: _metadata(
          quantization: 'Q4_K_M',
          fileSizeBytes: 1060000000,
        ),
      );

      expect(installed.fileSizeBytes, 1060000000);
      expect(installed.approximateFileSizeBytes, isNot(1060000000));
    });
  });

  group('group', () {
    test('sorts variants smallest first and better quantizations first', () {
      final families = ModelFamilies.group([
        _catalogModel(
          'qwen-3-1.7b',
          'Qwen 3 (Thinking)',
          '1.7B',
          localFileName: 'qwen3-1.7b-q4_k_m.gguf',
        ),
        _catalogModel(
          'qwen-3-0.6b-q8',
          'Qwen 3 (Thinking)',
          '0.6B',
          localFileName: 'qwen3-0.6b-q8_0.gguf',
        ),
        _catalogModel(
          'qwen-3-0.6b-q4',
          'Qwen 3 (Thinking)',
          '0.6B',
          localFileName: 'qwen3-0.6b-q4_k_m.gguf',
        ),
      ]);

      final family = families.single;
      expect(family.variants.map((variant) => variant.label).toList(), [
        '0.6B · Q8_0',
        '0.6B · Q4_K_M',
        '1.7B · Q4_K_M',
      ]);
    });

    test('summarizes a family that spans sizes', () {
      final families = ModelFamilies.group([
        _catalogModel(
          'smollm2-360m',
          'SmolLM2',
          '360M',
          localFileName: 'smollm2-360m-instruct-q4_k_m.gguf',
          isDownloaded: true,
        ),
        _catalogModel(
          'smollm2-1.7b',
          'SmolLM2',
          '1.7B',
          localFileName: 'smollm2-1.7b-instruct-q4_k_m.gguf',
        ),
      ]);

      final family = families.single;
      expect(family.displayName, 'SmolLM2');
      expect(family.parameterRange, '360M – 1.7B');
      expect(family.variantCount, 2);
      expect(family.installedCount, 1);
      expect(family.hasInstalled, isTrue);
      expect(family.lightest.parameterSize, '360M');
    });

    test('lists a family once even when its name is spelled differently', () {
      final families = ModelFamilies.group([
        _catalogModel(
          'qwen-2.5-coder-0.5b',
          'Qwen 2.5 Coder',
          '0.5B',
          localFileName: 'qwen2.5-coder-0.5b-instruct-q4_k_m.gguf',
        ),
        _catalogModel(
          'qwen-coder-2.5-1.5b',
          'Qwen Coder 2.5',
          '1.5B',
          localFileName: 'qwen2.5-coder-1.5b-instruct-q4_k_m.gguf',
        ),
      ]);

      expect(families, hasLength(1));
      expect(families.single.variantCount, 2);
    });

    test('unions capabilities in enum order', () {
      final families = ModelFamilies.group([
        _catalogModel(
          'a',
          'Mixed',
          '1B',
          capabilities: const [ModelCapability.tools],
        ),
        _catalogModel(
          'b',
          'Mixed',
          '3B',
          capabilities: const [ModelCapability.vision, ModelCapability.tools],
        ),
      ]);

      expect(families.single.capabilities, const [
        ModelCapability.vision,
        ModelCapability.tools,
      ]);
    });

    test('orders families by their lightest variant', () {
      final families = ModelFamilies.group([
        _catalogModel('big', 'Gemma 2', '2B'),
        _catalogModel('small', 'SmolLM2', '360M'),
      ]);

      expect(families.map((family) => family.displayName).toList(), [
        'SmolLM2',
        'Gemma 2',
      ]);
    });

    test('groups the real catalog without losing or inventing a model', () {
      final families = ModelFamilies.group(LlmModel.availableModels);
      final grouped = families
          .expand((family) => family.variants)
          .map((variant) => variant.id)
          .toList();

      expect(grouped, hasLength(LlmModel.availableModels.length));
      expect(grouped.toSet(), hasLength(LlmModel.availableModels.length));
      expect(
        families
            .firstWhere((family) => family.displayName == 'SmolLM2')
            .variantCount,
        2,
      );
      // The catalog spells this family two ways; both spellings resolve to one
      // family, and all four of its files sit inside it.
      final coderFamily = families.firstWhere(
        (family) => family.variants.any((v) => v.id == 'qwen-2.5-coder-0.5b'),
      );
      expect(coderFamily.variantCount, 4);
      expect(
        coderFamily.variants.map((variant) => variant.model.name).toSet(),
        {'Qwen 2.5 Coder', 'Qwen Coder 2.5'},
      );
    });
  });

  group('familyFitRank', () {
    const smallDeviceBytes = 2 * 1024 * 1024 * 1024;
    const largeDeviceBytes = 24 * 1024 * 1024 * 1024;

    ModelFamily family(String name, String parameterSize) {
      return ModelFamilies.group([
        _catalogModel(
          name.toLowerCase().replaceAll(' ', '-'),
          name,
          parameterSize,
          downloadUrl:
              'https://example/${name.replaceAll(' ', '-')}-q4_k_m.gguf',
        ),
      ]).single;
    }

    test('the smallest comfortable family ranks ahead of one that does not '
        'fit', () {
      final small = family('Qwen S', '0.6B');
      final large = family('Qwen XL', '30B');

      expect(
        familyFitRank(
          small,
          contextTokens: 4096,
          totalMemoryBytes: smallDeviceBytes,
        ),
        lessThan(
          familyFitRank(
            large,
            contextTokens: 4096,
            totalMemoryBytes: smallDeviceBytes,
          ),
        ),
      );
    });

    test('a device with no known memory rates nothing', () {
      expect(familyFitRank(family('Qwen S', '0.6B'), contextTokens: 4096), -1);
    });

    test('a family whose weights have no size estimate rates nothing', () {
      final unknown = ModelFamilies.group([
        _catalogModel('mystery', 'Mystery', 'Unknown'),
      ]).single;

      expect(
        familyFitRank(
          unknown,
          contextTokens: 4096,
          totalMemoryBytes: largeDeviceBytes,
        ),
        -1,
      );
    });

    test('sortFamiliesByFit sells rated families before unranked ones', () {
      final ratedComfortable = ModelFamilies.group([
        _catalogModel(
          'small',
          'Small',
          '0.6B',
          downloadUrl: 'https://example/small-q4_k_m.gguf',
        ),
      ]).single;
      final ratedNeverFits = ModelFamilies.group([
        _catalogModel(
          'huge',
          'Huge',
          '583.2B',
          downloadUrl: 'https://example/huge-iq2_m.gguf',
        ),
      ]).single;
      final unrated = ModelFamilies.group([
        _catalogModel('mystery', 'Mystery', 'Unknown'),
      ]).single;

      final families = [unrated, ratedNeverFits, ratedComfortable];
      sortFamiliesByFit(
        families,
        contextTokens: 4096,
        totalMemoryBytes: smallDeviceBytes,
        installedFirst: false,
      );

      // Comfortable first; a family that will certainly not fit is still
      // better described than an unknown; the unknown comes last, before it
      // used to come first — that order was the whole bug.
      expect(families.map((family) => family.lightest.model.id).toList(), [
        'small',
        'huge',
        'mystery',
      ]);
    });

    test('families ranking equally prefer the larger model', () {
      final oneB = ModelFamilies.group([
        _catalogModel(
          'one-b',
          'Suite One',
          '1B',
          downloadUrl: 'https://example/one-b-q4_k_m.gguf',
        ),
      ]).single;
      final fourB = ModelFamilies.group([
        _catalogModel(
          'four-b',
          'Suite Four',
          '4B',
          downloadUrl: 'https://example/four-b-q4_k_m.gguf',
        ),
      ]).single;

      final families = [oneB, fourB];
      sortFamiliesByFit(
        families,
        contextTokens: 4096,
        totalMemoryBytes: largeDeviceBytes,
        installedFirst: false,
      );

      // Both fit the large device comfortably; the more capable model leads.
      expect(families.map((family) => family.lightest.model.id).toList(), [
        'four-b',
        'one-b',
      ]);
    });

    test('IQ2 weights get a size estimate from the bits-per-weight table', () {
      final iq2mFamily = ModelFamilies.group([
        _catalogModel(
          'iq2m',
          'IQ2 Model',
          '583.2B',
          downloadUrl: 'https://example/hf/glm-iq2_m-00001-of-00003.gguf',
        ),
      ]).single;

      // 583.2B at ~2.7 bits per weight is ~200 GB — a ranked "will not fit",
      // not "unknown".
      expect(
        familyFitRank(
          iq2mFamily,
          contextTokens: 4096,
          totalMemoryBytes: smallDeviceBytes,
        ),
        ModelCompatibilityRating.notRecommended.index,
      );
    });
  });

  group('variantFitRating', () {
    // 2 GB of RAM means a 1.2 GB app budget (60% of the total).
    const smallDeviceBytes = 2 * 1024 * 1024 * 1024;
    // 24 GB of RAM means a 14.4 GB app budget.
    const largeDeviceBytes = 24 * 1024 * 1024 * 1024;
    const contextTokens = 4096;

    GgufMetadata kvMetadata({
      int layers = 24,
      int heads = 16,
      int embedding = 2048,
    }) {
      return GgufMetadata(
        architecture: 'qwen3',
        name: 'kv.gguf',
        version: 3,
        kvCount: 20,
        tensorCount: 200,
        fileSizeBytes: 486 * 1024 * 1024,
        parameterCount: 596049920,
        quantization: 'Q4_K_M',
        blockCount: layers,
        embeddingLength: embedding,
        numericScalars: {'qwen3.attention.head_count': heads},
      );
    }

    test('rates the smallest variant as comfortable on a big device', () {
      final variant = ModelFamilies.group([
        _catalogModel(
          'v1',
          'Qwen S',
          '1B',
          downloadUrl: 'https://example/qwen-s-1b-q4_k_m.gguf',
        ),
      ]).single.lightest;

      expect(
        variantFitRating(
          variant,
          kvCacheMetadata: null,
          contextTokens: contextTokens,
          totalMemoryBytes: largeDeviceBytes,
        ),
        ModelCompatibilityRating.recommended,
      );
    });

    test('rates a heavy variant beyond a small device', () {
      final variant = ModelFamilies.group([
        _catalogModel(
          'v2',
          'Qwen S',
          '100B',
          downloadUrl: 'https://example/qwen-s-100b-q8_0.gguf',
        ),
      ]).single.lightest;

      expect(
        variantFitRating(
          variant,
          kvCacheMetadata: null,
          contextTokens: contextTokens,
          totalMemoryBytes: largeDeviceBytes,
        ),
        ModelCompatibilityRating.notRecommended,
      );
    });

    test('the KV cache of a shared architecture changes the rating', () {
      LlmModel model(String id) => _catalogModel(
        id,
        'Qwen S',
        '1B',
        downloadUrl: 'https://example/qwen-s-1b-q4_k_m.gguf',
      );

      final family = ModelFamilies.group([model('a'), model('b')]).single;

      // 24 layers × 16 heads × 128 head dim at 4 KiB per token pair: the
      // aforementioned single-member KV cache, small enough to leave the
      // rating unchanged.
      expect(
        variantFitRating(
          family.lightest,
          kvCacheMetadata: kvMetadata(),
          contextTokens: contextTokens,
          totalMemoryBytes: smallDeviceBytes,
        ),
        isNotNull,
      );

      // 300 layers × 64 heads × 128 head dim: an absurdly large attention
      // shape must sink the rating, proving the cache is actually counted.
      expect(
        variantFitRating(
          family.lightest,
          kvCacheMetadata: kvMetadata(layers: 300, heads: 64, embedding: 8192),
          contextTokens: contextTokens,
          totalMemoryBytes: smallDeviceBytes,
        ),
        ModelCompatibilityRating.notRecommended,
      );
    });

    test('null without a size to rate or a budget to rate against', () {
      // The imported model has no quantization to estimate a file size from.
      final unknown = ModelFamilies.group([
        _catalogModel('x', 'Imported', '3B', localFileName: 'mystery.gguf'),
      ]).single.lightest;
      expect(
        variantFitRating(
          unknown,
          kvCacheMetadata: null,
          contextTokens: contextTokens,
          totalMemoryBytes: largeDeviceBytes,
        ),
        isNull,
      );

      // A known size is unrated when the device reports no memory at all.
      final known = ModelFamilies.group([
        _catalogModel(
          'y',
          'Qwen S',
          '1B',
          downloadUrl: 'https://example/qwen-s-1b-q4_k_m.gguf',
        ),
      ]).single.lightest;
      expect(
        variantFitRating(
          known,
          kvCacheMetadata: null,
          contextTokens: contextTokens,
        ),
        isNull,
      );
    });
  });
}
