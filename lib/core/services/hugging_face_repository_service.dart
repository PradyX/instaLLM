import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:installm/core/services/hugging_face_auth_service.dart';
import 'package:installm/core/utils/logger.dart';
import 'package:installm/features/model_selection/domain/llm_model.dart';

/// Thrown when a Hugging Face repository cannot be read or is unavailable.
class HuggingFaceRepositoryException implements Exception {
  const HuggingFaceRepositoryException(this.message);

  final String message;

  @override
  String toString() => 'HuggingFaceRepositoryException: $message';
}

/// One file inside a Hugging Face repository.
class HuggingFaceRepositoryFile {
  const HuggingFaceRepositoryFile({
    required this.path,
    required this.sizeBytes,
    required this.isProjector,
    required this.quantization,
  });

  /// Path inside the repository (may include folders).
  final String path;
  final int? sizeBytes;
  final bool isProjector;
  final String quantization;

  String get fileName => path.split('/').last;

  bool get isGguf => fileName.toLowerCase().endsWith('.gguf');
}

/// A selectable GGUF variant of a repository, with its paired vision
/// projector when one exists.
class HuggingFaceModelVariant {
  const HuggingFaceModelVariant({
    required this.filePath,
    required this.sizeBytes,
    required this.quantization,
    this.projectorPath,
    this.projectorSizeBytes,
  });

  final String filePath;
  final int? sizeBytes;
  final String quantization;
  final String? projectorPath;
  final int? projectorSizeBytes;

  String get fileName => filePath.split('/').last;
}

/// Files of one Hugging Face repository.
class HuggingFaceRepository {
  const HuggingFaceRepository({
    required this.repoId,
    required this.branch,
    required this.files,
  });

  final String repoId;
  final String branch;
  final List<HuggingFaceRepositoryFile> files;

  String get repositoryName {
    final segments = repoId.split('/');
    return segments.isEmpty ? repoId : segments.last;
  }

  String resolveUrl(String path) {
    return 'https://huggingface.co/$repoId/resolve/$branch/$path';
  }
}

