import 'package:flutter_riverpod/flutter_riverpod.dart';

/// How much of a model has arrived so far, shown on that model's card.
class DownloadProgress {
  final int received;
  final int total;

  const DownloadProgress({required this.received, required this.total});

  double get progress => total > 0 ? received / total : 0;
}

/// Models downloading right now, keyed by model id.
///
/// Progress deliberately lives outside the model list state. A download reports
/// progress several times a second, and keeping it in that state rebuilt every
/// screen that watches it — the model page sorts, filters and lays out its whole
/// list on each tick. The download's stream is delivered on the same isolate, so
/// that rendering starved the transfer: a 36 MB model took 115 s while the
/// progress UI was rendering and 22 s with the same code and the progress UI
/// detached (measured on a mid-range Android phone, 2026). Only the card that
/// shows a progress bar watches this provider.
final downloadProgressProvider =
    NotifierProvider<DownloadProgressNotifier, Map<String, DownloadProgress>>(
      DownloadProgressNotifier.new,
    );

/// Holds the live progress of each downloading model.
class DownloadProgressNotifier extends Notifier<Map<String, DownloadProgress>> {
  @override
  Map<String, DownloadProgress> build() => const {};

  /// Records progress for [modelId], starting an entry when there is none.
  ///
  /// A zero total is kept as "size unknown yet" rather than dropping the entry:
  /// the entry is what tells the card a download is running.
  void report(String modelId, {required int received, required int total}) {
    final current = state[modelId];
    final resolvedTotal = total > 0 ? total : current?.total ?? 0;
    if (current != null &&
        current.received == received &&
        current.total == resolvedTotal) {
      return;
    }
    state = {
      ...state,
      modelId: DownloadProgress(received: received, total: resolvedTotal),
    };
  }

  /// Marks [modelId] as downloading before its size is known.
  void start(String modelId) {
    if (state.containsKey(modelId)) return;
    state = {...state, modelId: const DownloadProgress(received: 0, total: 0)};
  }

  bool isDownloading(String modelId) => state.containsKey(modelId);

  /// Drops the entry once a download finished, failed or was paused.
  void clear(String modelId) {
    if (!state.containsKey(modelId)) return;
    state = Map<String, DownloadProgress>.from(state)..remove(modelId);
  }
}
