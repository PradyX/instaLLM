import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:installm/core/navigation/app_router.dart';
import 'package:installm/core/services/local_notification_service.dart';
import 'package:installm/features/reminders/application/scheduled_job_runner.dart';

/// The task a notification asked the app to show.
final focusedScheduledTaskProvider =
    NotifierProvider<FocusedScheduledTaskNotifier, String?>(
      FocusedScheduledTaskNotifier.new,
    );

class FocusedScheduledTaskNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void focus(String id) => state = id;

  void clear() => state = null;
}

final scheduledJobServiceProvider = Provider<ScheduledJobService>((ref) {
  final service = ScheduledJobService(ref);
  ref.onDispose(service.dispose);
  return service;
});

/// Keeps scheduled jobs moving while the app is alive
/// (Road Map 5 Phase 5.4).
///
/// There is no background daemon and no alarm: Android does not promise a
/// process the CPU, so the ticker lives inside the app and a job whose slot
/// passed while the app was not running is reported `skipped` by the runner
/// rather than woken for. Coming back to the app checks immediately, which is
/// what makes a job due during a long sleep surface as a skipped run with the
/// reason, and one due while the app was merely in the background still run.
class ScheduledJobService with WidgetsBindingObserver {
  ScheduledJobService(this._ref);

  final Ref _ref;

  /// Well inside the runner's grace window, so a due job is never made late by
  /// the tick itself.
  static const Duration tickInterval = Duration(seconds: 20);

  Timer? _timer;
  StreamSubscription<String>? _taps;
  bool _started = false;

  bool get isStarted => _started;

  void start() {
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(tickInterval, (_) => unawaited(checkNow()));
    _taps = LocalNotificationService.taps.listen(_openRun);
    unawaited(checkNow());
  }

  /// Runs every due job, if any. Safe to call at any time.
  Future<void> checkNow() async {
    try {
      await _ref.read(scheduledJobRunnerProvider).runDue();
    } catch (_) {
      // A store that cannot be read must not take the ticker down.
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(checkNow());
  }

  void _openRun(String payload) {
    if (!payload.startsWith('job:')) return;
    _ref
        .read(focusedScheduledTaskProvider.notifier)
        .focus(payload.substring('job:'.length));
    _ref.read(appRouterProvider).go(AppRoutes.reminders);
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
    unawaited(_taps?.cancel());
    _taps = null;
    if (_started) {
      WidgetsBinding.instance.removeObserver(this);
      _started = false;
    }
  }
}
