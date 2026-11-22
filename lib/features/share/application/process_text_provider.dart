import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The text-selection request another app is waiting on, if any
/// (Road Map 5 Phase 5.2).
///
/// Null means no app is waiting. False means the selection is editable and an
/// answer may be handed back; true means it is read-only and nothing may be
/// returned. The chat shows its "Replace selection" action only for the
/// editable case.
final processTextRequestProvider =
    NotifierProvider<ProcessTextRequestNotifier, bool?>(
      ProcessTextRequestNotifier.new,
    );

class ProcessTextRequestNotifier extends Notifier<bool?> {
  @override
  bool? build() => null;

  /// Records that another app asked InstaLLM to process a selection.
  void begin({required bool readOnly}) => state = readOnly;

  /// Forgets the request once its answer was handed over, or when the user
  /// carried on in the chat without using it.
  void clear() => state = null;
}
