import 'package:installm/features/share/domain/shared_content_receiver.dart';
import 'package:installm/features/share/domain/shared_payload.dart';

/// Turns platform share events into one callback (Road Map 5 Phase 5.1).
///
/// Separate from the widget that uses it so both paths — a share that launched
/// the app, and a share that arrives while it runs — can be tested without a
/// platform channel, and so the listener is attached before the launch payload
/// is read: a share delivered in between must not be lost.
class ShareInbox {
  ShareInbox({required this.receiver, required this.onPayload});

  final SharedContentReceiver receiver;
  final void Function(SharedPayload payload) onPayload;

  /// Attaches the live listener, then stages whatever launched the app.
  Future<void> start() async {
    receiver.listen(onPayload);
    final initial = await receiver.takeInitial();
    if (initial != null && !initial.isEmpty) onPayload(initial);
  }
}
