import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:installm/features/share/domain/shared_payload.dart';

/// Files another app shared that are waiting to become draft attachments
/// (Road Map 5 Phase 5.1).
///
/// The composer's own images are per-page state, so a share that lands while
/// the page does not exist yet — a cold start, or a share that arrives while
/// another screen is open — would be lost if it were handed straight to the
/// page. This holds it instead, and the composer takes it when it is ready.
final draftAttachmentsProvider =
    NotifierProvider<DraftAttachmentsNotifier, List<SharedAttachment>>(
      DraftAttachmentsNotifier.new,
    );

class DraftAttachmentsNotifier extends Notifier<List<SharedAttachment>> {
  @override
  List<SharedAttachment> build() => const [];

  /// Adds [attachments] behind anything already waiting.
  void stage(List<SharedAttachment> attachments) {
    if (attachments.isEmpty) return;
    state = [...state, ...attachments];
  }

  /// Returns everything waiting and empties the draft.
  List<SharedAttachment> take() {
    final staged = state;
    if (staged.isNotEmpty) state = const [];
    return staged;
  }
}
