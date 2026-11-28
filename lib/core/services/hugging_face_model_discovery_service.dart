import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:installm/features/model_selection/domain/llm_model.dart';
import 'package:installm/storage/secure_storage.dart';

/// One page of the model list Hugging Face serves.
///
/// [nextCursor] is null at the end of the list. The cursor is the service's own
/// encoding of one cursor per pipeline, because Hugging Face paginates each
/// pipeline separately and this service merges both into one list.
class HuggingFaceModelCatalog {
  const HuggingFaceModelCatalog({
    required this.models,
    required this.nextCursor,
    required this.hasMore,
    this.failed = false,
    this.rateLimited = false,
  });

  final List<LlmModel> models;
  final String? nextCursor;
  final bool hasMore;

  /// True when the read failed, so an empty page is not mistaken for the end
  /// of the catalog.
  final bool failed;

  /// True when the failure was Hugging Face refusing to serve more for a
  /// while, which is worth saying plainly instead of "check the connection".
  final bool rateLimited;

  static const empty = HuggingFaceModelCatalog(
    models: [],
    nextCursor: null,
    hasMore: false,
  );

  /// A page that could not be read. It still has more to offer, so the caller
  /// keeps its cursor instead of ending the list.
  static const failedPage = HuggingFaceModelCatalog(
    models: [],
    nextCursor: null,
    hasMore: true,
    failed: true,
  );

  /// A page refused because the request limit was reached. It is still a
  /// failure rather than the end of the list.
  static const rateLimitedPage = HuggingFaceModelCatalog(
    models: [],
    nextCursor: null,
    hasMore: true,
    failed: true,
    rateLimited: true,
  );
}

/// Builds the model list from Hugging Face instead of a list compiled into the
/// app.
///
/// The runtime it ships can load any architecture llama.cpp registers, so the
/// catalog is not a list of approved models: it is every GGUF repository Hugging
/// Face reports for text generation, readable a page at a time. A repository
/// that asks for a file this app cannot pick is skipped; a repository whose
/// architecture the runtime does not know fails at load with the runtime's own
/// message, the same as a file imported from storage.
///
/// Results with no search query are cached on disk, so a launch without a
/// network still shows the last catalog. Pages loaded past the first are cached
/// too, together with the cursor that continues from them.
class HuggingFaceModelDiscoveryService {
  // v2: pages now carry their files and GGUF headers, so a cached page from
  // v1 has neither and its cursor belongs to a different request.
  static const _cacheKey = 'hf_discovered_models_cache_v2';
  static const _cacheTtl = Duration(days: 7);

  /// Repositories read per pipeline per page. Two pipelines are read, so one
  /// page is at most twice this many repositories.
  static const _perPipelineLimit = 25;

  /// Pipeline tags we consider usable for on-device chat inference.
  static const _allowedPipelines = {'text-generation', 'image-text-to-text'};

  /// Preferred GGUF quantization suffixes, in priority order.
  static const _preferredQuantSuffixes = [
    'Q4_K_M.gguf',
    'Q4_K_S.gguf',
    'Q4_0.gguf',
    'Q5_K_M.gguf',
    'Q3_K_M.gguf',
    'Q8_0.gguf',
  ];

  HuggingFaceModelDiscoveryService({Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              baseUrl: 'https://huggingface.co',
              connectTimeout: const Duration(seconds: 20),
              receiveTimeout: const Duration(seconds: 20),
              headers: const {'Accept': 'application/json'},
            ),
          );

  final Dio _dio;

  /// The catalog as it was last written to disk, or null when nothing is
  /// cached. Reading it costs no network.
  Future<HuggingFaceModelCatalog?> readCachedCatalog() async {
    final cache = await _readCache();
    if (cache == null) return null;
    return HuggingFaceModelCatalog(
      models: cache.models,
      nextCursor: cache.nextCursor,
      hasMore: cache.nextCursor != null,
    );
  }

  /// Whether the cache is stale and should be refreshed.
  Future<bool> isCacheStale() async {
    final cache = await _readCache();
    if (cache == null) return true;
    return DateTime.now().difference(cache.fetchedAt) > _cacheTtl;
  }