/// Lists GGUF files of a Hugging Face repository so the user can pick a
/// quantization and download it through the existing resumable pipeline.
class HuggingFaceRepositoryService {
  HuggingFaceRepositoryService({Dio? dio, HuggingFaceAuthService? auth})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              baseUrl: 'https://huggingface.co',
              connectTimeout: const Duration(seconds: 20),
              receiveTimeout: const Duration(seconds: 20),
              headers: const {'Accept': 'application/json'},
            ),
          ),
      _auth = auth ?? HuggingFaceAuthService.instance {
    _dio.interceptors.add(_auth.requestInterceptor);
  }

  final Dio _dio;

  final HuggingFaceAuthService _auth;

  /// Quantizations in the order the app prefers them (best for devices first).
  static const List<String> preferredQuantOrder = [
    'Q4_K_M',
    'Q4_K_S',
    'Q4_0',
    'Q5_K_M',
    'Q3_K_M',
    'Q8_0',
    'Q6_K',
    'F16',
    'BF16',
  ];

  static final RegExp _repoIdPattern = RegExp(
    r'^[A-Za-z0-9][A-Za-z0-9._-]*/[A-Za-z0-9][A-Za-z0-9._-]*$',
  );

  /// Accepts `author/repository`, `huggingface.co/author/repository` or a
  /// full Hugging Face URL and returns the `author/repository` id.
  static String? parseRepositoryInput(String input) {
    var value = input.trim();
    if (value.isEmpty) return null;

    if (value.startsWith('huggingface.co/') ||
        value.startsWith('www.huggingface.co/')) {
      value = 'https://${value.replaceFirst('www.', '')}';
    }

    var candidate = value;
    final uri = Uri.tryParse(candidate);
    if (uri != null &&
        uri.hasAuthority &&
        (uri.host == 'huggingface.co' ||
            uri.host.endsWith('.huggingface.co'))) {
      final segments = uri.pathSegments
          .where((segment) => segment.isNotEmpty)
          .toList();
      if (segments.length < 2) return null;
      candidate = '${segments[0]}/${segments[1]}';
    }

    candidate = candidate.trim();
    if (candidate.toLowerCase().endsWith('.git')) {
      candidate = candidate.substring(0, candidate.length - 4);
    }
    if (!_repoIdPattern.hasMatch(candidate)) return null;
    return candidate;
  }

  /// Quantization labels used in GGUF file names. Longer labels are matched
  /// first so `Q4_K_M` is not shortened to `Q4_K` and `BF16` wins over `F16`.
  static const Set<String> knownQuantizations = {
    'Q4_K_M',
    'Q4_K_S',
    'Q5_K_M',
    'Q5_K_S',
    'Q3_K_S',
    'Q3_K_M',
    'Q3_K_L',
    'Q2_K_S',
    'Q6_K_L',
    // Base ggml type labels.
    'F32',
    'F16',
    'BF16',
    'F64',
    'Q4_0',
    'Q4_1',
    'Q5_0',
    'Q5_1',
    'Q8_0',
    'Q8_1',
    'Q2_K',
    'Q3_K',
    'Q4_K',
    'Q5_K',
    'Q6_K',
    'Q8_K',
    'IQ1_S',
    'IQ1_M',
    'IQ2_XXS',
    'IQ2_XS',
    'IQ2_S',
    'IQ3_XXS',
    'IQ3_S',
    'IQ4_NL',
    'IQ4_XS',
    'TQ1_0',
    'TQ2_0',
    'MXFP4',
    'NVFP4',
    'Q1_0',
    'Q2_0',
  };

  static final List<String> _quantizationsByLength = knownQuantizations.toList()
    ..sort((a, b) => b.length.compareTo(a.length));

  /// Detects the quantization label from a GGUF file name, e.g.
  /// `model-Q4_K_M.gguf` → `Q4_K_M`.
  static String quantizationFromFileName(String fileName) {
    final trimmed = fileName.trim();
    if (!trimmed.toLowerCase().endsWith('.gguf')) return 'Unknown';
    // `Qwen2.5-7B-Q4_K_M.gguf` normalizes to `QWEN2_5_7B_Q4_K_M`, so labels
    // written with `-`, `.` or `_` separators all become matchable.
    final normalized = trimmed
        .substring(0, trimmed.length - 5)
        .toUpperCase()
        .replaceAll(RegExp(r'[-.\s]+'), '_');
    for (final label in _quantizationsByLength) {
      final pattern = RegExp('(?:^|_)${RegExp.escape(label)}(?:_|\$)');
      if (pattern.hasMatch(normalized)) return label;
    }
    return 'Unknown';
  }

  /// Why a repository request failed, in words a user can act on.
  ///
  /// The dialog shows one line, so it names the transport or the status rather
  /// than blaming the connection for every failure.
  static String describeFailure(DioException error) {
    final status = error.response?.statusCode;
    if (status == 429) {
      return 'Hugging Face is rate-limiting this device (HTTP 429); '
          'wait a moment and try again';
    }
    if (status != null && status >= 500) {
      return 'Hugging Face is having trouble (HTTP $status); '
          'try again in a minute';
    }
    if (status != null) {
      return 'Hugging Face answered HTTP $status';
    }
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
        return 'the connection timed out after 20 s';
      case DioExceptionType.sendTimeout:
        return 'sending the request timed out after 20 s';
      case DioExceptionType.receiveTimeout:
        return 'Hugging Face stopped sending data for 20 s';
      case DioExceptionType.badCertificate:
        return 'the secure connection failed a certificate check; '
            'a VPN, proxy or hotspot sign-in page can cause this';
      case DioExceptionType.cancel:
        return 'the request was cancelled';
      case DioExceptionType.connectionError:
        final cause = error.error?.toString().trim();
        return cause == null || cause.isEmpty
            ? 'the connection failed'
            : 'the connection failed ($cause)';
      case DioExceptionType.badResponse:
      case DioExceptionType.transformTimeout:
      case DioExceptionType.unknown:
        final message = error.message?.trim();
        return message == null || message.isEmpty
            ? 'the request failed'
            : 'the request failed ($message)';
    }
  }

  /// Fetches the file list of [repoInput] (repo id or URL) with sizes.
  Future<HuggingFaceRepository> fetchRepository(String repoInput) async {
    final repoId = parseRepositoryInput(repoInput);
    if (repoId == null) {
      throw const HuggingFaceRepositoryException(
        'Enter a Hugging Face link or an author/repository name.',
      );
    }

    Map<String, dynamic>? json;
    try {
      final response = await _dio.get(
        '/api/models/$repoId',
        queryParameters: {'blobs': 'true'},
      );
      final data = response.data;
      if (data is Map<String, dynamic>) {
        json = data;
      } else if (data is Map) {
        json = Map<String, dynamic>.from(data);
      }
    } on DioException catch (error) {
      final status = error.response?.statusCode;
      // One line in the log answers the question the dialog cannot: which
      // request failed, and how. A generic "check your connection" once cost a
      // session of guessing while the host itself answered other requests.
      AppLogger.warning(
        'Hugging Face repository request failed: repo=$repoId, '
        'type=${error.type.name}, status=${status ?? '-'}, '
        'uri=${error.requestOptions.uri}',
      );
      if (status == 401 || status == 403) {
        throw const HuggingFaceRepositoryException(
          'This repository is private or gated. InstaLLM can only browse '
          'public Hugging Face repositories.',
        );
      }
      if (status == 404) {
        throw const HuggingFaceRepositoryException(
          'Repository not found. Check the author/repository name.',
        );
      }
      throw HuggingFaceRepositoryException(
        'Could not load $repoId from huggingface.co: '
        '${describeFailure(error)}.',
      );
    } catch (_) {
      throw const HuggingFaceRepositoryException(
        'Could not read this repository.',
      );
    }

    if (json == null) {
      throw const HuggingFaceRepositoryException(
        'Repository returned no data.',
      );
    }

    final files = <HuggingFaceRepositoryFile>[];
    final siblings = json['siblings'];
    if (siblings is List) {
      for (final sibling in siblings) {
        if (sibling is! Map) continue;
        final path = sibling['rfilename'];
        if (path is! String || path.isEmpty) continue;

        int? sizeBytes;
        final rawSize = sibling['size'];
        if (rawSize is num) sizeBytes = rawSize.toInt();
        if (sizeBytes == null) {
          final lfs = sibling['lfs'];
          if (lfs is Map && lfs['size'] is num) {
            sizeBytes = (lfs['size'] as num).toInt();
          }
        }

        final lower = path.toLowerCase();
        files.add(
          HuggingFaceRepositoryFile(
            path: path,
            sizeBytes: sizeBytes,
            isProjector: lower.contains('mmproj') && lower.endsWith('.gguf'),
            quantization: quantizationFromFileName(path),
          ),
        );
      }
    }

    final hasModelGguf = files.any((file) => file.isGguf && !file.isProjector);
    if (!hasModelGguf) {
      throw const HuggingFaceRepositoryException(
        'No GGUF model files were found in this repository.',
      );
    }

    return HuggingFaceRepository(repoId: repoId, branch: 'main', files: files);
  }

  /// The chat template the repository publishes for its tokenizer.
  ///
  /// A GGUF can be missing `tokenizer.chat_template` — several popular
  /// quantizations were converted before the converter kept it — while the
  /// repository still declares its template in `tokenizer_config.json`. Without
  /// that template an instruction model is indistinguishable from a base
  /// completion model. Returns null when the repository has no usable one.
  Future<String?> fetchChatTemplate(String repoInput) async {
    final repoId = parseRepositoryInput(repoInput);
    if (repoId == null) return null;

    try {
      final response = await _dio.get(
        '/$repoId/raw/main/tokenizer_config.json',
      );
      final data = response.data;
      final Map<String, dynamic> json;
      if (data is Map<String, dynamic>) {
        json = data;
      } else if (data is Map) {
        json = Map<String, dynamic>.from(data);
      } else if (data is String) {
        final decoded = jsonDecode(data);
        if (decoded is! Map) return null;
        json = Map<String, dynamic>.from(decoded);
      } else {
        return null;
      }
      return chatTemplateFromTokenizerConfig(json['chat_template']);
    } catch (_) {
      // A repository without a readable tokenizer config is not an error: the
      // file's own metadata still decides.
      return null;
    }
  }

  /// The template inside a `chat_template` value.
  ///
  /// Older repositories store one Jinja string; newer ones store a list of
  /// `{name, template}` entries, where the default is the one a chat needs.
  static String? chatTemplateFromTokenizerConfig(Object? raw) {
    if (raw is String) {
      final text = raw.trim();
      return text.isEmpty ? null : raw;
    }
    if (raw is List) {
      for (final entry in raw) {
        if (entry is Map && entry['name'] == 'default') {
          final template = entry['template'];
          if (template is String && template.trim().isNotEmpty) return template;
        }
      }
      for (final entry in raw) {
        if (entry is Map) {
          final template = entry['template'];
          if (template is String && template.trim().isNotEmpty) return template;
        }
      }
    }
    return null;
  }

  /// Context window the repository's GGUF files declare, read from the
  /// model's own metadata on huggingface.co (`gguf.context_length`).
  ///
  /// This is public metadata about a public file: no device, user or usage
  /// information is sent, and the request is one field of the model page.
  /// Repositories Hugging Face has not parsed, private or unreachable ones,
  /// and files that declare no context all answer null, so an unknown value
  /// never blocks the page that asks.
  Future<int?> fetchContextLength(String repoInput) async {
    final repoId = parseRepositoryInput(repoInput);
    if (repoId == null) return null;
    try {
      final response = await _dio.get(
        '/api/models/$repoId',
        queryParameters: {'expand[]': 'gguf'},
      );
      final data = response.data;
      final json = data is Map ? Map<String, dynamic>.from(data) : null;
      final gguf = json?['gguf'];
      if (gguf is! Map) return null;
      final context = gguf['context_length'];
      if (context is num && context > 0) return context.toInt();
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Repository files that are the same model as [fileName] in another
  /// quantization, best for a device first.
  ///
  /// A repository lists every quantization of everything it carries in one
  /// flat list, so the model is matched with its own quantization label
  /// removed: `qwen2.5-7b-instruct-q4_k_m.gguf` finds
  /// `qwen2.5-7b-instruct-q8_0.gguf` and leaves out the 3B file. Split parts
  /// (`...-00001-of-00002.gguf`) cannot be loaded alone, so they are never
  /// offered, and a file with no readable label is not a choice either.
  static List<HuggingFaceRepositoryFile> quantizationFilesFor(
    List<HuggingFaceRepositoryFile> files, {
    required String fileName,
  }) {
    final target = modelStemOf(fileName);
    if (target.isEmpty) return const [];

    final matches = <HuggingFaceRepositoryFile>[];
    for (final file in files) {
      if (!file.isGguf || file.isProjector) continue;
      if (file.quantization == 'Unknown') continue;
      if (modelStemOf(file.fileName) != target) continue;
      matches.add(file);
    }

    matches.sort((a, b) {
      final rank = _quantRank(
        a.quantization,
      ).compareTo(_quantRank(b.quantization));
      if (rank != 0) return rank;
      return _compareSize(a.sizeBytes, b.sizeBytes);
    });
    return matches;
  }

  /// A GGUF file name without its extension, its quantization label or its
  /// separators: `Qwen2.5-7B-Instruct-Q4_K_M.gguf` → `qwen2_5_7b_instruct`.
  ///
  /// Empty for a file name that cannot stand for a model of its own: a split
  /// part of a larger download.
  static String modelStemOf(String fileName) {
    var stem = fileName.trim().toLowerCase();
    if (stem.endsWith('.gguf')) {
      stem = stem.substring(0, stem.length - 5);
    }
    if (RegExp(r'-\d{5}-of-\d{5}$').hasMatch(stem)) return '';

    // Labels are written with `-`, `.` or `_`; one separator makes every one
    // of them matchable as a token of its own.
    final normalized = stem.replaceAll(RegExp(r'[-.\s]+'), '_');
    for (final label in _quantizationsByLength) {
      final pattern = RegExp(
        '(?:^|_)${RegExp.escape(label.toLowerCase())}(?:_|\$)',
      );
      if (pattern.hasMatch(normalized)) {
        return normalized.replaceFirst(pattern, '_');
      }
    }
    return normalized;
  }

  /// Groups repository files into download-ready variants, pairing the
  /// repository's vision projector (mmproj) when one exists.
  static List<HuggingFaceModelVariant> variantsFromFiles(
    List<HuggingFaceRepositoryFile> files,
  ) {
    final projectors = files.where((file) => file.isProjector).toList();
    final mains = files.where((file) => file.isGguf && !file.isProjector);

    final variants = <HuggingFaceModelVariant>[];
    for (final file in mains) {
      HuggingFaceRepositoryFile? paired;
      if (projectors.isNotEmpty) {
        final prefix = file.fileName
            .toLowerCase()
            .split(RegExp(r'[-_.]'))
            .first;
        paired = projectors.firstWhere(
          (candidate) =>
              prefix.isEmpty ||
              candidate.fileName.toLowerCase().contains(prefix),
          orElse: () => projectors.first,
        );
      }
      variants.add(
        HuggingFaceModelVariant(
          filePath: file.path,
          sizeBytes: file.sizeBytes,
          quantization: file.quantization,
          projectorPath: paired?.path,
          projectorSizeBytes: paired?.sizeBytes,
        ),
      );
    }

    variants.sort((a, b) {
      final rank = _quantRank(
        a.quantization,
      ).compareTo(_quantRank(b.quantization));
      if (rank != 0) return rank;
      return _compareSize(a.sizeBytes, b.sizeBytes);
    });
    return variants;
  }

  static int _quantRank(String quantization) {
    final index = preferredQuantOrder.indexOf(quantization);
    return index >= 0 ? index : preferredQuantOrder.length;
  }

  static int _compareSize(int? a, int? b) {
    if (a == null && b == null) return 0;
    if (a == null) return 1;
    if (b == null) return -1;
    return a.compareTo(b);
  }

  /// Builds an [LlmModel] that downloads [variant] through the normal
  /// resumable download flow.
  static LlmModel modelForVariant({
    required HuggingFaceRepository repository,
    required HuggingFaceModelVariant variant,
  }) {
    final repoName = repository.repositoryName;
    final baseName = variant.fileName.toLowerCase().endsWith('.gguf')
        ? variant.fileName.substring(0, variant.fileName.length - 5)
        : variant.fileName;
    final displayQuant = variant.quantization == 'Unknown'
        ? null
        : variant.quantization;
    final projectorPath = variant.projectorPath;

    return LlmModel(
      id: 'hfrepo-${slug(repoName)}-${slug(baseName)}',
      name: displayQuant == null ? repoName : '$repoName ($displayQuant)',
      parameterSize: guessParameterSize(repoName) ?? 'Unknown',
      description: 'Hugging Face • ${repository.repoId}',
      capabilities: [if (projectorPath != null) ModelCapability.vision],
      downloadUrl: repository.resolveUrl(variant.filePath),
      localFileName: variant.fileName,
      mmprojDownloadUrl: projectorPath == null
          ? null
          : repository.resolveUrl(projectorPath),
      mmprojLocalFileName: projectorPath?.split('/').last,
      // Provisional only: a repository is registered before its file exists,
      // so the real format is read from that file's own `tokenizer.chat_template`
      // when the model is loaded (ModelPromptFormatService).
      promptFormatId: 'chatml',
      isCustom: true,
      modelSource: ModelSource.customUrl,
    );
  }

  /// Guesses a display parameter size like `0.5B` or `7B` from a repo name.
  static String? guessParameterSize(String text) {
    final match = RegExp(
      r'(\d+(?:\.\d+)?)\s*([BMT])(?![a-z])',
      caseSensitive: false,
    ).firstMatch(text);
    if (match == null) return null;
    return '${match.group(1)}${match.group(2)!.toUpperCase()}';
  }

  static String slug(String value) {
    final slug = value
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    return slug.isEmpty ? 'model' : slug;
  }
}
