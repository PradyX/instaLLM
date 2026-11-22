import 'package:flutter/widgets.dart';

/// What a finished reply may put on the lock screen (Road Map 5 Phase 5.6).
///
/// Two rules are the whole point of the unit, so they live here as pure code
/// rather than inside a widget or a controller:
///
/// * the user is told once per finished reply, and only when they are not
///   looking at that reply, and
/// * the notice carries a short excerpt of the **answer** and nothing the user
///   typed. A prompt is the private half of a chat, so [excerpt] is only ever
///   handed the assistant's text and [announce] never receives the question.
class ReplyNotice {
  const ReplyNotice._();

  /// Longest body the notice may carry, before the trailing ellipsis.
  static const int excerptLimit = 160;

  /// Payload prefix that makes a notice a link into one conversation.
  static const String payloadPrefix = 'chat:';

  /// Whether this reply deserves a notice.
  ///
  /// Once per reply is the caller's job (it announces one message id once);
  /// what is decided here is *whether* the user is not looking: the app is not
  /// in the foreground, or it is, but another conversation is on screen.
  static bool shouldAnnounce({
    required AppLifecycleState? lifecycle,
    required bool conversationVisible,
    required bool fromScheduledJob,
  }) {
    // A scheduled job already posts its own "Done: …" notice with the run's
    // record, so a second notice for the same turn would be noise.
    if (fromScheduledJob) return false;
    if (lifecycle != null && lifecycle != AppLifecycleState.resumed) {
      return true;
    }
    return !conversationVisible;
  }

  /// The answer, cut down to something that fits a lock screen.
  ///
  /// Markdown is flattened because the shade does not render it, and the cut
  /// lands on a word boundary so the excerpt does not end mid-word. An answer
  /// with no words at all (a stopped or empty turn) yields an empty string,
  /// which the caller reads as "nothing to show".
  static String excerpt(String reply, {int limit = excerptLimit}) {
    var text = reply.replaceAll(RegExp(r'```[\s\S]*?```'), ' ');
    // Groups are read through replaceAllMapped: a Dart replacement string has
    // no `$1`, it would be inserted literally.
    text = text.replaceAllMapped(RegExp(r'`([^`]*)`'), (m) => m[1] ?? '');
    text = text.replaceAllMapped(
      RegExp(r'!\[([^\]]*)\]\([^)]*\)'),
      (m) => m[1] ?? '',
    );
    text = text.replaceAllMapped(
      RegExp(r'\[([^\]]+)\]\([^)]*\)'),
      (m) => m[1] ?? '',
    );
    text = text.replaceAll(RegExp(r'^\s{0,3}#{1,6}\s*', multiLine: true), '');
    text = text.replaceAll(RegExp(r'^\s{0,3}>\s?', multiLine: true), '');
    text = text.replaceAll(RegExp(r'^\s{0,3}[-*+]\s+', multiLine: true), '');
    text = text.replaceAll(RegExp(r'(\*\*|__|\*|~~)'), '');
    text = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (text.isEmpty) return '';

    // A one-line answer is the common case on a 0.5B model; make sure a
    // multi-line one still starts where the answer does.
    if (text.length <= limit) return text;

    var cut = text.substring(0, limit);
    final space = cut.lastIndexOf(' ');
    if (space > limit ~/ 2) cut = cut.substring(0, space);
    return '${cut.trimRight()}…';
  }

  static String payloadFor(String conversationId) =>
      '$payloadPrefix$conversationId';

  /// The conversation a tapped notice points at, or null for another notice.
  static String? conversationIdFrom(String payload) {
    if (!payload.startsWith(payloadPrefix)) return null;
    final id = payload.substring(payloadPrefix.length);
    return id.isEmpty ? null : id;
  }
}