  /// Reads one page of GGUF chat models, most downloaded first.
  ///
  /// [query] narrows the page with Hugging Face's own search, so a model the
  /// app has never seen is one query away. [cursor] continues a page the caller
  /// already read; null starts at the top.
  ///
  /// Search results are not cached: they are an answer to what the user typed,
  /// and the default list is what a launch without a network should show.
  ///
  /// [parameterRange] is a `num_parameters` range such as `min:0,max:1B`, read
  /// by Hugging Face itself. Paging a range gives a page full of models that
  /// size instead of hoping the download order happens to reach them.
  Future<HuggingFaceModelCatalog> load({
    String query = '',
    String? cursor,
    String? parameterRange,
  }) async {
    final trimmedQuery = query.trim();
    try {
      final raw = <_RawHfModel>[];
      final seen = <String>{};
      final nextCursors = <String, String?>{};

      var failedPipelines = 0;
      var rateLimited = false;
      for (final pipeline in _allowedPipelines) {
        final page = await _fetchPage(
          pipeline: pipeline,
          query: trimmedQuery,
          cursor: _cursorFor(cursor, pipeline),
          parameterRange: parameterRange,
        );
        if (page.failed) failedPipelines++;
        if (page.rateLimited) rateLimited = true;
        nextCursors[pipeline] = page.nextCursor;
        for (final model in page.models) {
          if (seen.add(model.repoId)) raw.add(model);
        }
      }

      if (raw.isEmpty) {
        if (rateLimited) return HuggingFaceModelCatalog.rateLimitedPage;
        return failedPipelines == _allowedPipelines.length
            ? HuggingFaceModelCatalog.failedPage
            : HuggingFaceModelCatalog.empty;
      }
      raw.sort((a, b) => b.downloads.compareTo(a.downloads));

      final discovered = <LlmModel>[];
      for (final batch in _chunk(raw, 5)) {
        final results = await Future.wait(
          batch.map((model) => _resolveModelDetail(model)),
        );
        discovered.addAll(results.whereType<LlmModel>());
      }

      final catalog = HuggingFaceModelCatalog(
        models: discovered,
        nextCursor: _encodeCursors(nextCursors),
        hasMore: nextCursors.values.any((value) => value != null),
      );

      // A filtered page is not the catalog: caching it would leave the next
      // launch showing one bucket as if it were everything.
      if (trimmedQuery.isEmpty && parameterRange == null) {
        await _cachePage(catalog, replace: cursor == null);
      }
      return catalog;
    } catch (error) {
      debugPrint('Catalog read failed: $error');
      return HuggingFaceModelCatalog.failedPage;
    }
  }

  // ---------------------------------------------------------------------------
  // API calls
  // ---------------------------------------------------------------------------

  Future<
    ({
      List<_RawHfModel> models,
      String? nextCursor,
      bool failed,
      bool rateLimited,
    })
  >
  _fetchPage({
    required String pipeline,
    required String query,
    required String? cursor,
    String? parameterRange,
  }) async {
    final models = <_RawHfModel>[];
    String? nextCursor;
    var failed = false;
    var rateLimited = false;
    try {
      final queryParams = <String, dynamic>{
        'filter': 'gguf',
        'sort': 'downloads',
        'direction': '-1',
        'limit': _perPipelineLimit,
        'pipeline_tag': pipeline,
        // The file list and the GGUF header arrive with the page, so reading
        // fifty models costs two requests instead of fifty-two. Hugging Face
        // rate-limited the old per-model reads as soon as a few pages loaded.
        'expand[]': ['tags', 'siblings', 'gguf'],
      };
      if (query.isNotEmpty) queryParams['search'] = query;
      if (parameterRange != null) {
        queryParams['num_parameters'] = parameterRange;
      }
      if (cursor != null && cursor.isNotEmpty) queryParams['cursor'] = cursor;

      final response = await _dio.get(
        '/api/models',
        queryParameters: queryParams,
      );
      nextCursor = _nextCursorFromLink(response.headers.value('link'));

      final data = response.data;
      if (data is List) {
        for (final item in data) {
          final map = item is Map ? Map<String, dynamic>.from(item) : null;
          if (map == null) continue;
          final raw = _RawHfModel.fromListJson(map, pipeline: pipeline);
          if (raw.repoId.isNotEmpty &&
              _allowedPipelines.contains(raw.pipelineTag)) {
            models.add(raw);
          }
        }
      }
    } catch (error) {
      failed = true;
      rateLimited = error is DioException && error.response?.statusCode == 429;
      // A wrong cursor answers 400 and would otherwise look like the end of
      // the list.
      debugPrint('Catalog page failed for $pipeline: $error');
    }
    return (
      models: models,
      nextCursor: nextCursor,
      failed: failed,
      rateLimited: rateLimited,
    );
  }

