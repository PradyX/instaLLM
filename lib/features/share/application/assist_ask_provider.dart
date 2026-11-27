import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Set when the assistant's floating composer sent a question (Road Map 5
/// Phase 5.3).
///
/// A summon that only opens the chat stages the screen and waits. A question
/// typed in the panel has already been sent by the user, so the chat asks it
/// rather than leaving it in the composer for a second press.
final assistAskProvider = NotifierProvider<AssistAskNotifier, int>(
  AssistAskNotifier.new,
);

class AssistAskNotifier extends Notifier<int> {
  @override
  int build() => 0;

  /// Records that the assistant panel sent a question.
  void signal() => state = state + 1;
}
