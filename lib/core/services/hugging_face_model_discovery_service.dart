import 'dart:convert';

import 'package:dio/dio.dart';
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
  });

  final List<LlmModel> models;
  final String? nextCursor;
  final bool hasMore;

  static const empty = HuggingFaceModelCatalog(
    models: [],
    nextCursor: null,
    hasMore: false,
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
  static const _cacheKey = 'hf_discovered_models_cache_v1';
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
  Future<HuggingFaceModelCatalog> load({
    String query = '',
    String? cursor,
  }) async {
    final trimmedQuery = query.trim();
    try {
      final raw = <_RawHfModel>[];
      final seen = <String>{};
      final nextCursors = <String, String?>{};

      for (final pipeline in _allowedPipelines) {
        final page = await _fetchPage(
          pipeline: pipeline,
          query: trimmedQuery,
          cursor: _cursorFor(cursor, pipeline),
        );
        nextCursors[pipeline] = page.nextCursor;
        for (final model in page.models) {
          if (seen.add(model.repoId)) raw.add(model);
        }
      }

      if (raw.isEmpty) return HuggingFaceModelCatalog.empty;
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

      if (trimmedQuery.isEmpty) {
        await _cachePage(catalog, replace: cursor == null);
      }
      return catalog;
    } catch (_) {
      return HuggingFaceModelCatalog.empty;
    }
  }

  // ---------------------------------------------------------------------------
  // API calls
  // ---------------------------------------------------------------------------

  Future<({List<_RawHfModel> models, String? nextCursor})> _fetchPage({
    required String pipeline,
    required String query,
    required String? cursor,
  }) async {
    final models = <_RawHfModel>[];
    String? nextCursor;
    try {
      final queryParams = <String, dynamic>{
        'filter': 'gguf',
        'sort': 'downloads',
        'direction': '-1',
        'limit': _perPipelineLimit,
        'pipeline_tag': pipeline,
      };
      if (query.isNotEmpty) queryParams['search'] = query;
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
          final raw = _RawHfModel.fromListJson(map);
          if (raw.repoId.isNotEmpty &&
              _allowedPipelines.contains(raw.pipelineTag)) {
            models.add(raw);
          }
        }
      }
    } catch (_) {
      // One pipeline failing still leaves the other one's page.
    }
    return (models: models, nextCursor: nextCursor);
  }

  /// The `cursor` of the `rel="next"` link Hugging Face returns, if any.
  ///
  /// Read from the raw header rather than through [Uri.queryParameters],
  /// which turns a `+` in the base64 cursor into a space and corrupts it.
  static String? _nextCursorFromLink(String? link) {
    if (link == null || link.isEmpty) return null;
    final next = RegExp(r'<([^>]+)>;\s*rel="next"').firstMatch(link)?.group(1);
    if (next == null) return null;
    return RegExp(r'[?&]cursor=([^&]+)').firstMatch(next)?.group(1);
  }

  /// The cursor this pipeline had reached, from the combined cursor.
  static String? _cursorFor(String? combined, String pipeline) {
    if (combined == null || combined.isEmpty) return null;
    for (final part in combined.split('||')) {
      final separator = part.indexOf('|');
      if (separator <= 0) continue;
      if (part.substring(0, separator) == pipeline) {
        final cursor = part.substring(separator + 1);
        return cursor.isEmpty ? null : cursor;
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
    return _sizeFromText(fileName) ??
        _sizeFromText(repoId) ??
        _estimateParameterSize(totalBytes);
  }

  /// The first `<number><M|B|T>` in [text], normalised.
  ///
  /// `Qwen2.5-1.5B-Instruct` answers `1.5B`; the `2.5` before a dash is skipped
  /// because it is not followed by a unit.
  static String? _sizeFromText(String text) {
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
      return _DiscoveryCache.fromJson(raw);
    } catch (_) {
      return null;
    }
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

  const _RawHfModel({
    required this.repoId,
    required this.pipelineTag,
    required this.tags,
    required this.downloads,
  });

  factory _RawHfModel.fromListJson(Map<String, dynamic> json) {
    final tags = <String>{};
    final rawTags = json['tags'];
    if (rawTags is List) {
      for (final tag in rawTags) {
        if (tag is String && tag.trim().isNotEmpty) {
          tags.add(tag.trim());
        }
      }
    }

    return _RawHfModel(
      repoId: (json['id'] ?? json['modelId'] ?? '').toString(),
      pipelineTag: (json['pipeline_tag'] ?? '').toString(),
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
