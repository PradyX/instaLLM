import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:installm/core/services/local_notification_service.dart';
import 'package:installm/core/services/service_providers.dart';
import 'package:installm/features/voice/data/whisper_model_service.dart';
import 'package:installm/features/voice/domain/whisper_model_option.dart';

/// The Whisper models this device has, and any download in flight.
class WhisperModelsState {
  const WhisperModelsState({
    this.isLoading = true,
    this.installed = const <InstalledWhisperModel>[],
    this.downloadingId,
    this.receivedBytes = 0,
    this.totalBytes = 0,
    this.errorMessage,
  });

  /// True until the first look at the model directory finishes.
  final bool isLoading;

  /// Installed models, smallest first.
  final List<InstalledWhisperModel> installed;

  /// Model currently downloading, if any. One at a time: the downloader
  /// writes into a shared directory and a second run would compete for disk
  /// and bandwidth with the first.
  final String? downloadingId;

  final int receivedBytes;
  final int totalBytes;
  final String? errorMessage;

  bool isInstalled(String id) {
    for (final model in installed) {
      if (model.option.id == id) return true;
    }
    return false;
  }

  bool get isDownloading => downloadingId != null;

  /// Fraction downloaded, or null while the total is unknown.
  double? progressFor(String id) {
    if (downloadingId != id || totalBytes <= 0) return null;
    return (receivedBytes / totalBytes).clamp(0.0, 1.0);
  }

  InstalledWhisperModel? installedModel(String id) {
    for (final model in installed) {
      if (model.option.id == id) return model;
    }
    return null;
  }

  WhisperModelsState copyWith({
    bool? isLoading,
    List<InstalledWhisperModel>? installed,
    Object? downloadingId = _unset,
    int? receivedBytes,
    int? totalBytes,
    Object? errorMessage = _unset,
  }) {
    return WhisperModelsState(
      isLoading: isLoading ?? this.isLoading,
      installed: installed ?? this.installed,
      downloadingId: downloadingId == _unset
          ? this.downloadingId
          : downloadingId as String?,
      receivedBytes: receivedBytes ?? this.receivedBytes,
      totalBytes: totalBytes ?? this.totalBytes,
      errorMessage: errorMessage == _unset
          ? this.errorMessage
          : errorMessage as String?,
    );
  }

  static const Object _unset = Object();
}

/// The service that owns Whisper model files.
final whisperModelServiceProvider = Provider<WhisperModelService>((ref) {
  return WhisperModelService(ref.watch(modelStorageServiceProvider));
});

/// How a finished download reaches the user. A provider rather than a direct
/// call so a test can watch the notice instead of the platform.
final modelDownloadNoticeProvider =
    Provider<Future<void> Function(String name)>(
      (ref) => LocalNotificationService.instance.showModelDownloadComplete,
    );

final whisperModelsProvider =
    StateNotifierProvider<WhisperModelsController, WhisperModelsState>((ref) {
      return WhisperModelsController(
        ref.watch(whisperModelServiceProvider),
        notifyDownloadComplete: ref.watch(modelDownloadNoticeProvider),
      );
    });

/// Keeps the picker in step with the model directory.
///
/// Downloads are the user's decision and always start from the picker; this
/// only reports what happened, so nothing is fetched in the background.
class WhisperModelsController extends StateNotifier<WhisperModelsState> {
  WhisperModelsController(
    this._service, {
    Future<void> Function(String name)? notifyDownloadComplete,
  }) : _notifyDownloadComplete =
           notifyDownloadComplete ??
           LocalNotificationService.instance.showModelDownloadComplete,
       super(const WhisperModelsState()) {
    refresh();
  }

  final WhisperModelService _service;

  /// Called once a model is installed, with the name to show in the notice.
  final Future<void> Function(String name) _notifyDownloadComplete;
  CancelToken? _cancelToken;

  /// Re-reads the model directory.
  ///
  /// [clearError] is false when the refresh is the tail of an operation that
  /// just reported why it failed: listing the models again must not wipe the
  /// reason the user needs to see.
  Future<void> refresh({bool clearError = true}) async {
    final installed = await _service.installed();
    if (!mounted) return;
    state = state.copyWith(
      isLoading: false,
      installed: installed,
      errorMessage: clearError ? null : state.errorMessage,
    );
  }

  /// Downloads [option], reporting progress as it goes.
  ///
  /// Returns true when the model is installed afterwards. A cancel or a
  /// failure leaves the error in the state, except for a cancel the user asked
  /// for — that is not something to report as a problem.
  Future<bool> download(WhisperModelOption option) async {
    if (state.isDownloading || state.isInstalled(option.id)) return false;

    final cancelToken = CancelToken();
    _cancelToken = cancelToken;
    state = state.copyWith(
      downloadingId: option.id,
      receivedBytes: 0,
      totalBytes: option.approximateBytes,
      errorMessage: null,
    );

    try {
      await _service.download(
        option,
        cancelToken: cancelToken,
        onProgress: (received, total) {
          if (!mounted) return;
          state = state.copyWith(
            receivedBytes: received,
            totalBytes: total > 0 ? total : option.approximateBytes,
          );
        },
      );
      _cancelToken = null;
      if (!mounted) return true;
      state = state.copyWith(
        downloadingId: null,
        receivedBytes: 0,
        totalBytes: 0,
      );
      await refresh();
      await _announce(option);
      return true;
    } catch (error) {
      _cancelToken = null;
      if (!mounted) return false;
      final wasCancelled = cancelToken.isCancelled;
      state = state.copyWith(
        downloadingId: null,
        receivedBytes: 0,
        totalBytes: 0,
        errorMessage: wasCancelled ? null : _messageOf(error),
      );
      await refresh(clearError: false);
      return false;
    }
  }

  /// Tells the user the model is installed.
  ///
  /// A notice is a convenience, not part of the download: a platform that
  /// refuses it must not make a finished model look failed. The download
  /// notice says nothing about the conversation or the model files.
  Future<void> _announce(WhisperModelOption option) async {
    try {
      await _notifyDownloadComplete('Whisper ${option.name}');
    } catch (_) {
      // LocalNotificationService reports its own failures; nothing here can
      // change the outcome of a download that already finished.
    }
  }

  /// Stops the download in flight. What arrived is kept, so the same model
  /// resumes from where it stopped next time.
  void cancelDownload() {
    _cancelToken?.cancel();
  }

  /// Deletes a downloaded model file.
  Future<void> remove(WhisperModelOption option) async {
    state = state.copyWith(errorMessage: null);
    try {
      await _service.remove(option);
    } catch (error) {
      if (!mounted) return;
      state = state.copyWith(errorMessage: _messageOf(error));
    }
    await refresh(clearError: false);
  }

  /// `Exception: something` reads badly in the UI, so the prefix is dropped.
  static String _messageOf(Object error) {
    const prefix = 'Exception: ';
    if (error is DioException) {
      final message = error.message?.trim();
      if (message != null && message.isNotEmpty) return message;
    }
    final text = error.toString();
    return text.startsWith(prefix) ? text.substring(prefix.length) : text;
  }
}
