import 'package:flutter_test/flutter_test.dart';
import 'package:installm/features/model_selection/domain/llm_model.dart';
import 'package:installm/features/model_selection/domain/model_catalog_merge.dart';

LlmModel _model({
  required String id,
  required String name,
  required String repository,
  String? fileName,
  bool downloaded = false,
  String size = '1.5B',
}) {
  final file = fileName ?? '${id.toLowerCase()}-q4_k_m.gguf';
  return LlmModel(
    id: id,
    name: name,
    parameterSize: size,
    description: 'test model',
    downloadUrl: 'https://huggingface.co/$repository/resolve/main/$file',
    localFileName: file,
    isDownloaded: downloaded,
  );
}

void main() {
  test('the same quantization from two publishers stays two entries', () {
    // Qwen and a community re-quantization both ship a file called
    // `qwen2.5-1.5b-instruct-q4_k_m.gguf`. Same model, same size, same
    // quantization — different provenance, so both are offered.
    final catalog = _model(
      id: 'qwen-2.5-1.5b',
      name: 'Qwen 2.5',
      repository: 'Qwen/Qwen2.5-1.5B-Instruct-GGUF',
      fileName: 'qwen2.5-1.5b-instruct-q4_k_m.gguf',
    );
    final custom = _model(
      id: 'hfrepo-qwen',
      name: 'Qwen2.5-1.5B-Instruct-GGUF',
      repository: 'bartowski/Qwen2.5-1.5B-Instruct-GGUF',
      fileName: 'qwen2.5-1.5b-instruct-q4_k_m.gguf',
    );

    final merged = mergeModelSources(
      catalogModels: [catalog],
      discoveredModels: const [],
      customModels: [custom],
    );

    expect(merged.map((model) => model.id), ['qwen-2.5-1.5b', 'hfrepo-qwen']);
  });

  test('one quantization of one repository is one entry, catalog first', () {
    // A repository record keeps the repository's spelling while the catalog
    // writes the same file in lowercase; both name the one file it serves.
    final catalog = _model(
      id: 'qwen-2.5-1.5b',
      name: 'Qwen 2.5',
      repository: 'Qwen/Qwen2.5-1.5B-Instruct-GGUF',
      fileName: 'qwen2.5-1.5b-instruct-q4_k_m.gguf',
    );
    final custom = _model(
      id: 'hfrepo-qwen',
      name: 'Qwen2.5-1.5B-Instruct-GGUF',
      repository: 'Qwen/Qwen2.5-1.5B-Instruct-GGUF',
      fileName: 'Qwen2.5-1.5B-Instruct-Q4_K_M.gguf',
    );

    final merged = mergeModelSources(
      catalogModels: [catalog],
      discoveredModels: const [],
      customModels: [custom],
    );

    expect(merged, hasLength(1));
    expect(merged.single.id, 'qwen-2.5-1.5b');
    expect(merged.single.name, 'Qwen 2.5');
  });

  test('the record whose file is installed stands for that file', () {
    // Dropping the installed record would show a file that is on disk as not
    // installed, and its id would stop being the user's selected model.
    final catalog = _model(
      id: 'qwen-2.5-1.5b',
      name: 'Qwen 2.5',
      repository: 'Qwen/Qwen2.5-1.5B-Instruct-GGUF',
      fileName: 'qwen2.5-1.5b-instruct-q4_k_m.gguf',
    );
    final custom = _model(
      id: 'hfrepo-qwen',
      name: 'Qwen2.5-1.5B-Instruct-GGUF',
      repository: 'Qwen/Qwen2.5-1.5B-Instruct-GGUF',
      fileName: 'Qwen2.5-1.5B-Instruct-Q4_K_M.gguf',
      downloaded: true,
    );

    final merged = mergeModelSources(
      catalogModels: [catalog],
      discoveredModels: const [],
      customModels: [custom],
    );

    expect(merged.single.id, 'hfrepo-qwen');
    expect(merged.single.isDownloaded, isTrue);
  });

  test('different quantizations of one model stay separate choices', () {
    final catalog = _model(
      id: 'qwen-3-4b',
      name: 'Qwen 3 (Thinking)',
      repository: 'Qwen/Qwen3-4B-GGUF',
      fileName: 'qwen3-4b-q4_k_m.gguf',
      size: '4B',
    );
    final custom = _model(
      id: 'hfrepo-qwen-q8',
      name: 'Qwen3-4B-GGUF (Q8_0)',
      repository: 'Qwen/Qwen3-4B-GGUF',
      fileName: 'qwen3-4b-q8_0.gguf',
      size: '4B',
    );

    final merged = mergeModelSources(
      catalogModels: [catalog],
      discoveredModels: const [],
      customModels: [custom],
    );

    expect(merged.map((model) => model.id), ['qwen-3-4b', 'hfrepo-qwen-q8']);
  });

  test('republished copies of one discovered model collapse to one entry', () {
    // Discovery names a record after its repository without the publisher, so
    // five publishers of the same model arrive with one name and one size. The
    // list shows name and size, so five rows read as five duplicates.
    final catalog = _model(
      id: 'qwen-2.5-0.5b',
      name: 'Qwen 2.5',
      repository: 'Qwen/Qwen2.5-0.5B-Instruct-GGUF',
      fileName: 'qwen2.5-0.5b-instruct-q4_k_m.gguf',
      size: '0.5B',
    );
    LlmModel published(String publisher) => _model(
      id: 'hf-${publisher.toLowerCase()}-qwen25',
      name: 'Qwen2.5 0.5B Instruct',
      repository: '$publisher/Qwen2.5-0.5B-Instruct-GGUF',
      fileName: 'qwen2.5-0.5b-instruct-q4_k_m.gguf',
      size: '898M',
    );

    final merged = mergeModelSources(
      catalogModels: [catalog],
      discoveredModels: [
        published('bartowski'),
        published('lmstudio-community'),
        published('ThomasBaruzier'),
        published('Qwen'),
        published('second-state'),
      ],
      customModels: const [],
    );

    expect(merged, hasLength(1));
    expect(merged.single.id, 'qwen-2.5-0.5b');
  });

  test('a discovered copy of a file the catalog ships is dropped', () {
    // The community publisher is a different repository, but it serves the one
    // file the catalog already offers, so it would be a second row with the same
    // name and the same size and no way to tell them apart.
    final catalog = _model(
      id: 'qwen-2.5-0.5b',
      name: 'Qwen 2.5',
      repository: 'Qwen/Qwen2.5-0.5B-Instruct-GGUF',
      fileName: 'qwen2.5-0.5b-instruct-q4_k_m.gguf',
      size: '0.5B',
    );

    final merged = mergeModelSources(
      catalogModels: [catalog],
      discoveredModels: [
        _model(
          id: 'hf-bartowski-qwen',
          name: 'Qwen2.5 0.5B Instruct',
          repository: 'bartowski/Qwen2.5-0.5B-Instruct-GGUF',
          fileName: 'qwen2.5-0.5b-instruct-q4_k_m.gguf',
          size: '898M',
        ),
      ],
      customModels: const [],
    );

    expect(merged.map((model) => model.id), ['qwen-2.5-0.5b']);
  });

  test('a discovered model no catalog entry links to keeps one publisher', () {
    LlmModel published(String publisher, {bool downloaded = false}) => _model(
      id: 'hf-${publisher.toLowerCase()}-tiny',
      name: 'Tiny Model',
      repository: '$publisher/Tiny-GGUF',
      fileName: 'tiny-q4_k_m.gguf',
      size: '1B',
      downloaded: downloaded,
    );

    final merged = mergeModelSources(
      catalogModels: const [],
      discoveredModels: [
        published('first'),
        published('second'),
        published('third', downloaded: true),
      ],
      customModels: const [],
    );

    // The installed copy stands for the model when nothing is official.
    expect(merged.map((model) => model.id), ['hf-third-tiny']);
  });

  test('a name and a size that differ are different models', () {
    final merged = mergeModelSources(
      catalogModels: const [],
      discoveredModels: [
        _model(
          id: 'small',
          name: 'Qwen2.5 0.5B Instruct',
          repository: 'a/Qwen2.5-0.5B-Instruct-GGUF',
          fileName: 'small-q4_k_m.gguf',
          size: '898M',
        ),
        _model(
          id: 'large',
          name: 'Qwen2.5 0.5B Instruct',
          repository: 'b/Qwen2.5-0.5B-Instruct-GGUF',
          fileName: 'large-q4_k_m.gguf',
          size: '1.5B',
        ),
      ],
      customModels: const [],
    );

    expect(merged.map((model) => model.id), ['small', 'large']);
  });

  test('the catalog leads, then discovery, then what the user added', () {
    final merged = mergeModelSources(
      catalogModels: [
        _model(
          id: 'catalog',
          name: 'Catalog',
          repository: 'org/catalog',
          fileName: 'catalog.gguf',
        ),
      ],
      discoveredModels: [
        _model(
          id: 'found',
          name: 'Found',
          repository: 'org/found',
          fileName: 'found.gguf',
        ),
      ],
      customModels: [
        _model(
          id: 'mine',
          name: 'Mine',
          repository: 'org/mine',
          fileName: 'mine.gguf',
        ),
      ],
    );

    expect(merged.map((model) => model.id), ['catalog', 'found', 'mine']);
  });
}