  /// The `cursor` of the `rel="next"` link Hugging Face returns, if any.
  ///
  /// Read from the raw header rather than through [Uri.queryParameters],
  /// which turns a `+` in the base64 cursor into a space and corrupts it.
  static String? _nextCursorFromLink(String? link) {
    if (link == null || link.isEmpty) return null;
    final next = RegExp(r'<([^>]+)>;\s*rel="next"').firstMatch(link)?.group(1);
    if (next == null) return null;
    final cursor = RegExp(r'[?&]cursor=([^&]+)').firstMatch(next)?.group(1);
    if (cursor == null) return null;
    // The link carries the cursor already percent-encoded, and Dio encodes the
    // value again when it builds the next request: a `%3D` would go out as
    // `%253D` and Hugging Face answers 400. Decode once here so every caller
    // holds the cursor itself, not its URL spelling.
    return _decodeCursor(cursor);
  }

  static String? _decodeCursor(String cursor) {
    try {
      return Uri.decodeComponent(cursor);
    } on FormatException {
      return cursor;
    }
  }

  /// The cursor this pipeline had reached, from the combined cursor.
  static String? _cursorFor(String? combined, String pipeline) {
    if (combined == null || combined.isEmpty) return null;
    for (final part in combined.split('||')) {
      final separator = part.indexOf('|');
      if (separator <= 0) continue;
      if (part.substring(0, separator) == pipeline) {
        // Cursors cached by an earlier build were stored in their URL spelling.
        final cursor = _decodeCursor(part.substring(separator + 1));
        return cursor == null || cursor.isEmpty ? null : cursor;
      }
    }
    return null;
  }

  /// One cursor per pipeline, joined. A pipeline with no further page is left
  /// out; the whole string is null when none has one.
  static String? _encodeCursors(Map<String, String?> cursors) {
    final parts = [
      for (final entry in cursors.entries)
        if (entry.value != null && entry.value!.isNotEmpty)
          '${entry.key}|${entry.value}',
    ];
    return parts.isEmpty ? null : parts.join('||');
  }

