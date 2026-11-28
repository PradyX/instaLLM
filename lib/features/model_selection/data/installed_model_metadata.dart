import 'dart:io';

import 'package:installm/core/services/model_storage_service.dart';
import 'package:installm/features/model_selection/data/gguf_reader.dart';
import 'package:installm/features/model_selection/domain/gguf_metadata.dart';
import 'package:installm/features/model_selection/domain/llm_model.dart';

/// Reads the GGUF header of installed files whose record carries none.
///
/// A catalog record describes a repository, not the file that was downloaded:
/// it knows tags and a size, never the chat template. The template is what says
/// a model can carry tool calls, so without this pass a downloaded model is
/// never offered the tools its own file supports, and its memory estimate and
/// context window stay unknown.
///
/// Only the metadata section is read, never the weights, and a file that cannot
/// be read keeps the record it already had.
class InstalledModelMetadata {
  InstalledModelMetadata({
    ModelStorageService? storage,
    Future<GgufMetadata> Function(String path)? readHeader,
  }) : _storage = storage ?? ModelStorageService(),
       _readHeader = readHeader ?? _readWithGgufReader;

  final ModelStorageService _storage;
  final Future<GgufMetadata> Function(String path) _readHeader;

  static Future<GgufMetadata> _readWithGgufReader(String path) {
    return const GgufReader().info(path);
  }

  /// [models] with a header on every installed record that lacked one.
  Future<List<LlmModel>> describe(List<LlmModel> models) async {
    final described = <LlmModel>[];
    for (final model in models) {
      final metadata = await read(model);
      described.add(
        metadata == null ? model : model.copyWith(ggufMetadata: metadata),
      );
    }
    return described;
  }

  /// The header of [model]'s installed file, or null when there is nothing to
  /// read: the model is not installed, the record already carries one, or the
  /// file could not be opened.
  Future<GgufMetadata?> read(LlmModel model) async {
    if (!model.isDownloaded || model.ggufMetadata != null) return null;
    try {
      final path = await _storage.resolveModelPath(model);
      if (path == null || path.trim().isEmpty) return null;
      if (!await File(path).exists()) return null;
      return await _readHeader(path);
    } catch (_) {
      return null;
    }
  }
}
