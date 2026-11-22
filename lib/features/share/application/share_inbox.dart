import 'package:installm/features/share/domain/shared_text_receiver.dart';

/// Turns platform share events into one callback (Road Map 5 Phase 5.1).
///
/// Separate from the widget that uses it so both paths — a share that launched
/// the app, and a share that arrives while it runs — can be tested without a
/// platform channel, and so the listener is attached before the launch payload
/// is read: a share delivered in between must not be lost.
class ShareInbox {
  ShareInbox({required this.receiver, required this.onText});

  final SharedTextReceiver receiver;
  final void Function(String text) onText;

  /// Attaches the live listener, then stages whatever launched the app.
  Future<void> start() async {
    receiver.listen(onText);
    final initial = await receiver.takeInitial();
    final text = initial?.trim();
    if (text != null && text.isNotEmpty) onText(text);
  }
}