  Future<LlmModel?> _resolveModelDetail(_RawHfModel raw) async {
    // The page already carries what the detail endpoint would answer.
    if (raw.siblings.isNotEmpty) {
      return _parseModelFromDetail(raw, {
        'siblings': [
          for (final file in raw.siblings) {'rfilename': file},
        ],
        'gguf': raw.gguf,
      });
    }
    try {
      final response = await _dio.get('/api/models/${raw.repoId}');
      final data = response.data;
      final json = data is Map<String, dynamic>
          ? data
          : data is Map
          ? Map<String, dynamic>.from(data)
          : data is String
          ? jsonDecode(data) as Map<String, dynamic>
          : null;
      if (json == null) return null;

      return _parseModelFromDetail(raw, json);
    } catch (_) {
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // Model parsing
  // ---------------------------------------------------------------------------

  LlmModel? _parseModelFromDetail(
    _RawHfModel raw,
    Map<String, dynamic> detailJson,
  ) {
    // Extract siblings (files in the repo).
    final siblings = <String>[];
    final rawSiblings = detailJson['siblings'];
    if (rawSiblings is List) {
      for (final sibling in rawSiblings) {
        final filename = sibling is Map ? sibling['rfilename'] : null;
        if (filename is String && filename.trim().isNotEmpty) {
          siblings.add(filename);
        }
      }
    }

    // Find the best GGUF file (Q4_K_M preferred).
    final ggufFile = _pickBestGgufFile(siblings);
    if (ggufFile == null) return null;

    // Detect mmproj file for vision models.
    final mmprojFile = siblings
        .where(
          (f) =>
              f.toLowerCase().contains('mmproj') &&
              f.toLowerCase().endsWith('.gguf'),
        )
        .cast<String?>()
        .firstOrNull;

    // Build download URLs.
    final downloadUrl =
        'https://huggingface.co/${raw.repoId}/resolve/main/$ggufFile';
    final mmprojDownloadUrl = mmprojFile != null
        ? 'https://huggingface.co/${raw.repoId}/resolve/main/$mmprojFile'
        : null;

    // Extract GGUF metadata.
    final ggufMeta = detailJson['gguf'];
    final architecture = ggufMeta is Map
        ? (ggufMeta['architecture'] ?? '').toString().toLowerCase()
        : '';
    final totalBytes = ggufMeta is Map ? ggufMeta['total'] : null;

    // Derive prompt format from architecture.
    final promptFormatId = promptFormatForArchitecture(architecture);

    // The model name is what the list shows; its parameter count is written in
    // it more reliably than it can be estimated from a quantized file's size.
    final name = _deriveModelName(raw.repoId, architecture);
    final parameterSize = _parameterSizeFor(
      repoId: raw.repoId,
      fileName: ggufFile,
      totalBytes: totalBytes,
    );

    // Derive capabilities from tags + pipeline.
    final capabilities = _deriveCapabilities(raw.tags, raw.pipelineTag);

    // Build description.
    final description = _buildDescription(raw, capabilities, architecture);

    final localFileName = ggufFile.toLowerCase();
    final id = 'hf-${raw.repoId.replaceAll('/', '-').toLowerCase()}';

    return LlmModel(
      id: id,
      name: name,
      parameterSize: parameterSize,
      description: description,
      capabilities: capabilities,
      downloadUrl: downloadUrl,
      localFileName: localFileName,
      mmprojDownloadUrl: mmprojDownloadUrl,
      mmprojLocalFileName: mmprojFile?.toLowerCase(),
      promptFormatId: promptFormatId,
      modelSource: ModelSource.discovered,
    );
  }

  String? _pickBestGgufFile(List<String> siblings) {
    final ggufFiles = siblings
        .where(
          (f) =>
              f.toLowerCase().endsWith('.gguf') &&
              !f.toLowerCase().contains('mmproj'),
        )
        .toList();
    if (ggufFiles.isEmpty) return null;

    // Try preferred quantizations in order.
    for (final suffix in _preferredQuantSuffixes) {
      final match = ggufFiles
          .where((f) => f.toUpperCase().endsWith(suffix.toUpperCase()))
          .cast<String?>()
          .firstOrNull;
      if (match != null) return match;
    }

    // Fallback: pick the first GGUF that isn't f16 (too large).
    final nonF16 = ggufFiles
        .where((f) => !f.toLowerCase().contains('f16'))
        .cast<String?>()
        .firstOrNull;
    return nonF16 ?? ggufFiles.first;
  }

  static String promptFormatForArchitecture(String architecture) {
    return switch (architecture) {
      'gemma3' => 'gemma3',
      _ => 'chatml',
    };
  }

  /// `350M`, `1.2B` and so on, read from the file name first and the repository
  /// name second, falling back to the byte-count estimate.
  ///
  /// The names are what the model's own publisher wrote; the estimate exists
  /// only for a repository that declares neither.
  static String _parameterSizeFor({
    required String repoId,
    required String fileName,
    required dynamic totalBytes,
  }) {
    return parameterSizeIn(fileName) ??
        parameterSizeIn(repoId) ??
        _estimateParameterSize(totalBytes);
  }

  /// The first `<number><M|B|T>` in [text], normalised.
  ///
  /// `Qwen2.5-1.5B-Instruct` answers `1.5B`; the `2.5` before a dash is skipped
  /// because it is not followed by a unit. Public so a record cached or
  /// persisted by a build that estimated the count from file bytes can read it
  /// again from the name it already carries.
  static String? parameterSizeIn(String? text) {
    if (text == null) return null;
    for (final match in RegExp(
      r'(\d+(?:\.\d+)?)\s*([MmBbTt])(?![A-Za-z0-9])',
    ).allMatches(text)) {
      final value = double.tryParse(match.group(1)!);
      if (value == null || value <= 0) continue;
      return '${match.group(1)}${match.group(2)!.toUpperCase()}';
    }
    return null;
  }

  static String _estimateParameterSize(dynamic totalBytes) {
    if (totalBytes is! int || totalBytes <= 0) return 'Unknown';

    // Q4_K_M is roughly 0.55 bytes per parameter.
    // Total GGUF bytes ≈ params × 0.55, so params ≈ total / 0.55.
    final estimatedParams = totalBytes / 0.55;

    if (estimatedParams >= 1e12) {
      return '${(estimatedParams / 1e12).toStringAsFixed(1)}T';
    }
    if (estimatedParams >= 1e9) {
      return '${(estimatedParams / 1e9).toStringAsFixed(1)}B';
    }
    if (estimatedParams >= 1e6) {
      return '${(estimatedParams / 1e6).toStringAsFixed(0)}M';
    }
    return 'Unknown';
  }

  List<ModelCapability> _deriveCapabilities(
    Set<String> tags,
    String pipelineTag,
  ) {
    final capabilities = <ModelCapability>{};
    final allSignals = {...tags, pipelineTag}.map((t) => t.toLowerCase());
    final seedText = allSignals.join(' ');

    // Vision
    if (tags.any(
          (t) => const {
            'multimodal',
            'vision',
            'image-text-to-text',
            'visual-question-answering',
          }.contains(t.toLowerCase()),
        ) ||
        pipelineTag.toLowerCase().contains('image') ||
        pipelineTag.toLowerCase().contains('vision')) {
      capabilities.add(ModelCapability.vision);
    }

    // Coding
    if (RegExp(r'\b(coder|coding|code)\b').hasMatch(seedText)) {
      capabilities.add(ModelCapability.coding);
    }

    // Thinking / Reasoning
    if (RegExp(r'\b(thinking|reasoner|qwq)\b').hasMatch(seedText) ||
        RegExp(r'\br1\b').hasMatch(seedText)) {
      capabilities.add(ModelCapability.thinking);
    }

    // Tools
    if (tags.any(
      (t) => const {
        'tools',
        'tool-use',
        'tool_use',
        'function-calling',
        'function_calling',
      }.contains(t.toLowerCase()),
    )) {
      capabilities.add(ModelCapability.tools);
    }

    return ModelCapability.values
        .where(capabilities.contains)
        .toList(growable: false);
  }

  String _deriveModelName(String repoId, String architecture) {
    // Use the repo name (after the slash), clean up suffixes like -GGUF.
    final repoName = repoId.contains('/') ? repoId.split('/').last : repoId;
    var name = repoName
        .replaceAll(RegExp(r'-GGUF$', caseSensitive: false), '')
        .replaceAll(RegExp(r'_GGUF$', caseSensitive: false), '')
        .replaceAll('_', ' ')
        .replaceAll('-', ' ');

    // Trim excessive whitespace.
    name = name.replaceAll(RegExp(r'\s+'), ' ').trim();
    return name.isEmpty ? repoId : name;
  }

  String _buildDescription(
    _RawHfModel raw,
    List<ModelCapability> capabilities,
    String architecture,
  ) {
    final parts = <String>[];
    if (raw.downloads > 0) {
      parts.add('${_formatDownloads(raw.downloads)} downloads');
    }
    if (architecture.isNotEmpty) parts.add(architecture);
    if (capabilities.isNotEmpty) {
      final labels = capabilities.map((c) => c.label).join(', ');
      parts.add(labels);
    }
    parts.add('from Hugging Face');
    return 'Popular GGUF model: ${parts.join(' · ')}.';
  }

  String _formatDownloads(int downloads) {
    if (downloads >= 1000000) {
      return '${(downloads / 1000000).toStringAsFixed(1)}M';
    }
    if (downloads >= 1000) {
      return '${(downloads / 1000).toStringAsFixed(1)}K';
    }
    return downloads.toString();
  }

  // ---------------------------------------------------------------------------
  // Caching
  // ---------------------------------------------------------------------------

  Future<_DiscoveryCache?> _readCache() async {
    try {
      final raw = await SecureStorage.instance.read(_cacheKey);
      if (raw == null) return null;
      final cache = _DiscoveryCache.fromJson(raw);
      if (cache == null) return null;
      return _DiscoveryCache(
        models: [for (final model in cache.models) _withSizeFromName(model)],
        nextCursor: cache.nextCursor,
        fetchedAt: cache.fetchedAt,
      );
    } catch (_) {
      return null;
    }
  }

  /// Reads the parameter count from the names a cached record already carries.
  ///
  /// A record cached before the count was read from names holds a byte-based
  /// estimate instead, which puts a 0.5B model in the 1–3B bucket. The file
  /// name is still on the record, so the count is read again rather than
  /// waiting for the cache to expire.
  static LlmModel _withSizeFromName(LlmModel model) {
    final parsed =
        parameterSizeIn(model.localFileName) ??
        parameterSizeIn(model.downloadUrl);
    if (parsed == null || parsed == model.parameterSize) return model;
    return model.copyWith(parameterSize: parsed);
  }

  /// Keeps [catalog] on disk, replacing the cached list for a first page and
  /// adding to it for a page that follows.
  Future<void> _cachePage(
    HuggingFaceModelCatalog catalog, {
    required bool replace,
  }) async {
    try {
      final models = <String, LlmModel>{};
      if (!replace) {
        final previous = await _readCache();
        for (final model in previous?.models ?? const <LlmModel>[]) {
          models[model.id] = model;
        }
      }
      for (final model in catalog.models) {
        models[model.id] = model;
      }
      await _writeCache(
        _DiscoveryCache(
          models: models.values.toList(growable: false),
          nextCursor: catalog.nextCursor,
          fetchedAt: DateTime.now(),
        ),
      );
    } catch (_) {
      // Best-effort caching.
    }
  }

  Future<void> _writeCache(_DiscoveryCache cache) async {
    try {
      await SecureStorage.instance.write(key: _cacheKey, value: cache.toJson());
    } catch (_) {
      // Best-effort caching.
    }
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  List<List<T>> _chunk<T>(List<T> list, int size) {
    final chunks = <List<T>>[];
    for (var i = 0; i < list.length; i += size) {
      final end = (i + size < list.length) ? i + size : list.length;
      chunks.add(list.sublist(i, end));
    }
    return chunks;
  }
}

// =============================================================================
// Internal models
// =============================================================================

class _RawHfModel {
  final String repoId;
  final String pipelineTag;
  final Set<String> tags;
  final int downloads;

  /// Files in the repository, when the page was read with `expand[]=siblings`.
  final List<String> siblings;

  /// The repository's GGUF header, when the page asked for it.
  final Map<String, dynamic>? gguf;

  const _RawHfModel({
    required this.repoId,
    required this.pipelineTag,
    required this.tags,
    required this.downloads,
    this.siblings = const [],
    this.gguf,
  });

  /// [pipeline] is the pipeline the page was read for: an expanded page
  /// leaves `pipeline_tag` out of each item.
  factory _RawHfModel.fromListJson(
    Map<String, dynamic> json, {
    required String pipeline,
  }) {
    final tags = <String>{};
    final rawTags = json['tags'];
    if (rawTags is List) {
      for (final tag in rawTags) {
        if (tag is String && tag.trim().isNotEmpty) {
          tags.add(tag.trim());
        }
      }
    }

    final siblings = <String>[];
    final rawSiblings = json['siblings'];
    if (rawSiblings is List) {
      for (final sibling in rawSiblings) {
        final name = sibling is Map ? sibling['rfilename'] : null;
        if (name is String && name.trim().isNotEmpty) siblings.add(name);
      }
    }
    final rawGguf = json['gguf'];

    return _RawHfModel(
      repoId: (json['id'] ?? json['modelId'] ?? '').toString(),
      pipelineTag: (json['pipeline_tag'] ?? pipeline).toString(),
      siblings: siblings,
      gguf: rawGguf is Map ? Map<String, dynamic>.from(rawGguf) : null,
      tags: tags,
      downloads: (json['downloads'] as int?) ?? 0,
    );
  }
}

class _DiscoveryCache {
  final List<LlmModel> models;
  final String? nextCursor;
  final DateTime fetchedAt;

  const _DiscoveryCache({
    required this.models,
    required this.nextCursor,
    required this.fetchedAt,
  });

  Map<String, dynamic> toJson() {
    return {
      'models': models.map((m) => m.toJson()).toList(),
      'nextCursor': nextCursor,
      'fetchedAt': fetchedAt.toIso8601String(),
    };
  }

  static _DiscoveryCache? fromJson(Map<String, dynamic> json) {
    final rawModels = json['models'];
    final rawFetchedAt = json['fetchedAt'];
    if (rawModels is! List || rawFetchedAt is! String) return null;

    final fetchedAt = DateTime.tryParse(rawFetchedAt);
    if (fetchedAt == null) return null;

    final models = <LlmModel>[];
    for (final item in rawModels) {
      if (item is Map) {
        try {
          models.add(LlmModel.fromJson(Map<String, dynamic>.from(item)));
        } catch (_) {
          // Skip malformed entries.
        }
      }
    }

    return _DiscoveryCache(
      models: models,
      nextCursor: json['nextCursor'] as String?,
      fetchedAt: fetchedAt,
    );
  }
}
