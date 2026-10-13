import 'dart:io';

import 'package:dio/dio.dart';
import 'package:installm/core/services/model_storage_service.dart';
import 'package:installm/core/utils/logger.dart';
import 'package:installm/features/voice/domain/whisper_model_option.dart';

/// A Whisper model that is on this device and ready to hear audio.
///
/// The three paths are what the engine is started with; they always belong to
/// the same model, because a model counts as installed only when all of its
/// files are here and complete.
class InstalledWhisperModel {
  const InstalledWhisperModel({
    required this.option,
    required this.encoderPath,
    required this.decoderPath,
    required this.tokensPath,
  });

  final WhisperModelOption option;
  final String encoderPath;
  final String decoderPath;
  final String tokensPath;
}

/// Owns the Whisper model files: what is installed, where it lives, and which
/// one transcription should use.
///
/// The files sit in the same model directory the rest of the app uses, so a
/// Whisper model is downloaded, resumed, cancelled and removed by the same
/// downloader the model screen already relies on. What is different is the
/// shape: one Whisper model is three files (encoder, decoder, tokens), and all
/// three have to arrive before the model can hear anything.
///
/// Whether a model is installed is read from the files themselves rather than
/// from a stored record, so nothing here can disagree with the disk: a model
/// that was deleted outside the app is simply gone, and an interrupted
/// download is not mistaken for a finished one.
class WhisperModelService {
  WhisperModelService(this._storage);

  final ModelStorageService _storage;

  /// How much of a file's expected size has to be on disk for it to count as
  /// complete. A download that stopped early leaves far less than this, while
  /// a few percent of drift only happens if the model repository re-exports a
  /// file we already know the size of.
  static const double _completeFraction = 0.9;

  /// The Whisper models installed right now, smallest first.
  Future<List<InstalledWhisperModel>> installed() async {
    final models = <InstalledWhisperModel>[];
    for (final option in WhisperModelCatalog.models) {
      final model = await _installedOrNull(option);
      if (model != null) models.add(model);
    }
    return models;
  }

  /// True when every file of [option] is on this device and complete.
  Future<bool> isInstalled(WhisperModelOption option) async {
    return await _installedOrNull(option) != null;
  }

  /// The model transcription should use.
  ///
  /// [preferredId] is the choice stored in settings; when that model is not
  /// installed (never downloaded, or removed later) the smallest installed one
  /// is used instead of failing, and null is returned only when nothing is
  /// installed at all.
  Future<InstalledWhisperModel?> resolve(String? preferredId) async {
    final models = await installed();
    if (models.isEmpty) return null;
    for (final model in models) {
      if (model.option.id == preferredId) return model;
    }
    return models.first;
  }

  /// Downloads every file of [option] into the model directory.
  ///
  /// Progress is reported against the whole model, so the picker shows one bar
  /// per model rather than one per file. Throws when a file fails or the
  /// download is cancelled; a cancelled download keeps the files it finished,
  /// so starting it again resumes instead of starting over.
  Future<void> download(
    WhisperModelOption option, {
    void Function(int received, int total)? onProgress,
    CancelToken? cancelToken,
  }) async {
    var completedBytes = 0;
    for (final file in option.files) {
      final path = await _storage.getLocalFilePath(file.fileName);
      if (_isCompleteFile(path, file)) {
        completedBytes += file.bytes;
        onProgress?.call(completedBytes, option.approximateBytes);
        continue;
      }

      final bytesBefore = completedBytes;
      await _storage.downloadModel(
        file.url,
        file.fileName,
        cancelToken: cancelToken,
        onProgress: (received, _) {
          onProgress?.call(bytesBefore + received, option.approximateBytes);
        },
      );

      if (!_isCompleteFile(path, file)) {
        throw Exception(
          'The download of ${option.name} did not finish. Start it again to '
          'resume where it stopped.',
        );
      }
      completedBytes = bytesBefore + file.bytes;
      onProgress?.call(completedBytes, option.approximateBytes);
    }
    AppLogger.info('Whisper model ${option.id} is installed in the model dir');
  }

  /// Removes every file of a downloaded model, and its download progress.
  ///
  /// Only file names this catalog defined are ever touched, so a model record
  /// from somewhere else cannot lead to deleting a file the app does not own.
  Future<void> remove(WhisperModelOption option) async {
    final owned = WhisperModelCatalog.ownedFileNames;
    var removed = 0;
    for (final file in option.files) {
      if (!owned.contains(file.fileName)) continue;
      await _storage.deleteModel(file.fileName);
      removed++;
    }
    if (removed > 0) {
      AppLogger.info('Whisper model ${option.id} was removed');
    }
  }

  /// The installed model behind [option], or null when any of its files is
  /// missing, still downloading, or too small to be the file it should be.
  Future<InstalledWhisperModel?> _installedOrNull(
    WhisperModelOption option,
  ) async {
    final paths = <String>[];
    for (final file in option.files) {
      final path = await _storage.getLocalFilePath(file.fileName);
      if (!_isCompleteFile(path, file)) return null;
      paths.add(path);
    }
    return InstalledWhisperModel(
      option: option,
      encoderPath: paths[0],
      decoderPath: paths[1],
      tokensPath: paths[2],
    );
  }

  /// A file is a usable part of a model when it exists, holds nearly all of
  /// the bytes it should, and has no download-progress sidecar — the
  /// downloader writes that `.json` next to a file it is still filling in, so
  /// its presence means "not finished yet", which also tells a resumable
  /// download apart from a complete one.
  static bool _isCompleteFile(String path, WhisperModelFile file) {
    final target = File(path);
    if (!target.existsSync()) return false;
    if (File('$path.json').existsSync()) return false;
    final expected = (file.bytes * _completeFraction).floor();
    return target.lengthSync() >= expected;
  }
}
