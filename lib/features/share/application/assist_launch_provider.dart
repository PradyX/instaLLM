import 'package:flutter_riverpod/flutter_riverpod.dart';

/// How many times the device's assistant slot launched InstaLLM
/// (Road Map 5 Phase 5.3).
///
/// A counter rather than a flag: an assistant launch has no content of its own,
/// so the only thing the chat has to do is put the user in the composer. A
/// counter lets the same launch be noticed twice — once from a cold start,
/// where the value is already set when the page builds, and once while the page
/// is open — without a launch being lost because a flag was already true.
final assistLaunchProvider = NotifierProvider<AssistLaunchNotifier, int>(
  AssistLaunchNotifier.new,
);

class AssistLaunchNotifier extends Notifier<int> {
  @override
  int build() => 0;

  /// Records that the assistant launched the app.
  void signal() => state = state + 1;
}
