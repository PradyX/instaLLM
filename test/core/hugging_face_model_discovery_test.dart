import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:installm/core/services/hugging_face_model_discovery_service.dart';
import 'package:installm/features/model_selection/domain/llm_model.dart';

/// Answers Dio requests from a map of repository to metadata, and records every
/// request so a test can see which page it asked for.
class _FakeHuggingFace implements HttpClientAdapter {
  _FakeHuggingFace(this.repos, this.nextCursorByPipeline);

  final Map<String, Map<String, dynamic>> repos;
  final Map<String, String?> nextCursorByPipeline;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final pipeline = options.queryParameters['pipeline_tag'] as String?;

    if (options.path.startsWith('/api/models/')) {
      final id = options.path.substring('/api/models/'.length);
      return ResponseBody.fromString(
        jsonEncode(_detail(repos[id]!)),
        200,
        headers: _jsonHeaders,
      );
    }

    final items = repos.values
        .where((repo) => pipeline == null || repo['pipeline_tag'] == pipeline)
        .map(_listItem)
        .toList();
    final cursor = nextCursorByPipeline[pipeline ?? ''];
    return ResponseBody.fromString(
      jsonEncode(items),
      200,
      headers: {
        ..._jsonHeaders,
        if (cursor != null)
          'link': [
            '<https://huggingface.co/api/models?cursor=$cursor>; rel="next"',
          ],
      },
    );
  }

  @override
  void close({bool force = false}) {}

  static const _jsonHeaders = {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  };

  static Map<String, dynamic> _listItem(Map<String, dynamic> repo) => {
    'id': repo['id'],
    'downloads': repo['downloads'],
    'pipeline_tag': repo['pipeline_tag'],
    'tags': repo['tags'],
  };

  static Map<String, dynamic> _detail(Map<String, dynamic> repo) => {
    'id': repo['id'],
    'siblings': [
      for (final file in repo['_files'] as List<String>) {'rfilename': file},
    ],
    'gguf': {'architecture': repo['_architecture'], 'total': repo['_total']},
  };
}

Map<String, dynamic> _repo({
  required String id,
  required int downloads,
  String pipeline = 'text-generation',
  List<String> files = const ['Model-Q4_K_M.gguf', 'Model-F16.gguf'],
  String architecture = 'llama',
  int total = 4 * 1000 * 1000 * 1000,
}) {
  return {
    'id': id,
    'downloads': downloads,
    'pipeline_tag': pipeline,
    'tags': ['gguf', pipeline],
    '_files': files,
    '_architecture': architecture,
    '_total': total,
  };
}

({HuggingFaceModelDiscoveryService service, _FakeHuggingFace adapter}) _service(
  Map<String, Map<String, dynamic>> repos, {
  Map<String, String?> nextCursorByPipeline = const {},
}) {
  final adapter = _FakeHuggingFace(repos, nextCursorByPipeline);
  final dio = Dio(BaseOptions(baseUrl: 'https://huggingface.co'))
    ..httpClientAdapter = adapter;
  return (
    service: HuggingFaceModelDiscoveryService(dio: dio),
    adapter: adapter,
  );
}

void main() {
  test('the app ships no model list of its own', () {
    expect(LlmModel.availableModels, isEmpty);
  });

  test('a page merges both pipelines, most downloaded first', () async {
    final fake = _service(
      {
        'a/Alpha-GGUF': _repo(id: 'a/Alpha-GGUF', downloads: 100),
        'b/Beta-GGUF': _repo(id: 'b/Beta-GGUF', downloads: 50),
        'v/Vision-GGUF': _repo(
          id: 'v/Vision-GGUF',
          downloads: 10,
          pipeline: 'image-text-to-text',
        ),
      },
      nextCursorByPipeline: {
        'text-generation': 'text-next',
        'image-text-to-text': 'vision-next',
      },
    );

    final page = await fake.service.load();

    expect(page.models.map((model) => model.name), ['Alpha', 'Beta', 'Vision']);
    expect(page.hasMore, isTrue);
    expect(page.nextCursor, isNotNull);
    // Every discovered record says where it came from.
    expect(
      page.models.map((model) => model.modelSource),
      everyElement(ModelSource.discovered),
    );
  });

  test('the next page continues each pipeline from its own cursor', () async {
    final fake = _service(
      {'a/Alpha-GGUF': _repo(id: 'a/Alpha-GGUF', downloads: 100)},
      nextCursorByPipeline: {
        'text-generation': 'text-next',
        'image-text-to-text': 'vision-next',
      },
    );

    Map<String?, Object?> cursorsAndPipelines() => {
      for (final request in fake.adapter.requests)
        if (request.path == '/api/models')
          request.queryParameters['pipeline_tag']:
              request.queryParameters['cursor'],
    };

    final first = await fake.service.load();
    expect(cursorsAndPipelines(), {
      'text-generation': null,
      'image-text-to-text': null,
    });

    fake.adapter.requests.clear();
    await fake.service.load(cursor: first.nextCursor);

    expect(cursorsAndPipelines(), {
      'text-generation': 'text-next',
      'image-text-to-text': 'vision-next',
    });
  });

  test(
    'a record takes its size from the model name, not the file bytes',
    () async {
      final fake = _service({
        'LiquidAI/LFM2.5-350M-GGUF': _repo(
          id: 'LiquidAI/LFM2.5-350M-GGUF',
          downloads: 12,
          files: [
            'LFM2.5-350M-F16.gguf',
            'LFM2.5-350M-Q4_K_M.gguf',
            'LFM2.5-350M-Q8_0.gguf',
          ],
          architecture: 'lfm2',
        ),
        'Qwen/Qwen2.5-1.5B-Instruct-GGUF': _repo(
          id: 'Qwen/Qwen2.5-1.5B-Instruct-GGUF',
          downloads: 11,
          files: ['qwen2.5-1.5b-instruct-q4_k_m.gguf'],
        ),
      });

      final page = await fake.service.load();
      final byName = {for (final model in page.models) model.name: model};

      expect(byName['LFM2.5 350M']!.parameterSize, '350M');
      expect(byName['Qwen2.5 1.5B Instruct']!.parameterSize, '1.5B');
      // Q4_K_M is preferred over the larger F16 the repository also lists.
      expect(byName['LFM2.5 350M']!.localFileName, 'lfm2.5-350m-q4_k_m.gguf');
    },
  );

  test('the end of the list says so', () async {
    final fake = _service({
      'a/Only-GGUF': _repo(id: 'a/Only-GGUF', downloads: 1),
    });

    final page = await fake.service.load();
    expect(page.hasMore, isFalse);
    expect(page.nextCursor, isNull);
  });

  test('a repository with no readable GGUF file is left out', () async {
    final fake = _service({
      'a/NoFiles-GGUF': _repo(
        id: 'a/NoFiles-GGUF',
        downloads: 5,
        files: ['README.md'],
      ),
    });

    final page = await fake.service.load();
    expect(page.models, isEmpty);
  });
}
